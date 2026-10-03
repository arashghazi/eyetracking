using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace EyeTracking.Domain;

// Measurement rules for build step 2 (backend/eyetracking/domain/measurement.py): calibration,
// regional validation, classification, coverage. The rules encode the design: eye region = upper
// half of the face, mouth region = lower half, missing data is never "not looking", and eye-level
// results need a passed validation.

public partial class MeasurementSettings
{
    public void Validate()
    {
        foreach (var (name, v) in new (string, double)[]
                 {
                     ("validation_min_correct", ValidationMinCorrect), ("validation_max_uncertain", ValidationMaxUncertain),
                     ("gaze_conf_threshold", GazeConfThreshold), ("quality_max_uncertain_share", QualityMaxUncertainShare),
                     ("quality_max_missing_share", QualityMaxMissingShare),
                 })
        {
            if (!(0.0 <= v && v <= 1.0))
                throw new Invalid($"{name} must be between 0 and 1");
        }
        if (MinRegionToErrorRatio < 1.0)
            throw new Invalid("min_region_to_error_ratio must be at least 1");
        if (!(5 <= CalibrationPoints && CalibrationPoints <= 16))
            throw new Invalid("calibration_points must be between 5 and 16");
    }

    /// <summary>A detached copy, for restoring values after a rejected change.</summary>
    public MeasurementSettings Copy() => (MeasurementSettings)MemberwiseClone();

    /// <summary>Same tunable values (Python compares the settings_values dicts).</summary>
    public bool SameValues(MeasurementSettings other) =>
        ValidationMinCorrect == other.ValidationMinCorrect
        && ValidationMaxUncertain == other.ValidationMaxUncertain
        && MinRegionToErrorRatio == other.MinRegionToErrorRatio
        && GazeConfThreshold == other.GazeConfThreshold
        && CalibrationPoints == other.CalibrationPoints
        && AllowContinueWithoutValidation == other.AllowContinueWithoutValidation
        && QualityMaxUncertainShare == other.QualityMaxUncertainShare
        && QualityMaxMissingShare == other.QualityMaxMissingShare;

    public void CopyValuesFrom(MeasurementSettings other)
    {
        ValidationMinCorrect = other.ValidationMinCorrect;
        ValidationMaxUncertain = other.ValidationMaxUncertain;
        MinRegionToErrorRatio = other.MinRegionToErrorRatio;
        GazeConfThreshold = other.GazeConfThreshold;
        CalibrationPoints = other.CalibrationPoints;
        AllowContinueWithoutValidation = other.AllowContinueWithoutValidation;
        QualityMaxUncertainShare = other.QualityMaxUncertainShare;
        QualityMaxMissingShare = other.QualityMaxMissingShare;
    }
}

public partial class Session
{
    public void EnsureOpen()
    {
        if (Status == SessionStatus.Ended)
            throw new Conflict("this session has ended");
    }
}

/// <summary>One estimator output as the participant app sends it (the RawSample request model,
/// with its defaults).</summary>
public sealed record RawSample(
    int TMs,
    bool FaceDetected = false,
    double[]? FaceBox = null,
    double FaceConf = 0.0,
    double? YawDeg = null,
    double? PitchDeg = null,
    double GazeConf = 0.0,
    int FrameW = 0,
    int FrameH = 0);

public sealed record CalibrationTarget(double X, double Y, IReadOnlyList<RawSample> Samples);

public sealed record ValidationTarget(string Region, double X, double Y, IReadOnlyList<RawSample> Samples);

/// <summary>A labelled stretch of the session between segment events (Python's segment dict).</summary>
public sealed class SegmentSpan
{
    /// <summary>The <c>segment</c> value of the start event as sent (normally a string), or "free".</summary>
    public JsonNode? Label { get; init; }
    public int StartedMs { get; init; }
    public int? EndedMs { get; set; }

    public JsonObject ToJson() => new() { ["label"] = Label?.DeepClone(), ["started_ms"] = StartedMs, ["ended_ms"] = EndedMs };
}

public sealed record Coverage(long TotalMs, long ClassifiableMs, long UncertainMs, long MissingMs, IReadOnlyDictionary<string, long> RegionMs);

public static class MeasurementRules
{
    public static readonly string[] Regions = ["eye", "mouth", "face_other", "outside", "uncertain"];
    public static readonly string[] Classifiable = ["eye", "mouth", "face_other", "outside"];
    public static readonly string[] Segments = ["baseline", "practice", "post", "free"];
    public static readonly string[] EventTypes =
    [
        "segment_start", "segment_end", "pause", "resume", "end", "camera_changed", "orientation_changed",
        "zoom_changed", "face_lost", "face_found", "comfort_answer", "media_start", "note",
    ];
    public static readonly string[] InvalidatingEvents = ["camera_changed", "orientation_changed", "zoom_changed"];
    public static readonly string[] FeatureNames = ["bias", "yaw_deg", "pitch_deg", "face_cx", "face_cy", "face_w"];

    /// <summary>A Python tuple as <c>str()</c> writes it: <c>('a', 'b')</c>.</summary>
    public static string TupleText(IEnumerable<string> items) => "(" + string.Join(", ", items.Select(i => $"'{i}'")) + ")";

    // ---------- geometry helpers ----------

    /// <summary>Python's <c>float(v)</c> for a JSON value; anything else fails like Python (a 500).</summary>
    private static double Float(JsonNode? n)
    {
        switch (n is JsonValue v ? v.GetValueKind() : JsonValueKind.Undefined)
        {
            case JsonValueKind.Number:
                return Json.Num(n)!.Value;
            case JsonValueKind.True:
                return 1.0;
            case JsonValueKind.False:
                return 0.0;
            case JsonValueKind.String when double.TryParse(n!.GetValue<string>().Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var d):
                return d;
            default:
                throw new InvalidOperationException($"could not convert {n?.ToJsonString() ?? "None"} to float");
        }
    }

    /// <summary>Python's <c>layout.get(key) or {}</c> for a nested dict.</summary>
    private static JsonObject Dict(JsonNode? n) => n switch
    {
        JsonObject o => o,
        _ when !Json.Truthy(n) => [],
        _ => throw new InvalidOperationException("expected a JSON object"),
    };

    private static (double X, double Y, double W, double H)? Box(JsonObject layout, string key)
    {
        var b = layout[key];
        if (!Json.Truthy(b))
            return null;
        return b switch
        {
            JsonArray a => a.Count != 4 ? null : (Float(a[0]), Float(a[1]), Float(a[2]), Float(a[3])),
            JsonObject o when o.Count != 4 => null,
            JsonValue v when v.GetValueKind() == JsonValueKind.String && v.GetValue<string>().Length != 4 => null,
            _ => throw new InvalidOperationException($"layout.{key} is not a box"),
        };
    }

    private static bool Inside(double x, double y, (double X, double Y, double W, double H)? box)
    {
        if (box is not { } b)
            return false;
        return b.X <= x && x <= b.X + b.W && b.Y <= y && y <= b.Y + b.H;
    }

    public static void ValidateLayout(JsonObject layout)
    {
        foreach (var key in new[] { "face_box", "eye_region", "mouth_region" })
        {
            if (Box(layout, key) is null)
                throw new Invalid($"layout.{key} must be [x, y, w, h]");
        }
        var screen = Dict(layout["screen"]);
        if (!Json.Truthy(screen["w"]) || !Json.Truthy(screen["h"]))
            throw new Invalid("layout.screen needs w and h");
        var (_, ey, ew, eh) = Box(layout, "eye_region")!.Value;
        var (_, my, mw, mh) = Box(layout, "mouth_region")!.Value;
        if (eh <= 0 || ew <= 0 || mh <= 0 || mw <= 0)
            throw new Invalid("regions must have positive size");
        if (ey + eh > my + 1e-6)
            throw new Invalid("eye_region must lie above mouth_region");
    }

    // ---------- raw samples and calibration ----------

    /// <summary>Features used by the calibration mapping; null when the sample is unusable.</summary>
    public static double[]? FeatureVector(RawSample raw)
    {
        if (!raw.FaceDetected || raw.YawDeg is null || raw.PitchDeg is null)
            return null;
        var box = raw.FaceBox;
        double fw = raw.FrameW, fh = raw.FrameH;
        if (box is null || box.Length != 4 || fw <= 0 || fh <= 0)
            return null;
        double x = box[0], y = box[1], w = box[2], h = box[3];
        return [1.0, raw.YawDeg.Value, raw.PitchDeg.Value, (x + w / 2) / fw, (y + h / 2) / fh, w / fw];
    }

    public static double SampleConfidence(RawSample raw)
    {
        if (!raw.FaceDetected)
            return 0.0;
        // min(face_conf, gaze_conf)
        return raw.GazeConf < raw.FaceConf ? raw.GazeConf : raw.FaceConf;
    }

    /// <summary>Least-squares affine mapping from gaze features to screen pixels, with a small ridge term.</summary>
    public static Calibration FitCalibration(IReadOnlyList<CalibrationTarget> targets, double confThreshold, int minTargets = 5, int minSamples = 5)
    {
        var rows = new List<double[]>();
        var xs = new List<double>();
        var ys = new List<double>();
        var perTarget = new List<(double X, double Y, int NValid)>();
        var usableTargets = 0;
        foreach (var t in targets)
        {
            var feats = t.Samples.Where(s => SampleConfidence(s) >= confThreshold).Select(FeatureVector).OfType<double[]>().ToList();
            perTarget.Add((t.X, t.Y, feats.Count));
            if (feats.Count < minSamples)
                continue;
            usableTargets++;
            foreach (var f in feats)
            {
                rows.Add(f);
                xs.Add(t.X);
                ys.Add(t.Y);
            }
        }
        if (usableTargets < minTargets)
            throw new Invalid($"calibration needs at least {minTargets} targets with {minSamples} valid samples each; got {usableTargets}");

        var k = FeatureNames.Length;
        var ata = new double[k, k];
        var atx = new double[k];
        var aty = new double[k];
        for (var i = 0; i < k; i++)
        {
            for (var j = 0; j < k; j++)
            {
                var sum = 0.0;
                foreach (var r in rows)
                    sum += r[i] * r[j];
                ata[i, j] = sum + (i == j && i > 0 ? 1e-6 : 0.0);
            }
            double sx = 0, sy = 0;
            for (var r = 0; r < rows.Count; r++)
            {
                sx += rows[r][i] * xs[r];
                sy += rows[r][i] * ys[r];
            }
            atx[i] = sx;
            aty[i] = sy;
        }
        var betaX = Solve(ata, atx);
        var betaY = Solve(ata, aty);

        var errors = new List<double>();
        var perTargetJson = new JsonArray();
        var idx = 0;
        foreach (var (px, py, n) in perTarget)
        {
            JsonNode? err = null;
            if (n >= minSamples)
            {
                var d = new double[n];
                for (var r = 0; r < n; r++)
                    d[r] = double.Hypot(Dot(rows[idx + r], betaX) - px, Dot(rows[idx + r], betaY) - py);
                err = Json.Float(PyMath.Median(d));
                errors.AddRange(d);
                idx += n;
            }
            perTargetJson.Add(new JsonObject { ["x"] = Json.Float(px), ["y"] = Json.Float(py), ["n_valid"] = n, ["err_px"] = err });
        }
        return new Calibration
        {
            SessionId = 0,
            Params = new JsonObject
            {
                ["features"] = Json.Array(FeatureNames),
                ["x"] = new JsonArray(betaX.Select(v => (JsonNode?)Json.Float(v)).ToArray()),
                ["y"] = new JsonArray(betaY.Select(v => (JsonNode?)Json.Float(v)).ToArray()),
            },
            ResidualPxMedian = PyMath.Median(errors),
            ResidualPxP90 = PyMath.Percentile(errors, 90),
            PerTarget = perTargetJson,
            Points = usableTargets,
            Accepted = true,
        };
    }

    public static (double X, double Y)? MapPoint(JsonObject parameters, RawSample raw)
    {
        var f = FeatureVector(raw);
        if (f is null)
            return null;
        return (Dot(Coefficients(parameters["x"], f.Length), f), Dot(Coefficients(parameters["y"], f.Length), f));
    }

    public static string ClassifyPoint((double X, double Y)? point, double conf, JsonObject layout, double confThreshold)
    {
        if (point is not { } p || conf < confThreshold)
            return "uncertain";
        var (x, y) = p;
        var screen = Dict(layout["screen"]);
        var w = screen.ContainsKey("w") ? Float(screen["w"]) : 0.0;
        var h = screen.ContainsKey("h") ? Float(screen["h"]) : 0.0;
        if (x < 0 || y < 0 || x > w || y > h)
            return "outside";
        if (Inside(x, y, Box(layout, "eye_region")))
            return "eye";
        if (Inside(x, y, Box(layout, "mouth_region")))
            return "mouth";
        if (Inside(x, y, Box(layout, "face_box")))
            return "face_other";
        return "outside";
    }

    public static ((double X, double Y)? Point, double Conf, string Region) ClassifyRaw(JsonObject parameters, RawSample raw, JsonObject layout, double confThreshold)
    {
        var point = MapPoint(parameters, raw);
        var conf = SampleConfidence(raw);
        return (point, conf, ClassifyPoint(point, conf, layout, confThreshold));
    }

    // ---------- validation ----------

    public static Validation EvaluateValidation(Calibration calibration, JsonObject layout, IReadOnlyList<ValidationTarget> targets, MeasurementSettings settings)
    {
        ValidateLayout(layout);
        if (targets.Count == 0)
            throw new Invalid("validation needs targets");
        var results = new JsonArray();
        var correct = 0;
        var totalSamples = 0;
        var uncertainSamples = 0;
        var present = new HashSet<string>();
        foreach (var t in targets)
        {
            var region = t.Region;
            if (region is not ("eye" or "mouth" or "outside"))
                throw new Invalid("validation target region must be eye, mouth or outside");
            present.Add(region);
            var counts = Regions.ToDictionary(r => r, _ => 0);
            foreach (var raw in t.Samples)
                counts[ClassifyRaw(calibration.Params, raw, layout, settings.GazeConfThreshold).Region]++;
            var n = t.Samples.Count;
            totalSamples += n;
            uncertainSamples += counts["uncertain"];
            // max() keeps the first region on ties
            var majority = "uncertain";
            var best = 0;
            foreach (var r in Classifiable)
            {
                if (counts[r] > best)
                {
                    best = counts[r];
                    majority = r;
                }
            }
            var isCorrect = majority == region && n > 0;
            correct += isCorrect ? 1 : 0;
            var countsJson = new JsonObject();
            foreach (var r in Regions)
                countsJson[r] = counts[r];
            results.Add(new JsonObject
            {
                ["region"] = region,
                ["x"] = Json.Float(t.X),
                ["y"] = Json.Float(t.Y),
                ["n"] = n,
                ["majority"] = majority,
                ["correct"] = isCorrect,
                ["uncertain_share"] = Json.Float(n > 0 ? (double)counts["uncertain"] / n : 1.0),
                ["counts"] = countsJson,
            });
        }
        var correctRatio = (double)correct / targets.Count;
        var uncertainRatio = totalSamples > 0 ? (double)uncertainSamples / totalSamples : 1.0;
        var eyeH = Box(layout, "eye_region")!.Value.H;
        var sizeRatio = eyeH / Math.Max(calibration.ResidualPxMedian, 1.0);
        var reasons = new List<string>();
        var missing = new[] { "eye", "mouth", "outside" }.Where(r => !present.Contains(r)).ToList();
        if (missing.Count > 0)
            reasons.Add("missing_target_regions:" + string.Join(",", missing));
        if (correctRatio < settings.ValidationMinCorrect)
            reasons.Add($"correct_ratio_below_{Json.PythonFloat(settings.ValidationMinCorrect)}");
        if (uncertainRatio > settings.ValidationMaxUncertain)
            reasons.Add($"uncertain_ratio_above_{Json.PythonFloat(settings.ValidationMaxUncertain)}");
        if (sizeRatio < settings.MinRegionToErrorRatio)
            reasons.Add($"eye_region_smaller_than_{Json.PythonFloat(settings.MinRegionToErrorRatio)}x_error");
        return new Validation
        {
            SettingsVersion = settings.Version,
            SessionId = calibration.SessionId,
            CalibrationId = calibration.Id,
            Layout = layout,
            Passed = reasons.Count == 0,
            CorrectRatio = PyMath.Round(correctRatio, 4),
            UncertainRatio = PyMath.Round(uncertainRatio, 4),
            SizeRatio = PyMath.Round(sizeRatio, 3),
            Reasons = reasons,
            Targets = results,
        };
    }

    // ---------- coverage and attention ----------

    public static List<SegmentSpan> SegmentsFromEvents(IEnumerable<SessionEvent> events, int? lastSampleT)
    {
        var segments = new List<SegmentSpan>();
        SegmentSpan? open = null;
        foreach (var e in events.OrderBy(e => e.TMs).ThenBy(e => e.Id))
        {
            if (e.Type == "segment_start")
            {
                if (open is not null && open.EndedMs is null)
                    open.EndedMs = e.TMs;
                JsonNode? label = e.Payload.TryGetPropertyValue("segment", out var given) ? given?.DeepClone() : "free";
                open = new SegmentSpan { Label = label, StartedMs = e.TMs };
                segments.Add(open);
            }
            else if (e.Type is "segment_end" or "end" && open is not null && open.EndedMs is null)
            {
                open.EndedMs = e.TMs;
            }
        }
        foreach (var s in segments)
        {
            if (s.EndedMs is null && lastSampleT is not null && lastSampleT > s.StartedMs)
                s.EndedMs = lastSampleT;
        }
        return segments;
    }

    /// <summary>Missing time is a gap in samples, never counted as looking anywhere.</summary>
    public static Coverage Coverage(IEnumerable<GazeSample> samples, IEnumerable<SegmentSpan> segments)
    {
        var regionMs = Classifiable.ToDictionary(r => r, _ => 0L);
        long uncertainMs = 0, coveredMs = 0, totalMs = 0;
        var ordered = samples.OrderBy(s => s.TMs).ToList();
        foreach (var seg in segments)
        {
            long start = seg.StartedMs;
            if (seg.EndedMs is not { } endValue || endValue <= start)
                continue;
            long end = endValue;
            totalMs += end - start;
            var inside = ordered.Where(s => start <= s.TMs && s.TMs <= end).ToList();
            if (inside.Count == 0)
                continue;
            var diffs = inside.Zip(inside.Skip(1), (a, b) => (long)b.TMs - a.TMs).Where(d => d > 0).Select(d => (double)d).ToList();
            var nominal = diffs.Count > 0 ? (long)PyMath.Median(diffs) : 100;
            nominal = Math.Max(20, Math.Min(nominal, 1000));
            for (var i = 0; i < inside.Count; i++)
            {
                var s = inside[i];
                var next = i + 1 < inside.Count ? inside[i + 1].TMs : end;
                var dur = Math.Max(0, Math.Min(next - s.TMs, 2 * nominal));
                coveredMs += dur;
                if (regionMs.ContainsKey(s.Region))
                    regionMs[s.Region] += dur;
                else
                    uncertainMs += dur;
            }
        }
        var classifiableMs = regionMs.Values.Sum();
        return new Coverage(totalMs, classifiableMs, uncertainMs, Math.Max(0, totalMs - coveredMs), regionMs);
    }

    /// <summary>Share of classifiable time per region (eye, mouth, face_other, outside), or null.</summary>
    public static Dictionary<string, double>? RegionShares(Coverage cov)
    {
        if (cov.ClassifiableMs <= 0)
            return null;
        return Classifiable.ToDictionary(r => r, r => PyMath.Round((double)cov.RegionMs[r] / cov.ClassifiableMs, 4));
    }

    public static JsonObject? SharesJson(Dictionary<string, double>? shares)
    {
        if (shares is null)
            return null;
        var o = new JsonObject();
        foreach (var r in Classifiable)
            o[r] = Json.Float(shares[r]);
        return o;
    }

    /// <summary>Eye-level results exist only with a passed validation on a real estimator and classifiable time.</summary>
    public static JsonObject EyeRegionAttention(Session session, Validation? validation, Dictionary<string, double>? shares)
    {
        static JsonObject No(string reason) => new() { ["evaluable"] = false, ["share"] = null, ["reason"] = reason };
        if (session.Synthetic)
            return No("synthetic_estimator");
        if (validation is null)
            return No("validation_missing");
        if (!validation.Passed)
            return No("validation_failed");
        if (shares is null)
            return No("no_classifiable_time");
        return new JsonObject { ["evaluable"] = true, ["share"] = Json.Float(shares["eye"]), ["reason"] = null };
    }

    public static JsonObject FaceRegionAttention(Dictionary<string, double>? shares) =>
        shares is null
            ? new JsonObject { ["share"] = null }
            : new JsonObject { ["share"] = Json.Float(PyMath.Round(shares["eye"] + shares["mouth"] + shares["face_other"], 4)) };

    // ---------- small dense linear algebra (numpy replacements) ----------

    private static double Dot(double[] a, double[] b)
    {
        if (a.Length != b.Length)
            throw new InvalidOperationException("shapes not aligned");
        var sum = 0.0;
        for (var i = 0; i < a.Length; i++)
            sum += a[i] * b[i];
        return sum;
    }

    private static double[] Coefficients(JsonNode? n, int length)
    {
        var a = n as JsonArray ?? throw new InvalidOperationException("calibration parameters are missing");
        var values = a.Select(Float).ToArray();
        return values.Length == length ? values : throw new InvalidOperationException("shapes not aligned");
    }

    /// <summary><c>np.linalg.solve</c>: Gaussian elimination with partial pivoting (LAPACK gesv).</summary>
    private static double[] Solve(double[,] matrix, double[] rhs)
    {
        var n = rhs.Length;
        var a = (double[,])matrix.Clone();
        var b = (double[])rhs.Clone();
        for (var col = 0; col < n; col++)
        {
            var pivot = col;
            for (var r = col + 1; r < n; r++)
            {
                if (Math.Abs(a[r, col]) > Math.Abs(a[pivot, col]))
                    pivot = r;
            }
            if (a[pivot, col] == 0)
                throw new InvalidOperationException("Singular matrix");
            if (pivot != col)
            {
                for (var c = 0; c < n; c++)
                    (a[col, c], a[pivot, c]) = (a[pivot, c], a[col, c]);
                (b[col], b[pivot]) = (b[pivot], b[col]);
            }
            for (var r = col + 1; r < n; r++)
            {
                var factor = a[r, col] / a[col, col];
                if (factor == 0)
                    continue;
                for (var c = col; c < n; c++)
                    a[r, c] -= factor * a[col, c];
                b[r] -= factor * b[col];
            }
        }
        var x = new double[n];
        for (var r = n - 1; r >= 0; r--)
        {
            var sum = b[r];
            for (var c = r + 1; c < n; c++)
                sum -= a[r, c] * x[c];
            x[r] = sum / a[r, r];
        }
        return x;
    }
}
