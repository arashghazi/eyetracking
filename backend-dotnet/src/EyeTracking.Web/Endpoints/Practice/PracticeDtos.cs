using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Practice;

// HTTP shapes of build step 3 (the pydantic models in backend/eyetracking/web/routers/practice.py).
// Trials use the application's TrialInput record, which carries the request model's defaults.

public sealed record ProtocolIn(string Name, JsonObject Definition) : IValidatedBody
{
    public void Validate(List<JsonObject> errors)
    {
        Check.MinLength(errors, Name, "name", 1);
        Check.MaxLength(errors, Name, "name", 200);
    }
}

public sealed record ProtocolPatch(string? Name = null, JsonObject? Definition = null);

public sealed record ProtocolOut(int Id, string Name, int Version, string Status, string Path, DateTime CreatedAt, DateTime? PublishedAt, JsonObject? Definition = null)
{
    public static ProtocolOut From(Protocol p, bool withDefinition) =>
        new(p.Id, p.Name, p.Version, p.Status.Value(), p.Path, p.CreatedAt, p.PublishedAt, withDefinition ? Json.CloneObj(p.Definition) : null);
}

public sealed record ContentIn(string Title, JsonObject Definition) : IValidatedBody
{
    public List<string> TopicTags { get; init; } = [];
    public string FaceId { get; init; } = "";
    public string VoiceId { get; init; } = "";

    public void Validate(List<JsonObject> errors)
    {
        Check.MinLength(errors, Title, "title", 1);
        Check.MaxLength(errors, Title, "title", 200);
    }
}

public sealed record ContentPatch(
    string? Title = null,
    JsonObject? Definition = null,
    List<string>? TopicTags = null,
    string? FaceId = null,
    string? VoiceId = null);

public sealed record ContentOut(
    int Id,
    string Title,
    IReadOnlyList<string> TopicTags,
    string FaceId,
    string VoiceId,
    string Status,
    bool TextReviewed,
    IReadOnlyList<string> MediaKeys,
    IReadOnlyList<string> MissingMedia,
    JsonObject? Definition = null)
{
    public static ContentOut From(ContentItem c, IReadOnlyList<string> missing, bool withDefinition) =>
        new(c.Id, c.Title, [.. c.TopicTags], c.FaceId, c.VoiceId, c.Status.Value(), c.TextReviewed, c.MediaKeys(), missing,
            withDefinition ? Json.CloneObj(c.Definition) : null);
}

public sealed record AssignmentIn(int ProtocolId, int? OrderIndex = null);

public sealed record AssignmentPatch(int? ContentId = null, string? Status = null) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Literal(errors, Status, "status", "cancelled");
}

public sealed record TopicIn(string Topic, string? FreeText = null) : IValidatedBody
{
    public void Validate(List<JsonObject> errors)
    {
        Check.MinLength(errors, Topic, "topic", 1);
        Check.MaxLength(errors, Topic, "topic", 200);
    }
}

public sealed record TrialsIn(List<TrialInput> Trials) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Items(errors, Trials, "trials", min: 1, max: 200);
}

public sealed record StageResultIn(int StageIndex, int? ComfortValue = null);

public sealed record StageResultOut(string Decision, int? NextStageIndex, string Reason, double? CorrectRatio, double InvalidShare, int Trials);

public sealed record AnswerIn(string SegmentId, string QuestionId, string Kind, string Option, int TMs) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Literal(errors, Kind, "kind", "interaction", "comprehension");
}

public sealed record AnswerOut(bool? Correct, string? NextSegmentId);
