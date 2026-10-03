using System.Net;
using System.Text.Json.Nodes;
using EyeTracking.Domain;

namespace EyeTracking.Tests;

/// <summary>Step 2 rules. The HTTP behaviour is covered by the shared contract tests
/// (backend/tests/test_measurement.py with EYETRACKING_PARITY=dotnet); these cover the
/// python_only test and the numeric pieces that replace Python and numpy.</summary>
public sealed class MeasurementTests : IClassFixture<MeasurementTests.Factory>
{
    public sealed class Factory : IDisposable
    {
        public ApiFactory Api { get; } = new();
        public void Dispose() => Api.Dispose();
    }

    private static readonly JsonObject Layout = new()
    {
        ["screen"] = new JsonObject { ["w"] = 1280, ["h"] = 720, ["dpr"] = 1 },
        ["face_box"] = new JsonArray(440, 120, 400, 480),
        ["eye_region"] = new JsonArray(440, 190, 400, 170),
        ["mouth_region"] = new JsonArray(440, 390, 400, 190),
    };

    private readonly ApiFactory _api;

    public MeasurementTests(Factory f) => _api = f.Api;

    /// <summary>test_measurement.py::test_coverage_counts_gaps_as_missing</summary>
    [Fact]
    public void Coverage_counts_gaps_as_missing()
    {
        var events = new List<SessionEvent>
        {
            new() { SessionId = 1, TMs = 0, Type = "segment_start", Payload = new JsonObject { ["segment"] = "baseline" } },
            new() { SessionId = 1, TMs = 10000, Type = "segment_end" },
        };
        var samples = Enumerable.Range(0, 21)
            .Select(i => new GazeSample { SessionId = 1, TMs = i * 100, X = 1.0, Y = 1.0, Conf = 0.9, Valid = true, Region = "eye", Segment = "baseline" })
            .ToList();
        samples.Add(new GazeSample { SessionId = 1, TMs = 2100, X = null, Y = null, Conf = 0.0, Valid = false, Region = "uncertain", Segment = "baseline" });
        var segs = MeasurementRules.SegmentsFromEvents(events, 2100);
        var cov = MeasurementRules.Coverage(samples, segs);
        Assert.Equal((10000L, 2100L, 200L, 7700L), (cov.TotalMs, cov.ClassifiableMs, cov.UncertainMs, cov.MissingMs));
        // an unfinished segment ends at the last sample
        segs = MeasurementRules.SegmentsFromEvents(events.Take(1), 2100);
        Assert.Equal("""[{"label":"baseline","started_ms":0,"ended_ms":2100}]""",
            new JsonArray(segs.Select(s => (JsonNode?)s.ToJson()).ToArray()).ToJsonString());
    }

    [Fact]
    public void Rounding_and_statistics_follow_python_and_numpy()
    {
        // Math.Round scales first and gives 0.02, 0.02 and 0.0002 here
        Assert.Equal(0.01, PyMath.Round(0.015, 2));
        Assert.Equal(0.03, PyMath.Round(0.025, 2));
        Assert.Equal(0.0003, PyMath.Round(0.00025, 4));
        Assert.Equal(0.12, PyMath.Round(0.125, 2));
        Assert.Equal(0.6667, PyMath.Round(2 / 3.0, 4));
        Assert.True(double.IsNegative(PyMath.Round(-0.001, 2)));
        Assert.Equal(2.5, PyMath.Median([4.0, 1.0, 3.0, 2.0]));
        Assert.Equal(9.0, PyMath.Percentile([3.0, 1.0, 2.0, 10.0, 7.5], 90));
        Assert.Equal(1.9, PyMath.Percentile([1.0, 2.0], 90));
        Assert.Equal("correct_ratio_below_0.8", $"correct_ratio_below_{Json.PythonFloat(0.8)}");
    }

    private static RawSample Raw(double x, double y, int t = 0, double conf = 0.9) =>
        new(t, true, [200, 120, 240, 240], conf, (x - 640) / 20.0, (y - 360) / 15.0, conf, 640, 480);

    [Fact]
    public void Calibration_fit_recovers_a_linear_mapping_and_classifies()
    {
        var targets = (from x in new[] { 128.0, 640.0, 1152.0 }
                       from y in new[] { 72.0, 360.0, 648.0 }
                       select new CalibrationTarget(x, y, Enumerable.Range(0, 8).Select(i => Raw(x, y, i * 100)).ToList())).ToList();
        var cal = MeasurementRules.FitCalibration(targets, 0.5);
        Assert.Equal(9, cal.Points);
        Assert.True(cal.ResidualPxMedian < 0.01 && cal.ResidualPxP90 < 0.01);
        Assert.Equal(9, cal.PerTarget.Count);
        Assert.Equal(8, (int)cal.PerTarget[0]!["n_valid"]!);

        var (point, conf, region) = MeasurementRules.ClassifyRaw(cal.Params, Raw(540, 270), Layout, 0.5);
        Assert.Equal(540, point!.Value.X, 3);
        Assert.Equal(270, point.Value.Y, 3);
        Assert.Equal((0.9, "eye"), (conf, region));
        Assert.Equal("mouth", MeasurementRules.ClassifyRaw(cal.Params, Raw(640, 480), Layout, 0.5).Region);
        Assert.Equal("outside", MeasurementRules.ClassifyRaw(cal.Params, Raw(60, 60), Layout, 0.5).Region);
        Assert.Equal("uncertain", MeasurementRules.ClassifyRaw(cal.Params, Raw(540, 270, conf: 0.1), Layout, 0.5).Region);

        var weak = targets.Select(t => t with { Samples = t.Samples.Select(s => s with { FaceConf = 0.2 }).ToList() }).ToList();
        var e = Assert.Throws<Invalid>(() => MeasurementRules.FitCalibration(weak, 0.5));
        Assert.Equal("calibration needs at least 5 targets with 5 valid samples each; got 0", e.Message);
    }

    [Fact]
    public async Task Sessions_start_at_id_1_and_errors_have_fastapi_shape()
    {
        var c = _api.Fresh();
        var admin = await c.Login(ApiFactory.AdminEmail, ApiFactory.AdminPassword);
        var studyId = (int)(await (await c.Post("/studies", new { name = "S" }, admin)).Json())["id"]!;
        var staffId = (int)(await (await c.Post("/users", new { email = "r@test.local", password = "staff-password-1", role = "researcher" }, admin)).Json())["id"]!;
        await c.Post($"/studies/{studyId}/members", new { user_id = staffId, study_role = "researcher" }, admin);
        var r = await c.Login("r@test.local", "staff-password-1");
        var invitation = (string)(await (await c.Post($"/studies/{studyId}/invitations", new { }, r)).Json())["token"]!;
        var accepted = await c.PostAsync($"/invitations/{invitation}/accept",
            System.Net.Http.Json.JsonContent.Create(new { email = "p@test.local", password = "participant-pw-1" }));
        var p = (string)(await accepted.Json())["access_token"]!;
        await c.Put($"/studies/{studyId}/information-sheet",
            new { aims = "a", discomfort_sources = "d", benefits = "b", data_handling = "h", stop_rules = "s" }, r);
        await c.Post("/me/consent", new { sheet_version = 1, participate = true }, p);

        var created = await c.Post("/me/sessions", new { screen = new { w = 1280, h = 720 } }, p);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var session = await created.Json();
        Assert.Equal(1, (int)session["id"]!);
        Assert.Equal("exclude", (string)session["quality"]!["grade"]!);

        var empty = await (await c.Post("/me/sessions/1/calibration", new { targets = Array.Empty<object>() }, p)).Json();
        Assert.Equal("""{"type":"too_short","loc":["body","targets"],"msg":"List should have at least 1 item after validation, not 0","input":[],"ctx":{"field_type":"List","min_length":1,"actual_length":0}}""",
            empty["detail"]![0]!.ToJsonString());
        var region = await (await c.Post("/me/sessions/1/validation",
            new { layout = new { }, targets = new[] { new { region = "nose", x = 1, y = 2, samples = Array.Empty<object>() } } }, p)).Json();
        Assert.Equal("""["body","targets",0,"region"]""", region["detail"]![0]!["loc"]!.ToJsonString());

        var query = await c.Get($"/studies/{studyId}/sessions/1/samples?offset=-1&limit=abc", r);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, query.StatusCode);
        var detail = (await query.Json())["detail"]!.AsArray();
        Assert.Equal(new[] { "greater_than_equal", "int_parsing" }, detail.Select(d => (string)d!["type"]!));
        Assert.Equal("-1", (string)detail[0]!["input"]!);
        var page = await (await c.Get($"/studies/{studyId}/sessions/1/samples?offset=1.0&limit=+2", r)).Json();
        Assert.Equal(0, (int)page["total"]!);
    }
}
