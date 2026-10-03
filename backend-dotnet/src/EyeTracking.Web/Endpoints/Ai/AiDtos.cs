using System.Text.Json.Nodes;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Ai;

// HTTP shapes of build step 5 (the pydantic models in backend/eyetracking/web/routers/ai.py).
// The responses are free-form JSON built by the use cases, except text-reviewed (ContentOut).

public sealed record BudgetIn(double? CostCapUnits = null, bool? SendFreeText = null);

public sealed record TextJobIn : IValidatedBody
{
    public int? AssignmentId { get; init; }
    public string? Topic { get; init; }
    public string? DisplayName { get; init; }
    public List<string>? Interests { get; init; }
    public int InteractionPoints { get; init; } = 2;
    public int LengthSeconds { get; init; } = 90;
    public string? Title { get; init; }
    public string FaceId { get; init; } = "";
    public string VoiceId { get; init; } = "";

    public void Validate(List<JsonObject> errors) => AiChecks.Strings(errors, Interests, "interests");
}

public sealed record VideoJobsIn(int ContentId, List<string>? SegmentIds = null, string? FaceId = null, string? VoiceId = null) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => AiChecks.Strings(errors, SegmentIds, "segment_ids");
}

internal static class AiChecks
{
    /// <summary>pydantic's <c>list[str]</c>: a null item is a <c>string_type</c> error at its position.</summary>
    public static void Strings(List<JsonObject> errors, List<string>? items, string field)
    {
        for (var i = 0; i < (items?.Count ?? 0); i++)
        {
            if (items![i] is null)
                errors.Add(RequestInvalid.Error("string_type", "Input should be a valid string", null, "body", field, i.ToString()));
        }
    }
}
