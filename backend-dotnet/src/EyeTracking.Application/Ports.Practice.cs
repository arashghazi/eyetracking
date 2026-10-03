using EyeTracking.Domain;

namespace EyeTracking.Application;

// Step 3 ports: protocols, content, assignments, practice (PracticeUnitOfWork in ports.py),
// plus the private media store and the signed media links.

public interface IProtocolRepo
{
    Protocol Add(Protocol p);
    Protocol? Get(int protocolId);
    /// <summary>Oldest first.</summary>
    List<Protocol> ListForStudy(int studyId);
    /// <summary>Highest version in the study (drafts are 0), 0 when there is none.</summary>
    int MaxVersion(int studyId);
}

public interface IContentRepo
{
    ContentItem Add(ContentItem c);
    ContentItem? Get(int contentId);
    /// <summary>Oldest first.</summary>
    List<ContentItem> ListForStudy(int studyId);
}

public interface IMediaRepo
{
    ContentMedia Add(ContentMedia m);
    ContentMedia? Get(int mediaId);
    ContentMedia? ByKey(int contentId, string key);
    /// <summary>Ordered by key.</summary>
    List<ContentMedia> ListForContent(int contentId);
}

public interface IAssignmentRepo
{
    Assignment Add(Assignment a);
    Assignment? Get(int assignmentId);
    /// <summary>Ordered by order_index, then id.</summary>
    List<Assignment> ListForParticipant(int participantId);
}

public interface ITrialRepo
{
    int AddMany(IReadOnlyCollection<Trial> trials);
    /// <summary>Ordered by id.</summary>
    List<Trial> ForSession(int sessionId);
}

public interface IStageResultRepo
{
    StageResult Add(StageResult r);
    /// <summary>Ordered by id.</summary>
    List<StageResult> ForSession(int sessionId);
}

public interface IAnswerRepo
{
    Answer Add(Answer a);
    /// <summary>Ordered by id.</summary>
    List<Answer> ForSession(int sessionId);
}

public partial interface IUnitOfWork
{
    IProtocolRepo Protocols { get; }
    IContentRepo Content { get; }
    IMediaRepo Media { get; }
    IAssignmentRepo Assignments { get; }
    ITrialRepo Trials { get; }
    IStageResultRepo StageResults { get; }
    IAnswerRepo Answers { get; }
}

/// <summary>Private file storage for content media, outside the web root.</summary>
public interface IMediaStore
{
    /// <summary>Writes the file and returns the relative path to store.</summary>
    string Save(string relativePath, byte[] data);
    string Absolute(string relativePath);
}

/// <summary>Short-lived signed media links; verifying needs no database lookup.</summary>
public interface IMediaSigner
{
    string Sign(int mediaId);
    /// <summary>The media id, or null when the token is invalid or has expired.</summary>
    int? Verify(string token);
}
