using EyeTracking.Domain;

namespace EyeTracking.Application;

// Step 4 ports: research data (ResearchUnitOfWork in ports.py). The access log came with step 1,
// whose identity reveal already writes to it. The participant's raw-data download also reads two
// later tables: debrief answers (step 6) and live conversations (step 7). Their repositories are
// partial so that those steps add their other methods in their own files.

public partial interface IDebriefAnswerRepo
{
    DebriefAnswer? ForSession(int sessionId);
}

public partial interface ILiveRepo
{
    LiveConversation? ConversationForSession(int sessionId);
    /// <summary>Ordered by index.</summary>
    List<LiveTurn> Turns(int conversationId);
}

public partial interface IUnitOfWork
{
    IDebriefAnswerRepo DebriefAnswers { get; }
    ILiveRepo Live { get; }

    /// <summary>Deletes everything recorded under a research code (sessions with everything hanging
    /// off them, consents, demographics, profile, assignments); the participant row and the account
    /// stay. Returns row counts per table, keyed and ordered as the Python service reported them.</summary>
    OrderedDictionary<string, int> PurgeParticipantResearchData(int participantId);

    /// <summary>Deletes the participant row (the identity link). Purge its research data first.</summary>
    void DeleteParticipant(int participantId);
}
