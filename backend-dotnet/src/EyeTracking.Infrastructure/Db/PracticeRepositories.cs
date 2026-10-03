using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Db;

// Step 3 repositories (backend/eyetracking/infrastructure/repositories.py).

public sealed partial class EfUnitOfWork
{
    public IProtocolRepo Protocols => field ??= new ProtocolRepo(this);
    public IContentRepo Content => field ??= new ContentRepo(this);
    public IMediaRepo Media => field ??= new MediaRepo(this);
    public IAssignmentRepo Assignments => field ??= new AssignmentRepo(this);
    public ITrialRepo Trials => field ??= new TrialRepo(this);
    public IStageResultRepo StageResults => field ??= new StageResultRepo(this);
    public IAnswerRepo Answers => field ??= new AnswerRepo(this);
}

internal sealed class ProtocolRepo(EfUnitOfWork uow) : Repo(uow), IProtocolRepo
{
    public Protocol Add(Protocol p) => Uow.Add(p);
    public Protocol? Get(int protocolId) => Db.Set<Protocol>().Find(protocolId);
    public List<Protocol> ListForStudy(int studyId) => Db.Set<Protocol>().Where(p => p.StudyId == studyId).OrderBy(p => p.Id).ToList();
    public int MaxVersion(int studyId) => Db.Set<Protocol>().Where(p => p.StudyId == studyId).Max(p => (int?)p.Version) ?? 0;
}

internal sealed class ContentRepo(EfUnitOfWork uow) : Repo(uow), IContentRepo
{
    public ContentItem Add(ContentItem c) => Uow.Add(c);
    public ContentItem? Get(int contentId) => Db.Set<ContentItem>().Find(contentId);
    public List<ContentItem> ListForStudy(int studyId) => Db.Set<ContentItem>().Where(c => c.StudyId == studyId).OrderBy(c => c.Id).ToList();
}

internal sealed class MediaRepo(EfUnitOfWork uow) : Repo(uow), IMediaRepo
{
    public ContentMedia Add(ContentMedia m) => Uow.Add(m);
    public ContentMedia? Get(int mediaId) => Db.Set<ContentMedia>().Find(mediaId);
    public ContentMedia? ByKey(int contentId, string key) => Db.Set<ContentMedia>().FirstOrDefault(m => m.ContentId == contentId && m.Key == key);

    // keys sort by code point, as SQLite's BINARY collation did
    public List<ContentMedia> ListForContent(int contentId) =>
        Db.Set<ContentMedia>().Where(m => m.ContentId == contentId).AsEnumerable().OrderBy(m => m.Key, StringComparer.Ordinal).ToList();
}

internal sealed class AssignmentRepo(EfUnitOfWork uow) : Repo(uow), IAssignmentRepo
{
    public Assignment Add(Assignment a) => Uow.Add(a);
    public Assignment? Get(int assignmentId) => Db.Set<Assignment>().Find(assignmentId);

    public List<Assignment> ListForParticipant(int participantId) =>
        Db.Set<Assignment>().Where(a => a.ParticipantId == participantId).OrderBy(a => a.OrderIndex).ThenBy(a => a.Id).ToList();
}

internal sealed class TrialRepo(EfUnitOfWork uow) : Repo(uow), ITrialRepo
{
    public int AddMany(IReadOnlyCollection<Trial> trials)
    {
        Db.Set<Trial>().AddRange(trials);
        Uow.Flush();
        return trials.Count;
    }

    public List<Trial> ForSession(int sessionId) => Db.Set<Trial>().Where(t => t.SessionId == sessionId).OrderBy(t => t.Id).ToList();
}

internal sealed class StageResultRepo(EfUnitOfWork uow) : Repo(uow), IStageResultRepo
{
    public StageResult Add(StageResult r) => Uow.Add(r);
    public List<StageResult> ForSession(int sessionId) => Db.Set<StageResult>().Where(r => r.SessionId == sessionId).OrderBy(r => r.Id).ToList();
}

internal sealed class AnswerRepo(EfUnitOfWork uow) : Repo(uow), IAnswerRepo
{
    public Answer Add(Answer a) => Uow.Add(a);
    public List<Answer> ForSession(int sessionId) => Db.Set<Answer>().Where(a => a.SessionId == sessionId).OrderBy(a => a.Id).ToList();
}
