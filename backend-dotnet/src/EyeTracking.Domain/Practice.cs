using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace EyeTracking.Domain;

// Practice rules for build step 3 (backend/eyetracking/domain/practice.py): protocol definitions,
// content, assignments, trials and outcomes. The design's constraints live here: one factor changes
// per stage, the number never goes beyond the protocol's final zone, nothing advances on a wrong
// answer, discomfort or invalid data, and "improvement" needs all three outcomes at once.
// Definitions are free-form JSON; a value of the wrong JSON type fails like Python (a 500) where
// Python would raise AttributeError or TypeError instead of Invalid.

public partial class Protocol
{
    /// <summary>Python's <c>str(definition.get("path", ""))</c>.</summary>
    public string Path => PracticeRules.PyStr(PracticeRules.Get(Definition, "path", ""));

    public void EnsureDraft()
    {
        if (Status != ProtocolStatus.Draft)
            throw new Conflict("published protocol versions cannot be edited; create a new draft");
    }
}

public partial class ContentItem
{
    public void EnsureDraft()
    {
        if (Status != ContentStatus.Draft)
            throw new Conflict("approved content cannot be edited");
    }

    /// <summary>Every media key the segments name, in order (duplicates kept): <c>media_key</c> and
    /// the values of <c>question.reaction_media_key</c>.</summary>
    public List<string> MediaKeys()
    {
        var keys = new List<string>();
        foreach (var node in PracticeRules.Items(PracticeRules.Get(Definition, "segments", new JsonArray())))
        {
            var seg = PracticeRules.AsDict(node);
            if (Json.Truthy(seg["media_key"]))
                keys.Add(Key(seg["media_key"]));
            if (PracticeRules.OrEmpty(seg["question"])["reaction_media_key"] is JsonObject reactions)
            {
                foreach (var (_, k) in reactions)
                    keys.Add(Key(k));
            }
        }
        return keys;
    }

    // Python keeps any value here and fails later (sorting, joining, the response model); text only.
    private static string Key(JsonNode? n) => Json.Str(n) ?? throw new InvalidOperationException("media keys must be text");
}

public sealed record StageDecision(string Decision, string Reason, int? NextStageIndex, double? CorrectRatio, double InvalidShare, int Trials);

public static partial class PracticeRules
{
    public static readonly string[] Paths = ["gradual_face", "interest_conversation", "live_conversation"];
    public static readonly string[] Zones = ["outside", "face_edge", "near_eyes", "eye_region"];
    public static readonly string[] ResponseModes = ["number", "four_choice", "symbol", "profile"];
    public static readonly string[] AnswerKinds = ["interaction", "comprehension"];
    public static readonly string[] Decisions = ["advance", "hold", "easier", "stop", "complete"];
    public static readonly string[] MediaTypes = ["video/webm", "video/mp4", "image/png", "image/jpeg"];
    public const int MaxMediaBytes = 200 * 1024 * 1024;

    [GeneratedRegex(@"\{\{\s*(display_name|topic)\s*\}\}")]
    private static partial Regex TokenRegex();

    [GeneratedRegex(@"^[A-Za-z0-9._-]{1,120}$")]
    private static partial Regex SafeKeyRegex();

    // ---------- Python semantics for free-form JSON ----------

    /// <summary><c>d.get(key, default)</c>: the default only when the key is missing (JSON null is None).</summary>
    public static JsonNode? Get(JsonObject d, string key, JsonNode? @default = null) =>
        d.TryGetPropertyValue(key, out var value) ? value : @default;

    /// <summary>A value used as a dict; anything else fails like Python's AttributeError.</summary>
    public static JsonObject AsDict(JsonNode? n) => n as JsonObject ?? throw new InvalidOperationException("expected a JSON object");

    /// <summary><c>value or {}</c> used as a dict.</summary>
    public static JsonObject OrEmpty(JsonNode? n) => n switch
    {
        JsonObject o => o,
        _ when !Json.Truthy(n) => [],
        _ => throw new InvalidOperationException("expected a JSON object"),
    };

    /// <summary>The items of a value Python iterates (an empty dict or string has none); anything
    /// else fails like Python's TypeError, or later when an item is used as a dict.</summary>
    public static IEnumerable<JsonNode?> Items(JsonNode? n) => n switch
    {
        JsonArray a => a,
        _ when n is not null && !Json.Truthy(n) && n.GetValueKind() is JsonValueKind.Object or JsonValueKind.String => [],
        _ => throw new InvalidOperationException("expected a JSON list"),
    };

    /// <summary>A JSON number Python reads as an int (an integer literal, not <c>4.0</c>).</summary>
    public static bool IsIntLiteral(JsonNode? n) =>
        Json.IsNumber(n) && n!.ToJsonString().All(c => c is '-' or (>= '0' and <= '9'));

    /// <summary>Python's <c>isinstance(v, int)</c> (bool included) as a long; null otherwise.</summary>
    public static long? PyInt(JsonNode? n)
    {
        if (Json.IsBool(n))
            return Json.Truthy(n) ? 1 : 0;
        if (!IsIntLiteral(n))
            return null;
        return long.TryParse(n!.ToJsonString(), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var v)
            ? v
            : n.ToJsonString().StartsWith('-') ? long.MinValue : long.MaxValue;
    }

    /// <summary>Python's <c>int(v)</c> for a validated definition number (truncates).</summary>
    public static int IntOf(JsonNode? n) => n switch
    {
        _ when Json.IsBool(n) => Json.Truthy(n) ? 1 : 0,
        _ when Json.IsNumber(n) => (int)Math.Truncate(Json.Num(n)!.Value),
        _ => throw new InvalidOperationException($"int() argument must be a number, not {PyStr(n)}"),
    };

    /// <summary>Python's <c>float(v)</c> for a validated definition number.</summary>
    public static double FloatOf(JsonNode? n) => n switch
    {
        _ when Json.IsBool(n) => Json.Truthy(n) ? 1.0 : 0.0,
        _ when Json.IsNumber(n) => Json.Num(n)!.Value,
        _ => throw new InvalidOperationException($"float() argument must be a number, not {PyStr(n)}"),
    };

    /// <summary>Python's <c>str(v)</c> of a JSON scalar, as f-strings write it into messages.</summary>
    public static string PyStr(JsonNode? n)
    {
        if (n is null)
            return "None";
        switch (n.GetValueKind())
        {
            case JsonValueKind.String:
                return n.GetValue<string>();
            case JsonValueKind.True:
                return "True";
            case JsonValueKind.False:
                return "False";
            case JsonValueKind.Number:
                if (IsIntLiteral(n))
                    return n.ToJsonString() == "-0" ? "0" : n.ToJsonString();
                return Json.PythonFloat(Json.Num(n)!.Value);
            default:
                return n.ToJsonString();
        }
    }

    /// <summary>Python's <c>==</c> between JSON values (<c>1 == 1.0 == True</c>).</summary>
    public static bool PyEquals(JsonNode? a, JsonNode? b)
    {
        if (a is null || b is null)
            return a is null && b is null;
        var numeric = (Json.IsNumber(a) || Json.IsBool(a)) && (Json.IsNumber(b) || Json.IsBool(b));
        if (numeric)
            return (Json.IsBool(a) ? (Json.Truthy(a) ? 1 : 0) : Json.Num(a)) == (Json.IsBool(b) ? (Json.Truthy(b) ? 1 : 0) : Json.Num(b));
        return (a, b) switch
        {
            (JsonArray x, JsonArray y) => x.Count == y.Count && x.Zip(y).All(p => PyEquals(p.First, p.Second)),
            (JsonObject x, JsonObject y) => x.Count == y.Count && x.All(p => y.TryGetPropertyValue(p.Key, out var v) && PyEquals(p.Value, v)),
            _ => Json.Str(a) is { } s && s == Json.Str(b),
        };
    }

    /// <summary>Python's <c>x in a_set</c>: lists and dicts cannot be looked up (TypeError).</summary>
    private static bool InSet(JsonNode? n, ISet<string> set) => n switch
    {
        JsonArray or JsonObject => throw new InvalidOperationException("unhashable type"),
        _ => Json.Str(n) is { } s && set.Contains(s),
    };

    // ---------- protocol validation ----------

    private static double Num(JsonObject d, string key, int lo, int hi, string where)
    {
        var v = d[key];
        if (!Json.IsNumber(v) || !(lo <= Json.Num(v) && Json.Num(v) <= hi))
            throw new Invalid($"{where}.{key} must be a number between {lo} and {hi}");
        return Json.Num(v)!.Value;
    }

    public static void ValidateProtocol(JsonObject? definition)
    {
        if (definition is null)
            throw new Invalid("definition must be an object");
        var path = Json.Str(definition["path"]);
        if (path is null || !Paths.Contains(path))
            throw new Invalid($"path must be one of {MeasurementRules.TupleText(Paths)}");
        Num(definition, "baseline_seconds", 10, 600, "definition");
        Num(definition, "post_seconds", 10, 600, "definition");
        var comfort = OrEmpty(definition["comfort"]);
        var scaleMax = (int)Num(comfort, "scale_max", 3, 7, "comfort");
        var labels = comfort["labels"] as JsonArray;
        if (labels is null || labels.Count != scaleMax || !labels.All(x => Json.Str(x) is { } s && s.Trim().Length > 0))
            throw new Invalid("comfort.labels must have one non-empty label per scale value");
        Num(comfort, "min_ok", 1, scaleMax, "comfort");
        var progression = OrEmpty(definition["progression"]);
        Num(progression, "hold_on_invalid_share_above", 0, 1, "progression");
        foreach (var key in new[] { "easier_on_comfort_below_min", "stop_on_two_low_comfort" })
        {
            if (!Json.IsBool(Get(progression, key, true)))
                throw new Invalid($"progression.{key} must be true or false");
        }
        if (path == "gradual_face")
        {
            if (definition["gradual"] is not JsonObject g)
                throw new Invalid("gradual settings are required for the gradual_face path");
            var limit = Json.Str(Get(g, "final_zone_limit", "near_eyes"));
            if (limit is null || !Zones.Contains(limit))
                throw new Invalid($"gradual.final_zone_limit must be one of {MeasurementRules.TupleText(Zones)}");
            if (g["stages"] is not JsonArray stages || !(1 <= stages.Count && stages.Count <= 20))
                throw new Invalid("gradual.stages must hold 1 to 20 stages");
            var simultaneous = Json.Truthy(Get(g, "allow_simultaneous_change", false));
            (int Level, string Zone)? prev = null;
            for (var i = 0; i < stages.Count; i++)
            {
                var where = $"gradual.stages[{i}]";
                var st = AsDict(stages[i]);
                var level = (int)Num(st, "face_level", 0, 3, where);
                var zone = Json.Str(st["number_zone"]);
                if (zone is null || !Zones.Contains(zone))
                    throw new Invalid($"{where}.number_zone must be one of {MeasurementRules.TupleText(Zones)}");
                if (Array.IndexOf(Zones, zone) > Array.IndexOf(Zones, limit))
                    throw new Invalid($"{where}.number_zone goes beyond final_zone_limit {limit}");
                Num(st, "trials", 1, 50, where);
                Num(st, "min_correct", 0, 1, where);
                Num(st, "trial_seconds", 2, 60, where);
                var mode = Json.Str(Get(st, "response_mode", "profile"));
                if (mode is null || !ResponseModes.Contains(mode))
                    throw new Invalid($"{where}.response_mode must be one of {MeasurementRules.TupleText(ResponseModes)}");
                if (prev is { } p)
                {
                    if (level < p.Level || Array.IndexOf(Zones, zone) < Array.IndexOf(Zones, p.Zone))
                        throw new Invalid($"{where} must not go back in face_level or number_zone");
                    var changed = (level != p.Level ? 1 : 0) + (zone != p.Zone ? 1 : 0);
                    if (changed > 1 && !simultaneous)
                        throw new Invalid($"{where} changes both face_level and number_zone; allow_simultaneous_change is off");
                }
                prev = (level, zone);
            }
        }
        else if (path == "live_conversation")
        {
            LiveRules.ValidateLive(definition["live"]);
        }
        else
        {
            if (definition["interest"] is not JsonObject it)
                throw new Invalid("interest settings are required for the interest_conversation path");
            Num(it, "interaction_points", 0, 5, "interest");
        }
    }

    // ---------- content validation and personalization ----------

    /// <summary>Python's <c>isinstance(v, (int, float)) and 0 &lt;= v &lt;= 1</c> (a bool counts as 0 or 1).</summary>
    private static bool IsFraction(JsonNode? v)
    {
        double? d = Json.IsBool(v) ? (Json.Truthy(v) ? 1 : 0) : Json.Num(v);
        return d is { } x && 0 <= x && x <= 1;
    }

    private static bool IsQuestion(JsonObject q) =>
        Json.Str(q["id"]) is not null && Json.Truthy(q["prompt"]) && q["options"] is JsonArray { Count: >= 2 };

    public static void ValidateContent(JsonObject? definition)
    {
        if (definition is null)
            throw new Invalid("definition must be an object");
        if (definition["segments"] is not JsonArray { Count: > 0 } segments)
            throw new Invalid("content needs at least one segment");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        for (var i = 0; i < segments.Count; i++)
        {
            var seg = AsDict(segments[i]);
            var sid = Json.Str(seg["id"]);
            if (sid is null || sid.Trim().Length == 0)
                throw new Invalid($"segments[{i}].id is required");
            if (!ids.Add(sid))
                throw new Invalid($"duplicate segment id {sid}");
            if (Json.Str(Get(seg, "text", "")) is null)
                throw new Invalid($"segment {sid}: text must be a string");
            Num(seg, "duration_s", 1, 900, $"segment {sid}");
            var layout = seg["face_layout"];
            if (layout is not null)
            {
                foreach (var key in new[] { "face_box", "eye_region", "mouth_region" })
                {
                    var box = AsDict(layout)[key];
                    if (box is not JsonArray { Count: 4 } b || !b.All(IsFraction))
                        throw new Invalid($"segment {sid}: face_layout.{key} must be four numbers between 0 and 1");
                }
            }
        }
        foreach (var node in segments)
        {
            var seg = AsDict(node);
            var segId = Json.Str(seg["id"]);
            if (seg["question"] is not { } qn)
                continue;
            var q = AsDict(qn);
            if (!IsQuestion(q))
                throw new Invalid($"segment {segId}: question needs id, prompt and at least two options");
            var options = (JsonArray)q["options"]!;
            // branches = q.get("branches") or {}; then set(branches) - set(options)
            var branches = Json.Truthy(q["branches"]) ? q["branches"] as JsonObject : [];
            if (branches is null)
                throw new Invalid($"segment {segId}: branches must map options to segment ids");
            if (options.Any(o => o is JsonArray or JsonObject))
                throw new InvalidOperationException("unhashable type");
            if (branches.Any(b => !options.Any(o => Json.Str(o) == b.Key)))
                throw new Invalid($"segment {segId}: branches must map options to segment ids");
            foreach (var (opt, target) in branches)
            {
                if (!InSet(target, ids))
                    throw new Invalid($"segment {segId}: branch {opt} points to unknown segment {PyStr(target)}");
            }
        }
        if (!InSet(definition["start_segment"], ids))
            throw new Invalid("start_segment must name an existing segment");
        var post = definition["post_segment"];
        if (post is not null && !InSet(post, ids))
            throw new Invalid("post_segment must name an existing segment");
        var comprehension = Json.Truthy(Get(definition, "comprehension", new JsonArray())) ? definition["comprehension"] : new JsonArray();
        var index = 0;
        foreach (var node in Items(comprehension))
        {
            var c = AsDict(node);
            if (!IsQuestion(c))
                throw new Invalid($"comprehension[{index}] needs id, prompt and at least two options");
            if (!((JsonArray)c["options"]!).Any(o => PyEquals(o, c["correct"])))
                throw new Invalid($"comprehension[{index}].correct must be one of its options");
            index++;
        }
    }

    public static string Personalize(string? text, string? displayName, string? topic)
    {
        var name = string.IsNullOrEmpty(displayName) ? "there" : displayName;
        var about = string.IsNullOrEmpty(topic) ? "your topic" : topic;
        return TokenRegex().Replace(text ?? "", m => m.Groups[1].Value == "display_name" ? name : about);
    }

    /// <summary><see cref="Personalize(string?, string?, string?)"/> of a definition value: falsy is "",
    /// anything but text fails like Python's TypeError.</summary>
    public static string Personalize(JsonNode? text, string? displayName, string? topic)
    {
        if (!Json.Truthy(text))
            return Personalize("", displayName, topic);
        return Personalize(Json.Str(text) ?? throw new InvalidOperationException("expected string"), displayName, topic);
    }

    /// <summary>The options as shown (personalized) to the original option; a later duplicate wins.</summary>
    private static Dictionary<string, JsonNode?> Shown(JsonObject q, string? displayName, string? topic)
    {
        var shown = new Dictionary<string, JsonNode?>(StringComparer.Ordinal);
        foreach (var o in Items(q["options"]))
            shown[Personalize(o, displayName, topic)] = o;
        return shown;
    }

    /// <summary>Options are matched after personalization, exactly as the participant saw them.</summary>
    public static string? NextSegment(JsonObject definition, string segmentId, string option, string? displayName = null, string? topic = null)
    {
        var seg = Items(Get(definition, "segments", new JsonArray())).Select(AsDict).FirstOrDefault(s => PyEquals(s["id"], segmentId))
            ?? throw new Invalid("unknown segment");
        if (seg["question"] is not { } qn)
            throw new Invalid("this segment has no question");
        var q = AsDict(qn);
        var shown = Shown(q, displayName, topic);
        if (!shown.TryGetValue(option, out var original))
            throw new Invalid("option is not one of the question's options");
        var target = Json.Str(original) is { } key ? OrEmpty(q["branches"])[key] : null;
        return target is null ? null : Json.Str(target) ?? PyStr(target);
    }

    public static bool ComprehensionCorrect(JsonObject definition, string questionId, string option, string? displayName = null, string? topic = null)
    {
        var q = Items(Get(definition, "comprehension", new JsonArray())).Select(AsDict).FirstOrDefault(c => PyEquals(c["id"], questionId))
            ?? throw new Invalid("unknown comprehension question");
        var shown = Shown(q, displayName, topic);
        if (!shown.TryGetValue(option, out var original))
            throw new Invalid("option is not one of the question's options");
        return PyEquals(original, q["correct"]);
    }

    /// <summary>Python keeps this rule next to the media store (infrastructure/media.py); the upload
    /// use case needs it, so it lives here.</summary>
    public static string SafeKey(string? key)
    {
        if (key is null || !SafeKeyRegex().IsMatch(key) || key.StartsWith('.'))
            throw new Invalid("media key may only contain letters, digits, dot, dash and underscore");
        return key;
    }

    // ---------- stage progression ----------

    /// <summary>Never advance on wrong answers, discomfort or invalid data; that is the design's rule.</summary>
    public static StageDecision EvaluateStage(JsonObject definition, int stageIndex, IReadOnlyList<Trial> trials, int? comfortValue, double invalidShare, int lowComfortStreak)
    {
        var stages = (JsonArray)AsDict(definition["gradual"])["stages"]!;
        if (!(0 <= stageIndex && stageIndex < stages.Count))
            throw new Invalid("stage_index is out of range for this protocol");
        var stage = AsDict(stages[stageIndex]);
        var comfort = AsDict(Get(definition, "comfort", new JsonObject()));
        var progression = AsDict(Get(definition, "progression", new JsonObject()));
        var n = trials.Count;
        double? ratio = n > 0 ? (double)trials.Count(t => t.Correct) / n : null;
        var isLast = stageIndex == stages.Count - 1;

        StageDecision Result(string decision, string reason, int? next) => new(decision, reason, next, ratio, invalidShare, n);

        if (comfortValue is { } value && value < IntOf(Get(comfort, "min_ok", 3)))
        {
            if (lowComfortStreak >= 1 && Json.Truthy(Get(progression, "stop_on_two_low_comfort", true)))
                return Result("stop", "low_comfort_twice", null);
            if (Json.Truthy(Get(progression, "easier_on_comfort_below_min", true)) && stageIndex > 0)
                return Result("easier", "low_comfort", stageIndex - 1);
            return Result("hold", "low_comfort", stageIndex);
        }
        if (invalidShare > FloatOf(Get(progression, "hold_on_invalid_share_above", 0.3)))
            return Result("hold", "invalid_data", stageIndex);
        if (n < IntOf(stage["trials"]))
            return Result("hold", "incomplete", stageIndex);
        if (ratio is null || ratio < FloatOf(stage["min_correct"]))
            return Result("hold", "accuracy", stageIndex);
        if (isLast)
            return Result("complete", "all_stages_done", null);
        return Result("advance", "criteria_met", stageIndex + 1);
    }

    // ---------- outcomes ----------

    public static JsonObject ComfortOutcome(IReadOnlyList<long> values, int minOk, int pauses, bool endedEarly)
    {
        JsonNode? mean = null;
        if (values.Count > 0)
        {
            // statistics.mean of ints is an int when it divides evenly, and round() keeps it an int
            var sum = values.Sum();
            mean = sum % values.Count == 0 ? JsonValue.Create(sum / values.Count) : Json.Float(PyMath.Round((double)sum / values.Count, 2));
        }
        return new JsonObject
        {
            ["answers"] = values.Count,
            ["min"] = values.Count > 0 ? values.Min() : null,
            ["mean"] = mean,
            ["low_count"] = values.Count(v => v < minOk),
            ["pauses"] = pauses,
            ["ended_early"] = endedEarly,
        };
    }

    public static JsonObject Improvement(
        JsonObject gaze, JsonObject comprehension, JsonObject numberTask, IReadOnlyList<long> comfortValues, int minOk, string? path, JsonObject? conversation = null)
    {
        var criteria = new JsonObject { ["eye_share_up"] = null, ["comfort_not_worse"] = null, ["comprehension_maintained"] = null };
        static JsonObject No(JsonObject criteria, JsonNode? reason) =>
            new() { ["eligible"] = false, ["result"] = null, ["criteria"] = criteria, ["reason"] = reason };
        if (!Json.Truthy(gaze["evaluable"]))
            return No(criteria, Json.Truthy(gaze["reason"]) ? gaze["reason"]!.DeepClone() : "gaze_not_evaluable");
        var b = Json.Num(gaze["baseline_eye_share"]);
        var p = Json.Num(gaze["post_eye_share"]);
        if (b is null || p is null)
            return No(criteria, "baseline_or_post_missing");
        criteria["eye_share_up"] = p > b;
        if (comfortValues.Count == 0)
            return No(criteria, "no_comfort_answers");
        criteria["comfort_not_worse"] = comfortValues[^1] >= comfortValues[0] && comfortValues[^1] >= minOk;
        double? share;
        if (path == "interest_conversation")
        {
            share = Json.Num(comprehension["share"]);
            criteria["comprehension_maintained"] = share is null ? null : share >= 0.5;
        }
        else if (path == "live_conversation")
        {
            var conv = conversation ?? [];
            share = Json.Num(conv["on_topic_share"]);
            var enough = (Json.Truthy(conv["participant_turns"]) ? Json.Num(conv["participant_turns"]) : 0) >= 2;
            criteria["comprehension_maintained"] = share is null || !enough ? null : share >= 0.5;
        }
        else
        {
            share = Json.Num(numberTask["share"]);
            criteria["comprehension_maintained"] = share is null ? null : share >= 0.5;
        }
        if (criteria["comprehension_maintained"] is null)
            return No(criteria, "no_content_responses");
        var result = criteria.All(c => Json.Truthy(c.Value));
        return new JsonObject { ["eligible"] = true, ["result"] = result, ["criteria"] = criteria, ["reason"] = null };
    }
}
