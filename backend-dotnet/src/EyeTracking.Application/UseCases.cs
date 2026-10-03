using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using static EyeTracking.Application.Authz;

namespace EyeTracking.Application;

/// <summary>Coded view: research code and research data, never the login email.</summary>
public sealed record ParticipantView(
    Participant Participant,
    Consent? Consent,
    Profile? Profile,
    DemographicsAnswer? Demographics,
    Readiness Readiness);

/// <summary>Profile fields a participant may change; null means "not sent" (left as it is).</summary>
public sealed record ProfileChanges(
    string? DisplayName = null,
    string? ResponseMode = null,
    string? VoicePreference = null,
    string? FacePreference = null,
    string? Speed = null,
    IReadOnlyList<string>? AccessibilityNeeds = null,
    IReadOnlyList<string>? Interests = null);

/// <summary>Use cases for build step 1 (accounts, studies, invitations, consent, profile,
/// demographics). Pure orchestration over ports; no HTTP, no SQL.</summary>
public static class UseCases
{
    private static string NormalizeEmail(string? email)
    {
        email = (email ?? "").Trim().ToLowerInvariant();
        if (!email.Contains('@') || email.Length < 5)
            throw new Invalid("a valid email address is required");
        return email;
    }

    private static void CheckPassword(string? password)
    {
        if ((password ?? "").Length < 8)
            throw new Invalid("password must be at least 8 characters");
    }

    // ---------- accounts ----------

    public static User? BootstrapAdmin(IUnitOfWork uow, IPasswordHasher hasher, string email, string password)
    {
        if (uow.Users.Count() > 0)
            return null;
        var user = uow.Users.Add(new User { Email = NormalizeEmail(email), PasswordHash = hasher.Hash(password), Role = Role.Admin });
        uow.Commit();
        return user;
    }

    public static User CreateUser(IUnitOfWork uow, IPasswordHasher hasher, Principal principal, string email, string password, Role role)
    {
        RequireRole(principal, Role.Admin);
        if (role == Role.Participant)
            throw new Invalid("participants join through invitations, not admin creation");
        email = NormalizeEmail(email);
        CheckPassword(password);
        if (uow.Users.ByEmail(email) is not null)
            throw new Conflict("email already registered");
        var user = uow.Users.Add(new User { Email = email, PasswordHash = hasher.Hash(password), Role = role });
        uow.Commit();
        return user;
    }

    public static (string Token, User User) Login(IUnitOfWork uow, IPasswordHasher hasher, ITokenIssuer tokens, string? email, string? password)
    {
        var user = uow.Users.ByEmail((email ?? "").Trim().ToLowerInvariant());
        if (user is null || !user.IsActive || !hasher.Verify(password ?? "", user.PasswordHash))
            throw new AuthenticationFailed("invalid email or password");
        return (tokens.Issue(user.Id, user.Role.Value()), user);
    }

    public static Principal? LoadPrincipal(IUnitOfWork uow, int userId)
    {
        var user = uow.Users.Get(userId);
        if (user is null || !user.IsActive)
            return null;
        var memberships = uow.Memberships.ForUser(userId);
        var participant = user.Role == Role.Participant ? uow.Participants.ByUser(userId) : null;
        return new Principal(userId, user.Role, memberships, participant);
    }

    // ---------- studies and membership ----------

    public static Study CreateStudy(IUnitOfWork uow, Principal principal, string? name)
    {
        RequireRole(principal, Role.Admin);
        if (string.IsNullOrWhiteSpace(name))
            throw new Invalid("study name is required");
        var study = uow.Studies.Add(new Study { Name = name.Trim() });
        uow.Commit();
        return study;
    }

    public static List<Study> ListStudies(IUnitOfWork uow, Principal principal) =>
        principal.Role == Role.Admin
            ? uow.Studies.ListAll()
            : uow.Studies.ListIds(principal.Memberships.Select(m => m.StudyId).ToList());

    public static StudyMembership AddMember(IUnitOfWork uow, Principal principal, int studyId, int userId, StudyRole studyRole, bool canLinkIdentity)
    {
        RequireRole(principal, Role.Admin);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var user = uow.Users.Get(userId);
        if (user is null || user.Role is not (Role.Researcher or Role.Analyst or Role.Admin))
            throw new Invalid("only researcher, analyst or admin accounts can be study members");
        if (uow.Memberships.Get(studyId, userId) is not null)
            throw new Conflict("already a member");
        var m = uow.Memberships.Add(new StudyMembership
        {
            StudyId = studyId, UserId = userId, StudyRole = studyRole, CanLinkIdentity = canLinkIdentity,
        });
        uow.Commit();
        return m;
    }

    // ---------- invitations ----------

    public static Invitation CreateInvitation(IUnitOfWork uow, IClock clock, Principal principal, int studyId, string? inviteeEmail, int expiresDays = 14)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        if (expiresDays is < 1 or > 90)
            throw new Invalid("expires_days must be between 1 and 90");
        var number = uow.Invitations.CountForStudy(studyId) + 1;
        var inv = uow.Invitations.Add(new Invitation
        {
            Token = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(24)),
            StudyId = studyId,
            Code = $"P-{number:D3}",
            CreatedBy = principal.UserId,
            ExpiresAt = clock.Now().AddDays(expiresDays),
            InviteeEmail = string.IsNullOrEmpty(inviteeEmail) ? null : NormalizeEmail(inviteeEmail),
        });
        uow.Commit();
        return inv;
    }

    public static (string Token, Participant Participant) AcceptInvitation(
        IUnitOfWork uow, IPasswordHasher hasher, ITokenIssuer tokens, IClock clock, string token, string? email, string? password)
    {
        var inv = uow.Invitations.ByToken(token);
        var now = clock.Now();
        if (inv is null || !inv.IsUsable(now))
            throw new NotFound("invitation is invalid, used or expired");
        email = NormalizeEmail(email);
        CheckPassword(password);
        if (inv.InviteeEmail is { Length: > 0 } && inv.InviteeEmail != email)
            throw new Invalid("this invitation was issued for a different email address");
        if (uow.Users.ByEmail(email) is not null)
            throw new Conflict("email already registered");
        var user = uow.Users.Add(new User { Email = email, PasswordHash = hasher.Hash(password!), Role = Role.Participant });
        var participant = uow.Participants.Add(new Participant { Code = inv.Code, StudyId = inv.StudyId, UserId = user.Id });
        inv.UsedAt = now;
        uow.Commit();
        return (tokens.Issue(user.Id, user.Role.Value()), participant);
    }

    // ---------- information sheet and consent ----------

    public static InformationSheet PublishInformationSheet(
        IUnitOfWork uow, Principal principal, int studyId,
        string aims, string discomfortSources, string benefits, string dataHandling, string stopRules)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var current = uow.Sheets.Current(studyId);
        var sheet = new InformationSheet
        {
            StudyId = studyId,
            Version = current is null ? 1 : current.Version + 1,
            Aims = aims, DiscomfortSources = discomfortSources, Benefits = benefits,
            DataHandling = dataHandling, StopRules = stopRules,
        };
        sheet.Validate();
        sheet = uow.Sheets.Add(sheet);
        uow.Commit();
        return sheet;
    }

    public static InformationSheet? GetStudySheet(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId);
        return uow.Sheets.Current(studyId);
    }

    public static InformationSheet? MyInformationSheet(IUnitOfWork uow, Principal principal) =>
        uow.Sheets.Current(RequireParticipant(principal).StudyId);

    public static Consent GiveConsent(IUnitOfWork uow, IClock clock, Principal principal, int sheetVersion, bool participate, bool audio, bool video)
    {
        var p = RequireParticipant(principal);
        var sheet = uow.Sheets.Current(p.StudyId)
            ?? throw new Invalid("no information sheet has been published for this study yet");
        if (sheetVersion != sheet.Version)
            throw new Conflict($"the information sheet has changed; please read version {sheet.Version}");
        if (!participate)
            throw new Invalid("consent to participate is required to continue; you may stop at any time later");
        var consent = uow.Consents.Add(new Consent
        {
            ParticipantId = p.Id, SheetVersion = sheet.Version, Participate = true,
            AudioRecording = audio, VideoRecording = video, GivenAt = clock.Now(),
        });
        uow.Commit();
        return consent;
    }

    public static Consent WithdrawConsent(IUnitOfWork uow, IClock clock, Principal principal)
    {
        var p = RequireParticipant(principal);
        var latest = uow.Consents.Latest(p.Id);
        if (latest is null || latest.WithdrawnAt is not null)
            throw new Conflict("there is no active consent to withdraw");
        latest.WithdrawnAt = clock.Now();
        uow.Commit();
        return latest;
    }

    // ---------- profile ----------

    public static Profile GetProfile(IUnitOfWork uow, Principal principal)
    {
        var p = RequireParticipant(principal);
        return uow.Profiles.Get(p.Id) ?? new Profile { ParticipantId = p.Id };
    }

    public static Profile UpdateProfile(IUnitOfWork uow, Principal principal, ProfileChanges changes)
    {
        var p = RequireParticipant(principal);
        var profile = uow.Profiles.Get(p.Id) ?? new Profile { ParticipantId = p.Id };
        static List<string> Clean(IEnumerable<string> values) =>
            values.Select(v => v.Trim()).Where(v => v.Length > 0).ToList();
        if (changes.DisplayName is not null)
            profile.DisplayName = changes.DisplayName.Trim() is { Length: > 0 } name ? name : null;
        if (changes.ResponseMode is not null)
            profile.ResponseMode = Wire.Parse<ResponseMode>(changes.ResponseMode);
        if (changes.VoicePreference is not null)
            profile.VoicePreference = changes.VoicePreference;
        if (changes.FacePreference is not null)
            profile.FacePreference = changes.FacePreference;
        if (changes.Speed is not null)
            profile.Speed = changes.Speed;
        if (changes.AccessibilityNeeds is not null)
            profile.AccessibilityNeeds = Clean(changes.AccessibilityNeeds);
        if (changes.Interests is not null)
            profile.Interests = Clean(changes.Interests);
        profile = uow.Profiles.Save(profile);
        uow.Commit();
        return profile;
    }

    // ---------- demographics ----------

    public static DemographicsForm PublishDemographicsForm(IUnitOfWork uow, Principal principal, int studyId, JsonArray fields)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var current = uow.Demographics.CurrentForm(studyId);
        var form = new DemographicsForm { StudyId = studyId, Version = current is null ? 1 : current.Version + 1, Fields = fields };
        form.Validate();
        form = uow.Demographics.AddForm(form);
        uow.Commit();
        return form;
    }

    public static DemographicsForm? GetStudyForm(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId);
        return uow.Demographics.CurrentForm(studyId);
    }

    public static DemographicsForm? MyDemographicsForm(IUnitOfWork uow, Principal principal) =>
        uow.Demographics.CurrentForm(RequireParticipant(principal).StudyId);

    public static DemographicsAnswer SubmitDemographics(IUnitOfWork uow, IClock clock, Principal principal, JsonObject answers)
    {
        var p = RequireParticipant(principal);
        var form = uow.Demographics.CurrentForm(p.StudyId) ?? throw new Invalid("this study has no demographics form");
        form.ValidateAnswers(answers);
        var record = uow.Demographics.Answers(p.Id) ?? new DemographicsAnswer { ParticipantId = p.Id, FormVersion = form.Version };
        record.FormVersion = form.Version;
        record.Answers = answers;
        record.UpdatedAt = clock.Now();
        record = uow.Demographics.SaveAnswers(record);
        uow.Commit();
        return record;
    }

    // ---------- participant views ----------

    private static ParticipantView View(IUnitOfWork uow, Participant p)
    {
        var sheet = uow.Sheets.Current(p.StudyId);
        var consent = uow.Consents.Latest(p.Id);
        var form = uow.Demographics.CurrentForm(p.StudyId);
        var answers = uow.Demographics.Answers(p.Id);
        return new ParticipantView(p, consent, uow.Profiles.Get(p.Id), answers, ReadinessRules.Compute(sheet, consent, form, answers));
    }

    public static ParticipantView MyParticipantView(IUnitOfWork uow, Principal principal) => View(uow, RequireParticipant(principal));

    /// <summary>Everything stored about the participant, for the participant. Comment 9: raw data for the person.</summary>
    public static JsonObject MyDataExport(IUnitOfWork uow, Principal principal)
    {
        var p = RequireParticipant(principal);
        var user = uow.Users.Get(p.UserId);
        var view = View(uow, p);
        return new JsonObject
        {
            ["account"] = new JsonObject
            {
                ["email"] = user?.Email,
                ["created_at"] = user is null ? null : JsonFormat.Timestamp(user.CreatedAt),
            },
            ["participant"] = new JsonObject
            {
                ["code"] = p.Code, ["study_id"] = p.StudyId, ["created_at"] = JsonFormat.Timestamp(p.CreatedAt),
            },
            ["consents"] = new JsonArray(uow.Consents.History(p.Id).Select(c => (JsonNode)JsonFormat.Entity(c)).ToArray()),
            ["profile"] = view.Profile is null ? null : JsonFormat.Entity(view.Profile),
            ["demographics"] = view.Demographics is null ? null : JsonFormat.Entity(view.Demographics),
            ["sessions"] = new JsonArray(),
        };
    }

    public static List<ParticipantView> ListParticipants(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        return uow.Participants.ListForStudy(studyId).Select(p => View(uow, p)).ToList();
    }

    public static ParticipantView GetParticipant(IUnitOfWork uow, Principal principal, int studyId, string code)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        var p = uow.Participants.ByCode(studyId, code) ?? throw new NotFound("participant not found");
        return View(uow, p);
    }

    public static string GetParticipantIdentity(IUnitOfWork uow, Principal principal, int studyId, string code)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        RequireIdentityLink(principal, studyId);
        var p = uow.Participants.ByCode(studyId, code) ?? throw new NotFound("participant not found");
        var user = uow.Users.Get(p.UserId) ?? throw new NotFound("participant account not found");
        uow.AccessLog.Add(new AccessLogEntry
        {
            StudyId = studyId, UserId = principal.UserId, Role = principal.Role.Value(), Action = "identity_reveal",
            Detail = new JsonObject { ["participant_code"] = code },
        });
        uow.Commit();
        return user.Email;
    }
}
