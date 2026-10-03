using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Accounts;

// HTTP shapes of build step 1 (backend/eyetracking/web/schemas.py). Names become snake_case on the wire.

public sealed record LoginIn(string Email, string Password);

public sealed record TokenOut(string AccessToken, string Role, string? ParticipantCode)
{
    public string TokenType => "bearer";
}

public sealed record AcceptInvitationIn(string Email, string Password);

public sealed record ParticipantRef(string Code, int StudyId);

public sealed record MeOut(int Id, string Email, string Role, ParticipantRef? Participant);

public sealed record ReadinessOut(bool Ready, IReadOnlyList<string> Reasons);

public sealed record ConsentOut(int SheetVersion, bool Participate, bool AudioRecording, bool VideoRecording, DateTime GivenAt, DateTime? WithdrawnAt);

public sealed record ConsentIn(int SheetVersion, bool Participate, bool AudioRecording = false, bool VideoRecording = false);

public sealed record SheetIn(string Aims, string DiscomfortSources, string Benefits, string DataHandling, string StopRules);

public sealed record SheetOut(string Aims, string DiscomfortSources, string Benefits, string DataHandling, string StopRules, int Version, DateTime PublishedAt);

public sealed record ProfileIn(
    string? DisplayName = null,
    string? ResponseMode = null,
    string? VoicePreference = null,
    string? FacePreference = null,
    string? Speed = null,
    List<string>? AccessibilityNeeds = null,
    List<string>? Interests = null) : IValidatedBody
{
    public void Validate(List<JsonObject> errors)
    {
        Check.Literal(errors, ResponseMode, "response_mode", "keyboard", "touch", "four_choice", "symbol");
        Check.Literal(errors, Speed, "speed", "slow", "normal", "fast");
    }
}

public sealed record ProfileOut(
    string? DisplayName, string ResponseMode, string? VoicePreference, string? FacePreference, string Speed,
    IReadOnlyList<string> AccessibilityNeeds, IReadOnlyList<string> Interests);

public sealed record DemographicsField(string Key, string Label, string Type, List<string>? Options = null, bool Required = false);

public sealed record DemographicsFormIn(List<DemographicsField> Fields) : IValidatedBody
{
    public void Validate(List<JsonObject> errors)
    {
        for (var i = 0; i < Fields.Count; i++)
        {
            var type = Fields[i].Type;
            if (type is "number" or "choice" or "text" or "boolean")
                continue;
            errors.Add(RequestInvalid.Error("literal_error", "Input should be 'number', 'choice', 'text' or 'boolean'", type,
                "body", "fields", i.ToString(), "type"));
        }
    }
}

public sealed record DemographicsFormOut(IReadOnlyList<DemographicsField> Fields, int Version, DateTime PublishedAt);

public sealed record DemographicsAnswersIn(JsonObject Answers);

public sealed record DemographicsAnswersOut(int FormVersion, JsonObject Answers, DateTime UpdatedAt);

public sealed record ParticipantMeOut(string Code, int StudyId, ReadinessOut Readiness, ConsentOut? Consent);

/// <summary>Researcher/analyst view: research code and research data only, never the login email.</summary>
public sealed record ParticipantCodedOut(string Code, ReadinessOut Readiness, ConsentOut? Consent, ProfileOut? Profile, DemographicsAnswersOut? Demographics);

public sealed record IdentityOut(string Email);

public sealed record StudyIn(string Name) : IValidatedBody
{
    public void Validate(List<JsonObject> errors)
    {
        Check.MinLength(errors, Name, "name", 1);
        Check.MaxLength(errors, Name, "name", 200);
    }
}

public sealed record StudyOut(int Id, string Name);

public sealed record UserIn(string Email, string Password, string Role) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Literal(errors, Role, "role", "researcher", "analyst", "admin");
}

public sealed record UserOut(int Id, string Email, string Role);

public sealed record MemberIn(int UserId, string StudyRole, bool CanLinkIdentity = false) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Literal(errors, StudyRole, "study_role", "researcher", "analyst");
}

public sealed record MemberOut(int UserId, string StudyRole, bool CanLinkIdentity, int StudyId);

public sealed record InvitationIn(string? InviteeEmail = null, int ExpiresDays = 14);

public sealed record InvitationOut(string Token, string Code, DateTime ExpiresAt);

/// <summary>Domain -> response mapping kept in one place so coded views never leak identity fields.</summary>
public static class AccountMappers
{
    public static ConsentOut? Consent(Consent? c) =>
        c is null ? null : new(c.SheetVersion, c.Participate, c.AudioRecording, c.VideoRecording, c.GivenAt, c.WithdrawnAt);

    public static SheetOut Sheet(InformationSheet s) =>
        new(s.Aims, s.DiscomfortSources, s.Benefits, s.DataHandling, s.StopRules, s.Version, s.PublishedAt);

    public static ProfileOut? Profile(Profile? p) =>
        p is null ? null : new(p.DisplayName, p.ResponseMode.Value(), p.VoicePreference, p.FacePreference, p.Speed, [.. p.AccessibilityNeeds], [.. p.Interests]);

    public static DemographicsFormOut Form(DemographicsForm f) =>
        new(f.Fields.OfType<JsonObject>().Select(x => new DemographicsField(
            Json.Str(x["key"]) ?? "", Json.Str(x["label"]) ?? "", Json.Str(x["type"]) ?? "",
            x["options"] is JsonArray o ? o.Select(v => Json.Str(v) ?? v?.ToJsonString() ?? "").ToList() : null,
            Json.Bool(x["required"]))).ToList(), f.Version, f.PublishedAt);

    public static DemographicsAnswersOut? Answers(DemographicsAnswer? a) =>
        a is null ? null : new(a.FormVersion, Json.CloneObj(a.Answers), a.UpdatedAt);

    public static ReadinessOut Readiness(ParticipantView v) => new(v.Readiness.Ready, [.. v.Readiness.Reasons]);

    public static ParticipantCodedOut Coded(ParticipantView v) =>
        new(v.Participant.Code, Readiness(v), Consent(v.Consent), Profile(v.Profile), Answers(v.Demographics));

    /// <summary>The stored form field: pydantic's model_dump(exclude_none=True).</summary>
    public static JsonObject StoredField(DemographicsField f)
    {
        var o = new JsonObject { ["key"] = f.Key, ["label"] = f.Label, ["type"] = f.Type };
        if (f.Options is not null)
            o["options"] = new JsonArray(f.Options.Select(x => (JsonNode?)JsonValue.Create(x)).ToArray());
        o["required"] = f.Required;
        return o;
    }
}
