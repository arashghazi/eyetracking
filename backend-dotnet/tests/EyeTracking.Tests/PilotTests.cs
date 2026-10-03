using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using EyeTracking.Infrastructure.Db;
using EyeTracking.Web.Endpoints.Pilot;
using Microsoft.Extensions.DependencyInjection;

namespace EyeTracking.Tests;

/// <summary>Step 6 rules. The HTTP behaviour is covered by the shared contract tests
/// (backend/tests/test_pilot.py with EYETRACKING_PARITY=dotnet); its python_only test checks the
/// Python SQLite dev-migration helper, which has no C# counterpart (the schema comes from EF).
/// These cover the Python numerics and text parsing the comparison relies on, and the pilot views
/// of live conversations, whose rows no endpoint can create before step 7. Expected values come
/// from CPython 3.12.</summary>
public sealed class PilotTests : IClassFixture<PilotTests.Factory>
{
    public sealed class Factory : IDisposable
    {
        public ApiFactory Api { get; } = new();
        public void Dispose() => Api.Dispose();
    }

    private static readonly JsonSerializerOptions Relaxed = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    private readonly ApiFactory _api;

    public PilotTests(Factory f) => _api = f.Api;

    [Fact]
    public void Hypot_and_sum_match_python_to_the_last_bit()
    {
        // math.hypot; the last six are pairs where sqrt(x*x + y*y) rounds differently
        (double X, double Y, double H)[] hypot =
        [
            (-1904.8178596072557, 1427.452025538998, 2380.325684332746), (1124.872221519055, 31.365092249084455, 1125.309416896974),
            (3.4953931539958787, 1215.601250884194, 1215.6062762771992), (-969.4705516449494, 1171.9074900798105, 1520.9340274357476),
            (15477.403431071389, 537.811131533394, 15486.744583073023), (492513.80607487954, 113.52506468191496, 492513.81915871595),
            (-237875.53337337295, -1218.7144899629322, 237878.65529020192), (3.0, 4.0, 5.0), (1e-310, 3e-310, 3.1622776601684e-310),
            (1e300, 1e300, 1.4142135623730952e300), (0.0, -0.0, 0.0), (double.PositiveInfinity, double.NaN, double.PositiveInfinity),
            (30.9603278013511, -18.644252422964286, 36.14069791769832), (-57.29966430408149, 85.40842966775884, 102.84868199288185),
            (-89.53548152746666, -24.907358020009212, 92.93534815070227), (13.24834917404489, -60.301973255707544, 61.74015495906602),
            (-97.80899724380166, -7.012030784753705, 98.06002507425916), (94.97141212733314, 18.548125481821813, 96.76570715056636),
        ];
        foreach (var (x, y, h) in hypot)
            Assert.Equal(h, PyMath.Hypot(x, y));
        Assert.True(double.IsNaN(PyMath.Hypot(1.0, double.NaN)));

        // sum() of floats (Neumaier since 3.12)
        Assert.Equal(1.0, PyMath.Sum(Enumerable.Repeat(0.1, 10)));
        Assert.Equal(1.0, PyMath.Sum([1e16, 1.0, -1e16]));
        Assert.Equal(0.7999999999999999, PyMath.Sum([0.3, 0.6, 0.1, -0.2, 1e-17]));
        Assert.Equal(-375.55056525435145, PyMath.Sum(
        [
            49.790371868658895, -48.036929062969826, -31.269263927433922, 49.58357204077906, 10.201849521574111, 7.695983425030676,
            -45.78921795688443, -35.364139666226976, -5.8458318872172015, -49.0424761379587, 11.03331620168344, 33.02894778275845,
            -11.383004431874646, -42.57190071782681, -29.12666903232426, 13.65874055252442, -48.449092655417445, -13.13247950993177,
            12.214923242634612, -37.277890772272144, 8.727126928958683, 33.23592288387658, -36.42620454242403, -11.39029697863183,
            12.724487598341192, -18.918871202749223, -27.161663161365734, 11.044482327624081, 22.539096467048424, -34.15242899997206,
            12.897727594081232, 5.39311930283143, 18.697400353950144, -11.179006187476404, -1.7483788702382128, -42.15021921585708,
            -45.25984294426465, -39.09527358509863, 1.2355826517056698, -24.482134551996605,
        ]));
        Assert.True(double.IsPositiveInfinity(PyMath.Sum([1e308, 1e308, -1.0])));
    }

    [Fact]
    public void Csv_reader_follows_python()
    {
        static string Read(string text, char delimiter) =>
            new JsonArray(PyCsv.Read(text, delimiter).Select(r => (JsonNode?)Json.Array(r)).ToArray()).ToJsonString(Relaxed);
        Assert.Equal("""[["a","b"],["1","2\n3"],[],["x\"y","z"]]""", Read("a,b\r\n1,\"2\n3\"\r\n\r\n\"x\"\"y\",z\n", ','));
        Assert.Equal("""[["a","b"],["qx","y"]]""", Read("a;b\n\"q\"x;y\n", ';'));
        Assert.Equal("""[["a","b"],["1","2"]]""", Read("a\tb\n1\t2", '\t'));
        Assert.Equal("""[["a,b"]]""", Read("\"a,b", ','));
        Assert.Equal("""[["a","b"],[],["",""]]""", Read("a,b\n\n,\n", ','));
        Assert.Equal("""[["a\u0000b","c"]]""", Read("a\0b,c\n", ','));
        var e = Assert.Throws<InvalidOperationException>(() => Read("a,b\rc,d\r", ','));
        Assert.StartsWith("new-line character seen in unquoted field", e.Message);
        Assert.Throws<InvalidOperationException>(() => Read(new string('x', PyCsv.FieldLimit + 1), ','));
        Assert.Equal(PyCsv.FieldLimit, PyCsv.Read(new string('x', PyCsv.FieldLimit), ',').Single()[0].Length);
    }

    [Fact]
    public void Float_text_is_parsed_like_python_and_pydantic()
    {
        // float(text)
        foreach (var (text, expected) in new (string, double?)[]
                 {
                     (" 1_000.5 ", 1000.5), ("+.5", 0.5), ("5.", 5.0), ("1e1_0", 1e10), ("-InFiNiTy", double.NegativeInfinity), ("１２", 12.0),
                     ("\u001c3\u001f", 3.0), ("1__0", null), ("_1", null), ("1_.5", null), (".", null), ("1e", null), ("0x10", null), ("", null),
                 })
            Assert.Equal(expected, PilotRules.PyFloatOfText(text));
        Assert.True(double.IsNaN(PilotRules.PyFloatOfText("nan")!.Value));
        // pydantic's float parsing of a form field
        foreach (var (text, expected) in new (string, double?)[]
                 {
                     ("1_000", 1000.0), (" 1_000", null), ("1_000 ", null), (" 1000 ", 1000.0), ("1_.5", 1.5), ("1._5", 1.5), ("+_1", 1.0),
                     ("1e_5", 1e5), ("1.", 1.0), (" .5", 0.5), ("+inf", double.PositiveInfinity), ("1e400", double.PositiveInfinity),
                     (" 1 ", 1.0), ("\u001c1", null), ("１２", null), ("1 000", null), ("1__0", null), ("1_", null), ("1_0\n", null),
                     ("0x1p3", null), ("1e5.5", null), ("infinite", null), ("+", null),
                 })
            Assert.Equal(expected, PilotEndpoints.PydanticFloat(text));
    }

    [Fact]
    public void Candidate_thresholds_keep_their_python_type()
    {
        var current = new MeasurementSettings { StudyId = 1 };
        var candidate = PilotRules.SettingsValues(current);
        candidate["validation_min_correct"] = 1;
        candidate["min_region_to_error_ratio"] = true;
        candidate["calibration_points"] = 9.7;
        PilotRules.ValidateCandidate(candidate);
        var stored = new JsonObject
        {
            ["passed"] = true, ["correct_ratio"] = 0.9, ["uncertain_ratio"] = 0.0, ["size_ratio"] = 0.5,
            ["reasons"] = new JsonArray("missing_target_regions:mouth", "other"),
        };
        Assert.Equal("""{"passed":false,"reasons":["missing_target_regions:mouth","correct_ratio_below_1","eye_region_smaller_than_Truex_error"]}""",
            PilotRules.Revalidate(stored, candidate).ToJsonString());
        candidate["calibration_points"] = "17";
        Assert.Equal("calibration_points must be between 5 and 16", Assert.Throws<Invalid>(() => PilotRules.ValidateCandidate(candidate)).Message);
        candidate["calibration_points"] = 9;
        candidate["min_region_to_error_ratio"] = "2";
        // Python compares a str with a float: TypeError, a server error
        Assert.Throws<InvalidOperationException>(() => PilotRules.ValidateCandidate(candidate));

        var summary = new JsonObject
        {
            ["synthetic"] = false, ["calibration"] = new JsonObject(), ["validation"] = new JsonObject { ["passed"] = true },
            ["coverage"] = new JsonObject { ["total_ms"] = 100, ["classifiable_ms"] = 50, ["uncertain_ms"] = 30, ["missing_ms"] = 20 },
        };
        Assert.Equal("""{"grade":"review","reasons":["uncertain_share_above_0","missing_share_above_False"]}""",
            ResearchRules.GradeQuality(summary, 0, false).AsDict().ToJsonString());
        Assert.Equal("""{"grade":"review","reasons":["uncertain_share_above_0.0","missing_share_above_0.1"]}""",
            ResearchRules.GradeQuality(summary, 0.0, 0.1).AsDict().ToJsonString());
    }

    [Fact]
    public void Distribution_interpolates_between_ranks()
    {
        Assert.Equal("""{"n":0}""", PilotRules.Distribution([double.NaN]).ToJsonString());
        Assert.Equal("""{"n":1,"min":2.0,"p25":2.0,"median":2.0,"p75":2.0,"p90":2.0,"max":2.0}""", PilotRules.Distribution([2]).ToJsonString());
        Assert.Equal("""{"n":4,"min":1.0,"p25":1.75,"median":2.5,"p75":3.25,"p90":3.7,"max":4.0}""", PilotRules.Distribution([4, 1, 3, double.NaN, 2]).ToJsonString());
    }

    private sealed record World(HttpClient C, string Researcher, string Participant, int StudyId, int SessionId);

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
        var created = await c.Post("/me/sessions",
            new { device = new { platform = "web" }, screen = new { w = 1280, h = 720 }, gaze_model = new { model_id = "m", synthetic = false } }, p);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        return new World(c, r, p, studyId, (int)(await created.Json())["id"]!);
    }

    [Fact]
    public async Task Live_monitor_and_pilot_report_read_the_conversation_tables()
    {
        var w = await Setup();
        var live = $"/studies/{w.StudyId}/sessions/{w.SessionId}/live";
        Assert.Null((await (await w.C.Get(live, w.Researcher)).Json())["conversation"]);
        using (var scope = _api.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>();
            var session = db.Set<Session>().Single(s => s.Id == w.SessionId);
            var protocol = new Protocol
            {
                StudyId = w.StudyId, Name = "Live", Version = 1, Status = ProtocolStatus.Published, Definition = new JsonObject { ["path"] = "live_conversation" },
            };
            db.Add(protocol);
            db.SaveChanges();
            session.ProtocolId = protocol.Id;
            var conversation = new LiveConversation
            {
                SessionId = session.Id, StudyId = w.StudyId, ParticipantId = session.ParticipantId, Topic = "Trains", InputMode = "text", TurnsUsed = 3,
                Status = ConversationStatus.Closed, EndReason = "time_limit",
            };
            db.Add(conversation);
            db.SaveChanges();
            db.AddRange(
                new LiveTurn { ConversationId = conversation.Id, SessionId = session.Id, Index = 0, Role = "avatar", Text = "Hi", Flags = ["redirect_line"] },
                new LiveTurn { ConversationId = conversation.Id, SessionId = session.Id, Index = 2, Role = "participant", Text = "b", TMs = 5000, Flags = ["participant_off_topic"] },
                new LiveTurn { ConversationId = conversation.Id, SessionId = session.Id, Index = 1, Role = "participant", Text = "a", Flags = ["participant_on_topic", "distress"] });
            db.SaveChanges();
        }
        // live_use_cases.monitor_block: counts and flags, never the text
        Assert.Equal("""{"status":"closed","input_mode":"text","turns_used":3,"distress":1,"redirects":1,"last_turn":{"role":"participant","flags":["participant_off_topic"],"t_ms":5000},"end_reason":"time_limit"}""",
            (await (await w.C.Get(live, w.Researcher)).Json())["conversation"]!.ToJsonString());
        var row = (await (await w.C.Get($"/studies/{w.StudyId}/pilot/report", w.Researcher)).Json())["rows"]![0]!;
        Assert.Equal((2, 0.5, 1, "time_limit"),
            ((int)row["conversation_turns"]!, (double)row["conversation_on_topic_share"]!, (int)row["conversation_distress"]!, (string)row["conversation_end_reason"]!));
        Assert.Equal("live_conversation", (string)row["path"]!);
        var csv = await (await w.C.Get($"/studies/{w.StudyId}/pilot/report.csv", w.Researcher)).Content.ReadAsStringAsync();
        Assert.EndsWith(",0,0,0,2,0.5,1,time_limit\r\n", csv);
    }

    private static MultipartFormDataContent Upload(byte[] data, params (string Name, string Value)[] fields)
    {
        var form = new MultipartFormDataContent();
        foreach (var (name, value) in fields)
            form.Add(new StringContent(value), name);
        var file = new ByteArrayContent(data);
        file.Headers.ContentType = new MediaTypeHeaderValue("text/csv");
        form.Add(file, "file", "tracker.csv");
        return form;
    }

    /// <summary>reference_samples.t_ms is a 32-bit column (as in the Python schema, which SQLite does
    /// not enforce) and SQL Server floats have no infinity: such files are refused, not a server error.</summary>
    [Fact]
    public async Task Reference_values_the_database_cannot_hold_are_refused()
    {
        var w = await Setup();
        var url = $"/studies/{w.StudyId}/sessions/{w.SessionId}/reference";
        async Task<HttpResponseMessage> Send(string text) =>
            await w.C.SendAsync(new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = Upload(Encoding.UTF8.GetBytes(text), ("source", "Lab"), ("time_column", "t"), ("x_column", "x"), ("y_column", "y"), ("time_unit", "us")),
            }.As(w.Researcher));
        var r = await Send("t,x,y\n1700000000000000,1,2\n");
        Assert.Equal(HttpStatusCode.UnprocessableEntity, r.StatusCode);
        Assert.Equal("time values are out of range; check time_unit and offset", (string)(await r.Json())["detail"]!);
        r = await Send("t,x,y\n1000,inf,2\n");
        Assert.Equal("coordinates must be finite numbers", (string)(await r.Json())["detail"]!);
        r = await Send("t,x,y\n1000,1,2\n2000,nan,2\n");
        Assert.Equal(HttpStatusCode.Created, r.StatusCode);
        Assert.Equal((2, 1), ((int)(await r.Json())["sample_count"]!, (int)(await r.Json())["valid_count"]!));
        using var scope = _api.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<EyeTrackingDb>();
        Assert.Equal(1, db.Set<ReferenceRecording>().Count());
        Assert.Equal("[[1,1.0,2.0,true],[2,null,null,false]]", new JsonArray(db.Set<ReferenceSample>().OrderBy(s => s.TMs).AsEnumerable()
            .Select(s => (JsonNode?)new JsonArray(s.TMs, s.X is { } x ? Json.Float(x) : null, s.Y is { } y ? Json.Float(y) : null, s.Valid)).ToArray()).ToJsonString());
    }
}
