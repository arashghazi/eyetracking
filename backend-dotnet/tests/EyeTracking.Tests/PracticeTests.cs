using System.Net;
using System.Net.Http.Headers;
using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Infrastructure;
using Microsoft.Extensions.DependencyInjection;

namespace EyeTracking.Tests;

/// <summary>Step 3 rules. The HTTP behaviour is covered by the shared contract tests
/// (backend/tests/test_practice.py with EYETRACKING_PARITY=dotnet); these cover what they cannot
/// reach: the signed media token format, link expiry, and the rules' Python edge cases.</summary>
public sealed class PracticeTests : IClassFixture<PracticeTests.Factory>
{
    public sealed class Factory : IDisposable
    {
        /// <summary>Unix seconds seen by the media signer of the in-process API.</summary>
        public double Now { get; set; } = 1_000_000;

        public ApiFactory Api { get; }

        public Factory() =>
            Api = new ApiFactory().Override(s => s.AddSingleton<IMediaSigner>(new HmacMediaSigner("test-secret", 60, () => Now)));

        public void Dispose() => Api.Dispose();
    }

    private readonly Factory _f;

    public PracticeTests(Factory f) => _f = f;

    [Fact]
    public void Media_tokens_have_the_python_format()
    {
        // HmacMediaSigner("test-secret", 60).sign(5) in Python at time.time() == 1000.7
        const string python = "eyJtIjogNSwgImUiOiAxMDYwfQ.43178db61d2a971effa3a1f4bbf88fa771c9b95e1a591466414c0f102197a0b3";
        var now = 1000.7;
        var signer = new HmacMediaSigner("test-secret", 60, () => now);
        Assert.Equal(python, signer.Sign(5));
        now = 1060.0;
        Assert.Equal(5, signer.Verify(python));
        now = 1060.5;
        Assert.Null(signer.Verify(python));
        now = 1000;
        Assert.Null(new HmacMediaSigner("other-secret", 60, () => now).Verify(python));
        Assert.Null(signer.Verify(python[..^4] + "0000"));
        Assert.Null(signer.Verify(python.ToUpperInvariant()));
        Assert.Null(signer.Verify(python + "é"));
        Assert.Null(signer.Verify("not-a-token"));
        Assert.Null(signer.Verify("."));
    }

    [Fact]
    public void Media_store_stays_inside_its_root()
    {
        var root = Path.Combine(Path.GetTempPath(), "eyetracking-cs-store-" + Guid.NewGuid().ToString("N")[..8]);
        try
        {
            var store = new LocalMediaStore(root);
            Assert.Equal("study-1/content-2/a.webm", store.Save("study-1/content-2/a.webm", [1, 2, 3]));
            Assert.Equal(3, File.ReadAllBytes(store.Absolute("study-1/content-2/a.webm")).Length);
            Assert.Throws<ArgumentException>(() => store.Absolute("../evil"));
            Assert.Throws<ArgumentException>(() => store.Absolute(""));
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, recursive: true);
        }
        Assert.Equal("s1.webm", PracticeRules.SafeKey("s1.webm"));
        foreach (var bad in new[] { "", ".hidden", "a/b", "..%2Fevil", "a b", new string('a', 121) })
            Assert.Equal("media key may only contain letters, digits, dot, dash and underscore", Assert.Throws<Invalid>(() => PracticeRules.SafeKey(bad)).Message);
    }

    private static JsonObject Gradual() => JsonNode.Parse("""
        {"path": "gradual_face", "baseline_seconds": 30, "post_seconds": 30,
         "comfort": {"scale_max": 5, "labels": ["1", "2", "3", "4", "5"], "min_ok": 3},
         "progression": {"hold_on_invalid_share_above": 0.3, "easier_on_comfort_below_min": true, "stop_on_two_low_comfort": true},
         "gradual": {"final_zone_limit": "near_eyes", "stages": [
            {"face_level": 0, "number_zone": "outside", "trials": 2, "min_correct": 0.5, "trial_seconds": 8},
            {"face_level": 1, "number_zone": "outside", "trials": 2, "min_correct": 1.0, "trial_seconds": 8}]}}
        """)!.AsObject();

    private static List<Trial> Trials(params bool[] correct) => correct.Select(c => new Trial { Correct = c }).ToList();

    [Fact]
    public void Stages_never_advance_on_discomfort_invalid_data_or_errors()
    {
        var d = Gradual();
        Assert.Equal(("easier", 0), Decide(PracticeRules.EvaluateStage(d, 1, Trials(true, true), 2, 0, 0)));
        Assert.Equal(("hold", 0), Decide(PracticeRules.EvaluateStage(d, 0, Trials(true, true), 2, 0, 0)));
        Assert.Equal(("stop", null), Decide(PracticeRules.EvaluateStage(d, 1, Trials(true, true), 1, 0, 1)));
        Assert.Equal(("hold", 1), Decide(PracticeRules.EvaluateStage(d, 1, Trials(true, true), 4, 0.31, 0)));
        Assert.Equal(("hold", 1), Decide(PracticeRules.EvaluateStage(d, 1, Trials(true), null, 0, 0)));
        Assert.Equal(("hold", 1), Decide(PracticeRules.EvaluateStage(d, 1, Trials(true, false), null, 0, 0)));
        Assert.Equal(("advance", 1), Decide(PracticeRules.EvaluateStage(d, 0, Trials(true, false), null, 0.3, 5)));
        var done = PracticeRules.EvaluateStage(d, 1, Trials(true, true), 5, 0, 0);
        Assert.Equal(("complete", "all_stages_done", null, 1.0, 2), (done.Decision, done.Reason, done.NextStageIndex, done.CorrectRatio, done.Trials));
        Assert.Null(PracticeRules.EvaluateStage(d, 0, [], null, 0, 0).CorrectRatio);
        Assert.Equal("stage_index is out of range for this protocol", Assert.Throws<Invalid>(() => PracticeRules.EvaluateStage(d, 2, [], null, 0, 0)).Message);

        static (string, int?) Decide(StageDecision s) => (s.Decision, s.NextStageIndex);
    }

    [Fact]
    public void Protocol_validation_messages_match_python()
    {
        PracticeRules.ValidateProtocol(Gradual());
        string Error(Action<JsonObject> change)
        {
            var d = Gradual();
            change(d);
            return Assert.Throws<Invalid>(() => PracticeRules.ValidateProtocol(d)).Message;
        }
        Assert.Equal("path must be one of ('gradual_face', 'interest_conversation', 'live_conversation')", Error(d => d["path"] = 3));
        Assert.Equal("definition.baseline_seconds must be a number between 10 and 600", Error(d => d["baseline_seconds"] = true));
        Assert.Equal("comfort.min_ok must be a number between 1 and 5", Error(d => d["comfort"]!["min_ok"] = 6));
        Assert.Equal("progression.stop_on_two_low_comfort must be true or false", Error(d => d["progression"]!["stop_on_two_low_comfort"] = 1));
        Assert.Equal("gradual.stages[1].number_zone goes beyond final_zone_limit outside",
            Error(d => { d["gradual"]!["final_zone_limit"] = "outside"; d["gradual"]!["stages"]![1]!["number_zone"] = "near_eyes"; }));
        Assert.Equal("gradual.stages[1] changes both face_level and number_zone; allow_simultaneous_change is off",
            Error(d => d["gradual"]!["stages"]![1]!["number_zone"] = "face_edge"));
        Assert.Equal("live settings are required for the live_conversation path", Error(d => d["path"] = "live_conversation"));
        // face_level 1.9 counts as level 1, as int() truncates
        var truncated = Gradual();
        truncated["gradual"]!["stages"]![1]!["face_level"] = 1.9;
        PracticeRules.ValidateProtocol(truncated);
    }

    [Fact]
    public void Outcomes_follow_python_numbers()
    {
        // statistics.mean of ints is an int when it divides evenly; round() keeps it so
        Assert.Equal("""{"answers":2,"min":4,"mean":4,"low_count":0,"pauses":1,"ended_early":false}""",
            PracticeRules.ComfortOutcome([4, 4], 3, 1, false).ToJsonString());
        Assert.Equal("2.33", PracticeRules.ComfortOutcome([4, 2, 1], 3, 0, true)["mean"]!.ToJsonString());
        Assert.Equal("""{"answers":0,"min":null,"mean":null,"low_count":0,"pauses":0,"ended_early":true}""",
            PracticeRules.ComfortOutcome([], 3, 0, true).ToJsonString());

        var gaze = new JsonObject { ["baseline_eye_share"] = 0.4, ["post_eye_share"] = 0.6, ["evaluable"] = true, ["reason"] = null };
        var comp = new JsonObject { ["share"] = 0.5 };
        var task = new JsonObject { ["share"] = null };
        Assert.Equal("""{"eligible":true,"result":true,"criteria":{"eye_share_up":true,"comfort_not_worse":true,"comprehension_maintained":true},"reason":null}""",
            PracticeRules.Improvement(gaze, comp, task, [3, 4], 3, "interest_conversation").ToJsonString());
        Assert.Equal("no_content_responses", (string)PracticeRules.Improvement(gaze, comp, task, [3, 4], 3, "gradual_face")["reason"]!);
        Assert.Equal("no_comfort_answers", (string)PracticeRules.Improvement(gaze, comp, task, [], 3, "gradual_face")["reason"]!);
        Assert.False((bool)PracticeRules.Improvement(gaze, comp, task, [4, 2], 3, "interest_conversation")["result"]!);
        var conv = LiveRules.ConversationOutcome([], null);
        Assert.Equal("no_content_responses", (string)PracticeRules.Improvement(gaze, comp, task, [3, 4], 3, "live_conversation", conv)["reason"]!);
        gaze["evaluable"] = false;
        gaze["reason"] = "synthetic_estimator";
        Assert.Equal("synthetic_estimator", (string)PracticeRules.Improvement(gaze, comp, task, [3, 4], 3, "interest_conversation")["reason"]!);
    }

    [Fact]
    public void Options_are_matched_as_the_participant_saw_them()
    {
        var content = JsonNode.Parse("""
            {"start_segment": "s1", "segments": [
               {"id": "s1", "duration_s": 5, "question": {"id": "q", "prompt": "p", "options": ["{{ topic }}", "Other"], "branches": {"Other": "s2"}}},
               {"id": "s2", "duration_s": 5}],
             "comprehension": [{"id": "c", "prompt": "n?", "options": [1, 2], "correct": 1.0}]}
            """)!.AsObject();
        PracticeRules.ValidateContent(content);
        Assert.Equal("Hi there, about your topic.", PracticeRules.Personalize("Hi {{display_name}}, about {{topic}}.", "", null));
        Assert.Null(PracticeRules.NextSegment(content, "s1", "Trains", "Sam", "Trains"));
        Assert.Equal("s2", PracticeRules.NextSegment(content, "s1", "Other", "Sam", "Trains"));
        Assert.Throws<Invalid>(() => PracticeRules.NextSegment(content, "s1", "{{ topic }}", "Sam", "Trains"));
        Assert.Equal("this segment has no question", Assert.Throws<Invalid>(() => PracticeRules.NextSegment(content, "s2", "x")).Message);
        // options that are not text cannot be shown; Python fails with a TypeError (a 500)
        Assert.Throws<InvalidOperationException>(() => PracticeRules.ComprehensionCorrect(content, "c", "1"));
        content["comprehension"]![0]!["options"] = new JsonArray("1", "2");
        Assert.Equal("comprehension[0].correct must be one of its options", Assert.Throws<Invalid>(() => PracticeRules.ValidateContent(content)).Message);
    }

    [Fact]
    public async Task Media_links_expire()
    {
        var c = _f.Api.Fresh();
        var admin = await c.Login(ApiFactory.AdminEmail, ApiFactory.AdminPassword);
        var studyId = (int)(await (await c.Post("/studies", new { name = "S" }, admin)).Json())["id"]!;
        var staffId = (int)(await (await c.Post("/users", new { email = "r@test.local", password = "staff-password-1", role = "researcher" }, admin)).Json())["id"]!;
        await c.Post($"/studies/{studyId}/members", new { user_id = staffId, study_role = "researcher" }, admin);
        var r = await c.Login("r@test.local", "staff-password-1");
        var definition = new { start_segment = "s1", segments = new[] { new { id = "s1", text = "Hi", media_key = "s1.webm", duration_s = 5 } } };
        var created = await c.Post($"/studies/{studyId}/content", new { title = "T", definition }, r);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var contentId = (int)(await created.Json())["id"]!;

        var form = new MultipartFormDataContent();
        var file = new ByteArrayContent(new byte[100]);
        file.Headers.ContentType = new MediaTypeHeaderValue("video/webm");
        form.Add(file, "file", "s1.webm");
        var upload = await c.SendAsync(new HttpRequestMessage(HttpMethod.Post, $"/studies/{studyId}/content/{contentId}/media/s1.webm") { Content = form }.As(r));
        Assert.Equal(HttpStatusCode.Created, upload.StatusCode);
        Assert.Equal("""{"key":"s1.webm","content_type":"video/webm","size":100}""", (await upload.Json()).ToJsonString());

        _f.Now = 2_000_000;
        var url = (string)(await (await c.Get($"/studies/{studyId}/content/{contentId}/media", r)).Json())[0]!["url"]!;
        var ok = await c.GetAsync(url);
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        Assert.Equal(100, (await ok.Content.ReadAsByteArrayAsync()).Length);
        _f.Now = 2_000_060.5;
        var expired = await c.GetAsync(url);
        Assert.Equal(HttpStatusCode.NotFound, expired.StatusCode);
        Assert.Equal("media link is invalid or has expired", (string)(await expired.Json())["detail"]!);
    }
}
