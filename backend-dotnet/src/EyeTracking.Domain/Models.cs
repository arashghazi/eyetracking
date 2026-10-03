using System.Text.Json;
using System.Text.Json.Nodes;

namespace EyeTracking.Domain;

// Framework-free entities and rules for build step 1.
//
// Identity (login email) and research code are deliberately separate objects:
// User holds the login identity, Participant holds the research code and all
// research data hangs off the participant, never off the user.

public enum Role { Participant, Researcher, Analyst, Admin }

public enum StudyRole { Researcher, Analyst }

public enum ResponseMode { Keyboard, Touch, FourChoice, Symbol }

public static class RetentionPolicies
{
    public const string DeleteAll = "delete_all";
    public const string KeepCoded = "keep_coded";
    public static readonly string[] All = [DeleteAll, KeepCoded];
}

public class User
{
    public int Id { get; set; }
    public string Email { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public Role Role { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class Study
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public string RetentionPolicy { get; set; } = RetentionPolicies.DeleteAll;
}

public class StudyMembership
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public int UserId { get; set; }
    public StudyRole StudyRole { get; set; }
    public bool CanLinkIdentity { get; set; }
}

public class Participant
{
    public int Id { get; set; }
    public string Code { get; set; } = "";
    public int StudyId { get; set; }
    public int UserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class Invitation
{
    public int Id { get; set; }
    public string Token { get; set; } = "";
    public int StudyId { get; set; }
    public string Code { get; set; } = "";
    public int CreatedBy { get; set; }
    public DateTime ExpiresAt { get; set; }
    public string? InviteeEmail { get; set; }
    public DateTime? UsedAt { get; set; }

    public bool IsUsable(DateTime now) => UsedAt is null && now < ExpiresAt;
}

/// <summary>The three mandatory sections come from the reviewer's comment 9.</summary>
public class InformationSheet
{
    public int Id { get; set; }
    public int StudyId { get; set; }
    public int Version { get; set; }
    public string Aims { get; set; } = "";
    public string DiscomfortSources { get; set; } = "";
    public string Benefits { get; set; } = "";
    public string DataHandling { get; set; } = "";
    public string StopRules { get; set; } = "";
    public DateTime PublishedAt { get; set; } = DateTime.UtcNow;

    public void Validate()
    {
        var missing = new (string Name, string Value)[]
            {
                ("aims", Aims), ("discomfort_sources", DiscomfortSources), ("benefits", Benefits),
                ("data_handling", DataHandling), ("stop_rules", StopRules),
            }
            .Where(s => string.IsNullOrWhiteSpace(s.Value))
            .Select(s => s.Name)
            .ToList();
        if (missing.Count > 0)
            throw new Invalid($"information sheet is missing required sections: {string.Join(", ", missing)}");
    }
}

public class Consent
{
    public int Id { get; set; }
    public int ParticipantId { get; set; }
    public int SheetVersion { get; set; }
    public bool Participate { get; set; }
    public bool AudioRecording { get; set; }
    public bool VideoRecording { get; set; }
    public DateTime GivenAt { get; set; } = DateTime.UtcNow;
    public DateTime? WithdrawnAt { get; set; }

    public bool IsActiveFor(int sheetVersion) => Participate && WithdrawnAt is null && SheetVersion == sheetVersion;
}

public class Profile
{
    public int Id { get; set; }
    public int ParticipantId { get; set; }
    public string? DisplayName { get; set; }
    public ResponseMode ResponseMode { get; set; } = ResponseMode.Touch;
    public string? VoicePreference { get; set; }
    public string? FacePreference { get; set; }
    public string Speed { get; set; } = "normal";
    public List<string> AccessibilityNeeds { get; set; } = [];
    public List<string> Interests { get; set; } = [];
}

/// <summary>Configurable per study; answers are stored under the research code.</summary>
public class DemographicsForm
{
    public static readonly string[] FieldTypes = ["boolean", "choice", "number", "text"];

    public int Id { get; set; }
    public int StudyId { get; set; }
    public int Version { get; set; }
    public JsonArray Fields { get; set; } = [];
    public DateTime PublishedAt { get; set; } = DateTime.UtcNow;

    private IEnumerable<JsonObject> FieldObjects => Fields.OfType<JsonObject>();

    public void Validate()
    {
        var keys = new HashSet<string>();
        foreach (var f in Fields)
        {
            var key = f is JsonObject o ? o["key"] : null;
            if (key is not JsonValue kv || kv.GetValueKind() != JsonValueKind.String || string.IsNullOrEmpty(kv.GetValue<string>()))
                throw new Invalid("every demographics field needs a string key");
            var name = kv.GetValue<string>();
            if (!keys.Add(name))
                throw new Invalid($"duplicate demographics field key: {name}");
            var type = Json.Str(f!["type"]);
            if (type is null || !FieldTypes.Contains(type))
                throw new Invalid($"field {name}: type must be one of ['boolean', 'choice', 'number', 'text']");
            if (type == "choice" && !Json.Truthy(f["options"]))
                throw new Invalid($"field {name}: choice fields need options");
        }
    }

    public void ValidateAnswers(JsonObject answers)
    {
        var known = FieldObjects.ToDictionary(f => Json.Str(f["key"])!, f => f);
        var unknown = answers.Select(a => a.Key).Where(k => !known.ContainsKey(k)).Order(StringComparer.Ordinal).ToList();
        if (unknown.Count > 0)
            throw new Invalid($"unknown demographics fields: {string.Join(", ", unknown)}");
        foreach (var (key, f) in known)
        {
            var value = answers[key];
            if (Json.IsBlank(value))
            {
                if (Json.Bool(f["required"]))
                    throw new Invalid($"field {key} is required");
                continue;
            }
            var kind = value!.GetValueKind();
            switch (Json.Str(f["type"]))
            {
                case "number" when kind != JsonValueKind.Number:
                    throw new Invalid($"field {key} must be a number");
                case "choice" when !(f["options"] as JsonArray ?? []).Any(o => JsonNode.DeepEquals(o, value)):
                    throw new Invalid($"field {key} must be one of its options");
                case "boolean" when kind is not (JsonValueKind.True or JsonValueKind.False):
                    throw new Invalid($"field {key} must be true or false");
                case "text" when kind != JsonValueKind.String:
                    throw new Invalid($"field {key} must be text");
            }
        }
    }

    public bool IsComplete(JsonObject? answers)
    {
        var required = FieldObjects.Where(f => Json.Bool(f["required"])).ToList();
        if (answers is null)
            return required.Count == 0;
        return required.All(f => !Json.IsBlank(answers[Json.Str(f["key"])!]));
    }
}

public class DemographicsAnswer
{
    public int Id { get; set; }
    public int ParticipantId { get; set; }
    public int FormVersion { get; set; }
    public JsonObject Answers { get; set; } = [];
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public sealed record Readiness(bool Ready, IReadOnlyList<string> Reasons);

public static class ReadinessRules
{
    public static Readiness Compute(InformationSheet? sheet, Consent? consent, DemographicsForm? form, DemographicsAnswer? answers)
    {
        var reasons = new List<string>();
        if (sheet is null)
            reasons.Add("no_information_sheet_published");
        else if (consent is null || !consent.IsActiveFor(sheet.Version))
            reasons.Add("consent_missing_or_outdated");
        if (form is not null && (answers is null || answers.FormVersion != form.Version || !form.IsComplete(answers.Answers)))
            reasons.Add("demographics_incomplete");
        return new Readiness(reasons.Count == 0, reasons);
    }
}
