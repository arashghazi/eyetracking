using EyeTracking.Application;
using EyeTracking.Domain;
using Microsoft.EntityFrameworkCore;

namespace EyeTracking.Infrastructure.Db;

// Step 5 repositories (backend/eyetracking/infrastructure/repositories.py): generation jobs and
// the per-study AI budget.

public sealed partial class EfUnitOfWork
{
    public IJobRepo Jobs => field ??= new JobRepo(this);
    public IAiBudgetRepo AiBudgets => field ??= new AiBudgetRepo(this);
}

internal sealed class JobRepo(EfUnitOfWork uow) : Repo(uow), IJobRepo
{
    public GenerationJob Add(GenerationJob j) => Uow.Add(j);
    public GenerationJob? Get(int jobId) => Db.Set<GenerationJob>().Find(jobId);

    public List<GenerationJob> ListForStudy(int studyId, string? status, long? contentId)
    {
        var q = Db.Set<GenerationJob>().Where(j => j.StudyId == studyId);
        // the status filter matches exactly, as SQLite's comparison did (SQL Server ignores case)
        if (!string.IsNullOrEmpty(status))
            q = q.Where(j => EF.Functions.Collate(j.Status, "Latin1_General_100_BIN2") == status);
        if (contentId is { } cid && cid != 0)
            q = q.Where(j => j.ContentId == cid);
        return q.OrderByDescending(j => j.Id).ToList();
    }

    public GenerationJob? NextQueued(DateTime now) =>
        Db.Set<GenerationJob>()
            .Where(j => j.Status == "queued" && (j.NextAttemptAt == null || j.NextAttemptAt <= now))
            .OrderBy(j => j.Id)
            .FirstOrDefault();
}

internal sealed class AiBudgetRepo(EfUnitOfWork uow) : Repo(uow), IAiBudgetRepo
{
    public AiBudget? Get(int studyId) => Db.Set<AiBudget>().FirstOrDefault(b => b.StudyId == studyId);
    public AiBudget Save(AiBudget b) => Uow.Save(b);
}
