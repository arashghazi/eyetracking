using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Anthropic;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Infrastructure.Ai;
using EyeTracking.Infrastructure.Db;
using EyeTracking.Web;
using EyeTracking.Web.Endpoints.Ai;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;

namespace EyeTracking.Tests;

/// <summary>Step 5 rules. The HTTP flow with the development providers is covered by the shared
/// contract test (backend/tests/test_ai.py with EYETRACKING_PARITY=dotnet); these are the C#
/// versions of the tests that swap providers, drive the worker, or check the adapters' requests
/// against stub transports. No real Anthropic or HeyGen call is ever made.</summary>
public sealed class AiTests : IClassFixture<AiTests.Factory>
{
    /// <summary>A text provider the test can swap while the API runs (app.state.ai_providers in Python).</summary>
    public sealed class SwitchText : ITextGenerator
    {
        public ITextGenerator Inner { get; set; } = new FakeTextGenerator();
        public JsonObject Info() => Inner.Info();
        public double EstimateCost(TextRequest req) => Inner.EstimateCost(req);
        public Task<(JsonObject Data, JsonObject Meta)> Generate(TextRequest req) => Inner.Generate(req);
    }

    public sealed class Factory : IDisposable
    {
        public SwitchText Text { get; } = new();
        public ApiFactory Api { get; }

        public Factory() => Api = new ApiFactory().Override(s => s.AddSingleton(new AiProviders(Text, new FakeVideoGenerator())));

        public void Dispose() => Api.Dispose();
    }

    private readonly Factory _f;

    public AiTests(Factory f)
    {
        _f = f;
        _f.Text.Inner = new FakeTextGenerator();
    }

    private sealed record World(HttpClient C, string Admin, string Researcher, string Analyst, int StudyId);

    private async Task<World> Setup()
    {
        var c = _f.Api.Fresh();
        var admin = await c.Login(ApiFactory.AdminEmail, ApiFactory.AdminPassword);
        var studyId = (int)(await (await c.Post("/studies", new { name = "Study A" }, admin)).Json())["id"]!;
        async Task<string> Staff(string email, string role)
        {
            var id = (int)(await (await c.Post("/users", new { email, password = "staff-password-1", role }, admin)).Json())["id"]!;
            Assert.Equal(HttpStatusCode.Created, (await c.Post($"/studies/{studyId}/members", new { user_id = id, study_role = role }, admin)).StatusCode);
            return await c.Login(email, "staff-password-1");
        }
        return new World(c, admin, await Staff("ra@test.local", "researcher"), await Staff("an@test.local", "analyst"), studyId);
    }

    // ---------- domain rules against Python's output ----------

    [Fact]
    public void Sample_script_schema_and_prompts_match_python()
    {
        var req = new TextRequest("Birds", null, [], 2, 90);
        Assert.Equal(JsonNode.Parse("""{"start_segment":"s1","post_segment":"s3","segments":[{"id":"s1","text":"[Sample content from the development provider] Hi there. Today I would like to talk with you about Birds. I find it interesting because there is always something new to notice.","duration_s":20,"question":{"id":"q1","prompt":"What would you like to hear about Birds first?","options":["How it started","What people enjoy about it"],"branches":{"How it started":"s2","What people enjoy about it":"s2"}},"media_key":"s1.webm"},{"id":"s2","text":"[Sample content from the development provider] Thank you for choosing. Many people say the best part of Birds is sharing it with someone else. It can be quiet or lively, and both are fine.","duration_s":20,"question":{"id":"q2","prompt":"Would you like one more short part?","options":["Yes","No"],"branches":{"Yes":"s3","No":"s3"}},"media_key":"s2.webm"},{"id":"s3","text":"[Sample content from the development provider] That is all for today, there. Thank you for listening. You can stop here or come back another time.","duration_s":12,"question":null,"media_key":"s3.webm"}],"comprehension":[{"id":"c1","prompt":"What was the conversation about?","options":["Birds","The weather"],"correct":"Birds"},{"id":"c2","prompt":"What did the speaker say is the best part?","options":["Sharing it with someone","Doing it alone"],"correct":"Sharing it with someone"}]}""")!.ToJsonString(),
            AiRules.SampleScript(req).ToJsonString());
        Assert.Equal(JsonNode.Parse(PythonSchema)!.ToJsonString(), AiRules.ContentSchema().ToJsonString());
        var (system, user) = AiRules.ScriptPrompt(new TextRequest("Trains", null, [], 2, 90, "steam engines"));
        Assert.Equal(PythonSystem, system);
        Assert.Equal("Topic: Trains.\nDo not use a name.\nTotal spoken length about 90 seconds across the segments (each 10 to 60 seconds).\nInclude 2 question point(s) between segments, then a final segment with no question that also serves as post_segment.\nSegment ids: s1, s2, ...; question ids q1, q2, ...; comprehension ids c1, c2 (two questions).\nThe participant added: steam engines", user);
        Assert.Equal("""{"topic":"Trains","display_name":null,"interests":[],"interaction_points":2,"length_seconds":90,"free_text_included":true}""",
            new TextRequest("Trains", null, [], 2, 90, "").Minimized().ToJsonString());

        // the model's branch lists become a mapping (a later duplicate option wins) and the title goes
        var model = JsonNode.Parse("""{"title":"t","segments":[{"id":"s1","question":{"branches":[{"option":"a","segment":"s1"},{"option":"a","segment":"s2"},{"option":"b","segment":"s3"}]}},{"id":"s2","question":null}]}""")!.AsObject();
        Assert.Equal("""{"segments":[{"id":"s1","question":{"branches":{"a":"s2","b":"s3"}}},{"id":"s2","question":null}]}""", AiRules.BranchesToDict(model).ToJsonString());
        Assert.Equal("t", (string)model["title"]!);
    }

    [Fact]
    public void Budget_and_job_rules_match_python()
    {
        string Refused(double estimate, double spent, double cap) =>
            Assert.Throws<Invalid>(() => new AiBudget { CostCapUnits = cap, SpentUnits = spent }.AssertAffordable(estimate)).Message;
        // f"{v:.3f}" rounds the exact binary value: 2.0005 is just above, 1.0005 just below the midpoint
        Assert.Equal("budget_exceeded: estimate 1.500 + spent 0.000 exceeds cap 0.000", Refused(1.5, 0, 0));
        Assert.Equal("budget_exceeded: estimate 0.062 + spent 2.001 exceeds cap 1.000", Refused(0.0625, 2.0005, 1.0));
        Assert.Equal("budget_exceeded: estimate 0.000 + spent 0.300 exceeds cap 0.300", Refused(1e-4, 0.1 + 0.2, 0.3));
        Assert.Equal("budget_exceeded: estimate 2.675 + spent 1.000 exceeds cap 3.000", Refused(2.675, 1.0005, 3.0));
        new AiBudget().AssertAffordable(0);
        new AiBudget { CostCapUnits = 3, SpentUnits = 1.5 }.AssertAffordable(1.5);
        Assert.Equal(0, new AiBudget { CostCapUnits = 1, SpentUnits = 2 }.Remaining());

        var now = new DateTime(2026, 1, 1);
        var job = new GenerationJob { Kind = "text" };
        job.MarkFailure(new string('e', 1200), now);
        Assert.Equal(("queued", 1, now.AddSeconds(30), 1000, (DateTime?)null), (job.Status, job.Attempts, job.NextAttemptAt!.Value, job.Error!.Length, job.FinishedAt));
        job.MarkFailure("e", now);
        Assert.Equal(("queued", 2, now.AddSeconds(60)), (job.Status, job.Attempts, job.NextAttemptAt!.Value));
        job.MarkFailure("e", now);
        Assert.Equal(("failed", 3, now.AddSeconds(60), now), (job.Status, job.Attempts, job.NextAttemptAt!.Value, job.FinishedAt!.Value));
        Assert.Equal("only queued jobs can be cancelled", Assert.Throws<Conflict>(job.Cancel).Message);
        job.Retry(now);
        Assert.Equal(("queued", (string?)null, now), (job.Status, job.Error, job.NextAttemptAt!.Value));
        job.Cancel();
        Assert.Equal("only failed jobs can be retried", Assert.Throws<Conflict>(() => job.Retry(now)).Message);
        var terminal = new GenerationJob();
        terminal.MarkFailure("x", now, terminal: true);
        Assert.Equal(("failed", 1), (terminal.Status, terminal.Attempts));
    }

    // ---------- test_budget_cap_retries_and_terminal_failures ----------

    [Fact]
    public async Task Budget_cap_retries_and_terminal_failures()
    {
        var w = await Setup();
        var c = w.C;
        var ai = $"/studies/{w.StudyId}/ai";
        _f.Text.Inner = new FailingTextGenerator(failures: 1, cost: 1.5);
        // a paid provider needs a cap
        var r = await c.Post($"{ai}/text-jobs", new { topic = "Birds", display_name = "Kim" }, w.Researcher);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, r.StatusCode);
        Assert.StartsWith("budget_exceeded", (string)(await r.Json())["detail"]!);
        Assert.Equal(HttpStatusCode.Forbidden, (await c.Put($"{ai}/budget", new { cost_cap_units = 5 }, w.Researcher)).StatusCode);
        r = await c.Put($"{ai}/budget", new { cost_cap_units = 5, send_free_text = true }, w.Admin);
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        Assert.Equal("""{"cost_cap_units":5.0,"spent_units":0.0,"remaining_units":5.0,"unit":"usd_estimate","send_free_text":true}""", (await r.Json()).ToJsonString());
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await c.Put($"{ai}/budget", new { cost_cap_units = -1 }, w.Admin)).StatusCode);
        var job = await (await c.Post($"{ai}/text-jobs", new { topic = "Birds", display_name = "Kim" }, w.Researcher)).Json();
        Assert.Equal(1.5, (double)job["cost_estimate_units"]!);
        var jobId = (int)job["id"]!;
        // three jobs of 1.5 fit; estimates are not reserved, so a fourth is accepted too
        await c.Post($"{ai}/text-jobs", new { topic = "Bees" }, w.Researcher);
        await c.Post($"{ai}/text-jobs", new { topic = "Boats" }, w.Researcher);
        Assert.Equal(HttpStatusCode.Created, (await c.Post($"{ai}/text-jobs", new { topic = "Bikes" }, w.Researcher)).StatusCode);

        // first pass: the provider fails once -> job re-queued with backoff, not failed
        Assert.Equal("""{"processed":1,"succeeded":0,"failed":0}""", (await (await c.Post($"{ai}/run?max_jobs=1", null, w.Researcher)).Json()).ToJsonString());
        var j = await (await c.Get($"{ai}/jobs/{jobId}", w.Researcher)).Json();
        Assert.Equal(("queued", 1, "RuntimeError: provider unavailable"), ((string)j["status"]!, (int)j["attempts"]!, (string)j["error"]!));
        Assert.NotNull(j["next_attempt_at"]);
        // backoff: the job is skipped until next_attempt_at; other queued jobs run
        Assert.Equal(1, (int)(await (await c.Post($"{ai}/run?max_jobs=1", null, w.Researcher)).Json())["processed"]!);
        Assert.Equal(1, (int)(await (await c.Get($"{ai}/jobs/{jobId}", w.Researcher)).Json())["attempts"]!);
        using (var scope = _f.Api.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>();
            db.Set<GenerationJob>().Find(jobId)!.NextAttemptAt = DateTime.UtcNow.AddSeconds(-1);
            db.SaveChanges();
        }
        Assert.Equal("""{"processed":1,"succeeded":1,"failed":0}""", (await (await c.Post($"{ai}/run?max_jobs=1", null, w.Researcher)).Json()).ToJsonString());
        j = await (await c.Get($"{ai}/jobs/{jobId}", w.Researcher)).Json();
        Assert.Equal(("succeeded", 1.5), ((string)j["status"]!, (double)j["cost_actual_units"]!));
        var st = await (await c.Get($"{ai}/status", w.Researcher)).Json();
        Assert.Equal("""{"cost_cap_units":5.0,"spent_units":3.0,"remaining_units":2.0,"unit":"usd_estimate"}""", st["budget"]!.ToJsonString());
        // now a 1.5 job still fits (3.0 + 1.5 <= 5)
        Assert.Equal(HttpStatusCode.Created, (await c.Post($"{ai}/text-jobs", new { topic = "Bugs" }, w.Researcher)).StatusCode);

        // terminal failure (refusal) fails at once and can be retried by hand; cancel only queued
        _f.Text.Inner = new FailingTextGenerator(failures: 99, cost: 0.0, terminal: true);
        var job2 = (int)(await (await c.Post($"{ai}/text-jobs", new { topic = "Cats" }, w.Researcher)).Json())["id"]!;
        await c.Post($"{ai}/run?max_jobs=50", null, w.Researcher);
        var j2 = await (await c.Get($"{ai}/jobs/{job2}", w.Researcher)).Json();
        Assert.Equal(("failed", "TerminalGenerationError: refusal: general_harms", 1), ((string)j2["status"]!, (string)j2["error"]!, (int)j2["attempts"]!));
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"{ai}/jobs/{job2}/cancel", null, w.Researcher)).StatusCode);
        Assert.Equal("queued", (string)(await (await c.Post($"{ai}/jobs/{job2}/retry", null, w.Researcher)).Json())["status"]!);
        Assert.Equal("cancelled", (string)(await (await c.Post($"{ai}/jobs/{job2}/cancel", null, w.Researcher)).Json())["status"]!);
        Assert.Equal(HttpStatusCode.Conflict, (await c.Post($"{ai}/jobs/{job2}/retry", null, w.Researcher)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await c.Post($"{ai}/jobs/{job2}/cancel", null, w.Analyst)).StatusCode);
    }

    // ---------- test_worker_run_once_processes_jobs ----------

    [Fact]
    public async Task Worker_run_once_processes_jobs()
    {
        var w = await Setup();
        Assert.Equal(HttpStatusCode.Created, (await w.C.Post($"/studies/{w.StudyId}/ai/text-jobs", new { topic = "Trains" }, w.Researcher)).StatusCode);
        var services = _f.Api.Services;
        var worker = new AiWorker(
            services.GetRequiredService<IServiceScopeFactory>(), services.GetRequiredService<AiProviders>(), services.GetRequiredService<IMediaStore>(),
            services.GetRequiredService<IClock>(), NullLogger<AiWorker>.Instance, 1);
        Assert.Equal("""{"processed":1,"succeeded":1,"failed":0}""", (await worker.RunOnce()).ToJsonString());
        Assert.Equal("""{"processed":0,"succeeded":0,"failed":0}""", (await worker.RunOnce()).ToJsonString());
        using (var scope = services.CreateScope())
        {
            var entry = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>().Set<AccessLogEntry>().Single(e => e.Action == "ai_job_run");
            Assert.Equal(("worker", 0, w.StudyId), (entry.Role, entry.UserId, entry.StudyId!.Value));
        }

        // as a hosted service it keeps passing until stopped
        var queued = (int)(await (await w.C.Post($"/studies/{w.StudyId}/ai/text-jobs", new { topic = "Boats" }, w.Researcher)).Json())["id"]!;
        await worker.StartAsync(CancellationToken.None);
        try
        {
            for (var i = 0; i < 100 && (string)(await (await w.C.Get($"/studies/{w.StudyId}/ai/jobs/{queued}", w.Researcher)).Json())["status"]! != "succeeded"; i++)
                await Task.Delay(100);
        }
        finally
        {
            await worker.StopAsync(CancellationToken.None);
        }
        Assert.Equal("succeeded", (string)(await (await w.C.Get($"/studies/{w.StudyId}/ai/jobs/{queued}", w.Researcher)).Json())["status"]!);
    }

    [Fact]
    public void Providers_and_worker_come_from_settings()
    {
        var fake = AiEndpoints.BuildProviders(new Settings());
        Assert.Equal((typeof(FakeTextGenerator), typeof(FakeVideoGenerator), false, 5), (fake.Text.GetType(), fake.Video.GetType(), fake.WorkerEnabled, fake.WorkerIntervalS));
        Assert.True((bool)fake.Video.Info()["configured"]!);
        Assert.False((bool)new FakeVideoGenerator("missing.webm").Info()["configured"]!);
        var real = AiEndpoints.BuildProviders(new Settings
        {
            AiTextProvider = "anthropic", AiTextModel = "claude-sonnet-5-5", AiVideoProvider = "heygen", AiWorkerEnabled = true, AiWorkerIntervalS = 7,
        });
        Assert.Equal("""{"name":"anthropic","model":"claude-sonnet-5-5","configured":false,"synthetic":false}""", real.Text.Info().ToJsonString());
        Assert.Equal("""{"name":"heygen","configured":false,"synthetic":false}""", real.Video.Info().ToJsonString());
        Assert.Equal((true, 7), (real.WorkerEnabled, real.WorkerIntervalS));

        int HostedServices(bool enabled)
        {
            var services = new ServiceCollection();
            new AiEndpoints().AddServices(services, new Settings { AiWorkerEnabled = enabled });
            return services.Count(s => s.ServiceType == typeof(Microsoft.Extensions.Hosting.IHostedService));
        }
        Assert.Equal((0, 1), (HostedServices(false), HostedServices(true)));
    }

    // ---------- test_anthropic_adapter_with_stub_client ----------

    /// <summary>Records every request and answers with the handler's response.</summary>
    private sealed class StubHandler(Func<HttpRequestMessage, string, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public List<(HttpRequestMessage Request, string Body)> Calls { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            Calls.Add((request, body));
            var response = respond(request, body);
            response.RequestMessage = request;
            return response;
        }
    }

    private static HttpResponseMessage JsonResponse(HttpStatusCode status, string json) =>
        new(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    private static AnthropicClient Client(StubHandler handler) =>
        new() { ApiKey = "test-key", HttpClient = new HttpClient(handler), MaxRetries = 0 };

    private static string Message(string stopReason, JsonArray content, string stopDetails = "null") =>
        $$$"""{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":{{{content.ToJsonString()}}},"stop_reason":"{{{stopReason}}}","stop_sequence":null,"stop_details":{{{stopDetails}}},"usage":{"input_tokens":1000,"output_tokens":2000}}""";

    [Fact]
    public async Task Anthropic_adapter_sends_the_python_request_and_parses_the_reply()
    {
        var req = new TextRequest("Trains", "Sam", ["trains"], 1, 60);
        var script = AiRules.SampleScript(req);
        // the model returns branches as a list of {option, segment} and a title, per the JSON schema
        var segments = new JsonArray();
        foreach (var s in script["segments"]!.AsArray())
        {
            var q = s!["question"];
            segments.Add(new JsonObject
            {
                ["id"] = s["id"]!.DeepClone(), ["text"] = s["text"]!.DeepClone(), ["duration_s"] = s["duration_s"]!.DeepClone(),
                ["question"] = q is null ? null : new JsonObject
                {
                    ["id"] = q["id"]!.DeepClone(), ["prompt"] = q["prompt"]!.DeepClone(), ["options"] = q["options"]!.DeepClone(),
                    ["branches"] = new JsonArray(q["branches"]!.AsObject().Select(b => (JsonNode?)new JsonObject { ["option"] = b.Key, ["segment"] = b.Value!.DeepClone() }).ToArray()),
                },
            });
        }
        var modelJson = new JsonObject
        {
            ["title"] = "Trains", ["start_segment"] = "s1", ["post_segment"] = "s3", ["comprehension"] = script["comprehension"]!.DeepClone(), ["segments"] = segments,
        };
        var handler = new StubHandler((_, _) => JsonResponse(HttpStatusCode.OK, Message("end_turn", [new JsonObject { ["type"] = "text", ["text"] = modelJson.ToJsonString() }])));
        var gen = new AnthropicTextGenerator(apiKey: null, model: "claude-opus-5-5", client: Client(handler));
        Assert.Equal("""{"name":"anthropic","model":"claude-opus-5-5","configured":true,"synthetic":false}""", gen.Info().ToJsonString());
        Assert.Equal(0.066, gen.EstimateCost(req));
        var (data, meta) = await gen.Generate(req);
        Assert.Equal("""{"option":"How it started","segment":"s2"}""", data["segments"]![0]!["question"]!["branches"]![0]!.ToJsonString());
        Assert.Equal("""{"cost_actual_units":0.044,"model":"claude-opus-5-5","input_tokens":1000,"output_tokens":2000}""", meta.ToJsonString());

        // exactly the Python request: beta endpoint, fallback beta header, no extra parameters
        var (request, body) = Assert.Single(handler.Calls);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("https://api.anthropic.com/v1/messages", request.RequestUri!.GetLeftPart(UriPartial.Path));
        Assert.Equal("test-key", Assert.Single(request.Headers.GetValues("x-api-key")));
        Assert.Equal("server-side-fallback-2026-07-01", string.Join(",", request.Headers.GetValues("anthropic-beta")));
        var sent = JsonNode.Parse(body)!.AsObject();
        Assert.Equal(["fallbacks", "max_tokens", "messages", "model", "output_config", "system"], sent.Select(p => p.Key).Order(StringComparer.Ordinal));
        Assert.Equal(("claude-opus-5-5", 16000, "default", PythonSystem), ((string)sent["model"]!, (int)sent["max_tokens"]!, (string)sent["fallbacks"]!, (string)sent["system"]!));
        var userPrompt = "Topic: Trains.\nAddress the participant as Sam.\nTheir interests: trains.\nTotal spoken length about 60 seconds across the segments (each 10 to 60 seconds).\nInclude 1 question point(s) between segments, then a final segment with no question that also serves as post_segment.\nSegment ids: s1, s2, ...; question ids q1, q2, ...; comprehension ids c1, c2 (two questions).";
        Assert.Equal(new JsonArray(new JsonObject { ["role"] = "user", ["content"] = userPrompt }).ToJsonString(), sent["messages"]!.ToJsonString());
        Assert.Equal(new JsonObject { ["format"] = new JsonObject { ["type"] = "json_schema", ["schema"] = JsonNode.Parse(PythonSchema) } }.ToJsonString(),
            sent["output_config"]!.ToJsonString());
        Assert.DoesNotContain("email", body, StringComparison.OrdinalIgnoreCase);

        // a refusal is terminal and names its category
        var refusing = new StubHandler((_, _) => JsonResponse(HttpStatusCode.OK,
            Message("refusal", [], """{"type":"refusal","category":"general_harms","explanation":"no"}""")));
        Assert.Equal("refusal: general_harms",
            (await Assert.ThrowsAsync<TerminalGenerationError>(() => new AnthropicTextGenerator(null, client: Client(refusing)).Generate(req))).Message);
        var uncategorized = new StubHandler((_, _) => JsonResponse(HttpStatusCode.OK, Message("refusal", [], """{"type":"refusal","category":null,"explanation":null}""")));
        Assert.Equal("refusal: unspecified",
            (await Assert.ThrowsAsync<TerminalGenerationError>(() => new AnthropicTextGenerator(null, client: Client(uncategorized)).Generate(req))).Message);
        var cut = new StubHandler((_, _) => JsonResponse(HttpStatusCode.OK, Message("max_tokens", [new JsonObject { ["type"] = "text", ["text"] = "{" }])));
        var e = await Assert.ThrowsAsync<GenerationError>(() => new AnthropicTextGenerator(null, client: Client(cut)).Generate(req));
        Assert.Equal(("RuntimeError", "the model hit max_tokens before finishing the script"), (e.Kind, e.Message));
        var empty = new StubHandler((_, _) => JsonResponse(HttpStatusCode.OK, Message("end_turn", [])));
        Assert.Equal("the model returned no text block",
            (await Assert.ThrowsAsync<GenerationError>(() => new AnthropicTextGenerator(null, client: Client(empty)).Generate(req))).Message);

        // invalid requests are terminal; rate limits and server errors are retried by the job runner
        const string error = """{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}""";
        foreach (var (status, name) in new[] { (HttpStatusCode.BadRequest, "BadRequestError"), (HttpStatusCode.Unauthorized, "AuthenticationError"),
                     (HttpStatusCode.Forbidden, "PermissionDeniedError"), (HttpStatusCode.NotFound, "NotFoundError") })
        {
            var failing = new StubHandler((_, _) => JsonResponse(status, error));
            var t = await Assert.ThrowsAsync<TerminalGenerationError>(() => new AnthropicTextGenerator(null, client: Client(failing)).Generate(req));
            Assert.Equal($"{name}: Error code: {(int)status} - {{'type': 'error', 'error': {{'type': 'invalid_request_error', 'message': 'bad'}}}}", t.Message);
        }
        foreach (var (status, name) in new[] { ((HttpStatusCode)429, "RateLimitError"), (HttpStatusCode.InternalServerError, "InternalServerError"),
                     ((HttpStatusCode)529, "OverloadedError"), (HttpStatusCode.UnprocessableEntity, "UnprocessableEntityError") })
        {
            var failing = new StubHandler((_, _) => JsonResponse(status, error));
            var g = await Assert.ThrowsAsync<GenerationError>(() => new AnthropicTextGenerator(null, client: Client(failing)).Generate(req));
            Assert.Equal((name, $"Error code: {(int)status} - {{'type': 'error', 'error': {{'type': 'invalid_request_error', 'message': 'bad'}}}}"), (g.Kind, g.Message));
        }

        var offline = new StubHandler((_, _) => throw new HttpRequestException("no route"));
        var io = await Assert.ThrowsAsync<GenerationError>(() => new AnthropicTextGenerator(null, client: Client(offline)).Generate(req));
        Assert.Equal(("APIConnectionError", "Connection error."), (io.Kind, io.Message));

        // the unconfigured adapter says so without a network call
        Assert.Contains("provider_not_configured", (await Assert.ThrowsAsync<TerminalGenerationError>(() => new AnthropicTextGenerator(null).Generate(req))).Message);
        Assert.False((bool)new AnthropicTextGenerator(null).Info()["configured"]!);
        Assert.True((bool)new AnthropicTextGenerator("k").Info()["configured"]!);
        Assert.Equal(0.033, new AnthropicTextGenerator("k", "claude-sonnet-5-5").EstimateCost(req));
        Assert.Equal(0.066, new AnthropicTextGenerator("k", "some-other-model").EstimateCost(req));
    }

    // ---------- test_heygen_adapter_with_mock_transport ----------

    [Fact]
    public async Task HeyGen_adapter_creates_polls_and_downloads()
    {
        var polls = 0;
        var handler = new StubHandler((request, body) =>
        {
            var uri = request.RequestUri!;
            if (uri.AbsolutePath == "/v2/video/generate")
                return JsonResponse(HttpStatusCode.OK, """{"data": {"video_id": "vid-1"}}""");
            if (uri.AbsolutePath == "/v1/video_status.get")
            {
                polls++;
                return JsonResponse(HttpStatusCode.OK, polls < 2
                    ? """{"data": {"status": "processing"}}"""
                    : """{"data": {"status": "completed", "video_url": "https://cdn.example/vid-1.mp4", "duration": 12}}""");
            }
            if (uri.Host == "cdn.example")
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent("MP4DATA"u8.ToArray()) { Headers = { { "Content-Type", "video/mp4" } } } };
            return new HttpResponseMessage(HttpStatusCode.NotFound);
        });
        var sleeps = new List<double>();
        var gen = new HeyGenVideoGenerator("k", transport: handler, pollIntervalS: 0, sleep: s => { sleeps.Add(s); return Task.CompletedTask; });
        Assert.Equal("""{"name":"heygen","configured":true,"synthetic":false}""", gen.Info().ToJsonString());
        Assert.Equal(PyMath.Round(10 / 2.5 / 60, 4), gen.EstimateCost("one two three four five six seven eight nine ten", 0));
        Assert.Equal(0.5, gen.EstimateCost("short", 30));
        Assert.Equal(0.0067, gen.EstimateCost("", 0));
        var (data, contentType, meta) = await gen.Generate("Hello there", "avatar-1", "voice-1");
        Assert.Equal(("MP4DATA", "video/mp4"), (Encoding.ASCII.GetString(data), contentType));
        Assert.Equal("""{"cost_actual_units":0.2,"duration_s":12.0,"video_id":"vid-1"}""", meta.ToJsonString());
        Assert.Equal([0.0], sleeps);

        Assert.Equal(4, handler.Calls.Count);
        var (create, createBody) = handler.Calls[0];
        Assert.Equal((HttpMethod.Post, "https://api.heygen.com/v2/video/generate"), (create.Method, create.RequestUri!.ToString()));
        Assert.Equal("k", Assert.Single(create.Headers.GetValues("X-Api-Key")));
        Assert.Equal("application/json", Assert.Single(create.Headers.GetValues("Accept")));
        Assert.Equal("""{"video_inputs":[{"character":{"type":"avatar","avatar_id":"avatar-1","avatar_style":"normal"},"voice":{"type":"text","input_text":"Hello there","voice_id":"voice-1"}}],"dimension":{"width":1280,"height":720}}""",
            createBody);
        Assert.Equal("https://api.heygen.com/v1/video_status.get?video_id=vid-1", handler.Calls[1].Request.RequestUri!.ToString());
        Assert.Equal("https://cdn.example/vid-1.mp4", handler.Calls[3].Request.RequestUri!.ToString());

        // client errors on create are terminal; other HTTP errors are retried with httpx's message
        var failing = new StubHandler((request, _) => request.RequestUri!.AbsolutePath == "/v2/video/generate"
            ? JsonResponse(HttpStatusCode.Unauthorized, """{"error": "bad key"}""")
            : new HttpResponseMessage(HttpStatusCode.InternalServerError));
        var t = await Assert.ThrowsAsync<TerminalGenerationError>(() => new HeyGenVideoGenerator("k", transport: failing, sleep: _ => Task.CompletedTask).Generate("x", "a", "v"));
        Assert.Equal("""heygen 401: {"error": "bad key"}""", t.Message);
        var down = new StubHandler((request, _) => request.RequestUri!.AbsolutePath == "/v2/video/generate"
            ? JsonResponse(HttpStatusCode.OK, """{"data": {"video_id": "v"}}""")
            : new HttpResponseMessage(HttpStatusCode.InternalServerError));
        var e = await Assert.ThrowsAsync<GenerationError>(() => new HeyGenVideoGenerator("k", "https://h.example/", transport: down).Generate("x", "a", "v"));
        Assert.Equal(("HTTPStatusError", "Server error '500 Internal Server Error' for url 'https://h.example/v1/video_status.get?video_id=v'\nFor more information check: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/500"),
            (e.Kind, e.Message));
        var refused = new StubHandler((request, _) => JsonResponse(HttpStatusCode.OK, request.RequestUri!.AbsolutePath == "/v2/video/generate"
            ? """{"data": {"video_id": "v"}}"""
            : """{"data": {"status": "failed", "error": {"code": 1}}}"""));
        Assert.Equal("heygen failed: {'code': 1}",
            (await Assert.ThrowsAsync<TerminalGenerationError>(() => new HeyGenVideoGenerator("k", transport: refused).Generate("x", "a", "v"))).Message);
        var noId = new StubHandler((_, _) => JsonResponse(HttpStatusCode.OK, """{"data": null}"""));
        Assert.Equal("heygen returned no video_id: {\"data\": null}",
            (await Assert.ThrowsAsync<GenerationError>(() => new HeyGenVideoGenerator("k", transport: noId).Generate("x", "a", "v"))).Message);
        Assert.Contains("provider_not_configured", (await Assert.ThrowsAsync<TerminalGenerationError>(() => new HeyGenVideoGenerator(null).Generate("x", "a", "v"))).Message);
        Assert.Contains("face_id and voice_id", (await Assert.ThrowsAsync<TerminalGenerationError>(() => new HeyGenVideoGenerator("k").Generate("x", "", ""))).Message);
    }

    // CONTENT_SCHEMA and the system prompt as Python writes them (json.dumps / script_prompt)
    private const string PythonSchema = """{"type": "object", "additionalProperties": false, "required": ["title", "start_segment", "post_segment", "segments", "comprehension"], "properties": {"title": {"type": "string"}, "start_segment": {"type": "string"}, "post_segment": {"type": "string"}, "segments": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["id", "text", "duration_s", "question"], "properties": {"id": {"type": "string"}, "text": {"type": "string"}, "duration_s": {"type": "number"}, "question": {"anyOf": [{"type": "null"}, {"type": "object", "additionalProperties": false, "required": ["id", "prompt", "options", "branches"], "properties": {"id": {"type": "string"}, "prompt": {"type": "string"}, "options": {"type": "array", "items": {"type": "string"}}, "branches": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["option", "segment"], "properties": {"option": {"type": "string"}, "segment": {"type": "string"}}}}}}]}}}}, "comprehension": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["id", "prompt", "options", "correct"], "properties": {"id": {"type": "string"}, "prompt": {"type": "string"}, "options": {"type": "array", "items": {"type": "string"}}, "correct": {"type": "string"}}}}}}""";

    private const string PythonSystem = "You write short spoken scripts for a research app that helps autistic young adults practise comfortable attention to a speaker's face. The speaker is a friendly adult who talks about a topic the participant chose. Rules: plain English, calm and respectful, no pressure to look, no medical claims, no personal questions, no jokes at anyone's expense, no eye-contact instructions. Each segment is spoken by the speaker as one take. Questions at segment ends are simple choices about the topic; every option must branch to an existing segment. Comprehension questions are about facts the speaker said, with exactly one correct option. Return only the JSON.";
}
