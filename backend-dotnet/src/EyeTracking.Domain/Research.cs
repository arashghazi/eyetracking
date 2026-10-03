using System.Globalization;
using System.Numerics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace EyeTracking.Domain;

// Research and data rules for build step 4 (backend/eyetracking/domain/research.py). A session's
// quality grade tells the analysis what to pool by default; nothing here manufactures accuracy,
// and missing time stays missing. GradeQuality came with step 2, whose session summaries carry it.

public sealed record Quality(string Grade, IReadOnlyList<string> Reasons)
{
    public JsonObject AsDict() => new() { ["grade"] = Grade, ["reasons"] = Json.Array(Reasons) };
}

/// <summary>A layout's first and last sample time in a session (Python's layout_ranges item).</summary>
public sealed record LayoutRange(int LayoutId, int FromMs, int ToMs);

public static partial class ResearchRules
{
    public static readonly IReadOnlyDictionary<string, int> RegionCodes =
        new Dictionary<string, int> { ["eye"] = 0, ["mouth"] = 1, ["face_other"] = 2, ["outside"] = 3, ["uncertain"] = 4 };

    public const string ExportVersion = "1";

    /// <summary>Grades a session summary (the dict built by the measurement use cases).</summary>
    public static Quality GradeQuality(JsonObject summary, double maxUncertainShare, double maxMissingShare) =>
        GradeQuality(summary, Json.Float(maxUncertainShare), Json.Float(maxMissingShare));

    /// <summary>The same with the thresholds as JSON values: the threshold review (step 6) grades with
    /// candidate values as sent, and Python writes an int threshold as <c>1</c>, not <c>1.0</c>. They are
    /// compared as numbers (other values fail like Python's TypeError) and written with <c>str()</c>.</summary>
    public static Quality GradeQuality(JsonObject summary, JsonNode? maxUncertainShare, JsonNode? maxMissingShare)
    {
        var exclude = new List<string>();
        var review = new List<string>();
        if (Json.Truthy(summary["synthetic"]))
            exclude.Add("synthetic_estimator");
        if (summary["calibration"] is null)
            exclude.Add("no_calibration");
        var cov = Json.Truthy(summary["coverage"]) ? summary["coverage"]!.AsObject() : [];
        var total = Json.Num(cov["total_ms"]) ?? 0;
        var classifiable = Json.Num(cov["classifiable_ms"]) ?? 0;
        var uncertain = Json.Num(cov["uncertain_ms"]) ?? 0;
        var missing = Json.Num(cov["missing_ms"]) ?? 0;
        if (classifiable <= 0)
            exclude.Add("no_classifiable_time");
        var val = summary["validation"];
        if (val is null || !Json.Truthy(val["passed"]))
            review.Add("validation_not_passed");
        var observed = classifiable + uncertain;
        if (observed > 0 && uncertain / observed > PracticeRules.FloatOf(maxUncertainShare))
            review.Add($"uncertain_share_above_{PyText.Str(maxUncertainShare)}");
        if (total > 0 && missing / total > PracticeRules.FloatOf(maxMissingShare))
            review.Add($"missing_share_above_{PyText.Str(maxMissingShare)}");
        if (Json.Str(summary["end_reason"]) == "ended_early")
            review.Add("ended_early");
        var notes = summary["notes"] as JsonArray ?? [];
        if (notes.Any(n => (Json.Str(n) ?? n?.ToJsonString() ?? "None").StartsWith("calibration_invalidated", StringComparison.Ordinal)))
            review.Add("calibration_invalidated");
        if (exclude.Count > 0)
            return new Quality("exclude", [.. exclude, .. review]);
        if (review.Count > 0)
            return new Quality("review", review);
        return new Quality("ok", []);
    }

    // ---------- comparability groups ----------

    public static string ScreenBucket(JsonObject screen)
    {
        var w = PyText.IntOf(screen["w"], orZero: true);
        var h = PyText.IntOf(screen["h"], orZero: true);
        return $"{PyText.FloorDiv(w, 300) * 300}x{PyText.FloorDiv(h, 300) * 300}";
    }

    public static string StimulusBucket(double? eyeRegionHeightPx)
    {
        if (eyeRegionHeightPx is null)
            return "unknown";
        var floored = PyText.FloorDiv(eyeRegionHeightPx.Value, 50);
        if (double.IsNaN(floored) || double.IsInfinity(floored))
            throw new InvalidOperationException("cannot convert float NaN or infinity to integer");
        return $"{new BigInteger(floored) * 50}px";
    }

    /// <summary>Sessions in different groups are never pooled. The parts are the session's JSON
    /// values; a part that is set but not text fails like Python's str.join.</summary>
    public static string GroupKey(JsonNode? devicePlatform, string? protocolVersion, JsonNode? estimator, JsonObject? screen, double? eyeRegionHeightPx)
    {
        static string Part(JsonNode? value, string fallback) =>
            !Json.Truthy(value) ? fallback : Json.Str(value) ?? throw new InvalidOperationException("sequence item: expected str instance");
        return string.Join("|",
            Part(devicePlatform, "unknown"),
            string.IsNullOrEmpty(protocolVersion) ? "none" : protocolVersion,
            Part(estimator, "unknown"),
            ScreenBucket(screen ?? []),
            StimulusBucket(eyeRegionHeightPx));
    }

    // ---------- replay helpers ----------

    /// <summary><c>[t_ms, x, y, conf, region_code]</c> per sample, x and y to 0.1 px.</summary>
    public static JsonArray CompactSamples(IEnumerable<GazeSample> samples) =>
        new(samples.Select(s => (JsonNode?)new JsonArray(
            s.TMs,
            s.X is null ? null : Json.Float(PyMath.Round(s.X.Value, 1)),
            s.Y is null ? null : Json.Float(PyMath.Round(s.Y.Value, 1)),
            Json.Float(PyMath.Round(s.Conf, 3)),
            RegionCodes.TryGetValue(s.Region, out var code) ? code : 4)).ToArray());

    /// <summary>First and last sample time per layout, in the order the layouts first appear.</summary>
    public static List<LayoutRange> LayoutRanges(IEnumerable<GazeSample> samples)
    {
        var ranges = new List<LayoutRange>();
        var index = new Dictionary<int, int>();
        foreach (var s in samples)
        {
            if (s.LayoutId is not { } id)
                continue;
            if (index.TryGetValue(id, out var i))
                ranges[i] = ranges[i] with { FromMs = Math.Min(ranges[i].FromMs, s.TMs), ToMs = Math.Max(ranges[i].ToMs, s.TMs) };
            else
            {
                index[id] = ranges.Count;
                ranges.Add(new LayoutRange(id, s.TMs, s.TMs));
            }
        }
        return ranges;
    }

    /// <summary>Share of classifiable samples per step; null where a step has no samples.</summary>
    public static JsonArray QualityStrip(IEnumerable<GazeSample> samples, int startMs, int endMs, int stepMs = 1000)
    {
        var output = new JsonArray();
        if (endMs <= startMs)
            return output;
        var ordered = samples.OrderBy(s => s.TMs).ToList();
        var idx = 0;
        for (long t = startMs; t < endMs; t += stepMs)
        {
            var stop = Math.Min(t + stepMs, endMs);
            while (idx < ordered.Count && ordered[idx].TMs < t)
                idx++;
            var j = idx;
            int valid = 0, total = 0;
            while (j < ordered.Count && ordered[j].TMs < stop)
            {
                total++;
                valid += MeasurementRules.Classifiable.Contains(ordered[j].Region) ? 1 : 0;
                j++;
            }
            output.Add(new JsonObject
            {
                ["from_ms"] = t,
                ["to_ms"] = stop,
                ["valid_share"] = total > 0 ? Json.Float(PyMath.Round((double)valid / total, 3)) : null,
            });
        }
        return output;
    }

    /// <summary>Stretches without samples longer than <paramref name="minGapFactor"/> times the usual spacing.</summary>
    public static JsonArray SampleGaps(IEnumerable<GazeSample> samples, double minGapFactor = 2.0, int defaultNominalMs = 100)
    {
        var ordered = samples.Select(s => (long)s.TMs).Order().ToList();
        if (ordered.Count < 2)
            return [];
        var pairs = ordered.Zip(ordered.Skip(1)).ToList();
        var diffs = pairs.Where(p => p.Second > p.First).Select(p => p.Second - p.First).Order().ToList();
        var nominal = diffs.Count > 0 ? diffs[diffs.Count / 2] : defaultNominalMs;
        nominal = Math.Max(20, Math.Min(nominal, 1000));
        return new JsonArray(pairs
            .Where(p => p.Second - p.First > minGapFactor * nominal)
            .Select(p => (JsonNode?)new JsonObject { ["from_ms"] = p.First, ["to_ms"] = p.Second })
            .ToArray());
    }

    /// <summary>Pause to resume (or end) intervals; a pause still open runs to <paramref name="endMs"/>.</summary>
    public static JsonArray PauseIntervals(IEnumerable<SessionEvent> events, int? endMs)
    {
        var output = new JsonArray();
        int? openAt = null;
        foreach (var e in events.OrderBy(e => e.TMs).ThenBy(e => e.Id))
        {
            if (e.Type == "pause" && openAt is null)
                openAt = e.TMs;
            else if (e.Type is "resume" or "end" && openAt is not null)
            {
                output.Add(new JsonObject { ["from_ms"] = openAt, ["to_ms"] = e.TMs });
                openAt = null;
            }
        }
        if (openAt is not null && endMs is not null && endMs > openAt)
            output.Add(new JsonObject { ["from_ms"] = openAt, ["to_ms"] = endMs });
        return output;
    }

    // ---------- data dictionary ----------

    private static readonly (string Name, string Type, string Unit, string Meaning)[] DataDictionaryFields =
    [
        ("session_id", "integer", "", "Session identifier."),
        ("participant_code", "string", "", "Research code; never the login identity."),
        ("created_at", "datetime (UTC)", "", "When the session was created."),
        ("path", "string", "", "gradual_face or interest_conversation; empty for measurement-only sessions."),
        ("protocol_name", "string", "", "Name of the published protocol version the session ran."),
        ("protocol_version", "integer", "", "Immutable protocol version number."),
        ("sheet_version", "integer", "", "Information-sheet version the participant consented to at export time."),
        ("device_platform", "string", "", "web, android, ..."),
        ("screen", "string", "px", "Screen width x height and pixel ratio."),
        ("estimator", "string", "", "Gaze model id."),
        ("gaze_model_version", "string", "", "Gaze model version; 'untrained' or a synthetic id means no measurement."),
        ("synthetic", "boolean", "", "True when the estimator makes no measurement claim."),
        ("quality", "string", "", "ok, review or exclude (see quality_reasons)."),
        ("quality_reasons", "string", "", "Semicolon-separated reasons behind the grade."),
        ("calibration_residual_px", "number", "px", "Median calibration error on the participant's screen."),
        ("validation_passed", "boolean", "", "Regional validation (eye / mouth / outside) passed."),
        ("settings_version", "integer", "", "Measurement-settings version the validation was judged with (empty for validations recorded before step 6)."),
        ("size_ratio", "number", "", "Eye-region height divided by calibration error."),
        ("total_ms", "integer", "ms", "Observed segment time (baseline + practice + post)."),
        ("classifiable_share", "number", "0-1", "Share of total time with a classifiable gaze region."),
        ("uncertain_share", "number", "0-1", "Share of total time with an uncertain estimate."),
        ("missing_share", "number", "0-1", "Share of total time without samples; never counted as looking away."),
        ("face_share", "number", "0-1", "Share of classifiable time inside the face."),
        ("eye_share", "number", "0-1", "Share of classifiable time in the eye region; empty when not evaluable."),
        ("baseline_eye_share", "number", "0-1", "Eye share during the prompt-free baseline."),
        ("post_eye_share", "number", "0-1", "Eye share during the prompt-free post observation."),
        ("eye_share_delta", "number", "0-1", "post_eye_share minus baseline_eye_share."),
        ("comprehension_share", "number", "0-1", "Correct comprehension answers over answered."),
        ("number_task_share", "number", "0-1", "Correct number readings over trials."),
        ("stages_completed", "integer", "", "Gradual stages finished with advance or complete."),
        ("comfort_min", "integer", "scale", "Lowest comfort answer."),
        ("comfort_mean", "number", "scale", "Mean comfort answer."),
        ("comfort_low_count", "integer", "", "Comfort answers below the study's lowest comfortable value."),
        ("pauses", "integer", "", "Pause events."),
        ("ended_early", "boolean", "", "Participant ended before the plan finished."),
        ("improvement", "string", "", "true, false or empty; true only when eye share rose, comfort did not worsen and content responses held."),
        ("group_key", "string", "", "device | protocol version | estimator | screen bucket | stimulus bucket; sessions in different groups are not pooled."),
        ("demo_<key>", "varies", "", "Demographics answer for <key>, stored under the research code."),
        ("export_version", "string", "", "Version of this export layout."),
        ("samples.t_ms", "integer", "ms", "Client monotonic time of the frame."),
        ("samples.x / samples.y", "number", "px", "Mapped gaze point on the participant's screen; empty when uncertain."),
        ("samples.conf", "number", "0-1", "Estimator confidence proxy."),
        ("samples.region", "string", "", "eye, mouth, face_other, outside or uncertain."),
    ];

    /// <summary>Every export column with its type, unit and meaning (a fresh copy per call).</summary>
    public static JsonArray DataDictionary() =>
        new(DataDictionaryFields.Select(f => (JsonNode?)new JsonObject
        {
            ["name"] = f.Name, ["type"] = f.Type, ["unit"] = f.Unit, ["meaning"] = f.Meaning,
        }).ToArray());
}

/// <summary>The text Python writes for exports: <c>str()</c> of JSON values (csv cells, f-strings),
/// <c>json.dumps</c>, the csv module's excel dialect, and the integer and date parsing the
/// research rules rely on. JSON numbers are read as Python's json module reads them: an integer
/// literal is an int, anything else a float.</summary>
public static class PyText
{
    // ---------- str() and repr() ----------

    /// <summary><c>str(v)</c> of a value loaded from JSON.</summary>
    public static string Str(JsonNode? n) => n is not null && n.GetValueKind() == JsonValueKind.String ? n.GetValue<string>() : Repr(n);

    /// <summary><c>repr(v)</c> of a value loaded from JSON (lists and dicts print their items with repr).</summary>
    public static string Repr(JsonNode? n)
    {
        switch (n)
        {
            case null:
                return "None";
            case JsonArray a:
                return "[" + string.Join(", ", a.Select(Repr)) + "]";
            case JsonObject o:
                return "{" + string.Join(", ", o.Select(p => $"{ReprString(p.Key)}: {Repr(p.Value)}")) + "}";
        }
        return n.GetValueKind() switch
        {
            JsonValueKind.String => ReprString(n.GetValue<string>()),
            JsonValueKind.True => "True",
            JsonValueKind.False => "False",
            JsonValueKind.Number => IsIntLiteral(n) ? BigInteger.Parse(n.ToJsonString(), CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture) : FloatStr(Json.Num(n)!.Value),
            _ => "None",
        };
    }

    /// <summary><c>str(float)</c>: the shortest round-trip digits, <c>inf</c> and <c>nan</c> by name.</summary>
    public static string FloatStr(double value) => value switch
    {
        double.PositiveInfinity => "inf",
        double.NegativeInfinity => "-inf",
        _ when double.IsNaN(value) => "nan",
        _ => Json.PythonFloat(value),
    };

    /// <summary>A JSON number Python reads as an int (no fraction, no exponent).</summary>
    public static bool IsIntLiteral(JsonNode? n) =>
        Json.IsNumber(n) && n!.ToJsonString().All(c => c is '-' or (>= '0' and <= '9'));

    private static string ReprString(string s)
    {
        var quote = s.Contains('\'') && !s.Contains('"') ? '"' : '\'';
        var sb = new StringBuilder().Append(quote);
        foreach (var rune in s.EnumerateRunes())
        {
            var v = rune.Value;
            if (v == quote || v == '\\')
                sb.Append('\\').Append((char)v);
            else if (v == '\t')
                sb.Append("\\t");
            else if (v == '\n')
                sb.Append("\\n");
            else if (v == '\r')
                sb.Append("\\r");
            else if (IsPrintable(rune))
                sb.Append(rune.ToString());
            else if (v <= 0xFF)
                sb.Append("\\x").Append(v.ToString("x2", CultureInfo.InvariantCulture));
            else if (v <= 0xFFFF)
                sb.Append("\\u").Append(v.ToString("x4", CultureInfo.InvariantCulture));
            else
                sb.Append("\\U").Append(v.ToString("x8", CultureInfo.InvariantCulture));
        }
        return sb.Append(quote).ToString();
    }

    // str.isprintable: everything except "Other" and "Separator" categories, but the plain space
    private static bool IsPrintable(Rune r) => r.Value == ' ' || Rune.GetUnicodeCategory(r) is not (
        UnicodeCategory.Control or UnicodeCategory.Format or UnicodeCategory.Surrogate or UnicodeCategory.PrivateUse
        or UnicodeCategory.OtherNotAssigned or UnicodeCategory.LineSeparator or UnicodeCategory.ParagraphSeparator
        or UnicodeCategory.SpaceSeparator);

    // ---------- int() and // ----------

    /// <summary>Python's <c>int(v)</c> of a JSON value (with <paramref name="orZero"/>: <c>int(v or 0)</c>).
    /// Floats truncate, numeric text is parsed; anything else fails like Python's TypeError/ValueError.</summary>
    public static BigInteger IntOf(JsonNode? n, bool orZero = false)
    {
        if (orZero && !Json.Truthy(n))
            return BigInteger.Zero;
        if (Json.IsBool(n))
            return Json.Truthy(n) ? BigInteger.One : BigInteger.Zero;
        if (IsIntLiteral(n))
            return BigInteger.Parse(n!.ToJsonString(), CultureInfo.InvariantCulture);
        if (Json.IsNumber(n))
        {
            var d = Json.Num(n)!.Value;
            if (double.IsNaN(d) || double.IsInfinity(d))
                throw new InvalidOperationException("cannot convert float NaN or infinity to integer");
            return new BigInteger(Math.Truncate(d));
        }
        if (Json.Str(n) is { } text)
        {
            var t = text.Trim();
            var body = t.StartsWith('+') || t.StartsWith('-') ? t[1..] : t;
            if (body.Length > 0 && char.IsAsciiDigit(body[0]) && char.IsAsciiDigit(body[^1]) && !body.Contains("__")
                && body.All(c => char.IsAsciiDigit(c) || c == '_'))
                return BigInteger.Parse(t.Replace("_", ""), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture);
            throw new InvalidOperationException($"invalid literal for int() with base 10: {ReprString(text)}");
        }
        throw new InvalidOperationException("int() argument must be a string or a real number");
    }

    /// <summary>Python's <c>a // b</c> on ints (floors toward negative infinity).</summary>
    public static BigInteger FloorDiv(BigInteger a, BigInteger b)
    {
        var q = BigInteger.DivRem(a, b, out var r);
        return r != 0 && (r < 0) != (b < 0) ? q - 1 : q;
    }

    /// <summary>Python's <c>a // b</c> on floats (CPython's float_floor_div).</summary>
    public static double FloorDiv(double a, double b)
    {
        var mod = a % b; // fmod
        var div = (a - mod) / b;
        if (mod != 0 && (b < 0) != (mod < 0))
            div -= 1.0;
        if (div == 0)
            return Math.CopySign(0.0, a / b);
        var floor = Math.Floor(div);
        return div - floor > 0.5 ? floor + 1.0 : floor;
    }

    // ---------- json.dumps ----------

    /// <summary><c>json.dumps(v, indent=indent, ensure_ascii=ensureAscii)</c>: <c>", "</c> and <c>": "</c>
    /// between items without an indent, <c>","</c> and line breaks with one.</summary>
    public static string JsonDumps(JsonNode? n, int? indent = null, bool ensureAscii = true)
    {
        var sb = new StringBuilder();
        Dump(sb, n, indent, ensureAscii, 0);
        return sb.ToString();
    }

    private static void Dump(StringBuilder sb, JsonNode? n, int? indent, bool ascii, int level)
    {
        switch (n)
        {
            case null:
                sb.Append("null");
                return;
            case JsonArray a:
                Container(sb, '[', ']', a.Count, indent, level, i => Dump(sb, a[i], indent, ascii, level + 1));
                return;
            case JsonObject o:
                var items = o.ToList();
                Container(sb, '{', '}', items.Count, indent, level, i =>
                {
                    DumpString(sb, items[i].Key, ascii);
                    sb.Append(": ");
                    Dump(sb, items[i].Value, indent, ascii, level + 1);
                });
                return;
        }
        switch (n.GetValueKind())
        {
            case JsonValueKind.String:
                DumpString(sb, n.GetValue<string>(), ascii);
                break;
            case JsonValueKind.True:
                sb.Append("true");
                break;
            case JsonValueKind.False:
                sb.Append("false");
                break;
            case JsonValueKind.Number:
                sb.Append(IsIntLiteral(n)
                    ? BigInteger.Parse(n.ToJsonString(), CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture)
                    : Json.PythonFloat(Json.Num(n)!.Value));
                break;
            default:
                sb.Append("null");
                break;
        }
    }

    private static void Container(StringBuilder sb, char open, char close, int count, int? indent, int level, Action<int> item)
    {
        if (count == 0)
        {
            sb.Append(open).Append(close);
            return;
        }
        sb.Append(open);
        for (var i = 0; i < count; i++)
        {
            if (indent is { } step)
                sb.Append(i == 0 ? "" : ",").Append('\n').Append(' ', step * (level + 1));
            else if (i > 0)
                sb.Append(", ");
            item(i);
        }
        if (indent is { } width)
            sb.Append('\n').Append(' ', width * level);
        sb.Append(close);
    }

    private static void DumpString(StringBuilder sb, string s, bool ascii)
    {
        sb.Append('"');
        foreach (var c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                case '\b': sb.Append("\\b"); break;
                case '\f': sb.Append("\\f"); break;
                default:
                    if (c < 0x20 || (ascii && c > 0x7E))
                        sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    else
                        sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }

    // ---------- csv (excel dialect) ----------

    /// <summary>One row as <c>csv.writer</c> writes it: comma separated, a cell quoted when it holds a
    /// comma, a quote or a line break (quotes doubled), <c>\r\n</c> at the end.</summary>
    public static void CsvRow(StringBuilder sb, IReadOnlyList<string> cells)
    {
        for (var i = 0; i < cells.Count; i++)
        {
            if (i > 0)
                sb.Append(',');
            var cell = cells[i];
            // a row of one empty cell is written as "" so that it is not an empty line
            if (cell.IndexOfAny([',', '"', '\r', '\n']) >= 0 || (cells.Count == 1 && cell.Length == 0))
                sb.Append('"').Append(cell.Replace("\"", "\"\"")).Append('"');
            else
                sb.Append(cell);
        }
        sb.Append("\r\n");
    }

    /// <summary>Text encoded as Python's <c>"utf-8-sig"</c> (UTF-8 with a byte order mark).</summary>
    public static byte[] Utf8Sig(string text) => [0xEF, 0xBB, 0xBF, .. Encoding.UTF8.GetBytes(text)];

    // ---------- date.fromisoformat ----------

    /// <summary>CPython's <c>date.fromisoformat</c>: <c>YYYY-MM-DD</c>, <c>YYYYMMDD</c> and ISO week dates
    /// (<c>YYYY-Www[-D]</c>); like CPython it does not look past the parsed part. Null where it raises.</summary>
    public static DateOnly? DateFromIsoFormat(string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        if (bytes.Length is not (7 or 8 or 10))
            return null;
        var p = 0;
        int Digits(int n)
        {
            var v = 0;
            for (var k = 0; k < n; k++, p++)
            {
                if (p >= bytes.Length || bytes[p] is < (byte)'0' or > (byte)'9')
                    return -1;
                v = v * 10 + (bytes[p] - '0');
            }
            return v;
        }
        byte At(int i) => i < bytes.Length ? bytes[i] : (byte)0;
        var year = Digits(4);
        if (year < 0)
            return null;
        var dash = At(p) == '-';
        if (dash)
            p++;
        if (At(p) == 'W')
        {
            p++;
            var week = Digits(2);
            if (week < 0)
                return null;
            var day = 1;
            if (p < bytes.Length)
            {
                if (dash && At(p++) != '-')
                    return null;
                day = Digits(1);
                if (day < 0)
                    return null;
            }
            return IsoWeekDate(year, week, day);
        }
        var month = Digits(2);
        if (month < 0 || (dash && At(p++) != '-'))
            return null;
        var dd = Digits(2);
        if (dd < 0 || year < 1 || month is < 1 or > 12 || dd < 1 || dd > DateTime.DaysInMonth(year, month))
            return null;
        return new DateOnly(year, month, dd);
    }

    private static DateOnly? IsoWeekDate(int year, int week, int day)
    {
        if (year < 1 || year > 9999 || day is < 1 or > 7)
            return null;
        if (week is < 1 or > 53 || (week == 53 && ISOWeek.GetWeeksInYear(year) < 53))
            return null;
        try
        {
            return DateOnly.FromDateTime(ISOWeek.ToDateTime(year, week, (DayOfWeek)(day % 7)));
        }
        catch (ArgumentOutOfRangeException)
        {
            return null;
        }
    }
}
