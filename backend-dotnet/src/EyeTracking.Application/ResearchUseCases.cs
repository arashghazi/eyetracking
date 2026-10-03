using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using static EyeTracking.Application.Authz;

namespace EyeTracking.Application;

/// <summary>A file an export produced: its download name, bytes and media type.</summary>
public sealed record ExportFile(string Name, byte[] Data, string MediaType);

/// <summary>The analysis and export filters as the router passes them; null means "not sent".</summary>
public sealed record AnalysisFilters(
    string? Participant = null,
    string? Path = null,
    string? ProtocolVersion = null,
    string? Device = null,
    string? From = null,
    string? To = null,
    string? Quality = null,
    bool IncludeSynthetic = false)
{
    /// <summary>The filters that were given, in the router's order (Python drops None and "";
    /// include_synthetic is a bool and always stays).</summary>
    public JsonObject Given()
    {
        var o = new JsonObject();
        foreach (var (key, value) in new[]
                 {
                     ("participant", Participant), ("path", Path), ("protocol_version", ProtocolVersion), ("device", Device),
                     ("from", From), ("to", To), ("quality", Quality),
                 })
        {
            if (!string.IsNullOrEmpty(value))
                o[key] = value;
        }
        o["include_synthetic"] = IncludeSynthetic;
        return o;
    }
}

/// <summary>Use cases for build step 4 (research_use_cases.py): replay, quality, analysis, exports,
/// access log, the participant's raw data and deletion. Every replay, analysis, export, identity
/// reveal and deletion is written to the access log in the same transaction.</summary>
public static class ResearchUseCases
{
    public static readonly string[] AnalysisColumns =
    [
        "session_id", "participant_code", "created_at", "path", "protocol_name", "protocol_version", "sheet_version",
        "device_platform", "screen", "estimator", "gaze_model_version", "synthetic", "quality", "quality_reasons",
        "calibration_residual_px", "validation_passed", "size_ratio", "total_ms", "classifiable_share", "uncertain_share",
        "missing_share", "face_share", "eye_share", "baseline_eye_share", "post_eye_share", "eye_share_delta",
        "comprehension_share", "number_task_share", "stages_completed", "comfort_min", "comfort_mean", "comfort_low_count",
        "pauses", "ended_early", "improvement", "group_key",
    ];

    private static JsonNode? Ts(DateTime? t) => t is null ? null : JsonFormat.Timestamp(t.Value);

    /// <summary>Python's <c>(d or {}).get(key)</c> on a summary part, as a copy.</summary>
    private static JsonNode? At(JsonNode? d, string key) => d is JsonObject o ? o[key]?.DeepClone() : null;

    public static void LogAccess(IUnitOfWork uow, Principal principal, int? studyId, string action, JsonObject? detail = null) =>
        uow.AccessLog.Add(new AccessLogEntry
        {
            StudyId = studyId, UserId = principal.UserId, Role = principal.Role.Value(), Action = action, Detail = detail ?? [],
        });

    // ---------- replay ----------

    private static Session StudySession(IUnitOfWork uow, Principal principal, int studyId, int sessionId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        var s = uow.Sessions.Get(sessionId);
        if (s is null || s.StudyId != studyId)
            throw new NotFound("session not found");
        return s;
    }

    private static string CodeOf(IUnitOfWork uow, int studyId, int participantId) =>
        uow.Participants.ListForStudy(studyId).FirstOrDefault(x => x.Id == participantId)?.Code ?? "?";

    /// <summary>A key into a dict whose keys are text: other values are never found, and lists and
    /// dicts cannot be looked up at all (Python's TypeError).</summary>
    private static string? TextKey(JsonNode? key) => key switch
    {
        JsonArray or JsonObject => throw new InvalidOperationException("unhashable type"),
        _ => Json.Str(key),
    };

    /// <summary>Everything to replay a session: segments, layouts, compact samples, events, trials,
    /// answers, a quality strip, sample gaps, pauses and signed media links. Never participant video.</summary>
    public static JsonObject Replay(IUnitOfWork uow, IMediaSigner signer, Principal principal, int studyId, int sessionId)
    {
        var s = StudySession(uow, principal, studyId, sessionId);
        var summary = MeasurementUseCases.Summarize(uow, s);
        var sid = s.Id;
        var samples = uow.Samples.ForSession(sid);
        var events = uow.Events.ForSession(sid);
        int? lastT = samples.Count == 0 ? null : samples.Max(x => x.TMs);
        var segments = MeasurementRules.SegmentsFromEvents(events, lastT);
        var startMs = segments.Select(g => g.StartedMs).Concat(samples.Take(1).Select(x => x.TMs)).DefaultIfEmpty(0).Min();
        var endMs = segments.Select(g => g.EndedMs ?? 0).Append(lastT ?? 0).Max();
        var allLayouts = uow.Layouts.SessionAll(sid);
        var layouts = new List<(int From, JsonObject Item)>();
        foreach (var range in ResearchRules.LayoutRanges(samples))
        {
            var l = allLayouts.FirstOrDefault(x => x.Id == range.LayoutId);
            if (l is not null)
            {
                layouts.Add((range.FromMs, new JsonObject
                {
                    ["id"] = l.Id, ["segment"] = l.Segment, ["stage_index"] = l.StageIndex, ["layout"] = Json.CloneObj(l.Layout),
                    ["from_ms"] = range.FromMs, ["to_ms"] = range.ToMs,
                }));
            }
        }
        var media = new JsonArray();
        if (s.AssignmentId is { } assignmentId && assignmentId != 0)
        {
            var a = uow.Assignments.Get(assignmentId);
            var content = a is { ContentId: { } contentId } && contentId != 0 ? uow.Content.Get(contentId) : null;
            var byKey = new Dictionary<string, ContentMedia>(StringComparer.Ordinal);
            var keyOfSegment = new Dictionary<string, JsonNode?>(StringComparer.Ordinal);
            if (content is not null)
            {
                foreach (var m in uow.Media.ListForContent(content.Id))
                    byKey[m.Key] = m;
                foreach (var node in PracticeRules.Items(PracticeRules.Get(content.Definition, "segments", new JsonArray())))
                {
                    var seg = PracticeRules.AsDict(node);
                    var id = TextKey(seg["id"]) ?? throw new InvalidOperationException("content segments need text ids");
                    keyOfSegment[id] = PracticeRules.Get(seg, "media_key");
                }
            }
            ContentMedia? Find(JsonNode? key) => TextKey(key) is { } k && byKey.TryGetValue(k, out var m) ? m : null;
            foreach (var e in events.Where(e => e.Type == "media_start"))
            {
                var segmentId = PracticeRules.Get(e.Payload, "segment_id");
                var segmentKey = TextKey(segmentId) is { } sk && keyOfSegment.TryGetValue(sk, out var found) ? found : null;
                // str(media_key or "") or key_of_segment.get(segment_id) or ""
                var mediaKey = PracticeRules.Get(e.Payload, "media_key");
                JsonNode? key = Json.Truthy(mediaKey) ? PyText.Str(mediaKey) : Json.Truthy(segmentKey) ? segmentKey : "";
                var m = Find(key) ?? Find(Json.Truthy(segmentKey) ? segmentKey : "");
                media.Add(new JsonObject
                {
                    ["segment_id"] = segmentId?.DeepClone(),
                    ["media_key"] = m is not null ? m.Key : Json.Truthy(key) ? key!.DeepClone() : null,
                    ["start_ms"] = e.TMs,
                    ["url"] = m is null ? null : $"/media/{signer.Sign(m.Id)}",
                });
            }
        }
        LogAccess(uow, principal, studyId, "replay", new JsonObject { ["session_id"] = sid });
        uow.Commit();
        var protocol = summary["protocol"];
        return new JsonObject
        {
            ["session"] = new JsonObject
            {
                ["id"] = s.Id,
                ["participant_code"] = CodeOf(uow, studyId, s.ParticipantId),
                ["status"] = s.Status.Value(),
                ["created_at"] = Ts(s.CreatedAt),
                ["synthetic"] = s.Synthetic,
                ["quality"] = summary["quality"]?.DeepClone(),
                ["protocol"] = Json.Truthy(protocol)
                    ? new JsonObject { ["name"] = At(protocol, "name"), ["version"] = At(protocol, "version"), ["path"] = At(protocol, "path") }
                    : protocol?.DeepClone(),
            },
            ["screen"] = Json.CloneObj(s.Screen),
            ["segments"] = new JsonArray(segments.Select(g => (JsonNode?)g.ToJson()).ToArray()),
            ["layouts"] = new JsonArray(layouts.OrderBy(x => x.From).Select(x => (JsonNode?)x.Item).ToArray()),
            ["samples"] = ResearchRules.CompactSamples(samples),
            ["events"] = new JsonArray(events.Select(e => (JsonNode?)new JsonObject
            {
                ["t_ms"] = e.TMs, ["type"] = e.Type, ["payload"] = Json.CloneObj(e.Payload),
            }).ToArray()),
            ["trials"] = new JsonArray(uow.Trials.ForSession(sid).Select(t => (JsonNode?)new JsonObject
            {
                ["stage_index"] = t.StageIndex, ["trial_index"] = t.TrialIndex, ["t_ms"] = t.TMs, ["number_shown"] = t.NumberShown,
                ["zone"] = t.Zone, ["position"] = Json.CloneObj(t.Position), ["face_level"] = t.FaceLevel, ["response"] = t.Response,
                ["correct"] = t.Correct, ["response_ms"] = t.ResponseMs,
            }).ToArray()),
            ["answers"] = Answers(uow, sid),
            ["quality_strip"] = ResearchRules.QualityStrip(samples, startMs, endMs),
            ["gaps"] = ResearchRules.SampleGaps(samples),
            ["pauses"] = ResearchRules.PauseIntervals(events, endMs),
            ["media"] = media,
        };
    }

    private static JsonArray Answers(IUnitOfWork uow, int sessionId) =>
        new(uow.Answers.ForSession(sessionId).Select(a => (JsonNode?)new JsonObject
        {
            ["segment_id"] = a.SegmentId, ["question_id"] = a.QuestionId, ["kind"] = a.Kind, ["option"] = a.Option,
            ["correct"] = a.Correct, ["t_ms"] = a.TMs,
        }).ToArray());

    // ---------- analysis and exports ----------

    private static DateOnly? ParseDate(string? value)
    {
        if (string.IsNullOrEmpty(value))
            return null;
        // value[:10] counts code points
        var head = string.Concat(value.EnumerateRunes().Take(10).Select(r => r.ToString()));
        return PyText.DateFromIsoFormat(head) ?? throw new Invalid("dates must be YYYY-MM-DD");
    }

    private static JsonNode? Share(long? part, long? total)
    {
        if (total is null or 0)
            return null;
        return Json.Float(PyMath.Round((double)(part ?? 0) / total.Value, 4));
    }

    private static long? Long(JsonNode? n) => Json.Num(n) is { } d ? (long)d : null;

    /// <summary>One analysis row: the row as the API shows it, plus what exports and trends need.</summary>
    private sealed record AnalysisRow(JsonObject Data, DateTime CreatedAt, string ParticipantCode, string GroupKey, JsonObject Demographics);

    private sealed record AnalysisResult(JsonObject Filters, List<AnalysisRow> Rows, JsonArray Groups, JsonArray Trends, int Excluded)
    {
        public JsonObject ToJson() => new()
        {
            ["filters"] = Json.CloneObj(Filters),
            ["rows"] = new JsonArray(Rows.Select(r => (JsonNode?)Json.CloneObj(r.Data)).ToArray()),
            ["groups"] = Json.CloneArr(Groups),
            ["trends"] = Json.CloneArr(Trends),
            ["excluded"] = Excluded,
            ["note"] = "Sessions from different groups are never pooled into one trend by default.",
        };
    }

    private static AnalysisResult AnalysisRows(IUnitOfWork uow, Principal principal, int studyId, AnalysisFilters filters)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var participants = uow.Participants.ListForStudy(studyId).ToDictionary(p => p.Id);
        var sheet = uow.Sheets.Current(studyId);
        var qualityFilter = (string.IsNullOrEmpty(filters.Quality) ? "ok,review" : filters.Quality).Split(',').Where(q => q != "").ToHashSet();
        var includeSynthetic = filters.IncludeSynthetic;
        DateOnly? dFrom = ParseDate(filters.From), dTo = ParseDate(filters.To);
        var rows = new List<AnalysisRow>();
        var excluded = 0;
        foreach (var s in uow.Sessions.ListForStudy(studyId))
        {
            var code = participants.TryGetValue(s.ParticipantId, out var p) ? p.Code : "?";
            if (!string.IsNullOrEmpty(filters.Participant) && code != filters.Participant)
                continue;
            var summary = MeasurementUseCases.Summarize(uow, s);
            var proto = summary["protocol"] as JsonObject ?? [];
            if (!string.IsNullOrEmpty(filters.Path) && Json.Str(proto["path"]) != filters.Path)
                continue;
            if (!string.IsNullOrEmpty(filters.ProtocolVersion) && PyText.Str(proto["version"]) != filters.ProtocolVersion)
                continue;
            var platform = PracticeRules.Get(s.Device, "platform");
            if (!string.IsNullOrEmpty(filters.Device) && Json.Str(platform) != filters.Device)
                continue;
            var day = DateOnly.FromDateTime(s.CreatedAt);
            if (dFrom is not null && day < dFrom)
                continue;
            if (dTo is not null && day > dTo)
                continue;
            if (s.Synthetic && !includeSynthetic)
            {
                excluded++;
                continue;
            }
            var quality = summary["quality"]!;
            if (!qualityFilter.Contains(Json.Str(quality["grade"]) ?? ""))
            {
                excluded++;
                continue;
            }
            var val = uow.Validations.Latest(s.Id);
            double? eyeH = val is not null && Json.Truthy(val.Layout["eye_region"])
                ? PracticeRules.FloatOf(PracticeRules.Items(val.Layout["eye_region"]).ElementAt(3))
                : null;
            var gk = ResearchRules.GroupKey(
                platform, proto.Count > 0 ? PyText.Str(proto["version"]) : null, PracticeRules.Get(s.GazeModel, "model_id"), s.Screen, eyeH);
            var cov = summary["coverage"]!;
            var output = summary["outcomes"]!;
            var gaze = output["gaze"]!;
            var gazeEvaluable = Json.Truthy(gaze["evaluable"]);
            var eyeAttention = summary["eye_region_attention"];
            var demo = uow.Demographics.Answers(s.ParticipantId);
            var demographics = demo is null ? new JsonObject() : Json.CloneObj(demo.Answers);
            var post = Json.Num(gaze["post_eye_share"]);
            var baseline = Json.Num(gaze["baseline_eye_share"]);
            long? totalMs = Long(cov["total_ms"]);
            var created = JsonFormat.Timestamp(s.CreatedAt);
            var row = new JsonObject
            {
                ["session_id"] = s.Id,
                ["participant_code"] = code,
                ["created_at"] = created,
                ["path"] = At(proto, "path"),
                ["protocol_name"] = At(proto, "name"),
                ["protocol_version"] = At(proto, "version"),
                ["sheet_version"] = sheet?.Version,
                ["device_platform"] = platform?.DeepClone(),
                ["screen"] = $"{PyText.Str(PracticeRules.Get(s.Screen, "w"))}x{PyText.Str(PracticeRules.Get(s.Screen, "h"))}@{PyText.Str(PracticeRules.Get(s.Screen, "dpr", 1))}",
                ["estimator"] = At(s.GazeModel, "model_id"),
                ["gaze_model_version"] = At(s.GazeModel, "model_version"),
                ["synthetic"] = s.Synthetic,
                ["quality"] = quality["grade"]?.DeepClone(),
                ["quality_reasons"] = string.Join(";", (quality["reasons"] as JsonArray ?? []).Select(PyText.Str)),
                ["calibration_residual_px"] = At(summary["calibration"], "residual_px_median"),
                ["validation_passed"] = At(summary["validation"], "passed"),
                ["settings_version"] = At(summary["validation"], "settings_version"),
                ["size_ratio"] = At(summary["validation"], "size_ratio"),
                ["total_ms"] = cov["total_ms"]?.DeepClone(),
                ["classifiable_share"] = Share(Long(cov["classifiable_ms"]), totalMs),
                ["uncertain_share"] = Share(Long(cov["uncertain_ms"]), totalMs),
                ["missing_share"] = Share(Long(cov["missing_ms"]), totalMs),
                ["face_share"] = At(summary["face_region_attention"], "share"),
                ["eye_share"] = eyeAttention is JsonObject ea && Json.Truthy(ea["evaluable"]) ? At(ea, "share") : null,
                ["baseline_eye_share"] = gazeEvaluable ? gaze["baseline_eye_share"]?.DeepClone() : null,
                ["post_eye_share"] = gazeEvaluable ? gaze["post_eye_share"]?.DeepClone() : null,
                ["eye_share_delta"] = gazeEvaluable && post is not null && baseline is not null ? Json.Float(PyMath.Round(post.Value - baseline.Value, 4)) : null,
                ["comprehension_share"] = output["comprehension"]!["share"]?.DeepClone(),
                ["number_task_share"] = output["number_task"]!["share"]?.DeepClone(),
                ["stages_completed"] = output["number_task"]!["stages_completed"]?.DeepClone(),
                ["comfort_min"] = output["comfort"]!["min"]?.DeepClone(),
                ["comfort_mean"] = output["comfort"]!["mean"]?.DeepClone(),
                ["comfort_low_count"] = output["comfort"]!["low_count"]?.DeepClone(),
                ["pauses"] = output["comfort"]!["pauses"]?.DeepClone(),
                ["ended_early"] = output["comfort"]!["ended_early"]?.DeepClone(),
                ["improvement"] = output["improvement"]!["result"]?.DeepClone(),
                ["group_key"] = gk,
                ["demographics"] = Json.CloneObj(demographics),
            };
            rows.Add(new AnalysisRow(row, s.CreatedAt, code, gk, demographics));
        }
        var groups = new OrderedDictionary<string, (int Sessions, HashSet<string> Participants)>();
        foreach (var r in rows)
        {
            var g = groups.TryGetValue(r.GroupKey, out var existing) ? existing : (Sessions: 0, Participants: new HashSet<string>());
            g.Participants.Add(r.ParticipantCode);
            groups[r.GroupKey] = (g.Sessions + 1, g.Participants);
        }
        var groupList = groups.Select(g =>
        {
            var parts = g.Key.Split('|');
            return (g.Value.Sessions, Item: new JsonObject
            {
                ["group_key"] = g.Key, ["device_platform"] = parts[0], ["protocol_version"] = parts[1], ["estimator"] = parts[2],
                ["screen_bucket"] = parts[3], ["stimulus_bucket_px"] = parts[4], ["sessions"] = g.Value.Sessions,
                ["participants"] = g.Value.Participants.Count,
            });
        }).ToList();
        var trends = new OrderedDictionary<(string Code, string Group), JsonArray>();
        foreach (var r in rows.OrderBy(r => r.CreatedAt))
        {
            if (!trends.TryGetValue((r.ParticipantCode, r.GroupKey), out var points))
                trends[(r.ParticipantCode, r.GroupKey)] = points = [];
            points.Add(new JsonObject
            {
                ["session_id"] = r.Data["session_id"]?.DeepClone(),
                ["created_at"] = r.Data["created_at"]?.DeepClone(),
                ["baseline_eye_share"] = r.Data["baseline_eye_share"]?.DeepClone(),
                ["post_eye_share"] = r.Data["post_eye_share"]?.DeepClone(),
                ["comfort_mean"] = r.Data["comfort_mean"]?.DeepClone(),
                ["comprehension_share"] = r.Data["comprehension_share"]?.DeepClone(),
                ["number_task_share"] = r.Data["number_task_share"]?.DeepClone(),
                ["quality"] = r.Data["quality"]?.DeepClone(),
            });
        }
        return new AnalysisResult(
            filters.Given(),
            rows,
            new JsonArray(groupList.OrderBy(g => -g.Sessions).Select(g => (JsonNode?)g.Item).ToArray()),
            new JsonArray(trends.Select(t => (JsonNode?)new JsonObject
            {
                ["participant_code"] = t.Key.Code, ["group_key"] = t.Key.Group, ["points"] = t.Value,
            }).ToArray()),
            excluded);
    }

    public static JsonObject Analysis(IUnitOfWork uow, Principal principal, int studyId, AnalysisFilters filters)
    {
        var result = AnalysisRows(uow, principal, studyId, filters);
        LogAccess(uow, principal, studyId, "analysis", new JsonObject { ["filters"] = Json.CloneObj(result.Filters), ["rows"] = result.Rows.Count });
        uow.Commit();
        return result.ToJson();
    }

    private static JsonObject Flatten(AnalysisRow row, IReadOnlyList<string> demoKeys)
    {
        var flat = new JsonObject();
        foreach (var k in AnalysisColumns)
            flat[k] = row.Data[k]?.DeepClone();
        foreach (var k in demoKeys)
            flat[$"demo_{k}"] = row.Demographics[k]?.DeepClone();
        flat["export_version"] = ResearchRules.ExportVersion;
        return flat;
    }

    /// <summary>The coded session table as CSV (UTF-8 with a BOM, Excel-friendly) or JSON; one
    /// <c>demo_&lt;key&gt;</c> column per demographics answer key, never the email.</summary>
    public static ExportFile ExportSessions(IUnitOfWork uow, Principal principal, int studyId, AnalysisFilters filters, string fmt)
    {
        var result = AnalysisRows(uow, principal, studyId, filters);
        var demoKeys = result.Rows.SelectMany(r => r.Demographics.Select(d => d.Key)).Distinct().Order(StringComparer.Ordinal).ToList();
        var flat = result.Rows.Select(r => Flatten(r, demoKeys)).ToList();
        string[] columns = [.. AnalysisColumns, .. demoKeys.Select(k => $"demo_{k}"), "export_version"];
        ExportFile file;
        if (fmt == "json")
        {
            var payload = new JsonObject
            {
                ["export_version"] = ResearchRules.ExportVersion,
                ["study_id"] = studyId,
                ["filters"] = Json.CloneObj(result.Filters),
                ["generated_at"] = JsonFormat.Timestamp(DateTime.UtcNow),
                ["rows"] = new JsonArray(flat.Select(f => (JsonNode?)f).ToArray()),
            };
            file = new ExportFile($"study-{studyId}-sessions.json", Encoding.UTF8.GetBytes(PyText.JsonDumps(payload, indent: 1)), "application/json");
        }
        else
        {
            var sb = new StringBuilder();
            PyText.CsvRow(sb, columns);
            foreach (var r in flat)
                PyText.CsvRow(sb, columns.Select(k => r[k] is { } v ? PyText.Str(v) : "").ToList());
            file = new ExportFile($"study-{studyId}-sessions.csv", PyText.Utf8Sig(sb.ToString()), "text/csv");
        }
        LogAccess(uow, principal, studyId, $"export_sessions_{fmt}", new JsonObject { ["filters"] = Json.CloneObj(result.Filters), ["rows"] = flat.Count });
        uow.Commit();
        return file;
    }

    public static ExportFile ExportSamples(IUnitOfWork uow, Principal principal, int studyId, int sessionId)
    {
        var s = StudySession(uow, principal, studyId, sessionId);
        var sb = new StringBuilder();
        PyText.CsvRow(sb, ["t_ms", "x", "y", "conf", "valid", "region", "segment", "layout_id"]);
        foreach (var x in uow.Samples.ForSession(s.Id))
        {
            PyText.CsvRow(sb,
            [
                x.TMs.ToString(CultureInfo.InvariantCulture),
                x.X is null ? "" : PyText.FloatStr(PyMath.Round(x.X.Value, 2)),
                x.Y is null ? "" : PyText.FloatStr(PyMath.Round(x.Y.Value, 2)),
                PyText.FloatStr(PyMath.Round(x.Conf, 3)),
                x.Valid ? "1" : "0",
                x.Region,
                x.Segment,
                x.LayoutId is { } id && id != 0 ? id.ToString(CultureInfo.InvariantCulture) : "",
            ]);
        }
        LogAccess(uow, principal, studyId, "export_samples_csv", new JsonObject { ["session_id"] = s.Id });
        uow.Commit();
        return new ExportFile($"session-{s.Id}-samples.csv", PyText.Utf8Sig(sb.ToString()), "text/csv");
    }

    public static ExportFile ExportEvents(IUnitOfWork uow, Principal principal, int studyId, int sessionId)
    {
        var s = StudySession(uow, principal, studyId, sessionId);
        var sb = new StringBuilder();
        PyText.CsvRow(sb, ["t_ms", "type", "payload_json"]);
        foreach (var e in uow.Events.ForSession(s.Id))
            PyText.CsvRow(sb, [e.TMs.ToString(CultureInfo.InvariantCulture), e.Type, PyText.JsonDumps(e.Payload, ensureAscii: false)]);
        LogAccess(uow, principal, studyId, "export_events_csv", new JsonObject { ["session_id"] = s.Id });
        uow.Commit();
        return new ExportFile($"session-{s.Id}-events.csv", PyText.Utf8Sig(sb.ToString()), "text/csv");
    }

    public static JsonArray DataDictionary() => ResearchRules.DataDictionary();

    public static JsonArray AccessLog(IUnitOfWork uow, Principal principal, int studyId, int limit)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (limit is < 1 or > 1000)
            throw new Invalid("limit must be 1..1000");
        return new JsonArray(uow.AccessLog.ListForStudy(studyId, limit).Select(e => (JsonNode?)new JsonObject
        {
            ["at"] = Ts(e.CreatedAt), ["user_id"] = e.UserId, ["role"] = e.Role, ["action"] = e.Action, ["detail"] = Json.CloneObj(e.Detail),
        }).ToArray());
    }

    // ---------- participant raw data and deletion ----------

    private static JsonObject? DebriefOf(IUnitOfWork uow, int sessionId)
    {
        var a = uow.DebriefAnswers.ForSession(sessionId);
        return a is null ? null : new JsonObject { ["form_version"] = a.FormVersion, ["answers"] = Json.CloneObj(a.Answers), ["skipped"] = a.Skipped };
    }

    private static JsonObject? ConversationOf(IUnitOfWork uow, int sessionId)
    {
        var c = uow.Live.ConversationForSession(sessionId);
        if (c is null)
            return null;
        return new JsonObject
        {
            ["topic"] = c.Topic, ["input_mode"] = c.InputMode, ["transcript_kept"] = c.TranscriptAllowed, ["status"] = c.Status.Value(),
            ["end_reason"] = c.EndReason,
            ["turns"] = new JsonArray(uow.Live.Turns(c.Id).Select(t => (JsonNode?)new JsonObject
            {
                ["index"] = t.Index, ["role"] = t.Role, ["text"] = t.Text, ["chars"] = t.Chars, ["t_ms"] = t.TMs, ["flags"] = Json.Array(t.Flags),
            }).ToArray()),
        };
    }

    /// <summary>Everything stored about the participant, for the participant: the account and
    /// consent records plus every session's summary and raw data. No camera video exists.</summary>
    public static JsonObject MyFullData(IUnitOfWork uow, Principal principal)
    {
        var p = RequireParticipant(principal);
        var data = UseCases.MyDataExport(uow, principal);
        var sessions = new JsonArray();
        foreach (var s in uow.Sessions.ListForParticipant(p.Id))
        {
            var sid = s.Id;
            sessions.Add(new JsonObject
            {
                ["summary"] = MeasurementUseCases.Summarize(uow, s),
                ["samples"] = ResearchRules.CompactSamples(uow.Samples.ForSession(sid)),
                ["events"] = new JsonArray(uow.Events.ForSession(sid).Select(e => (JsonNode?)new JsonObject
                {
                    ["t_ms"] = e.TMs, ["type"] = e.Type, ["payload"] = Json.CloneObj(e.Payload),
                }).ToArray()),
                ["trials"] = new JsonArray(uow.Trials.ForSession(sid).Select(t => (JsonNode?)new JsonObject
                {
                    ["stage_index"] = t.StageIndex, ["trial_index"] = t.TrialIndex, ["t_ms"] = t.TMs, ["number_shown"] = t.NumberShown,
                    ["zone"] = t.Zone, ["response"] = t.Response, ["correct"] = t.Correct,
                }).ToArray()),
                ["answers"] = Answers(uow, sid),
                ["debrief"] = DebriefOf(uow, sid),
                ["conversation"] = ConversationOf(uow, sid),
            });
        }
        data["sessions"] = sessions;
        data["export_version"] = ResearchRules.ExportVersion;
        data["note"] = "Gaze estimates and session events are the raw data. No camera video exists.";
        LogAccess(uow, principal, p.StudyId, "self_export", new JsonObject { ["participant_id"] = p.Id });
        uow.Commit();
        return data;
    }

    private static JsonObject Counts(OrderedDictionary<string, int> deleted)
    {
        var o = new JsonObject();
        foreach (var (k, v) in deleted)
            o[k] = v;
        return o;
    }

    /// <summary>Withdrawal: the study's retention policy decides whether the research data goes
    /// (delete_all) or stays coded (keep_coded); the identity link is always removed (the login is
    /// erased and disabled).</summary>
    public static JsonObject EraseMe(IUnitOfWork uow, IClock clock, Principal principal, string confirm)
    {
        var p = RequireParticipant(principal);
        if (confirm != "DELETE MY DATA")
            throw new Invalid("confirmation phrase must be exactly \"DELETE MY DATA\"");
        var study = uow.Studies.Get(p.StudyId);
        var policy = study is not null ? study.RetentionPolicy : RetentionPolicies.DeleteAll;
        var deleted = policy == RetentionPolicies.DeleteAll ? uow.PurgeParticipantResearchData(p.Id) : new OrderedDictionary<string, int>();
        var user = uow.Users.Get(p.UserId);
        if (user is not null)
        {
            user.Email = $"erased-{user.Id}@erased.invalid";
            user.PasswordHash = "!";
            user.IsActive = false;
        }
        if (policy == RetentionPolicies.DeleteAll)
            uow.DeleteParticipant(p.Id);
        LogAccess(uow, principal, p.StudyId, "erasure", new JsonObject { ["participant_id"] = p.Id, ["policy"] = policy, ["deleted"] = Counts(deleted) });
        uow.Commit();
        return new JsonObject { ["policy"] = policy, ["deleted"] = Counts(deleted), ["identity_removed"] = true };
    }

    public static JsonObject DeleteParticipantData(IUnitOfWork uow, Principal principal, int studyId, string code, string confirm)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var p = uow.Participants.ByCode(studyId, code) ?? throw new NotFound("participant not found");
        if (confirm != code)
            throw new Invalid("confirmation must repeat the research code");
        var deleted = uow.PurgeParticipantResearchData(p.Id);
        LogAccess(uow, principal, studyId, "participant_data_deleted", new JsonObject { ["participant_code"] = code, ["deleted"] = Counts(deleted) });
        uow.Commit();
        return new JsonObject { ["participant_code"] = code, ["deleted"] = Counts(deleted) };
    }

    // ---------- study policy ----------

    private static JsonObject StudyView(Study st) => new() { ["id"] = st.Id, ["name"] = st.Name, ["retention_policy"] = st.RetentionPolicy };

    /// <summary>Admins manage studies, so they may read the study record without being members.</summary>
    public static JsonObject GetStudy(IUnitOfWork uow, Principal principal, int studyId)
    {
        if (principal.Role != Role.Admin)
            RequireStudyAccess(principal, studyId);
        var st = uow.Studies.Get(studyId) ?? throw new NotFound("study not found");
        return StudyView(st);
    }

    public static JsonObject UpdateStudy(IUnitOfWork uow, Principal principal, int studyId, string? retentionPolicy)
    {
        RequireRole(principal, Role.Admin);
        var st = uow.Studies.Get(studyId) ?? throw new NotFound("study not found");
        if (retentionPolicy is not null)
        {
            if (!RetentionPolicies.All.Contains(retentionPolicy))
                throw new Invalid($"retention_policy must be one of {MeasurementRules.TupleText(RetentionPolicies.All)}");
            st.RetentionPolicy = retentionPolicy;
        }
        uow.Commit();
        return StudyView(st);
    }
}
