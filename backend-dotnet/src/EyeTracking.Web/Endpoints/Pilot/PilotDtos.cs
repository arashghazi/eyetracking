using System.Globalization;
using System.Text.Json.Nodes;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Pilot;

// HTTP shapes of build step 6 (the pydantic models in backend/eyetracking/web/routers/pilot.py).
// The responses are free-form JSON built by the use cases; the tracker import is a multipart form
// (see PilotEndpoints.ImportForm). Free-form dicts and lists are read as JSON and checked here, so
// a wrong type gets pydantic's dict_type/list_type error.

public sealed record ObservationIn(string Category, string Text, string Severity = "info", int? TMs = null);

public sealed record DebriefFormIn(JsonNode? Questions = null, bool? Enabled = null) : IValidatedBody
{
    /// <summary>pydantic's <c>list[dict[str, Any]] | None</c>.</summary>
    public void Validate(List<JsonObject> errors)
    {
        if (Questions is null)
            return;
        if (Questions is not JsonArray items)
        {
            errors.Add(RequestInvalid.Error("list_type", "Input should be a valid list", null, "body", "questions"));
            return;
        }
        for (var i = 0; i < items.Count; i++)
        {
            if (items[i] is not JsonObject)
                errors.Add(RequestInvalid.Error("dict_type", "Input should be a valid dictionary", null, "body", "questions", i.ToString(CultureInfo.InvariantCulture)));
        }
    }
}

public sealed record DebriefAnswerIn(int FormVersion) : IValidatedBody
{
    public JsonNode? Answers { get; init; } = new JsonObject();
    public bool Skipped { get; init; }

    public void Validate(List<JsonObject> errors) => PilotChecks.Dict(errors, Answers, "answers");
}

public sealed record ThresholdReviewIn : IValidatedBody
{
    public JsonNode? Changes { get; init; } = new JsonObject();
    public bool IncludeSynthetic { get; init; }

    public void Validate(List<JsonObject> errors) => PilotChecks.Dict(errors, Changes, "changes");
}

internal static class PilotChecks
{
    /// <summary>pydantic's <c>dict[str, Any]</c> (null is not a dict either).</summary>
    public static void Dict(List<JsonObject> errors, JsonNode? value, string field)
    {
        if (value is not JsonObject)
            errors.Add(RequestInvalid.Error("dict_type", "Input should be a valid dictionary", null, "body", field));
    }
}
