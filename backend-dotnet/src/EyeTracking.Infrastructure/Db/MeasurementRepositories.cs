using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Db;

// Step 2 repositories (backend/eyetracking/infrastructure/repositories.py).

public sealed partial class EfUnitOfWork
{
    public ISettingsVersionRepo SettingsVersions => field ??= new SettingsVersionRepo(this);
    public ISessionRepo Sessions => field ??= new SessionRepo(this);
    public ICalibrationRepo Calibrations => field ??= new CalibrationRepo(this);
    public IValidationRepo Validations => field ??= new ValidationRepo(this);
    public ILayoutRepo Layouts => field ??= new LayoutRepo(this);
    public ISampleRepo Samples => field ??= new SampleRepo(this);
    public IEventRepo Events => field ??= new EventRepo(this);
    public IMeasurementSettingsRepo MeasurementSettings => field ??= new MeasurementSettingsRepo(this);
}

internal sealed class SessionRepo(EfUnitOfWork uow) : Repo(uow), ISessionRepo
{
    public Session Add(Session s) => Uow.Add(s);
    public Session? Get(int sessionId) => Db.Set<Session>().Find(sessionId);

    public List<Session> ListForParticipant(int participantId) =>
        Db.Set<Session>().Where(s => s.ParticipantId == participantId).OrderByDescending(s => s.Id).ToList();

    public List<Session> ListForStudy(int studyId) =>
        Db.Set<Session>().Where(s => s.StudyId == studyId).OrderByDescending(s => s.Id).ToList();
}

internal sealed class CalibrationRepo(EfUnitOfWork uow) : Repo(uow), ICalibrationRepo
{
    public Calibration Add(Calibration c) => Uow.Add(c);

    public Calibration? Latest(int sessionId) =>
        Db.Set<Calibration>().Where(c => c.SessionId == sessionId).OrderByDescending(c => c.Id).FirstOrDefault();
}

internal sealed class ValidationRepo(EfUnitOfWork uow) : Repo(uow), IValidationRepo
{
    public Validation Add(Validation v) => Uow.Add(v);

    public Validation? Latest(int sessionId) =>
        Db.Set<Validation>().Where(v => v.SessionId == sessionId).OrderByDescending(v => v.Id).FirstOrDefault();
}

internal sealed class LayoutRepo(EfUnitOfWork uow) : Repo(uow), ILayoutRepo
{
    public StimulusLayout Add(StimulusLayout l) => Uow.Add(l);

    public StimulusLayout? Latest(int sessionId) =>
        Db.Set<StimulusLayout>().Where(l => l.SessionId == sessionId).OrderByDescending(l => l.Id).FirstOrDefault();

    public List<StimulusLayout> SessionAll(int sessionId) =>
        Db.Set<StimulusLayout>().Where(l => l.SessionId == sessionId).OrderBy(l => l.Id).ToList();
}

internal sealed class SampleRepo(EfUnitOfWork uow) : Repo(uow), ISampleRepo
{
    public int AddMany(IReadOnlyCollection<GazeSample> samples)
    {
        Db.Set<GazeSample>().AddRange(samples);
        Uow.Flush();
        return samples.Count;
    }

    public List<GazeSample> ForSession(int sessionId) =>
        Db.Set<GazeSample>().Where(s => s.SessionId == sessionId).OrderBy(s => s.TMs).ThenBy(s => s.Id).ToList();

    public (int Total, List<GazeSample> Items) Page(int sessionId, int offset, int limit)
    {
        var query = Db.Set<GazeSample>().Where(s => s.SessionId == sessionId);
        var total = query.Count();
        var items = query.OrderBy(s => s.TMs).ThenBy(s => s.Id).Skip(offset).Take(limit).ToList();
        return (total, items);
    }
}

internal sealed class EventRepo(EfUnitOfWork uow) : Repo(uow), IEventRepo
{
    public SessionEvent Add(SessionEvent e) => Uow.Add(e);

    public List<SessionEvent> ForSession(int sessionId) =>
        Db.Set<SessionEvent>().Where(e => e.SessionId == sessionId).OrderBy(e => e.TMs).ThenBy(e => e.Id).ToList();
}

internal sealed class MeasurementSettingsRepo(EfUnitOfWork uow) : Repo(uow), IMeasurementSettingsRepo
{
    public MeasurementSettings? Get(int studyId) => Db.Set<MeasurementSettings>().FirstOrDefault(m => m.StudyId == studyId);
    public MeasurementSettings Save(MeasurementSettings s) => Uow.Save(s);
}

internal sealed class SettingsVersionRepo(EfUnitOfWork uow) : Repo(uow), ISettingsVersionRepo
{
    public SettingsVersion Add(SettingsVersion v) => Uow.Add(v);

    public List<SettingsVersion> ListForStudy(int studyId) =>
        Db.Set<SettingsVersion>().Where(v => v.StudyId == studyId).OrderBy(v => v.Version).ToList();
}
