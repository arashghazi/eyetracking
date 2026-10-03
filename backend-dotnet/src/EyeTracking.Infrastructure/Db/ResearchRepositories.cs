using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Db;

// Step 4 repositories (backend/eyetracking/infrastructure/repositories.py): the reads research
// needs from the step 6 and step 7 tables. Those steps add their other methods to these partial
// classes. The access log repository came with step 1; the deletion rules are in ResearchDeletion.cs.

public sealed partial class EfUnitOfWork
{
    public IDebriefAnswerRepo DebriefAnswers => field ??= new DebriefAnswerRepo(this);
    public ILiveRepo Live => field ??= new LiveRepo(this);
}

internal sealed partial class DebriefAnswerRepo(EfUnitOfWork uow) : Repo(uow), IDebriefAnswerRepo
{
    public DebriefAnswer? ForSession(int sessionId) => Db.Set<DebriefAnswer>().FirstOrDefault(a => a.SessionId == sessionId);
}

internal sealed partial class LiveRepo(EfUnitOfWork uow) : Repo(uow), ILiveRepo
{
    public LiveConversation? ConversationForSession(int sessionId) => Db.Set<LiveConversation>().FirstOrDefault(c => c.SessionId == sessionId);

    public List<LiveTurn> Turns(int conversationId) =>
        Db.Set<LiveTurn>().Where(t => t.ConversationId == conversationId).OrderBy(t => t.Index).ThenBy(t => t.Id).ToList();
}
