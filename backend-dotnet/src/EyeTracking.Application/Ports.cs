using EyeTracking.Domain;

namespace EyeTracking.Application;

// Ports the use cases depend on. Infrastructure implements them.
// Repository "Add" methods assign the id immediately (like a SQLAlchemy flush); nothing is
// permanent until IUnitOfWork.Commit. Each build step adds its repositories to the partial
// IUnitOfWork in its own file.

public interface IUserRepo
{
    User Add(User user);
    User? Get(int userId);
    User? ByEmail(string email);
    int Count();
}

public interface IStudyRepo
{
    Study Add(Study study);
    Study? Get(int studyId);
    List<Study> ListIds(IReadOnlyCollection<int> ids);
    List<Study> ListAll();
}

public interface IMembershipRepo
{
    StudyMembership Add(StudyMembership m);
    List<StudyMembership> ForUser(int userId);
    StudyMembership? Get(int studyId, int userId);
}

public interface IParticipantRepo
{
    Participant Add(Participant p);
    Participant? ByUser(int userId);
    Participant? ByCode(int studyId, string code);
    List<Participant> ListForStudy(int studyId);
    int CountForStudy(int studyId);
}

public interface IInvitationRepo
{
    Invitation Add(Invitation inv);
    Invitation? ByToken(string token);
    int CountForStudy(int studyId);
}

public interface ISheetRepo
{
    InformationSheet Add(InformationSheet sheet);
    InformationSheet? Current(int studyId);
}

public interface IConsentRepo
{
    Consent Add(Consent c);
    Consent? Latest(int participantId);
    List<Consent> History(int participantId);
}

public interface IProfileRepo
{
    Profile? Get(int participantId);
    Profile Save(Profile profile);
}

public interface IDemographicsRepo
{
    DemographicsForm AddForm(DemographicsForm form);
    DemographicsForm? CurrentForm(int studyId);
    DemographicsAnswer? Answers(int participantId);
    DemographicsAnswer SaveAnswers(DemographicsAnswer a);
}

public interface IAccessLogRepo
{
    AccessLogEntry Add(AccessLogEntry e);
    List<AccessLogEntry> ListForStudy(int studyId, int limit);
}

public partial interface IUnitOfWork : IDisposable
{
    IUserRepo Users { get; }
    IStudyRepo Studies { get; }
    IMembershipRepo Memberships { get; }
    IParticipantRepo Participants { get; }
    IInvitationRepo Invitations { get; }
    ISheetRepo Sheets { get; }
    IConsentRepo Consents { get; }
    IProfileRepo Profiles { get; }
    IDemographicsRepo Demographics { get; }
    IAccessLogRepo AccessLog { get; }

    void Commit();
    void Rollback();
}

public interface IPasswordHasher
{
    string Hash(string password);
    bool Verify(string password, string passwordHash);
}

public interface ITokenIssuer
{
    string Issue(int userId, string role);
    int? Parse(string token);
}

public interface IClock
{
    /// <summary>UTC, without a time zone marker (the Python service used naive utcnow).</summary>
    DateTime Now();
}
