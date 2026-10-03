using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace EyeTracking.Domain;

// Supervised pilot rules for build step 6 (backend/eyetracking/domain/pilot.py): observations,
// debrief, threshold review and comparison with a research eye tracker. The settings version
// pieces came with step 2: measurement settings changes are versioned from the start.
// Nothing here changes a threshold on its own: the review only shows what a candidate would
// change, and a researcher decides. Agreement with a reference tracker describes one session on
// one computer; it is not a general accuracy claim.

public partial class Observation
{
    public void Validate()
    {
        if (!PilotRules.ObsCategories.Contains(Category))
            throw new Invalid("category must be one of " + string.Join(", ", PilotRules.ObsCategories));
        if (!PilotRules.ObsSeverities.Contains(Severity))
            throw new Invalid("severity must be one of " + string.Join(", ", PilotRules.ObsSeverities));
        Text = (Text ?? "").Trim();
        if (Text.Length == 0)
            throw new Invalid("observation text is required");
        if (Text.EnumerateRunes().Count() > PilotRules.MaxObservationChars)
            throw new Invalid($"observation text is limited to {PilotRules.MaxObservationChars} characters");
        if (TMs is < 0)
            throw new Invalid("t_ms must not be negative");
    }
}

/// <summary>One row of a tracker export: session time, CSS pixels (null when not valid), validity.</summary>
public readonly record struct ReferenceRow(long TMs, double? X, double? Y, bool Valid);

/// <summary>A webcam sample as the comparison reads it (Python's dict from _webcam_points).</summary>
public sealed record WebcamPoint(int TMs, double? X, double? Y, bool Valid, string Region, string Segment, int? LayoutId);

public static partial class PilotRules
{
    // ---------- supervisor observations ----------

    public static readonly string[] ObsCategories = ["comfort", "comprehension", "technical", "ux", "protocol", "other"];
    public static readonly string[] ObsSeverities = ["info", "minor", "major", "stop"];
    public const int MaxObservationChars = 2000;

    // ---------- settings versions ----------

    public static readonly string[] SettingsFields =
    [
        "validation_min_correct", "validation_max_uncertain", "min_region_to_error_ratio", "gaze_conf_threshold",
        "calibration_points", "allow_continue_without_validation", "quality_max_uncertain_share", "quality_max_missing_share",
    ];

    public const int MaxRationaleChars = 1000;

    /// <summary>The tunable values of a study's settings, keyed like <see cref="SettingsFields"/>.</summary>
    public static JsonObject SettingsValues(MeasurementSettings s) => new()
    {
        ["validation_min_correct"] = Json.Float(s.ValidationMinCorrect),
        ["validation_max_uncertain"] = Json.Float(s.ValidationMaxUncertain),
        ["min_region_to_error_ratio"] = Json.Float(s.MinRegionToErrorRatio),
        ["gaze_conf_threshold"] = Json.Float(s.GazeConfThreshold),
        ["calibration_points"] = s.CalibrationPoints,
        ["allow_continue_without_validation"] = s.AllowContinueWithoutValidation,
        ["quality_max_uncertain_share"] = Json.Float(s.QualityMaxUncertainShare),
        ["quality_max_missing_share"] = Json.Float(s.QualityMaxMissingShare),
    };

    /// <summary>MeasurementSettings.validate on candidate values kept as JSON. Python's setattr keeps
    /// what was sent (an int stays an int and prints as one), so the review works on the values as
    /// given: <c>float(v)</c> and <c>int(v)</c> where validate converts, plain comparisons elsewhere.
    /// Values Python cannot convert or compare fail like its ValueError/TypeError.</summary>
    public static void ValidateCandidate(JsonObject values)
    {
        foreach (var name in new[] { "validation_min_correct", "validation_max_uncertain", "gaze_conf_threshold", "quality_max_uncertain_share", "quality_max_missing_share" })
        {
            var v = PyFloat(values[name]);
            if (!(0.0 <= v && v <= 1.0))
                throw new Invalid($"{name} must be between 0 and 1");
        }
        if (PracticeRules.FloatOf(values["min_region_to_error_ratio"]) < 1.0)
            throw new Invalid("min_region_to_error_ratio must be at least 1");
        var points = PyText.IntOf(values["calibration_points"]);
        if (!(5 <= points && points <= 16))
            throw new Invalid("calibration_points must be between 5 and 16");
    }

    // ---------- debrief ----------

    public static readonly string[] QuestionTypes = ["scale", "yes_no", "choice", "text"];
    public const int MaxQuestions = 20;
    public const int MaxTextAnswer = 1000;
    private static readonly Regex KeyPattern = new("^[a-z][a-z0-9_]{0,39}$", RegexOptions.CultureInvariant);

    /// <summary>The questions a study starts with (a fresh copy per call).</summary>
    public static JsonArray DefaultDebriefQuestions() =>
    [
        new JsonObject
        {
            ["key"] = "instructions_clear", ["type"] = "scale", ["prompt"] = "How easy were the instructions to understand?", ["scale_max"] = 5,
            ["labels"] = new JsonArray("Very hard", "Hard", "OK", "Easy", "Very easy"), ["required"] = true,
        },
        new JsonObject
        {
            ["key"] = "comfort_overall", ["type"] = "scale", ["prompt"] = "How comfortable did you feel during the session?", ["scale_max"] = 5,
            ["labels"] = new JsonArray("Very uncomfortable", "Uncomfortable", "Neutral", "Comfortable", "Very comfortable"), ["required"] = true,
        },
        new JsonObject { ["key"] = "anything_uncomfortable", ["type"] = "yes_no", ["prompt"] = "Was anything uncomfortable or upsetting?", ["required"] = false },
        new JsonObject { ["key"] = "uncomfortable_detail", ["type"] = "text", ["prompt"] = "If something was uncomfortable, what was it? (optional)", ["required"] = false },
        new JsonObject { ["key"] = "camera_setup_easy", ["type"] = "yes_no", ["prompt"] = "Was setting up the camera easy?", ["required"] = false },
        new JsonObject { ["key"] = "one_change", ["type"] = "text", ["prompt"] = "If you could change one thing, what would it be? (optional)", ["required"] = false },
    ];

    public static JsonArray ValidateDebriefQuestions(JsonNode? questions)
    {
        if (questions is not JsonArray list || list.Count is < 1 or > MaxQuestions)
            throw new Invalid($"a debrief form needs 1 to {MaxQuestions} questions");
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var output = new JsonArray();
        for (var i = 0; i < list.Count; i++)
        {
            var where = $"questions[{i}]";
            if (list[i] is not JsonObject q)
                throw new Invalid($"{where} must be an object");
            var key = Json.Truthy(q["key"]) ? PyText.Str(q["key"]) : "";
            if (!KeyPattern.IsMatch(key))
                throw new Invalid($"{where}.key must start with a letter and use a-z, 0-9 or _ (max 40)");
            if (!seen.Add(key))
                throw new Invalid($"{where}.key '{key}' is used twice");
            var qtype = Json.Str(q["type"]);
            if (qtype is null || !QuestionTypes.Contains(qtype))
                throw new Invalid($"{where}.type must be one of " + string.Join(", ", QuestionTypes));
            var prompt = (Json.Truthy(q["prompt"]) ? PyText.Str(q["prompt"]) : "").Trim();
            if (prompt.Length == 0 || prompt.EnumerateRunes().Count() > 300)
                throw new Invalid($"{where}.prompt is required (max 300 characters)");
            var clean = new JsonObject
            {
                ["key"] = key, ["type"] = qtype, ["prompt"] = prompt,
                ["required"] = q.TryGetPropertyValue("required", out var required) && Json.Truthy(required),
            };
            if (qtype == "scale")
            {
                var smax = q.TryGetPropertyValue("scale_max", out var given) ? given : 5;
                if (!PyText.IsIntLiteral(smax) || PracticeRules.PyInt(smax) is not (>= 2 and <= 10))
                    throw new Invalid($"{where}.scale_max must be a whole number from 2 to 10");
                var labels = Json.Truthy(q["labels"]) ? PyIter(q["labels"]).ToList() : [];
                if (labels.Count > 0 && (labels.Count != PracticeRules.PyInt(smax) || !labels.All(IsText)))
                    throw new Invalid($"{where}.labels must have one text per scale point");
                clean["scale_max"] = smax!.DeepClone();
                clean["labels"] = new JsonArray(labels.Select(x => (JsonNode?)Json.Str(x)!.Trim()).ToArray());
            }
            else if (qtype == "choice")
            {
                var options = Json.Truthy(q["options"]) ? PyIter(q["options"]).ToList() : [];
                if (options.Count is < 2 or > 10 || !options.All(IsText))
                    throw new Invalid($"{where}.options needs 2 to 10 texts");
                if (options.Select(x => Json.Str(x)!.Trim()).Distinct(StringComparer.Ordinal).Count() != options.Count)
                    throw new Invalid($"{where}.options must be different");
                clean["options"] = new JsonArray(options.Select(x => (JsonNode?)Json.Str(x)!.Trim()).ToArray());
            }
            output.Add(clean);
        }
        return output;
    }

    /// <summary><c>isinstance(x, str) and x.strip()</c></summary>
    private static bool IsText(JsonNode? x) => Json.Str(x) is { } s && s.Trim().Length > 0;

    /// <summary>What Python iterates over a JSON value: list items, the characters of a text, the keys
    /// of a dict; anything else is not iterable (TypeError).</summary>
    private static IEnumerable<JsonNode?> PyIter(JsonNode? n) => n switch
    {
        JsonArray a => a,
        JsonObject o => o.Select(p => (JsonNode?)p.Key),
        _ when Json.Str(n) is { } s => s.EnumerateRunes().Select(r => (JsonNode?)r.ToString()),
        _ => throw new InvalidOperationException("object is not iterable"),
    };

    public static JsonObject ValidateDebriefAnswers(JsonArray questions, JsonNode? answers)
    {
        if (answers is not JsonObject given)
            throw new Invalid("answers must be an object");
        var known = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
        foreach (var q in questions.OfType<JsonObject>())
            known[Json.Str(q["key"]) ?? ""] = q;
        var unknown = given.Select(p => p.Key).Where(k => !known.ContainsKey(k)).Order(StringComparer.Ordinal).ToList();
        if (unknown.Count > 0)
            throw new Invalid("unknown questions: " + string.Join(", ", unknown));
        var clean = new JsonObject();
        foreach (var (key, q) in known)
        {
            var v = given[key];
            if (v is null || (Json.Str(v) is { } blank && blank.Trim().Length == 0))
            {
                if (Json.Truthy(q["required"]))
                    throw new Invalid($"'{key}' needs an answer");
                continue;
            }
            var type = Json.Str(q["type"]);
            if (type == "scale")
            {
                var smax = q["scale_max"];
                if (!PyText.IsIntLiteral(v) || PyText.IntOf(v) < 1 || PyText.IntOf(v) > PyText.IntOf(smax))
                    throw new Invalid($"'{key}' must be a whole number from 1 to {PyText.Str(smax)}");
            }
            else if (type == "yes_no")
            {
                if (!Json.IsBool(v))
                    throw new Invalid($"'{key}' must be true or false");
            }
            else if (type == "choice")
            {
                if (!PyIter(q["options"]).Any(o => PracticeRules.PyEquals(v, o)))
                    throw new Invalid($"'{key}' must be one of the options");
            }
            else
            {
                if (Json.Str(v) is not { } text)
                    throw new Invalid($"'{key}' must be text");
                v = text.Trim();
                if (text.Trim().EnumerateRunes().Count() > MaxTextAnswer)
                    throw new Invalid($"'{key}' is limited to {MaxTextAnswer} characters");
            }
            clean[key] = v.DeepClone();
        }
        return clean;
    }

    // ---------- threshold review ----------

    /// <summary>Re-evaluates a stored validation (a summary's <c>validation</c>) under candidate
    /// thresholds. Uses only what the validation stored (ratios and missing target regions). The
    /// confidence threshold changes how each sample is classified, so it cannot be re-evaluated here.</summary>
    public static JsonObject Revalidate(JsonObject stored, JsonObject candidate)
    {
        var reasons = new JsonArray();
        if (Json.Truthy(stored["reasons"]))
        {
            foreach (var r in PyIter(stored["reasons"]))
            {
                if (PyText.Str(r).StartsWith("missing_target_regions", StringComparison.Ordinal))
                    reasons.Add(r?.DeepClone());
            }
        }
        if (Json.Num(stored["correct_ratio"]) < PracticeRules.FloatOf(candidate["validation_min_correct"]))
            reasons.Add($"correct_ratio_below_{PyText.Str(candidate["validation_min_correct"])}");
        if (Json.Num(stored["uncertain_ratio"]) > PracticeRules.FloatOf(candidate["validation_max_uncertain"]))
            reasons.Add($"uncertain_ratio_above_{PyText.Str(candidate["validation_max_uncertain"])}");
        if (Json.Num(stored["size_ratio"]) < PracticeRules.FloatOf(candidate["min_region_to_error_ratio"]))
            reasons.Add($"eye_region_smaller_than_{PyText.Str(candidate["min_region_to_error_ratio"])}x_error");
        return new JsonObject { ["passed"] = reasons.Count == 0, ["reasons"] = reasons };
    }

    /// <summary>n, min, quartiles, p90 and max (linear interpolation between ranks), rounded to 4 decimals.</summary>
    public static JsonObject Distribution(IEnumerable<double> values)
    {
        var vals = values.Where(v => !double.IsNaN(v)).Order().ToArray();
        if (vals.Length == 0)
            return new JsonObject { ["n"] = 0 };
        double Q(double p)
        {
            if (vals.Length == 1)
                return vals[0];
            var pos = p * (vals.Length - 1);
            var lo = (int)Math.Floor(pos);
            var hi = Math.Min(lo + 1, vals.Length - 1);
            return vals[lo] + (vals[hi] - vals[lo]) * (pos - lo);
        }
        JsonNode R(double v) => Json.Float(PyMath.Round(v, 4));
        return new JsonObject
        {
            ["n"] = vals.Length, ["min"] = R(vals[0]), ["p25"] = R(Q(0.25)), ["median"] = R(Q(0.5)),
            ["p75"] = R(Q(0.75)), ["p90"] = R(Q(0.9)), ["max"] = R(vals[^1]),
        };
    }

    // ---------- research eye tracker comparison ----------

    public static readonly IReadOnlyDictionary<string, double> TimeUnits = new Dictionary<string, double> { ["ms"] = 1.0, ["us"] = 0.001, ["s"] = 1000.0 };
    public static readonly string[] CoordSpaces = ["css_px", "device_px", "norm"];
    public const int MaxReferenceRows = 2_000_000;

    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    /// <summary>Parses a tracker export into (session t_ms, x, y, valid) in the app's CSS pixels.
    /// <para>opts: time_column, x_column, y_column, valid_column (optional), valid_values (comma list),
    /// time_unit (ms|us|s), offset (tracker time at session t_ms = 0, in time_unit), coord_space
    /// (css_px|device_px|norm), origin_x / origin_y (CSS px of the app's top-left on the tracker's
    /// screen; 0 when the app runs full screen), delimiter (',' ';' or 'tab'; guessed when empty).</para></summary>
    public static List<ReferenceRow> ParseReferenceCsv(byte[] data, JsonObject opts, JsonObject screen)
    {
        var unit = opts.TryGetPropertyValue("time_unit", out var u) ? u : "ms";
        if (Json.Str(unit) is not { } unitName || !TimeUnits.TryGetValue(unitName, out var unitFactor))
            throw new Invalid("time_unit must be ms, us or s");
        var space = opts.TryGetPropertyValue("coord_space", out var cs) ? cs : "css_px";
        if (Json.Str(space) is not { } spaceName || !CoordSpaces.Contains(spaceName))
            throw new Invalid("coord_space must be css_px, device_px or norm");
        double offset, originX, originY;
        try
        {
            offset = PyFloat(Json.Truthy(opts["offset"]) ? opts["offset"] : 0);
            originX = PyFloat(Json.Truthy(opts["origin_x"]) ? opts["origin_x"] : 0);
            originY = PyFloat(Json.Truthy(opts["origin_y"]) ? opts["origin_y"] : 0);
        }
        catch (InvalidOperationException)
        {
            throw new Invalid("offset, origin_x and origin_y must be numbers");
        }
        var dpr = PyFloat(Json.Truthy(screen["dpr"]) ? screen["dpr"] : 1);
        if (dpr == 0)
            dpr = 1.0;
        var sw = PyFloat(Json.Truthy(screen["w"]) ? screen["w"] : 0);
        var sh = PyFloat(Json.Truthy(screen["h"]) ? screen["h"] : 0);
        if (spaceName == "norm" && (sw <= 0 || sh <= 0))
            throw new Invalid("norm coordinates need the session's screen size");

        string text;
        try
        {
            text = StrictUtf8.GetString(data);
            if (text.StartsWith('﻿'))
                text = text[1..];
        }
        catch (DecoderFallbackException)
        {
            text = Encoding.Latin1.GetString(data);
        }
        char delim;
        switch (Json.Truthy(opts["delimiter"]) ? Json.Str(opts["delimiter"]) : "")
        {
            case "tab": delim = '\t'; break;
            case ",": delim = ','; break;
            case ";": delim = ';'; break;
            default:
                // the most frequent of tab, ';' and ',' in the first 4096 characters (ties in that order)
                var head = string.Concat(text.EnumerateRunes().Take(4096).Select(r => r.ToString()));
                delim = '\t';
                var best = head.Count(c => c == '\t');
                foreach (var candidate in new[] { ';', ',' })
                {
                    var n = head.Count(c => c == candidate);
                    if (n > best)
                        (delim, best) = (candidate, n);
                }
                break;
        }

        using var records = PyCsv.Read(text, delim).GetEnumerator();
        var cols = records.MoveNext() ? records.Current : [];
        string? Col(string key) => Json.Truthy(opts[key]) ? PyText.Str(opts[key]) : null;
        string? tcol = Col("time_column"), xcol = Col("x_column"), ycol = Col("y_column"), vcol = Col("valid_column");
        foreach (var (name, col) in new[] { ("time_column", tcol), ("x_column", xcol), ("y_column", ycol) })
        {
            if (col is null)
                throw new Invalid($"{name} is required");
        }
        foreach (var (name, col) in new[] { ("time_column", tcol), ("x_column", xcol), ("y_column", ycol), ("valid_column", vcol) })
        {
            if (col is not null && !cols.Contains(col))
                throw new Invalid($"{name} '{col}' is not in the file; columns: " + string.Join(", ", cols.Take(30)));
        }
        var validText = Json.Truthy(opts["valid_values"]) ? PyText.Str(opts["valid_values"]) : "1,true,valid,yes";
        var validValues = validText.Split(',').Select(v => v.Trim()).Where(v => v.Length > 0).Select(v => v.ToLowerInvariant()).ToHashSet(StringComparer.Ordinal);

        // csv.DictReader: dict(zip(fieldnames, row)), later duplicate names win, and names past a
        // short row are None
        string? Cell(List<string> row, string name)
        {
            string? value = null;
            for (var j = 0; j < cols.Count; j++)
            {
                if (cols[j] == name)
                    value = j < row.Count ? row[j] : null;
            }
            return value;
        }
        double? Num(string? v)
        {
            if (v is null)
                return null;
            v = delim != ',' ? v.Trim().Replace(',', '.') : v.Trim();
            if (v.Length == 0)
                return null;
            var f = PyFloatOfText(v);
            return f is null || double.IsNaN(f.Value) ? null : f;
        }

        var output = new List<ReferenceRow>();
        var i = 0;
        while (records.MoveNext())
        {
            var row = records.Current;
            if (row.Count == 0)
                continue;
            if (i++ >= MaxReferenceRows)
                throw new Invalid($"the file has more than {MaxReferenceRows} rows");
            var t = Num(Cell(row, tcol!));
            if (t is null)
                continue;
            var tMs = PyRoundToLong((t.Value - offset) * unitFactor);
            double? x = Num(Cell(row, xcol!)), y = Num(Cell(row, ycol!));
            var ok = x is not null && y is not null;
            if (vcol is not null)
                ok = ok && validValues.Contains((Cell(row, vcol) ?? "").Trim().ToLowerInvariant());
            if (ok)
            {
                if (spaceName == "device_px")
                    (x, y) = (x / dpr, y / dpr);
                else if (spaceName == "norm")
                    (x, y) = (x * sw, y * sh);
                (x, y) = (x - originX, y - originY);
            }
            else
            {
                x = y = null;
            }
            output.Add(new ReferenceRow(tMs, x, y, ok));
        }
        if (output.Count == 0)
            throw new Invalid("no rows with a time value were found");
        // sorted by time; equal times keep the file's order
        return output.OrderBy(r => r.TMs).ToList();
    }

    /// <summary>Python's <c>int(round(x))</c>: half to even; infinity and NaN fail (OverflowError,
    /// ValueError). Values past the 64-bit range are clamped (Python's int would not fit the
    /// database column either).</summary>
    private static long PyRoundToLong(double x)
    {
        if (!double.IsFinite(x))
            throw new InvalidOperationException("cannot convert float infinity or NaN to integer");
        var r = Math.Round(x, MidpointRounding.ToEven);
        return r >= 9.2e18 ? long.MaxValue : r <= -9.2e18 ? long.MinValue : (long)r;
    }

    /// <summary><c>bisect.bisect_left</c> on times shifted by <paramref name="shift"/>, then the nearer
    /// neighbour (the earlier one on a tie) within the tolerance; -1 when there is none.</summary>
    private static int Nearest(long[] refT, long t, long toleranceMs, long shift = 0)
    {
        int lo = 0, hi = refT.Length;
        while (lo < hi)
        {
            var mid = (lo + hi) >>> 1;
            if (refT[mid] + shift < t)
                lo = mid + 1;
            else
                hi = mid;
        }
        int best = -1;
        var bestD = toleranceMs + 1;
        for (var j = lo - 1; j <= lo; j++)
        {
            if (j >= 0 && j < refT.Length)
            {
                var d = Math.Abs(refT[j] + shift - t);
                if (d < bestD)
                    (best, bestD) = (j, d);
            }
        }
        return bestD <= toleranceMs ? best : -1;
    }

    public static JsonNode? CohenKappa(Dictionary<string, Dictionary<string, int>> matrix, IReadOnlyList<string> labels)
    {
        var n = labels.Sum(a => labels.Sum(b => matrix[a][b]));
        if (n == 0)
            return null;
        var po = (double)labels.Sum(a => matrix[a][a]) / n;
        var pe = PyMath.Sum(labels.Select(a => (double)labels.Sum(b => matrix[a][b]) / n * ((double)labels.Sum(b => matrix[b][a]) / n)));
        if (pe >= 1.0)
            return null;
        return Json.Float(PyMath.Round((po - pe) / (1 - pe), 4));
    }

    private sealed class SegmentCounts
    {
        public int Pairs, WebcamEye, ReferenceEye, WebcamClassified;
    }

    /// <summary>Pairs each webcam sample with the nearest reference sample in time and compares them.
    /// Reference points are classified with the same stimulus layout as the webcam sample they are
    /// paired with.</summary>
    public static JsonObject CompareWithReference(
        IReadOnlyList<WebcamPoint> webcam, IReadOnlyList<ReferenceRow> reference, IReadOnlyDictionary<int, JsonObject> layouts, long toleranceMs)
    {
        if (toleranceMs is < 1 or > 500)
            throw new Invalid("tolerance_ms must be between 1 and 500");
        var refT = reference.Select(r => r.TMs).ToArray();
        var labels = MeasurementRules.Classifiable;
        var matrix = labels.ToDictionary(a => a, _ => labels.ToDictionary(b => b, _ => 0));
        var dists = new List<double>();
        var dxs = new List<double>();
        var dys = new List<double>();
        int paired = 0, webcamUncertainRefValid = 0, refInvalid = 0, unpaired = 0;
        var perSegment = new Dictionary<string, SegmentCounts>(StringComparer.Ordinal);
        foreach (var w in webcam)
        {
            var j = Nearest(refT, w.TMs, toleranceMs);
            if (j < 0)
            {
                unpaired++;
                continue;
            }
            var r = reference[j];
            if (!r.Valid)
            {
                refInvalid++;
                continue;
            }
            if (!layouts.TryGetValue(w.LayoutId is { } id && id != 0 ? id : -1, out var layout))
                continue;
            var refRegion = MeasurementRules.ClassifyPoint((r.X!.Value, r.Y!.Value), 1.0, layout, 0.0);
            var label = string.IsNullOrEmpty(w.Segment) ? "free" : w.Segment;
            if (!perSegment.TryGetValue(label, out var seg))
                perSegment[label] = seg = new SegmentCounts();
            if (!w.Valid || !labels.Contains(w.Region) || w.X is null)
            {
                webcamUncertainRefValid++;
                seg.Pairs++;
                seg.ReferenceEye += refRegion == "eye" ? 1 : 0;
                continue;
            }
            paired++;
            seg.Pairs++;
            seg.WebcamClassified++;
            seg.WebcamEye += w.Region == "eye" ? 1 : 0;
            seg.ReferenceEye += refRegion == "eye" ? 1 : 0;
            matrix[w.Region][refRegion]++;
            double dx = w.X.Value - r.X.Value, dy = w.Y!.Value - r.Y.Value;
            dxs.Add(dx);
            dys.Add(dy);
            dists.Add(PyMath.Hypot(dx, dy));
        }
        var agree = labels.Sum(a => matrix[a][a]);
        var segments = perSegment
            .Select(p => new JsonObject
            {
                ["segment"] = p.Key,
                ["pairs"] = p.Value.Pairs,
                ["webcam_eye_share"] = p.Value.WebcamClassified > 0 ? Json.Float(PyMath.Round((double)p.Value.WebcamEye / p.Value.WebcamClassified, 4)) : null,
                ["reference_eye_share"] = p.Value.Pairs > 0 ? Json.Float(PyMath.Round((double)p.Value.ReferenceEye / p.Value.Pairs, 4)) : null,
            })
            .OrderBy(s => (string)s["segment"]!, StringComparer.Ordinal);
        var eyeRow = matrix["eye"].Values.Sum();
        var eyeCol = labels.Sum(a => matrix[a]["eye"]);
        var confusion = new JsonObject();
        foreach (var a in labels)
        {
            var row = new JsonObject();
            foreach (var b in labels)
                row[b] = matrix[a][b];
            confusion[a] = row;
        }
        return new JsonObject
        {
            ["tolerance_ms"] = toleranceMs,
            ["webcam_samples"] = webcam.Count,
            ["paired_classified"] = paired,
            ["webcam_uncertain_while_reference_valid"] = webcamUncertainRefValid,
            ["reference_invalid"] = refInvalid,
            ["no_reference_in_time"] = unpaired,
            ["distance_px"] = Distribution(dists),
            ["bias_px"] = new JsonObject
            {
                ["x"] = dxs.Count > 0 ? Json.Float(PyMath.Round(PyMath.Sum(dxs) / dxs.Count, 2)) : null,
                ["y"] = dys.Count > 0 ? Json.Float(PyMath.Round(PyMath.Sum(dys) / dys.Count, 2)) : null,
            },
            ["region_agreement"] = paired > 0 ? Json.Float(PyMath.Round((double)agree / paired, 4)) : null,
            ["cohen_kappa"] = CohenKappa(matrix, labels),
            ["confusion"] = new JsonObject { ["rows_webcam_columns_reference"] = confusion },
            ["eye_region"] = new JsonObject
            {
                ["precision"] = eyeRow > 0 ? Json.Float(PyMath.Round((double)matrix["eye"]["eye"] / eyeRow, 4)) : null,
                ["recall"] = eyeCol > 0 ? Json.Float(PyMath.Round((double)matrix["eye"]["eye"] / eyeCol, 4)) : null,
            },
            ["segments"] = new JsonArray(segments.Select(s => (JsonNode?)s).ToArray()),
            ["note"] = "Agreement for this session on this computer only. Distances are in the app's CSS pixels; not a general accuracy claim.",
        };
    }

    /// <summary>Searches the time shift (added to reference times) that minimises the median distance.
    /// Estimating the alignment from the same data makes the agreement optimistic; callers must say so.</summary>
    public static long EstimateOffset(IReadOnlyList<WebcamPoint> webcam, IReadOnlyList<ReferenceRow> reference, long windowMs, int stepMs = 20)
    {
        if (!(0 < windowMs && windowMs <= 10_000))
            throw new Invalid("auto-align window must be between 1 and 10000 ms");
        var every = Math.Max(1, webcam.Count / 2000);
        var pts = webcam.Where(w => w.Valid && w.X is not null).Where((_, k) => k % every == 0).ToList();
        var validRef = reference.Where(r => r.Valid).ToList();
        if (pts.Count == 0 || validRef.Count == 0)
            return 0;
        var refT = validRef.Select(r => r.TMs).ToArray();
        long bestShift = 0;
        var best = double.PositiveInfinity;
        var ds = new List<double>(pts.Count);
        for (var shift = -windowMs; shift <= windowMs; shift += stepMs)
        {
            ds.Clear();
            foreach (var w in pts)
            {
                var j = Nearest(refT, w.TMs, stepMs, shift);
                if (j >= 0)
                    ds.Add(PyMath.Hypot(w.X!.Value - validRef[j].X!.Value, w.Y!.Value - validRef[j].Y!.Value));
            }
            if (ds.Count >= Math.Max(10, pts.Count / 4))
            {
                ds.Sort();
                var med = ds[ds.Count / 2];
                if (med < best)
                    (best, bestShift) = (med, shift);
            }
        }
        return bestShift;
    }

    // ---------- Python's float() ----------

    /// <summary>Python's <c>float(v)</c> of a JSON value: numbers and bools, numeric text; anything
    /// else fails like its TypeError/ValueError.</summary>
    public static double PyFloat(JsonNode? n)
    {
        if (Json.Str(n) is { } text)
            return PyFloatOfText(text) ?? throw new InvalidOperationException($"could not convert string to float: {PyText.Repr(n)}");
        return PracticeRules.FloatOf(n);
    }

    /// <summary>Python's <c>float(text)</c>: surrounding whitespace, a sign, digits (any script) with
    /// single underscores between them, an optional fraction and exponent, or inf/infinity/nan in
    /// any case. Null where it raises.</summary>
    public static double? PyFloatOfText(string text)
    {
        var sb = new StringBuilder(text.Length);
        foreach (var r in text.Trim(PySpace).EnumerateRunes())
        {
            if (!r.IsAscii && Rune.GetUnicodeCategory(r) == UnicodeCategory.DecimalDigitNumber)
                sb.Append((char)('0' + (int)Rune.GetNumericValue(r)));
            else
                sb.Append(r.ToString());
        }
        var s = sb.ToString();
        var special = SpecialFloat().Match(s);
        if (special.Success)
        {
            var negative = special.Groups[1].Value == "-";
            return special.Groups[2].Value.Equals("nan", StringComparison.OrdinalIgnoreCase)
                ? double.NaN
                : negative ? double.NegativeInfinity : double.PositiveInfinity;
        }
        if (!FloatLiteral().IsMatch(s))
            return null;
        return double.Parse(s.Replace("_", ""), NumberStyles.Float, CultureInfo.InvariantCulture);
    }

    /// <summary>The characters Python's <c>str.strip()</c> removes beyond .NET's white space.</summary>
    private static readonly char[] PySpace =
    [
        .. Enumerable.Range(0, 0x10000).Select(c => (char)c).Where(c => char.IsWhiteSpace(c) || c is >= '\x1c' and <= '\x1f'),
    ];

    [GeneratedRegex(@"^([+-]?)(inf|infinity|nan)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SpecialFloat();

    [GeneratedRegex(@"^[+-]?(?:[0-9](?:_?[0-9])*(?:\.(?:[0-9](?:_?[0-9])*)?)?|\.[0-9](?:_?[0-9])*)(?:[eE][+-]?[0-9](?:_?[0-9])*)?$", RegexOptions.CultureInvariant)]
    private static partial Regex FloatLiteral();
}

/// <summary>Python's <c>csv.reader</c> over <c>io.StringIO(text)</c> with the excel dialect and another
/// delimiter (not strict): lines end at "\n", a record ends at "\r" or "\n" outside quotes, quoted fields
/// may span lines and double their quotes, text after a closing quote is kept, an empty line is an
/// empty record, and a field holds at most 131072 characters. csv.Error is an InvalidOperationException.</summary>
public static class PyCsv
{
    public const int FieldLimit = 131072;

    private enum State { StartRecord, StartField, InField, InQuotedField, QuoteInQuotedField, EatCrnl }

    private const int Eol = -1;

    public static IEnumerable<List<string>> Read(string text, char delimiter)
    {
        var pos = 0;
        while (true)
        {
            var fields = new List<string>();
            var field = new StringBuilder();
            var fieldLen = 0;
            var state = State.StartRecord;

            void Save()
            {
                fields.Add(field.ToString());
                field.Clear();
                fieldLen = 0;
            }

            void Add(int c)
            {
                if (fieldLen >= FieldLimit)
                    throw new InvalidOperationException($"field larger than field limit ({FieldLimit})");
                field.Append((char)c);
                // a surrogate pair is one character for Python
                if (!char.IsLowSurrogate((char)c))
                    fieldLen++;
            }

            void Process(int c)
            {
                var lineEnd = c is '\n' or '\r' or Eol;
                switch (state)
                {
                    case State.StartRecord:
                        if (c == Eol)
                            return;
                        if (c is '\n' or '\r')
                        {
                            state = State.EatCrnl;
                            return;
                        }
                        state = State.StartField;
                        goto case State.StartField;
                    case State.StartField:
                        if (lineEnd)
                        {
                            Save();
                            state = c == Eol ? State.StartRecord : State.EatCrnl;
                        }
                        else if (c == '"')
                            state = State.InQuotedField;
                        else if (c == delimiter)
                            Save();
                        else
                        {
                            Add(c);
                            state = State.InField;
                        }
                        return;
                    case State.InField:
                        if (lineEnd)
                        {
                            Save();
                            state = c == Eol ? State.StartRecord : State.EatCrnl;
                        }
                        else if (c == delimiter)
                        {
                            Save();
                            state = State.StartField;
                        }
                        else
                            Add(c);
                        return;
                    case State.InQuotedField:
                        if (c == Eol)
                            return;
                        if (c == '"')
                            state = State.QuoteInQuotedField;
                        else
                            Add(c);
                        return;
                    case State.QuoteInQuotedField:
                        if (c == '"')
                        {
                            Add(c);
                            state = State.InQuotedField;
                        }
                        else if (c == delimiter)
                        {
                            Save();
                            state = State.StartField;
                        }
                        else if (lineEnd)
                        {
                            Save();
                            state = c == Eol ? State.StartRecord : State.EatCrnl;
                        }
                        else
                        {
                            Add(c);
                            state = State.InField;
                        }
                        return;
                    case State.EatCrnl:
                        if (c is '\n' or '\r')
                            return;
                        if (c == Eol)
                        {
                            state = State.StartRecord;
                            return;
                        }
                        throw new InvalidOperationException("new-line character seen in unquoted field - do you need to open the file with newline=''?");
                }
            }

            do
            {
                if (pos >= text.Length)
                {
                    // end of input: an unfinished record is returned as it is
                    if (fieldLen != 0 || state == State.InQuotedField)
                    {
                        Save();
                        yield return fields;
                    }
                    yield break;
                }
                var newline = text.IndexOf('\n', pos);
                var end = newline < 0 ? text.Length : newline + 1;
                for (var k = pos; k < end; k++)
                    Process(text[k]);
                pos = end;
                Process(Eol);
            }
            while (state != State.StartRecord);
            yield return fields;
        }
    }
}
