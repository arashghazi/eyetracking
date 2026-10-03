using System.Globalization;
using System.Text.Json.Nodes;

namespace EyeTracking.Domain;

// AI content generation rules for build step 5 (backend/eyetracking/domain/ai.py): jobs, budget,
// prompts and sample content. The provider is swappable; nothing generated reaches a participant
// without review, approval and explicit attachment. Only the topic, display name, interests and
// constraints are sent to a provider; never the camera image, the login email or gaze data.

public partial class AiBudget
{
    public double Remaining() => Math.Max(0.0, CostCapUnits - SpentUnits);

    /// <summary>A paid job needs an admin-set cap that it fits under; free providers always pass.</summary>
    public void AssertAffordable(double estimate)
    {
        if (estimate <= 0)
            return;
        if (SpentUnits + estimate > CostCapUnits + 1e-9)
            throw new Invalid($"budget_exceeded: estimate {AiRules.Fixed3(estimate)} + spent {AiRules.Fixed3(SpentUnits)} exceeds cap {AiRules.Fixed3(CostCapUnits)}");
    }
}

public partial class GenerationJob
{
    public void Cancel()
    {
        if (Status != "queued")
            throw new Conflict("only queued jobs can be cancelled");
        Status = "cancelled";
    }

    public void Retry(DateTime now)
    {
        if (Status != "failed")
            throw new Conflict("only failed jobs can be retried");
        Status = "queued";
        Error = null;
        NextAttemptAt = now;
    }

    /// <summary>Counts the attempt; a terminal failure or the last attempt fails the job, anything
    /// else queues it again after a backoff.</summary>
    public void MarkFailure(string message, DateTime now, bool terminal = false)
    {
        Attempts += 1;
        Error = AiRules.Head(message, 1000);
        if (terminal || Attempts >= MaxAttempts)
        {
            Status = "failed";
            FinishedAt = now;
        }
        else
        {
            Status = "queued";
            NextAttemptAt = now.AddSeconds(AiRules.BackoffSeconds(Attempts));
        }
    }
}

/// <summary>What a text provider receives (TextRequest in ai.py): the topic, the name to use, the
/// interests and the shape of the script. Free text only when the study allows it.</summary>
public sealed record TextRequest(
    string Topic, string? DisplayName, IReadOnlyList<string> Interests, int InteractionPoints, int LengthSeconds, string? FreeText = null)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(Topic) || Topic.EnumerateRunes().Count() > 200)
            throw new Invalid("topic is required (up to 200 characters)");
        if (!(0 <= InteractionPoints && InteractionPoints <= 5))
            throw new Invalid("interaction_points must be between 0 and 5");
        if (!(30 <= LengthSeconds && LengthSeconds <= 600))
            throw new Invalid("length_seconds must be between 30 and 600");
    }

    /// <summary>What the job keeps of the request: the free text itself is never stored on the job.</summary>
    public JsonObject Minimized() => new()
    {
        ["topic"] = Topic,
        ["display_name"] = DisplayName,
        ["interests"] = Json.Array(Interests),
        ["interaction_points"] = InteractionPoints,
        ["length_seconds"] = LengthSeconds,
        ["free_text_included"] = FreeText is not null,
    };
}

public static class AiRules
{
    public static readonly string[] JobKinds = ["text", "video"];
    public static readonly string[] JobStatuses = ["queued", "running", "succeeded", "failed", "cancelled"];
    public const int MaxAttempts = 3;
    public const string SampleMark = "[Sample content from the development provider]";

    public static double BackoffSeconds(int attempts) => 30 * Math.Pow(2, Math.Max(0, attempts - 1));

    /// <summary>Python's <c>text[:n]</c> (code points, not UTF-16 units).</summary>
    public static string Head(string text, int n) =>
        string.Concat(text.EnumerateRunes().Take(n).Select(r => r.ToString()));

    /// <summary>Python's <c>f"{v:.3f}"</c>: the exact binary value rounded half-to-even.</summary>
    public static string Fixed3(double v) => PyMath.Round(v, 3).ToString("F3", CultureInfo.InvariantCulture);

    // CONTENT_SCHEMA, as json.dumps writes it (keys in the same order)
    private const string ContentSchemaJson = """
        {"type": "object", "additionalProperties": false, "required": ["title", "start_segment", "post_segment", "segments", "comprehension"],
         "properties": {"title": {"type": "string"}, "start_segment": {"type": "string"}, "post_segment": {"type": "string"},
          "segments": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["id", "text", "duration_s", "question"],
           "properties": {"id": {"type": "string"}, "text": {"type": "string"}, "duration_s": {"type": "number"},
            "question": {"anyOf": [{"type": "null"}, {"type": "object", "additionalProperties": false, "required": ["id", "prompt", "options", "branches"],
             "properties": {"id": {"type": "string"}, "prompt": {"type": "string"}, "options": {"type": "array", "items": {"type": "string"}},
              "branches": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["option", "segment"],
               "properties": {"option": {"type": "string"}, "segment": {"type": "string"}}}}}}]}}}},
          "comprehension": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["id", "prompt", "options", "correct"],
           "properties": {"id": {"type": "string"}, "prompt": {"type": "string"}, "options": {"type": "array", "items": {"type": "string"}}, "correct": {"type": "string"}}}}}}
        """;

    /// <summary>The JSON schema the text model must answer in (a fresh copy each call).</summary>
    public static JsonObject ContentSchema() => JsonNode.Parse(ContentSchemaJson)!.AsObject();

    /// <summary>System and user prompts for a short, calm, age-respectful conversation script.</summary>
    public static (string System, string User) ScriptPrompt(TextRequest req)
    {
        const string system =
            "You write short spoken scripts for a research app that helps autistic young adults practise comfortable "
            + "attention to a speaker's face. The speaker is a friendly adult who talks about a topic the participant chose. "
            + "Rules: plain English, calm and respectful, no pressure to look, no medical claims, no personal questions, "
            + "no jokes at anyone's expense, no eye-contact instructions. Each segment is spoken by the speaker as one take. "
            + "Questions at segment ends are simple choices about the topic; every option must branch to an existing segment. "
            + "Comprehension questions are about facts the speaker said, with exactly one correct option. Return only the JSON.";
        var parts = new List<string>
        {
            $"Topic: {req.Topic}.",
            !string.IsNullOrEmpty(req.DisplayName) ? $"Address the participant as {req.DisplayName}." : "Do not use a name.",
            req.Interests.Count > 0 ? $"Their interests: {string.Join(", ", req.Interests)}." : "",
            $"Total spoken length about {req.LengthSeconds} seconds across the segments (each 10 to 60 seconds).",
            $"Include {req.InteractionPoints} question point(s) between segments, then a final segment with no question that also serves as post_segment.",
            "Segment ids: s1, s2, ...; question ids q1, q2, ...; comprehension ids c1, c2 (two questions).",
        };
        if (!string.IsNullOrEmpty(req.FreeText))
            parts.Add($"The participant added: {req.FreeText}");
        return (system, string.Join("\n", parts.Where(p => p.Length > 0)));
    }

    /// <summary>The model returns branches as a list of {option, segment}; the content format wants a mapping.</summary>
    public static JsonObject BranchesToDict(JsonObject definition)
    {
        var result = Json.CloneObj(definition);
        foreach (var node in PracticeRules.Items(PracticeRules.Get(result, "segments", new JsonArray())))
        {
            var q = PracticeRules.AsDict(node)["question"];
            if (Json.Truthy(q) && PracticeRules.AsDict(q)["branches"] is JsonArray branches)
            {
                var mapping = new JsonObject();
                foreach (var b in branches)
                {
                    var branch = PracticeRules.AsDict(b);
                    var option = Json.Str(Required(branch, "option")) ?? throw new InvalidOperationException("branch options must be text");
                    mapping[option] = Required(branch, "segment")?.DeepClone();
                }
                q!["branches"] = mapping;
            }
        }
        result.Remove("title");
        return result;
    }

    public static JsonObject AssignMediaKeys(JsonObject definition)
    {
        foreach (var node in PracticeRules.Items(PracticeRules.Get(definition, "segments", new JsonArray())))
        {
            var seg = PracticeRules.AsDict(node);
            seg["media_key"] = $"{PyText.Str(Required(seg, "id"))}.webm";
        }
        return definition;
    }

    /// <summary>Python's <c>d[key]</c>: a missing key fails (KeyError).</summary>
    private static JsonNode? Required(JsonObject d, string key) =>
        d.TryGetPropertyValue(key, out var value) ? value : throw new KeyNotFoundException($"'{key}'");

    /// <summary>Deterministic sample content for the development provider; visibly marked as a sample.</summary>
    public static JsonObject SampleScript(TextRequest req)
    {
        var name = string.IsNullOrEmpty(req.DisplayName) ? "there" : req.DisplayName;
        var topic = req.Topic;
        var segments = new JsonArray
        {
            new JsonObject
            {
                ["id"] = "s1",
                ["text"] = $"{SampleMark} Hi {name}. Today I would like to talk with you about {topic}. I find it interesting because there is always something new to notice.",
                ["duration_s"] = 20,
                ["question"] = new JsonObject
                {
                    ["id"] = "q1",
                    ["prompt"] = $"What would you like to hear about {topic} first?",
                    ["options"] = new JsonArray("How it started", "What people enjoy about it"),
                    ["branches"] = new JsonObject { ["How it started"] = "s2", ["What people enjoy about it"] = "s2" },
                },
            },
            new JsonObject
            {
                ["id"] = "s2",
                ["text"] = $"{SampleMark} Thank you for choosing. Many people say the best part of {topic} is sharing it with someone else. It can be quiet or lively, and both are fine.",
                ["duration_s"] = 20,
                ["question"] = null,
            },
            new JsonObject
            {
                ["id"] = "s3",
                ["text"] = $"{SampleMark} That is all for today, {name}. Thank you for listening. You can stop here or come back another time.",
                ["duration_s"] = 12,
                ["question"] = null,
            },
        };
        if (req.InteractionPoints >= 2)
        {
            segments[1]!["question"] = new JsonObject
            {
                ["id"] = "q2",
                ["prompt"] = "Would you like one more short part?",
                ["options"] = new JsonArray("Yes", "No"),
                ["branches"] = new JsonObject { ["Yes"] = "s3", ["No"] = "s3" },
            };
        }
        var definition = new JsonObject
        {
            ["start_segment"] = "s1",
            ["post_segment"] = "s3",
            ["segments"] = segments,
            ["comprehension"] = new JsonArray
            {
                new JsonObject { ["id"] = "c1", ["prompt"] = "What was the conversation about?", ["options"] = new JsonArray(topic, "The weather"), ["correct"] = topic },
                new JsonObject
                {
                    ["id"] = "c2", ["prompt"] = "What did the speaker say is the best part?",
                    ["options"] = new JsonArray("Sharing it with someone", "Doing it alone"), ["correct"] = "Sharing it with someone",
                },
            },
        };
        return AssignMediaKeys(definition);
    }
}
