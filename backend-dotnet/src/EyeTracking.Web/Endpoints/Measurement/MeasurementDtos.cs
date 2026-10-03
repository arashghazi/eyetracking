using System.Globalization;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Measurement;

// HTTP shapes of build step 2 (the pydantic models in backend/eyetracking/web/routers/sessions.py).
// Raw samples use the domain's RawSample record, which carries the request model's defaults.

public sealed record SettingsOut(
    double ValidationMinCorrect,
    double ValidationMaxUncertain,
    double MinRegionToErrorRatio,
    double GazeConfThreshold,
    int CalibrationPoints,
    bool AllowContinueWithoutValidation,
    double QualityMaxUncertainShare,
    double QualityMaxMissingShare,
    int Version = 1)
{
    public static SettingsOut From(MeasurementSettings s) => new(
        s.ValidationMinCorrect, s.ValidationMaxUncertain, s.MinRegionToErrorRatio, s.GazeConfThreshold, s.CalibrationPoints,
        s.AllowContinueWithoutValidation, s.QualityMaxUncertainShare, s.QualityMaxMissingShare, s.Version);
}

public sealed record SettingsIn(
    string? Rationale = null,
    double? ValidationMinCorrect = null,
    double? ValidationMaxUncertain = null,
    double? MinRegionToErrorRatio = null,
    double? GazeConfThreshold = null,
    int? CalibrationPoints = null,
    bool? AllowContinueWithoutValidation = null,
    double? QualityMaxUncertainShare = null,
    double? QualityMaxMissingShare = null);

public sealed record SessionCreateIn(JsonObject Screen)
{
    public JsonObject Device { get; init; } = [];
    public JsonObject Camera { get; init; } = [];
    public JsonObject GazeModel { get; init; } = [];
    public int? AssignmentId { get; init; }
}

public sealed record CameraCheckIn(
    bool FaceDetected,
    double FaceConf = 0.0,
    bool LightingOk = true,
    int FrameW = 0,
    int FrameH = 0,
    string? CameraLabel = null);

public sealed record CalibrationTargetIn(double X, double Y, List<RawSample> Samples);

public sealed record CalibrationIn(List<CalibrationTargetIn> Targets) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Items(errors, Targets, "targets", min: 1, max: 16);
}

public sealed record CalibrationOut(int CalibrationId, double ResidualPxMedian, double ResidualPxP90, JsonArray PerTarget, bool Accepted, IReadOnlyList<string> Reasons);

public sealed record ValidationTargetIn(string Region, double X, double Y, List<RawSample> Samples);

public sealed record ValidationIn(JsonObject Layout, List<ValidationTargetIn> Targets) : IValidatedBody
{
    public void Validate(List<JsonObject> errors)
    {
        for (var i = 0; i < Targets.Count; i++)
            Check.LiteralAt(errors, Targets[i].Region, ["body", "targets", i.ToString(CultureInfo.InvariantCulture), "region"], "eye", "mouth", "outside");
        Check.Items(errors, Targets, "targets", min: 1, max: 20);
    }
}

public sealed record ValidationOut(
    int ValidationId, bool Passed, double CorrectRatio, double UncertainRatio, double SizeRatio, IReadOnlyList<string> Reasons, JsonArray Targets);

public sealed record LayoutIn(string Segment, JsonObject Layout, int? StageIndex = null) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Literal(errors, Segment, "segment", "baseline", "practice", "post", "free");
}

public sealed record SamplesIn(List<RawSample> Samples) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Items(errors, Samples, "samples", min: 1, max: 500);
}

public sealed record EventIn(int TMs, string Type, JsonObject? Payload = null);

public sealed record SamplesPage(int Total, JsonArray Items);
