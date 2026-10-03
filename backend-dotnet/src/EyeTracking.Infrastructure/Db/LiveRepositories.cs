using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Db;

// Step 7 repository (SqlLiveRepo in backend/eyetracking/infrastructure/repositories.py): the rest of
// the live conversation repository. Its reads and EfUnitOfWork.Live came with step 4
// (ResearchRepositories.cs); the deletion rules already purge both tables (ResearchDeletion.cs).

internal sealed partial class LiveRepo
{
    public LiveConversation AddConversation(LiveConversation c) => Uow.Add(c);

    public LiveTurn AddTurn(LiveTurn t) => Uow.Add(t);

    public List<LiveConversation> OpenForStudy(int studyId) =>
        Db.Set<LiveConversation>().Where(c => c.StudyId == studyId && c.Status == ConversationStatus.Open).ToList();
}
