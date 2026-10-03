using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Db;

// Step 1 repositories (backend/eyetracking/infrastructure/repositories.py).

internal abstract class Repo(EfUnitOfWork uow)
{
    protected EfUnitOfWork Uow { get; } = uow;
    protected EyeTrackingDb Db => Uow.Db;
}

internal sealed class UserRepo(EfUnitOfWork uow) : Repo(uow), IUserRepo
{
    public User Add(User user) => Uow.Add(user);
    public User? Get(int userId) => Db.Set<User>().Find(userId);
    public User? ByEmail(string email) => Db.Set<User>().FirstOrDefault(u => u.Email == email);
    public int Count() => Db.Set<User>().Count();
}

internal sealed class StudyRepo(EfUnitOfWork uow) : Repo(uow), IStudyRepo
{
    public Study Add(Study study) => Uow.Add(study);
    public Study? Get(int studyId) => Db.Set<Study>().Find(studyId);

    public List<Study> ListIds(IReadOnlyCollection<int> ids) =>
        ids.Count == 0 ? [] : Db.Set<Study>().Where(s => ids.Contains(s.Id)).OrderBy(s => s.Id).ToList();

    public List<Study> ListAll() => Db.Set<Study>().OrderBy(s => s.Id).ToList();
}

internal sealed class MembershipRepo(EfUnitOfWork uow) : Repo(uow), IMembershipRepo
{
    public StudyMembership Add(StudyMembership m) => Uow.Add(m);
    public List<StudyMembership> ForUser(int userId) => Db.Set<StudyMembership>().Where(m => m.UserId == userId).OrderBy(m => m.Id).ToList();

    public StudyMembership? Get(int studyId, int userId) =>
        Db.Set<StudyMembership>().FirstOrDefault(m => m.StudyId == studyId && m.UserId == userId);
}

internal sealed class ParticipantRepo(EfUnitOfWork uow) : Repo(uow), IParticipantRepo
{
    public Participant Add(Participant p) => Uow.Add(p);
    public Participant? ByUser(int userId) => Db.Set<Participant>().FirstOrDefault(p => p.UserId == userId);
    public Participant? ByCode(int studyId, string code) => Db.Set<Participant>().FirstOrDefault(p => p.StudyId == studyId && p.Code == code);

    public List<Participant> ListForStudy(int studyId) =>
        Db.Set<Participant>().Where(p => p.StudyId == studyId).AsEnumerable().OrderBy(p => p.Code, StringComparer.Ordinal).ToList();

    public int CountForStudy(int studyId) => Db.Set<Participant>().Count(p => p.StudyId == studyId);
}

internal sealed class InvitationRepo(EfUnitOfWork uow) : Repo(uow), IInvitationRepo
{
    public Invitation Add(Invitation inv) => Uow.Add(inv);
    public Invitation? ByToken(string token) => Db.Set<Invitation>().FirstOrDefault(i => i.Token == token);
    public int CountForStudy(int studyId) => Db.Set<Invitation>().Count(i => i.StudyId == studyId);
}

internal sealed class SheetRepo(EfUnitOfWork uow) : Repo(uow), ISheetRepo
{
    public InformationSheet Add(InformationSheet sheet) => Uow.Add(sheet);

    public InformationSheet? Current(int studyId) =>
        Db.Set<InformationSheet>().Where(s => s.StudyId == studyId).OrderByDescending(s => s.Version).FirstOrDefault();
}

internal sealed class ConsentRepo(EfUnitOfWork uow) : Repo(uow), IConsentRepo
{
    public Consent Add(Consent c) => Uow.Add(c);

    public Consent? Latest(int participantId) =>
        Db.Set<Consent>().Where(c => c.ParticipantId == participantId).OrderByDescending(c => c.Id).FirstOrDefault();

    public List<Consent> History(int participantId) =>
        Db.Set<Consent>().Where(c => c.ParticipantId == participantId).OrderBy(c => c.Id).ToList();
}

internal sealed class ProfileRepo(EfUnitOfWork uow) : Repo(uow), IProfileRepo
{
    public Profile? Get(int participantId) => Db.Set<Profile>().FirstOrDefault(p => p.ParticipantId == participantId);
    public Profile Save(Profile profile) => Uow.Save(profile);
}

internal sealed class DemographicsRepo(EfUnitOfWork uow) : Repo(uow), IDemographicsRepo
{
    public DemographicsForm AddForm(DemographicsForm form) => Uow.Add(form);

    public DemographicsForm? CurrentForm(int studyId) =>
        Db.Set<DemographicsForm>().Where(f => f.StudyId == studyId).OrderByDescending(f => f.Version).FirstOrDefault();

    public DemographicsAnswer? Answers(int participantId) => Db.Set<DemographicsAnswer>().FirstOrDefault(a => a.ParticipantId == participantId);
    public DemographicsAnswer SaveAnswers(DemographicsAnswer a) => Uow.Save(a);
}

internal sealed class AccessLogRepo(EfUnitOfWork uow) : Repo(uow), IAccessLogRepo
{
    public AccessLogEntry Add(AccessLogEntry e) => Uow.Add(e);

    public List<AccessLogEntry> ListForStudy(int studyId, int limit) =>
        Db.Set<AccessLogEntry>().Where(e => e.StudyId == studyId).OrderByDescending(e => e.Id).Take(limit).ToList();
}
