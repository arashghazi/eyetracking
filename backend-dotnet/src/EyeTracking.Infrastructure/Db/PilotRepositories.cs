using System.Data;
using EyeTracking.Application;
using EyeTracking.Domain;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace EyeTracking.Infrastructure.Db;

// Step 6 repositories (backend/eyetracking/infrastructure/repositories.py): observations, debrief
// forms and answers, research tracker recordings. Settings versions came with step 2, the debrief
// answer lookup by session with step 4; the deletion rules are in ResearchDeletion.cs.

public sealed partial class EfUnitOfWork
{
    public IObservationRepo Observations => field ??= new ObservationRepo(this);
    public IDebriefFormRepo DebriefForms => field ??= new DebriefFormRepo(this);
    public IReferenceRepo References => field ??= new ReferenceRepo(this);
}

internal sealed class ObservationRepo(EfUnitOfWork uow) : Repo(uow), IObservationRepo
{
    public Observation Add(Observation o) => Uow.Add(o);
    public List<Observation> ForSession(int sessionId) => Db.Set<Observation>().Where(o => o.SessionId == sessionId).OrderBy(o => o.Id).ToList();
    public List<Observation> ForStudy(int studyId) => Db.Set<Observation>().Where(o => o.StudyId == studyId).OrderBy(o => o.Id).ToList();
}

internal sealed class DebriefFormRepo(EfUnitOfWork uow) : Repo(uow), IDebriefFormRepo
{
    public DebriefForm Add(DebriefForm f) => Uow.Add(f);

    public DebriefForm? Current(int studyId) =>
        Db.Set<DebriefForm>().Where(f => f.StudyId == studyId).OrderByDescending(f => f.Version).FirstOrDefault();

    public DebriefForm? GetVersion(int studyId, int version) =>
        Db.Set<DebriefForm>().FirstOrDefault(f => f.StudyId == studyId && f.Version == version);
}

internal sealed partial class DebriefAnswerRepo
{
    public DebriefAnswer Add(DebriefAnswer a) => Uow.Add(a);
    public List<DebriefAnswer> ForStudy(int studyId) => Db.Set<DebriefAnswer>().Where(a => a.StudyId == studyId).OrderBy(a => a.Id).ToList();
}

internal sealed class ReferenceRepo(EfUnitOfWork uow) : Repo(uow), IReferenceRepo
{
    private const int Chunk = 50_000;

    /// <summary>The rows go in with SqlBulkCopy inside the request transaction (Python inserted them
    /// in chunks with a core insert); the change tracker never sees them.</summary>
    public ReferenceRecording Add(ReferenceRecording r, IReadOnlyList<ReferenceRow> rows)
    {
        Uow.Add(r);
        var connection = (SqlConnection)Db.Database.GetDbConnection();
        var transaction = (SqlTransaction?)Db.Database.CurrentTransaction?.GetDbTransaction();
        using var bulk = new SqlBulkCopy(connection, SqlBulkCopyOptions.CheckConstraints, transaction)
        {
            DestinationTableName = "reference_samples",
            BulkCopyTimeout = 0,
        };
        foreach (var name in new[] { "recording_id", "t_ms", "x", "y", "valid" })
            bulk.ColumnMappings.Add(name, name);
        for (var start = 0; start < rows.Count; start += Chunk)
        {
            using var table = new DataTable();
            table.Columns.Add("recording_id", typeof(int));
            table.Columns.Add("t_ms", typeof(int));
            table.Columns.Add("x", typeof(double));
            table.Columns.Add("y", typeof(double));
            table.Columns.Add("valid", typeof(bool));
            for (var i = start; i < Math.Min(rows.Count, start + Chunk); i++)
            {
                var row = rows[i];
                table.Rows.Add(r.Id, checked((int)row.TMs), row.X is { } x ? x : DBNull.Value, row.Y is { } y ? y : DBNull.Value, row.Valid);
            }
            bulk.WriteToServer(table);
        }
        return r;
    }

    public ReferenceRecording? Get(int recordingId) => Db.Set<ReferenceRecording>().Find(recordingId);

    public List<ReferenceRecording> ForSession(int sessionId) =>
        Db.Set<ReferenceRecording>().Where(r => r.SessionId == sessionId).OrderBy(r => r.Id).ToList();

    public List<ReferenceRecording> ForStudy(int studyId) =>
        Db.Set<ReferenceRecording>().Where(r => r.StudyId == studyId).OrderBy(r => r.Id).ToList();

    public List<ReferenceRow> Samples(int recordingId) =>
        Db.Set<ReferenceSample>()
            .Where(s => s.RecordingId == recordingId)
            .OrderBy(s => s.TMs).ThenBy(s => s.Id)
            .Select(s => new { s.TMs, s.X, s.Y, s.Valid })
            .AsEnumerable()
            .Select(s => new ReferenceRow(s.TMs, s.X, s.Y, s.Valid))
            .ToList();
}
