using System.Net;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using EyeTracking.Infrastructure.Db;
using Microsoft.Extensions.DependencyInjection;

namespace EyeTracking.Tests;

/// <summary>Step 4 rules. The HTTP behaviour is covered by the shared contract tests
/// (backend/tests/test_research.py with EYETRACKING_PARITY=dotnet); these cover what they cannot
/// reach: the Python text formats of the exports, the replay helpers' edge cases, and deletion
/// under SQL Server's enforced foreign keys with rows in the pilot and live tables, which no
/// endpoint can create before steps 6 and 7.</summary>
public sealed class ResearchTests : IClassFixture<ResearchTests.Factory>
{
    public sealed class Factory : IDisposable
    {
        public ApiFactory Api { get; } = new();
        public void Dispose() => Api.Dispose();
    }

    private static readonly JsonSerializerOptions Relaxed = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    private readonly ApiFactory _api;

    public ResearchTests(Factory f) => _api = f.Api;

    private static GazeSample Sample(int t, string region = "eye", int? layout = null) =>
        new() { TMs = t, X = region == "uncertain" ? null : 10.04, Y = 20.05, Conf = 0.12345, Region = region, LayoutId = layout };

    [Fact]
    public void Replay_helpers_follow_python()
    {
        var samples = new[] { Sample(100, layout: 2), Sample(900, "uncertain", 2), Sample(1100, layout: 1), Sample(2600, layout: 2) };
        Assert.Equal("""[[100,10.0,20.1,0.123,0],[900,null,20.1,0.123,4]]""", ResearchRules.CompactSamples(samples.Take(2)).ToJsonString());
        Assert.Equal(new[] { new LayoutRange(2, 100, 2600), new LayoutRange(1, 1100, 1100) }, ResearchRules.LayoutRanges(samples));
        Assert.Equal("""[{"from_ms":0,"to_ms":1000,"valid_share":0.5},{"from_ms":1000,"to_ms":2000,"valid_share":1.0},{"from_ms":2000,"to_ms":2500,"valid_share":null}]""",
            ResearchRules.QualityStrip(samples, 0, 2500).ToJsonString());
        Assert.Empty(ResearchRules.QualityStrip(samples, 10, 10));
        // the median spacing is 800 ms, so no stretch is longer than twice that
        Assert.Equal("[]", ResearchRules.SampleGaps(samples).ToJsonString());
        Assert.Equal("""[{"from_ms":0,"to_ms":5000}]""", ResearchRules.SampleGaps([Sample(0), Sample(5000)]).ToJsonString());

        SessionEvent E(int id, int t, string type) => new() { Id = id, TMs = t, Type = type };
        Assert.Equal("""[{"from_ms":10,"to_ms":20},{"from_ms":30,"to_ms":90}]""",
            ResearchRules.PauseIntervals([E(3, 30, "pause"), E(2, 20, "end"), E(1, 10, "pause"), E(4, 40, "pause")], 90).ToJsonString());
        Assert.Equal("[]", ResearchRules.PauseIntervals([E(1, 10, "pause")], 10).ToJsonString());

        var screen = new JsonObject { ["w"] = 1279.9, ["h"] = "601", ["dpr"] = 2 };
        Assert.Equal("android|none|unknown|1200x600|unknown", ResearchRules.GroupKey("android", null, null, screen, null));
        Assert.Equal("unknown|3|m|-300x0|-50px", ResearchRules.GroupKey("", "3", "m", new JsonObject { ["w"] = -1 }, -0.5));
        Assert.Equal("web|2|m|0x0|150px", ResearchRules.GroupKey("web", "2", "m", null, 199.99));
        Assert.Throws<InvalidOperationException>(() => ResearchRules.GroupKey(5, "2", "m", null, null));
        Assert.Throws<InvalidOperationException>(() => ResearchRules.ScreenBucket(new JsonObject { ["w"] = "12.5" }));
    }

    [Fact]
    public void Exports_write_python_text()
    {
        var sb = new StringBuilder();
        PyText.CsvRow(sb, ["a,b", "q\"x", "n\nl", "r\rx", " lead", "", "tab\tx"]);
        PyText.CsvRow(sb, [""]);
        Assert.Equal("\"a,b\",\"q\"\"x\",\"n\nl\",\"r\rx\", lead,,tab\tx\r\n\"\"\r\n", sb.ToString());
        Assert.Equal(new byte[] { 0xEF, 0xBB, 0xBF, (byte)'a' }, PyText.Utf8Sig("a"));

        var value = JsonNode.Parse("""{"a": "é \u007f\u0001", "b": [1, 2.5, null, true, {}], "c": {}, "d": [], "e": {"x": [1]}, "f": "😀", "g": 1e16, "h": -0, "i": 4.0}""");
        Assert.Equal("{\n \"a\": \"\\u00e9 \\u007f\\u0001\",\n \"b\": [\n  1,\n  2.5,\n  null,\n  true,\n  {}\n ],\n \"c\": {},\n \"d\": [],\n \"e\": {\n  \"x\": [\n   1\n  ]\n },\n \"f\": \"\\ud83d\\ude00\",\n \"g\": 1e+16,\n \"h\": 0,\n \"i\": 4.0\n}",
            PyText.JsonDumps(value, indent: 1));
        Assert.Equal("{\"a\": \"é \u007f\\u0001\\\"\\\\/\", \"n\": 1e-07, \"e\": \"😀\", \"l\": [1, null]}",
            PyText.JsonDumps(JsonNode.Parse("""{"a": "é \u007f\u0001\"\\/", "n": 1e-7, "e": "😀", "l": [1, null]}"""), ensureAscii: false));

        Assert.Equal("""["a'b", 'c"d', 'e\'f"g', '\n', 'é', '\x7f', '\u200b', '\\', 1.0, None, True]""",
            PyText.Str(JsonNode.Parse("""["a'b", "c\"d", "e'f\"g", "\n", "é", "\u007f", "\u200b", "\\", 1.0, null, true]""")));
        Assert.Equal("{'k': None}", PyText.Str(JsonNode.Parse("""{"k": null}""")));
        // Python's repr uses an exponent from 1e16 on (.NET's round-trip format only from 1e17)
        Assert.Equal(("1.5e+16", "-1e+16", "9999999999999998.0", "1e+17", "5e-05", "-0.0", "1.0"),
            (Json.PythonFloat(1.5e16), Json.PythonFloat(-1e16), Json.PythonFloat(9999999999999998.0), Json.PythonFloat(1e17), Json.PythonFloat(5e-05), Json.PythonFloat(-0.0), Json.PythonFloat(1)));
        Assert.Equal(("1000.0", "12345678901234567890", "inf"), (PyText.Str(JsonNode.Parse("1e3")), PyText.Str(JsonNode.Parse("12345678901234567890")), PyText.FloatStr(double.PositiveInfinity)));

        // date.fromisoformat(value[:10]) of CPython 3.12
        foreach (var (text, expected) in new (string, string?)[]
                 {
                     ("2090-01-01", "2090-01-01"), ("20900101", "2090-01-01"), ("2090-W01", "2090-01-02"), ("2090W011", "2090-01-02"),
                     ("2090-W01-1", "2090-01-02"), ("20900101xx", "2090-01-01"), ("2026-W53-1", "2026-12-28"), ("2090-01", null),
                     ("2090-1-1", null), ("bad", null), ("0000-01-01", null), ("2090-02-30", null), ("2090-W53-1", null), ("２０９０-01-01", null),
                 })
            Assert.Equal(expected, PyText.DateFromIsoFormat(text)?.ToString("yyyy-MM-dd"));
    }

    private sealed record World(HttpClient C, string Admin, string Researcher, string Participant, int StudyId, int ParticipantId, int UserId);

    private async Task<World> Setup()
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
        await c.Put("/me/profile", new { display_name = "Sam" }, p);
        var created = await c.Post("/me/sessions", new { screen = new { w = 1280, h = 720 } }, p);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        using var scope = _api.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>();
        var participant = db.Set<Participant>().Single();
        return new World(c, admin, r, p, studyId, participant.Id, participant.UserId);
    }

    /// <summary>One row in every table that hangs off a session or a participant, wired with the
    /// foreign keys SQL Server enforces (validation -> calibration, sample -> layout, turn ->
    /// conversation, reference sample -> recording, ...).</summary>
    private void FillEveryTable(World w)
    {
        using var scope = _api.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>();
        var session = db.Set<Session>().Single(s => s.ParticipantId == w.ParticipantId);
        var protocol = new Protocol { StudyId = w.StudyId, Name = "P", Version = 1, Status = ProtocolStatus.Published };
        db.Add(protocol);
        db.SaveChanges();
        var assignment = new Assignment { ParticipantId = w.ParticipantId, StudyId = w.StudyId, ProtocolId = protocol.Id };
        var calibration = new Calibration { SessionId = session.Id, Points = 9 };
        var layout = new StimulusLayout { SessionId = session.Id, Segment = "practice" };
        var recording = new ReferenceRecording { StudyId = w.StudyId, SessionId = session.Id, Source = "tobii", UploadedBy = w.UserId };
        var conversation = new LiveConversation { SessionId = session.Id, StudyId = w.StudyId, ParticipantId = w.ParticipantId, Topic = "Trains", InputMode = "text" };
        db.AddRange(assignment, calibration, layout, recording, conversation);
        db.SaveChanges();
        session.AssignmentId = assignment.Id;
        session.ProtocolId = protocol.Id;
        db.AddRange(
            new Validation { SessionId = session.Id, CalibrationId = calibration.Id },
            new GazeSample { SessionId = session.Id, TMs = 1, Region = "eye", Segment = "practice", LayoutId = layout.Id },
            new GazeSample { SessionId = session.Id, TMs = 2, Region = "uncertain", Segment = "practice", LayoutId = layout.Id },
            new SessionEvent { SessionId = session.Id, TMs = 1, Type = "note" },
            new Trial { SessionId = session.Id, NumberShown = "7", Zone = "outside" },
            new StageResult { SessionId = session.Id, Decision = "hold", Reason = "r" },
            new Answer { SessionId = session.Id, SegmentId = "s1", QuestionId = "q1", Kind = "interaction", Option = "a" },
            new Observation { StudyId = w.StudyId, SessionId = session.Id, AuthorId = w.UserId, Category = "c", Severity = "low", Text = "t" },
            new DebriefAnswer { StudyId = w.StudyId, SessionId = session.Id, ParticipantId = w.ParticipantId, FormVersion = 1, Answers = new JsonObject { ["q"] = "yes" } },
            new ReferenceSample { RecordingId = recording.Id, TMs = 1 },
            new ReferenceSample { RecordingId = recording.Id, TMs = 2 },
            new LiveTurn { ConversationId = conversation.Id, SessionId = session.Id, Index = 1, Role = "participant", Text = "hi", Chars = 2, Flags = ["participant_on_topic"] },
            new LiveTurn { ConversationId = conversation.Id, SessionId = session.Id, Index = 0, Role = "avatar", Text = "hello", Chars = 5 });
        db.SaveChanges();
    }

    private const string AllCounts =
        """{"sessions":1,"reference_samples":2,"reference_recordings":1,"observations":1,"debrief_answers":1,"live_turns":2,"live_conversations":1,"samples":2,"events":1,"trials":1,"stage_results":1,"answers":1,"validations":1,"calibrations":1,"layouts":1,"consents":1,"demographics":0,"profile":1,"assignments":1}""";

    private int Rows(params Func<EyeTrackingDb, int>[] tables)
    {
        using var scope = _api.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>();
        return tables.Sum(count => count(db));
    }

    private static int Count<T>(EyeTrackingDb db) where T : class => db.Set<T>().Count();

    private static readonly Func<EyeTrackingDb, int>[] ResearchTables =
    [
        Count<Session>, Count<Calibration>, Count<Validation>, Count<StimulusLayout>, Count<GazeSample>, Count<SessionEvent>,
        Count<Trial>, Count<StageResult>, Count<Answer>, Count<Assignment>, Count<Observation>, Count<DebriefAnswer>,
        Count<ReferenceRecording>, Count<ReferenceSample>, Count<LiveConversation>, Count<LiveTurn>, Count<Consent>, Count<Profile>,
    ];

    [Fact]
    public async Task Raw_data_includes_debrief_and_conversation_and_researcher_deletion_purges_every_table()
    {
        var w = await Setup();
        FillEveryTable(w);
        var data = await (await w.C.Get("/me/data", w.Participant)).Json();
        var session = data["sessions"]![0]!;
        Assert.Equal("""{"form_version":1,"answers":{"q":"yes"},"skipped":false}""", session["debrief"]!.ToJsonString());
        Assert.Equal("""{"topic":"Trains","input_mode":"text","transcript_kept":false,"status":"open","end_reason":null,"turns":[{"index":0,"role":"avatar","text":"hello","chars":5,"t_ms":null,"flags":[]},{"index":1,"role":"participant","text":"hi","chars":2,"t_ms":null,"flags":["participant_on_topic"]}]}""",
            session["conversation"]!.ToJsonString());

        var url = $"/studies/{w.StudyId}/participants/P-001/data";
        var r = await w.C.Send(HttpMethod.Delete, url, new { confirm = "P-001" }, w.Researcher);
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        Assert.Equal($$"""{"participant_code":"P-001","deleted":{{AllCounts}}}""", (await r.Json()).ToJsonString());
        Assert.Equal(0, Rows(ResearchTables));
        Assert.Equal(1, Rows(Count<Participant>));
        // the protocol is study configuration, not participant data
        Assert.Equal(1, Rows(Count<Protocol>));
        var log = await (await w.C.Get($"/studies/{w.StudyId}/access-log", w.Researcher)).Json();
        Assert.Equal("participant_data_deleted", (string)log[0]!["action"]!);
        Assert.Equal(AllCounts, log[0]!["detail"]!["deleted"]!.ToJsonString());

        // nothing left: every count is reported, in Python's order
        r = await w.C.Send(HttpMethod.Delete, url, new { confirm = "P-001" }, w.Researcher);
        Assert.Equal("""{"sessions":0,"samples":0,"events":0,"trials":0,"stage_results":0,"answers":0,"validations":0,"calibrations":0,"layouts":0,"reference_samples":0,"reference_recordings":0,"observations":0,"debrief_answers":0,"live_turns":0,"live_conversations":0,"consents":0,"demographics":0,"profile":0,"assignments":0}""",
            (await r.Json())["deleted"]!.ToJsonString());
    }

    [Fact]
    public async Task Erasure_under_delete_all_removes_the_participant_row_after_every_child()
    {
        var w = await Setup();
        FillEveryTable(w);
        var r = await w.C.Post("/me/erase", new { confirm = "DELETE MY DATA" }, w.Participant);
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        Assert.Equal($$"""{"policy":"delete_all","deleted":{{AllCounts}},"identity_removed":true}""", (await r.Json()).ToJsonString());
        Assert.Equal(0, Rows([.. ResearchTables, Count<Participant>]));
        using var scope = _api.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>();
        var user = db.Set<User>().Single(u => u.Id == w.UserId);
        Assert.Equal(($"erased-{w.UserId}@erased.invalid", "!", false), (user.Email, user.PasswordHash, user.IsActive));
        var entry = db.Set<AccessLogEntry>().OrderByDescending(e => e.Id).First();
        Assert.Equal(("erasure", "participant", w.StudyId), (entry.Action, entry.Role, entry.StudyId!.Value));
        Assert.Equal($$"""{"participant_id":{{w.ParticipantId}},"policy":"delete_all","deleted":{{AllCounts}}}""", entry.Detail.ToJsonString());
    }

    [Fact]
    public async Task Erasure_under_keep_coded_keeps_the_coded_rows_and_removes_the_identity()
    {
        var w = await Setup();
        FillEveryTable(w);
        Assert.Equal(HttpStatusCode.OK, (await w.C.Put($"/studies/{w.StudyId}", new { retention_policy = "keep_coded" }, w.Admin)).StatusCode);
        var before = Rows(ResearchTables);
        var r = await w.C.Post("/me/erase", new { confirm = "DELETE MY DATA" }, w.Participant);
        Assert.Equal("""{"policy":"keep_coded","deleted":{},"identity_removed":true}""", (await r.Json()).ToJsonString());
        Assert.Equal(before, Rows(ResearchTables));
        Assert.Equal(HttpStatusCode.Unauthorized, (await w.C.Get("/me", w.Participant)).StatusCode);
        // the coded rows can still be deleted later by a researcher
        r = await w.C.Send(HttpMethod.Delete, $"/studies/{w.StudyId}/participants/P-001/data", new { confirm = "P-001" }, w.Researcher);
        Assert.Equal(AllCounts, (await r.Json())["deleted"]!.ToJsonString());
        Assert.Equal(0, Rows(ResearchTables));
    }

    [Fact]
    public async Task Query_and_path_errors_have_fastapi_shape()
    {
        var w = await Setup();
        var r = await w.C.Get($"/studies/{w.StudyId}/exports/sessions.xml?include_synthetic=maybe", w.Researcher);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, r.StatusCode);
        Assert.Equal("""{"detail":[{"type":"literal_error","loc":["path","fmt"],"msg":"Input should be 'csv' or 'json'","input":"xml","ctx":{"expected":"'csv' or 'json'"}},{"type":"bool_parsing","loc":["query","include_synthetic"],"msg":"Input should be a valid boolean, unable to interpret input","input":"maybe"}]}""",
            (await r.Json()).ToJsonString(Relaxed));
        r = await w.C.Get($"/studies/{w.StudyId}/exports/samples.csv", w.Researcher);
        Assert.Equal("""{"detail":[{"type":"missing","loc":["query","session_id"],"msg":"Field required","input":null}]}""", (await r.Json()).ToJsonString());
        // authentication comes first
        Assert.Equal(HttpStatusCode.Unauthorized, (await w.C.GetAsync($"/studies/{w.StudyId}/exports/sessions.xml")).StatusCode);
        r = await w.C.Get($"/studies/{w.StudyId}/exports/samples.csv?session_id=1", w.Researcher);
        Assert.Equal("text/csv; charset=utf-8", r.Content.Headers.ContentType!.ToString());
        Assert.Equal("attachment; filename=\"session-1-samples.csv\"", r.Content.Headers.ContentDisposition!.ToString());
        Assert.Equal(PyText.Utf8Sig("t_ms,x,y,conf,valid,region,segment,layout_id\r\n"), await r.Content.ReadAsByteArrayAsync());
    }
}
