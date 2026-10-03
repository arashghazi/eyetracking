using System.Net;
using System.Text.Json.Nodes;
using EyeTracking.Domain;

namespace EyeTracking.Tests;

/// <summary>Step 1 rules. The HTTP behaviour is covered by the shared contract tests
/// (backend/tests with EYETRACKING_PARITY=dotnet); these check the C#-only pieces.</summary>
public sealed class AccountTests : IClassFixture<AccountTests.Factory>
{
    public sealed class Factory : IDisposable
    {
        public ApiFactory Api { get; } = new();
        public void Dispose() => Api.Dispose();
    }

    private readonly ApiFactory _api;

    public AccountTests(Factory f) => _api = f.Api;

    [Fact]
    public void Demographics_answers_follow_python_rules()
    {
        var form = new DemographicsForm
        {
            Version = 1,
            Fields =
            [
                new JsonObject { ["key"] = "age", ["label"] = "Age", ["type"] = "number", ["required"] = true },
                new JsonObject { ["key"] = "gender", ["label"] = "G", ["type"] = "choice", ["options"] = new JsonArray("a", "b"), ["required"] = false },
                new JsonObject { ["key"] = "diagnosis", ["label"] = "D", ["type"] = "boolean", ["required"] = true },
            ],
        };
        form.Validate();
        form.ValidateAnswers(new JsonObject { ["age"] = 25, ["diagnosis"] = true });
        Assert.Throws<Invalid>(() => form.ValidateAnswers(new JsonObject { ["age"] = true, ["diagnosis"] = true }));
        Assert.Throws<Invalid>(() => form.ValidateAnswers(new JsonObject { ["age"] = 3, ["diagnosis"] = "yes" }));
        Assert.Throws<Invalid>(() => form.ValidateAnswers(new JsonObject { ["age"] = 3, ["diagnosis"] = true, ["gender"] = "c" }));
        Assert.Throws<Invalid>(() => form.ValidateAnswers(new JsonObject { ["diagnosis"] = true, ["age"] = "" }));
        Assert.True(form.IsComplete(new JsonObject { ["age"] = 1, ["diagnosis"] = false }));
        Assert.False(form.IsComplete(null));
    }

    [Fact]
    public void Enum_and_float_wire_format_matches_python()
    {
        Assert.Equal("camera_ok", SessionStatus.CameraOk.Value());
        Assert.Equal("four_choice", ResponseMode.FourChoice.Value());
        Assert.Equal(AssignmentStatus.PendingTopic, Wire.Parse<AssignmentStatus>("pending_topic"));
        Assert.Equal("1.0", Json.PythonFloat(1));
        Assert.Equal("0.25", Json.PythonFloat(0.25));
        Assert.Equal("2026-10-03T10:15:00", JsonFormat.Timestamp(new DateTime(2026, 10, 3, 10, 15, 0)));
        Assert.Equal("2026-10-03T10:15:00.123456", JsonFormat.Timestamp(new DateTime(2026, 10, 3, 10, 15, 0).AddTicks(1234560)));
    }

    [Fact]
    public async Task Health_validation_shape_and_bearer_errors()
    {
        var c = _api.Fresh();
        Assert.Equal("ok", (string)(await (await c.GetAsync("/health")).Json())["status"]!);

        var missing = await c.PostAsync("/auth/login", new StringContent("{}", System.Text.Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, missing.StatusCode);
        var detail = (await missing.Json())["detail"]!.AsArray();
        Assert.Contains(detail, e => (string)e!["loc"]![1]! == "email" && (string)e["msg"]! == "Field required");

        var noToken = await c.GetAsync("/me");
        Assert.Equal(HttpStatusCode.Unauthorized, noToken.StatusCode);
        Assert.Equal("authentication required", (string)(await noToken.Json())["detail"]!);
        Assert.Equal("invalid or expired token", (string)(await (await c.Get("/me", "nonsense")).Json())["detail"]!);

        var admin = await c.Login(ApiFactory.AdminEmail, ApiFactory.AdminPassword);
        var study = await c.Post("/studies", new { name = "" }, admin);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, study.StatusCode);
        Assert.Equal("string_too_short", (string)(await study.Json())["detail"]![0]!["type"]!);

        var notFound = await c.GetAsync("/no/such/route");
        Assert.Equal(HttpStatusCode.NotFound, notFound.StatusCode);
        Assert.Equal("Not Found", (string)(await notFound.Json())["detail"]!);
    }

    [Fact]
    public async Task Invitation_tokens_and_codes_match_exactly()
    {
        var c = _api.Fresh();
        var admin = await c.Login(ApiFactory.AdminEmail, ApiFactory.AdminPassword);
        var studyId = (int)(await (await c.Post("/studies", new { name = "S" }, admin)).Json())["id"]!;
        var researcher = (int)(await (await c.Post("/users", new { email = "r@test.local", password = "staff-password-1", role = "researcher" }, admin)).Json())["id"]!;
        await c.Post($"/studies/{studyId}/members", new { user_id = researcher, study_role = "researcher" }, admin);
        var r = await c.Login("r@test.local", "staff-password-1");
        var inv = await (await c.Post($"/studies/{studyId}/invitations", new { }, r)).Json();
        var token = (string)inv["token"]!;
        var flipped = token.ToUpperInvariant() == token ? token.ToLowerInvariant() : token.ToUpperInvariant();
        var wrongCase = await c.PostAsync($"/invitations/{flipped}/accept",
            System.Net.Http.Json.JsonContent.Create(new { email = "p@test.local", password = "participant-pw-1" }));
        Assert.Equal(HttpStatusCode.NotFound, wrongCase.StatusCode);
        await c.PostAsync($"/invitations/{token}/accept",
            System.Net.Http.Json.JsonContent.Create(new { email = "p@test.local", password = "participant-pw-1" }));
        Assert.Equal(HttpStatusCode.NotFound, (await c.Get($"/studies/{studyId}/participants/p-001", r)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await c.Get($"/studies/{studyId}/participants/P-001", r)).StatusCode);
    }
}
