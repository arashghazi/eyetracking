using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using static EyeTracking.Application.Authz;

namespace EyeTracking.Application;

/// <summary>The import form of a research tracker export as the router passes it (Form fields;
/// null where FastAPI gives None).</summary>
public sealed record ReferenceImportOptions(
    string TimeColumn,
    string XColumn,
    string YColumn,
    string? ValidColumn,
    string? ValidValues,
    string TimeUnit,
    double Offset,
    string CoordSpace,
    double OriginX,
    double OriginY,
    string? Delimiter);

/// <summary>Use cases for build step 6 (pilot_use_cases.py), the supervised pilot. Supervisors
/// (researchers) observe sessions live and write observations; participants may answer a short
/// versioned debrief after a session; researchers review what candidate thresholds would change
/// before saving a new settings version; one comparison day with a research eye tracker is
/// supported by importing its export per session. Every read of study data here is an explicit,
/// logged research access, and only study members reach it.</summary>
public static class PilotUseCases
{
    private static readonly StudyRole[] Readers = [StudyRole.Researcher, StudyRole.Analyst];
    public const int LiveWindowMs = 10_000;
    public const int ActiveHours = 12;

    private static JsonNode? Ts(DateTime? t) => t is null ? null : JsonFormat.Timestamp(t.Value);

    private static JsonNode? F(double? v) => v is null ? null : Json.Float(v.Value);

    /// <summary>Python's <c>(d or {}).get(key)</c> on a JSON part, as a copy.</summary>
    private static JsonNode? At(JsonNode? d, string key) => d is JsonObject o ? o[key]?.DeepClone() : null;

    /// <summary>A dict key for a JSON value (Python hashes 1, 1.0 and True alike; lists and dicts
    /// cannot be keys).</summary>
    private static string DictKey(JsonNode? n) => n switch
    {
        JsonArray or JsonObject => throw new InvalidOperationException("unhashable type"),
        _ when Json.Str(n) is { } s => "s:" + s,
        _ when Json.IsBool(n) => "n:" + (Json.Truthy(n) ? "1" : "0"),
        _ when Json.IsNumber(n) => "n:" + Json.PythonFloat(Json.Num(n)!.Value),
        _ => "none",
    };

    private static Session SessionInStudy(IUnitOfWork uow, Principal principal, int studyId, int sessionId, params StudyRole[] roles)
    {
        RequireStudyAccess(principal, studyId, roles);
        var s = uow.Sessions.Get(sessionId);
        if (s is null || s.StudyId != studyId)
            throw new NotFound("session not found");
        return s;
    }

    private static Dictionary<int, string> Codes(IUnitOfWork uow, int studyId) =>
        uow.Participants.ListForStudy(studyId).ToDictionary(p => p.Id, p => p.Code);

    private static string CodeOf(Dictionary<int, string> codes, int participantId) => codes.GetValueOrDefault(participantId, "?");

    // ---------- supervisor observations ----------

    private static JsonObject ObsView(Observation o) => new()
    {
        ["id"] = o.Id, ["session_id"] = o.SessionId, ["author_id"] = o.AuthorId, ["category"] = o.Category,
        ["severity"] = o.Severity, ["text"] = o.Text, ["t_ms"] = o.TMs, ["created_at"] = Ts(o.CreatedAt),
    };

    public static JsonObject AddObservation(IUnitOfWork uow, Principal principal, int studyId, int sessionId, string category, string severity, string text, int? tMs)
    {
        var s = SessionInStudy(uow, principal, studyId, sessionId, StudyRole.Researcher);
        var o = new Observation { StudyId = studyId, SessionId = s.Id, AuthorId = principal.UserId, Category = category, Severity = severity, Text = text, TMs = tMs };
        o.Validate();
        o = uow.Observations.Add(o);
        uow.Commit();
        return ObsView(o);
    }

    public static JsonArray ListObservations(IUnitOfWork uow, Principal principal, int studyId, int sessionId)
    {
        var s = SessionInStudy(uow, principal, studyId, sessionId, Readers);
        return new JsonArray(uow.Observations.ForSession(s.Id).Select(o => (JsonNode?)ObsView(o)).ToArray());
    }

    // ---------- debrief ----------

    /// <summary>The saved form, or the unsaved default (version 0, off).</summary>
    private static DebriefForm CurrentForm(IUnitOfWork uow, int studyId) =>
        uow.DebriefForms.Current(studyId) ?? new DebriefForm { StudyId = studyId, Version = 0, Questions = PilotRules.DefaultDebriefQuestions(), Enabled = false };

    private static JsonObject FormView(DebriefForm f) => new()
    {
        ["version"] = f.Version, ["enabled"] = f.Enabled, ["questions"] = Json.CloneArr(f.Questions), ["saved"] = f.Id != 0,
    };

    public static JsonObject GetDebriefForm(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId, Readers);
        return FormView(CurrentForm(uow, studyId));
    }

    /// <summary>Questions are versioned; answers keep the version they were given for. <c>enabled</c> is a switch.</summary>
    public static JsonObject PutDebriefForm(IUnitOfWork uow, Principal principal, int studyId, JsonArray? questions, bool? enabled)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var cur = uow.DebriefForms.Current(studyId);
        var clean = questions is not null ? PilotRules.ValidateDebriefQuestions(questions) : null;
        DebriefForm form;
        if (cur is null || (clean is not null && !PracticeRules.PyEquals(clean, cur.Questions)))
        {
            var baseQuestions = cur is not null ? Json.CloneArr(cur.Questions) : PilotRules.DefaultDebriefQuestions();
            form = uow.DebriefForms.Add(new DebriefForm
            {
                StudyId = studyId,
                Version = (cur?.Version ?? 0) + 1,
                Questions = clean ?? baseQuestions,
                Enabled = enabled ?? cur?.Enabled ?? false,
            });
        }
        else
        {
            form = cur;
            if (enabled is not null)
                form.Enabled = enabled.Value;
        }
        uow.Commit();
        return FormView(form);
    }

    private static Session OwnSession(IUnitOfWork uow, Principal principal, int sessionId)
    {
        var p = RequireParticipant(principal);
        var s = uow.Sessions.Get(sessionId);
        if (s is null || s.ParticipantId != p.Id)
            throw new NotFound("session not found");
        return s;
    }

    private static JsonObject? AnswerView(DebriefAnswer? a) => a is null ? null : new JsonObject
    {
        ["form_version"] = a.FormVersion, ["answers"] = Json.CloneObj(a.Answers), ["skipped"] = a.Skipped, ["created_at"] = Ts(a.CreatedAt),
    };

    public static JsonObject MyDebrief(IUnitOfWork uow, Principal principal, int sessionId)
    {
        var s = OwnSession(uow, principal, sessionId);
        var form = CurrentForm(uow, s.StudyId);
        var answer = uow.DebriefAnswers.ForSession(s.Id);
        var open = form.Enabled && form.Id != 0;
        return new JsonObject
        {
            ["enabled"] = open,
            ["session_ended"] = s.Status == SessionStatus.Ended,
            ["form"] = open ? FormView(form) : null,
            ["answer"] = AnswerView(answer),
        };
    }

    public static JsonObject SubmitDebrief(IUnitOfWork uow, Principal principal, int sessionId, int formVersion, JsonObject? answers, bool skipped)
    {
        var s = OwnSession(uow, principal, sessionId);
        if (s.Status != SessionStatus.Ended)
            throw new Conflict("the questions open when the session has ended");
        var form = uow.DebriefForms.Current(s.StudyId);
        if (form is null || !form.Enabled)
            throw new Conflict("this study does not ask questions after a session");
        if (formVersion != form.Version)
            throw new Conflict("the questions have changed; please reload them");
        if (uow.DebriefAnswers.ForSession(s.Id) is not null)
            throw new Conflict("this session's questions are already answered");
        var clean = skipped ? [] : PilotRules.ValidateDebriefAnswers(form.Questions, answers ?? []);
        var a = uow.DebriefAnswers.Add(new DebriefAnswer
        {
            StudyId = s.StudyId, SessionId = s.Id, ParticipantId = s.ParticipantId, FormVersion = form.Version, Answers = clean, Skipped = skipped,
        });
        uow.Commit();
        return AnswerView(a)!;
    }

    // ---------- live monitor ----------

    public static JsonArray ActiveSessions(IUnitOfWork uow, IClock clock, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        var since = clock.Now().AddHours(-ActiveHours);
        var codes = Codes(uow, studyId);
        var output = new List<(DateTime CreatedAt, JsonObject Row)>();
        foreach (var s in uow.Sessions.ListForStudy(studyId))
        {
            if (s.Status == SessionStatus.Ended || s.CreatedAt < since)
                continue;
            var events = uow.Events.ForSession(s.Id);
            var last = events.Count > 0 ? events.OrderBy(e => e.TMs).ThenBy(e => e.Id).Last() : null;
            output.Add((s.CreatedAt, new JsonObject
            {
                ["session_id"] = s.Id,
                ["participant_code"] = CodeOf(codes, s.ParticipantId),
                ["status"] = s.Status.Value(),
                ["created_at"] = Ts(s.CreatedAt),
                ["device_platform"] = s.Device["platform"]?.DeepClone(),
                ["protocol_id"] = s.ProtocolId,
                ["last_event"] = last is null ? null : new JsonObject { ["type"] = last.Type, ["t_ms"] = last.TMs, ["created_at"] = Ts(last.CreatedAt) },
            }));
        }
        return new JsonArray(output.OrderByDescending(r => r.CreatedAt).Select(r => (JsonNode?)r.Row).ToArray());
    }

    /// <summary>What a supervisor sitting next to the participant needs, polled every few seconds.
    /// The access is logged once per monitoring start (<paramref name="first"/>), not on every poll.</summary>
    public static JsonObject LiveStatus(IUnitOfWork uow, IClock clock, Principal principal, int studyId, int sessionId, bool first)
    {
        var s = SessionInStudy(uow, principal, studyId, sessionId, StudyRole.Researcher);
        var sid = s.Id;
        var samples = uow.Samples.ForSession(sid);
        var events = uow.Events.ForSession(sid);
        int? lastT = samples.Count > 0 ? samples.Max(x => x.TMs) : null;
        var counts = new Dictionary<string, int>();
        foreach (var r in MeasurementRules.Classifiable.Append("uncertain"))
            counts[r] = 0;
        var recentN = 0;
        if (lastT is not null)
        {
            foreach (var x in samples)
            {
                if (x.TMs >= lastT - LiveWindowMs)
                {
                    recentN++;
                    counts[counts.ContainsKey(x.Region) ? x.Region : "uncertain"]++;
                }
            }
        }
        var segments = MeasurementRules.SegmentsFromEvents(events, null);
        var current = segments.AsEnumerable().Reverse().FirstOrDefault(g => g.EndedMs is null)?.Label?.DeepClone();
        var ordered = events.OrderBy(e => e.TMs).ThenBy(e => e.Id).ToList();
        var pauseState = ordered.Where(e => e.Type is "pause" or "resume").Select(e => e.Type).ToList();
        var stages = uow.StageResults.ForSession(sid);
        var lastStage = stages.Count > 0 ? stages[^1] : null;
        var layout = uow.Layouts.Latest(sid);
        var val = uow.Validations.Latest(sid);
        DateTime? lastEventAt = events.Count > 0 ? events.Max(e => e.CreatedAt) : null;
        var now = clock.Now();
        var regions = new JsonObject();
        foreach (var (k, v) in counts)
            regions[k] = v;
        var result = new JsonObject
        {
            ["session_id"] = sid,
            ["participant_code"] = CodeOf(Codes(uow, studyId), s.ParticipantId),
            ["status"] = s.Status.Value(),
            ["synthetic"] = s.Synthetic,
            ["estimator"] = s.GazeModel["model_id"]?.DeepClone(),
            ["calibration_valid"] = s.CalibrationValid,
            ["validation"] = val is null ? null : new JsonObject { ["passed"] = val.Passed, ["reasons"] = Json.Array(val.Reasons) },
            ["current_segment"] = current,
            ["paused"] = pauseState.Count > 0 && pauseState[^1] == "pause",
            ["pauses"] = pauseState.Count(t => t == "pause"),
            ["stage_index"] = layout?.StageIndex,
            ["last_stage_result"] = lastStage is null ? null : new JsonObject
            {
                ["stage_index"] = lastStage.StageIndex, ["decision"] = lastStage.Decision, ["reason"] = lastStage.Reason,
                ["comfort_value"] = lastStage.ComfortValue, ["correct_ratio"] = F(lastStage.CorrectRatio),
            },
            ["samples_total"] = samples.Count,
            ["last_sample_t_ms"] = lastT,
            ["recent_window_ms"] = LiveWindowMs,
            ["recent"] = new JsonObject
            {
                ["samples"] = recentN,
                ["valid_share"] = recentN > 0 ? Json.Float(PyMath.Round(1 - (double)counts["uncertain"] / recentN, 4)) : null,
                ["regions"] = regions,
            },
            ["recent_events"] = new JsonArray(ordered.TakeLast(8).Select(e => (JsonNode?)new JsonObject
            {
                ["t_ms"] = e.TMs, ["type"] = e.Type, ["payload"] = Json.CloneObj(e.Payload),
            }).ToArray()),
            // timedelta.total_seconds(): whole microseconds over 10**6
            ["seconds_since_last_event"] = lastEventAt is null ? null : Json.Float(PyMath.Round((now - lastEventAt.Value).Ticks / 10 / 1e6, 1)),
            ["observations"] = uow.Observations.ForSession(sid).Count,
            ["conversation"] = LiveUseCases.MonitorBlock(uow, sid),
            ["end_reason"] = s.EndReason,
            ["note"] = "Live view for the supervisor. Region counts come from the webcam estimate; with a synthetic estimator they mean nothing.",
        };
        if (first)
        {
            ResearchUseCases.LogAccess(uow, principal, studyId, "live_monitor", new JsonObject { ["session_id"] = sid });
            uow.Commit();
        }
        return result;
    }

    // ---------- threshold review ----------

    private sealed class DeviceCounts(JsonNode? device)
    {
        public JsonNode? Device { get; } = device;
        public int Sessions, Validated, PassCurrent, PassCandidate;
    }

    private sealed record ReviewRow(JsonObject Data, bool ValidationCurrentPassed, bool? ValidationCandidatePassed, string QualityCurrent, string QualityCandidate, bool Changed);

    /// <summary>Shows what candidate thresholds would change on the recorded sessions. Saves nothing:
    /// a researcher decides and saves a new settings version with a rationale.</summary>
    public static JsonObject ThresholdReview(IUnitOfWork uow, Principal principal, int studyId, JsonObject changes, bool includeSynthetic)
    {
        RequireStudyAccess(principal, studyId, Readers);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var current = MeasurementUseCases.SettingsForStudy(uow, studyId);
        // the candidate keeps each value as sent (Python's setattr), so it is JSON here
        var candidate = PilotRules.SettingsValues(current);
        var unknown = changes.Select(p => p.Key).Where(k => !PilotRules.SettingsFields.Contains(k)).Order(StringComparer.Ordinal).ToList();
        if (unknown.Count > 0)
            throw new Invalid("unknown settings: " + string.Join(", ", unknown));
        foreach (var (k, v) in changes)
        {
            if (v is not null)
                candidate[k] = v.DeepClone();
        }
        PilotRules.ValidateCandidate(candidate);
        var currentValues = PilotRules.SettingsValues(current);
        var notes = new List<string>();
        if (!PracticeRules.PyEquals(candidate["gaze_conf_threshold"], currentValues["gaze_conf_threshold"]))
            notes.Add("gaze_conf_threshold changes how each sample is classified; recorded sessions are not re-classified here and the change applies to new sessions only.");
        if (!PracticeRules.PyEquals(candidate["calibration_points"], currentValues["calibration_points"])
            || !PracticeRules.PyEquals(candidate["allow_continue_without_validation"], currentValues["allow_continue_without_validation"]))
            notes.Add("calibration_points and allow_continue_without_validation apply to new sessions only.");
        var codes = Codes(uow, studyId);
        var rows = new List<ReviewRow>();
        string[] metricNames = ["correct_ratio", "uncertain_ratio", "size_ratio", "residual_px_median", "uncertain_share", "missing_share"];
        var metrics = metricNames.ToDictionary(k => k, _ => new List<double>());
        var byDevice = new Dictionary<string, DeviceCounts>();
        var skippedSynthetic = 0;
        foreach (var s in uow.Sessions.ListForStudy(studyId))
        {
            if (s.Synthetic && !includeSynthetic)
            {
                skippedSynthetic++;
                continue;
            }
            var summary = MeasurementUseCases.Summarize(uow, s);
            var val = Json.Truthy(summary["validation"]) ? summary["validation"]!.AsObject() : null;
            var cov = Json.Truthy(summary["coverage"]) ? summary["coverage"]!.AsObject() : [];
            var total = Json.Num(cov["total_ms"]) ?? 0;
            var observed = (Json.Num(cov["classifiable_ms"]) ?? 0) + (Json.Num(cov["uncertain_ms"]) ?? 0);
            var candVal = val is not null ? PilotRules.Revalidate(val, candidate) : null;
            var candSummary = (JsonObject)summary.DeepClone();
            if (val is not null)
            {
                var merged = Json.CloneObj(val);
                merged["passed"] = candVal!["passed"]!.DeepClone();
                merged["reasons"] = candVal["reasons"]!.DeepClone();
                candSummary["validation"] = merged;
            }
            else
            {
                candSummary["validation"] = null;
            }
            var candQuality = ResearchRules.GradeQuality(candSummary, candidate["quality_max_uncertain_share"], candidate["quality_max_missing_share"]);
            if (val is not null)
            {
                foreach (var k in new[] { "correct_ratio", "uncertain_ratio", "size_ratio" })
                    metrics[k].Add(Json.Num(val[k])!.Value);
            }
            if (Json.Truthy(summary["calibration"]))
                metrics["residual_px_median"].Add(Json.Num(summary["calibration"]!["residual_px_median"])!.Value);
            if (observed != 0)
                metrics["uncertain_share"].Add((Json.Num(cov["uncertain_ms"]) ?? 0) / observed);
            if (total != 0)
                metrics["missing_share"].Add((Json.Num(cov["missing_ms"]) ?? 0) / total);
            var platform = s.Device["platform"];
            JsonNode device = Json.Truthy(platform) ? platform!.DeepClone() : "unknown";
            var key = DictKey(device);
            if (!byDevice.TryGetValue(key, out var d))
                byDevice[key] = d = new DeviceCounts(device);
            d.Sessions++;
            var passedCurrent = val is not null && Json.Truthy(val["passed"]);
            var passedCandidate = candVal is not null && Json.Truthy(candVal["passed"]);
            if (val is not null)
            {
                d.Validated++;
                d.PassCurrent += passedCurrent ? 1 : 0;
                d.PassCandidate += passedCandidate ? 1 : 0;
            }
            var qualityCurrent = summary["quality"]!.AsObject();
            var gradeCurrent = Json.Str(qualityCurrent["grade"])!;
            var changed = (val is not null && passedCurrent != passedCandidate) || gradeCurrent != candQuality.Grade;
            rows.Add(new ReviewRow(new JsonObject
            {
                ["session_id"] = s.Id,
                ["participant_code"] = CodeOf(codes, s.ParticipantId),
                ["created_at"] = Ts(s.CreatedAt),
                ["device_platform"] = device.DeepClone(),
                ["synthetic"] = s.Synthetic,
                ["settings_version"] = val is not null ? val["settings_version"]?.DeepClone() : null,
                ["validation_current"] = val is not null ? new JsonObject { ["passed"] = val["passed"]?.DeepClone(), ["reasons"] = val["reasons"]?.DeepClone() } : null,
                ["validation_candidate"] = candVal,
                ["quality_current"] = qualityCurrent.DeepClone(),
                ["quality_candidate"] = candQuality.AsDict(),
                ["changed"] = changed,
                ["metrics"] = new JsonObject
                {
                    ["correct_ratio"] = val is not null ? val["correct_ratio"]?.DeepClone() : null,
                    ["uncertain_ratio"] = val is not null ? val["uncertain_ratio"]?.DeepClone() : null,
                    ["size_ratio"] = val is not null ? val["size_ratio"]?.DeepClone() : null,
                    ["residual_px_median"] = At(summary["calibration"], "residual_px_median"),
                },
            }, passedCurrent, candVal is null ? null : passedCandidate, gradeCurrent, candQuality.Grade, changed));
        }

        JsonObject Grades(Func<ReviewRow, string> grade)
        {
            var output = new JsonObject { ["ok"] = 0, ["review"] = 0, ["exclude"] = 0 };
            foreach (var r in rows)
                output[grade(r)] = ((int?)output[grade(r)] ?? 0) + 1;
            return output;
        }

        var validated = rows.Where(r => r.Data["validation_current"] is not null).ToList();
        var given = new JsonObject();
        foreach (var (k, v) in changes)
        {
            if (v is not null)
                given[k] = v.DeepClone();
        }
        var distributions = new JsonObject();
        foreach (var (k, v) in metrics)
            distributions[k] = PilotRules.Distribution(v);
        var result = new JsonObject
        {
            ["current"] = new JsonObject { ["version"] = current.Version, ["values"] = currentValues },
            ["candidate"] = new JsonObject { ["values"] = candidate, ["changes"] = given },
            ["sessions"] = rows.Count,
            ["skipped_synthetic"] = skippedSynthetic,
            ["includes_synthetic"] = includeSynthetic,
            ["validated_sessions"] = validated.Count,
            ["validation_pass"] = new JsonObject
            {
                ["current"] = validated.Count(r => r.ValidationCurrentPassed),
                ["candidate"] = validated.Count(r => r.ValidationCandidatePassed == true),
            },
            ["quality"] = new JsonObject { ["current"] = Grades(r => r.QualityCurrent), ["candidate"] = Grades(r => r.QualityCandidate) },
            ["changed_sessions"] = rows.Count(r => r.Changed),
            ["distributions"] = distributions,
            ["by_device"] = new JsonArray(byDevice.Values.OrderByDescending(d => d.Sessions).Select(d => (JsonNode?)new JsonObject
            {
                ["device_platform"] = d.Device?.DeepClone(), ["sessions"] = d.Sessions, ["validated"] = d.Validated,
                ["pass_current"] = d.PassCurrent, ["pass_candidate"] = d.PassCandidate,
            }).ToArray()),
            ["rows"] = new JsonArray(rows.Select(r => (JsonNode?)r.Data).ToArray()),
            ["notes"] = Json.Array(notes.Append("Nothing is saved. A researcher decides and saves a new settings version with a rationale.")),
        };
        ResearchUseCases.LogAccess(uow, principal, studyId, "threshold_review", new JsonObject
        {
            ["changes"] = given.DeepClone(), ["sessions"] = rows.Count, ["includes_synthetic"] = includeSynthetic,
        });
        uow.Commit();
        return result;
    }

    // ---------- research eye tracker ----------

    private static JsonObject RecView(ReferenceRecording r) => new()
    {
        ["id"] = r.Id, ["session_id"] = r.SessionId, ["source"] = r.Source, ["settings"] = Json.CloneObj(r.Settings),
        ["sample_count"] = r.SampleCount, ["valid_count"] = r.ValidCount, ["uploaded_by"] = r.UploadedBy, ["created_at"] = Ts(r.CreatedAt),
    };

    private static List<WebcamPoint> WebcamPoints(IUnitOfWork uow, int sessionId) =>
        uow.Samples.ForSession(sessionId).Select(x => new WebcamPoint(x.TMs, x.X, x.Y, x.Valid, x.Region, x.Segment, x.LayoutId)).ToList();

    public static JsonObject ImportReference(
        IUnitOfWork uow, Principal principal, int studyId, int sessionId, string? source, ReferenceImportOptions opts, long autoAlignWindowMs, byte[] data)
    {
        var s = SessionInStudy(uow, principal, studyId, sessionId, StudyRole.Researcher);
        source = (source ?? "").Trim();
        // the column holds 120 UTF-16 units; Python counted characters
        if (source.Length == 0 || source.EnumerateRunes().Count() > 120 || source.Length > 120)
            throw new Invalid("source (the tracker's name and model) is required, max 120 characters");
        if (data.Length == 0)
            throw new Invalid("the file is empty");
        // the options that were given, in the router's order (Python drops None and "")
        var clean = new JsonObject();
        foreach (var (key, value) in new (string, JsonNode?)[]
                 {
                     ("time_column", opts.TimeColumn), ("x_column", opts.XColumn), ("y_column", opts.YColumn), ("valid_column", opts.ValidColumn),
                     ("valid_values", opts.ValidValues), ("time_unit", opts.TimeUnit), ("offset", Json.Float(opts.Offset)), ("coord_space", opts.CoordSpace),
                     ("origin_x", Json.Float(opts.OriginX)), ("origin_y", Json.Float(opts.OriginY)), ("delimiter", opts.Delimiter),
                 })
        {
            if (!Json.IsBlank(value))
                clean[key] = value;
        }
        var rows = PilotRules.ParseReferenceCsv(data, clean, s.Screen);
        clean["alignment"] = "given_offset";
        if (autoAlignWindowMs != 0)
        {
            var shift = PilotRules.EstimateOffset(WebcamPoints(uow, s.Id), rows, autoAlignWindowMs);
            rows = rows.Select(r => r with { TMs = r.TMs + shift }).ToList();
            clean["alignment"] = "estimated_from_data";
            clean["auto_align_window_ms"] = autoAlignWindowMs;
            clean["estimated_shift_ms"] = shift;
        }
        // the column is a 32-bit integer (as in the Python schema); SQLite would have kept larger values
        if (rows.Any(r => r.TMs is < int.MinValue or > int.MaxValue))
            throw new Invalid("time values are out of range; check time_unit and offset");
        if (rows.Any(r => r.X is { } x && !double.IsFinite(x) || r.Y is { } y && !double.IsFinite(y)))
            throw new Invalid("coordinates must be finite numbers");
        var rec = new ReferenceRecording
        {
            StudyId = studyId, SessionId = s.Id, Source = source, UploadedBy = principal.UserId, Settings = clean,
            SampleCount = rows.Count, ValidCount = rows.Count(r => r.Valid),
        };
        rec = uow.References.Add(rec, rows);
        ResearchUseCases.LogAccess(uow, principal, studyId, "reference_import", new JsonObject
        {
            ["session_id"] = s.Id, ["recording_id"] = rec.Id, ["rows"] = rows.Count,
        });
        uow.Commit();
        return RecView(rec);
    }

    public static JsonArray ListReferences(IUnitOfWork uow, Principal principal, int studyId, int sessionId)
    {
        var s = SessionInStudy(uow, principal, studyId, sessionId, Readers);
        return new JsonArray(uow.References.ForSession(s.Id).Select(r => (JsonNode?)RecView(r)).ToArray());
    }

    public static JsonObject CompareReference(IUnitOfWork uow, Principal principal, int studyId, int sessionId, int recordingId, long toleranceMs)
    {
        var s = SessionInStudy(uow, principal, studyId, sessionId, Readers);
        var rec = uow.References.Get(recordingId);
        if (rec is null || rec.SessionId != s.Id)
            throw new NotFound("reference recording not found");
        var layouts = new Dictionary<int, JsonObject>();
        foreach (var l in uow.Layouts.SessionAll(s.Id))
            layouts[l.Id] = l.Layout;
        var result = PilotRules.CompareWithReference(WebcamPoints(uow, s.Id), uow.References.Samples(rec.Id), layouts, toleranceMs);
        var val = uow.Validations.Latest(s.Id);
        var caveats = new List<string>();
        if (s.Synthetic)
            caveats.Add("The webcam side used a synthetic estimator; agreement numbers mean nothing.");
        if (Json.Str(rec.Settings["alignment"]) == "estimated_from_data")
            caveats.Add("The time alignment was estimated from this same data, which makes the agreement optimistic.");
        if (val is null || !val.Passed)
            caveats.Add("This session's regional validation did not pass.");
        result["recording"] = RecView(rec);
        result["session"] = new JsonObject
        {
            ["id"] = s.Id,
            ["participant_code"] = CodeOf(Codes(uow, studyId), s.ParticipantId),
            ["estimator"] = s.GazeModel["model_id"]?.DeepClone(),
            ["gaze_model_version"] = s.GazeModel["model_version"]?.DeepClone(),
            ["synthetic"] = s.Synthetic,
            ["validation_passed"] = val is not null && val.Passed,
            ["screen"] = Json.CloneObj(s.Screen),
        };
        result["caveats"] = Json.Array(caveats);
        ResearchUseCases.LogAccess(uow, principal, studyId, "reference_compare", new JsonObject { ["session_id"] = s.Id, ["recording_id"] = rec.Id });
        uow.Commit();
        return result;
    }

    // ---------- pilot report ----------

    private sealed class QuestionStats(JsonObject data)
    {
        public JsonObject Data { get; } = data;
        public List<long> Values { get; } = [];
    }

    private static (JsonArray Stats, JsonArray Comments) DebriefStats(
        IUnitOfWork uow, int studyId, IEnumerable<DebriefAnswer> answers, Dictionary<int, string> codesBySession)
    {
        var forms = new Dictionary<int, DebriefForm?>();
        var stats = new Dictionary<string, QuestionStats>(StringComparer.Ordinal);
        var comments = new JsonArray();
        foreach (var a in answers)
        {
            if (a.Skipped)
                continue;
            if (!forms.TryGetValue(a.FormVersion, out var form))
                forms[a.FormVersion] = form = uow.DebriefForms.GetVersion(studyId, a.FormVersion);
            foreach (var q in form?.Questions.OfType<JsonObject>() ?? [])
            {
                var key = Json.Str(q["key"]) ?? "";
                var v = a.Answers[key];
                if (v is null)
                    continue;
                if (!stats.TryGetValue(key, out var st))
                {
                    stats[key] = st = new QuestionStats(new JsonObject
                    {
                        ["key"] = q["key"]?.DeepClone(), ["type"] = q["type"]?.DeepClone(), ["prompt"] = q["prompt"]?.DeepClone(),
                        ["answered"] = 0, ["counts"] = new JsonObject(),
                    });
                }
                st.Data["answered"] = (int)st.Data["answered"]! + 1;
                var type = Json.Str(q["type"]);
                if (type == "text")
                {
                    comments.Add(new JsonObject
                    {
                        ["session_id"] = a.SessionId, ["participant_code"] = codesBySession.GetValueOrDefault(a.SessionId, "?"),
                        ["key"] = q["key"]?.DeepClone(), ["text"] = v.DeepClone(),
                    });
                    continue;
                }
                var label = Json.IsBool(v) ? PyText.Str(v).ToLowerInvariant() : PyText.Str(v);
                var counts = st.Data["counts"]!.AsObject();
                counts[label] = ((int?)counts[label] ?? 0) + 1;
                if (type == "scale")
                    st.Values.Add((long)PyText.IntOf(v));
            }
        }
        foreach (var st in stats.Values)
        {
            if (st.Values.Count > 0)
                st.Data["mean"] = Json.Float(PyMath.Round((double)st.Values.Sum() / st.Values.Count, 3));
        }
        return (new JsonArray(stats.Values.Select(st => (JsonNode?)st.Data).ToArray()), comments);
    }

    /// <summary>The report, plus each row's session start for the CSV (Python's str(datetime)).</summary>
    private static (JsonObject Data, List<DateTime> CreatedAt) PilotReportData(IUnitOfWork uow, Principal principal, int studyId, bool includeSynthetic)
    {
        RequireStudyAccess(principal, studyId, Readers);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var codes = Codes(uow, studyId);
        var settings = MeasurementUseCases.SettingsForStudy(uow, studyId);
        var observations = uow.Observations.ForStudy(studyId);
        var obsBySession = observations.GroupBy(o => o.SessionId).ToDictionary(g => g.Key, g => g.ToList());
        var debriefs = new Dictionary<int, DebriefAnswer>();
        foreach (var a in uow.DebriefAnswers.ForStudy(studyId))
            debriefs[a.SessionId] = a;
        var refs = uow.References.ForStudy(studyId).GroupBy(r => r.SessionId).ToDictionary(g => g.Key, g => g.Count());
        var rows = new List<JsonObject>();
        var createdAt = new List<DateTime>();
        var comfortValues = new Dictionary<string, int>(StringComparer.Ordinal);
        var skippedSynthetic = 0;
        var keptSessions = new HashSet<int>();
        foreach (var s in uow.Sessions.ListForStudy(studyId))
        {
            if (s.Synthetic && !includeSynthetic)
            {
                skippedSynthetic++;
                continue;
            }
            var sid = s.Id;
            keptSessions.Add(sid);
            var summary = MeasurementUseCases.Summarize(uow, s);
            var output = Json.Truthy(summary["outcomes"]) ? summary["outcomes"] : null;
            var comfort = Json.Truthy(At(output, "comfort")) ? output!["comfort"] : null;
            var stages = uow.StageResults.ForSession(sid);
            foreach (var st in stages)
            {
                if (st.ComfortValue is { } cv)
                    comfortValues[cv.ToString(CultureInfo.InvariantCulture)] = comfortValues.GetValueOrDefault(cv.ToString(CultureInfo.InvariantCulture)) + 1;
            }
            var obs = obsBySession.GetValueOrDefault(sid) ?? [];
            var d = debriefs.GetValueOrDefault(sid);
            var val = Json.Truthy(summary["validation"]) ? summary["validation"] : null;
            var protocol = Json.Truthy(summary["protocol"]) ? summary["protocol"] : null;
            var conversation = Json.Truthy(At(output, "conversation")) ? output!["conversation"] : null;
            var quality = summary["quality"]!;
            JsonNode? ScreenPart(string key, JsonNode? missing) => s.Screen.TryGetPropertyValue(key, out var v) ? v : missing;
            var debriefAnswers = new JsonObject();
            if (d is not null && !d.Skipped)
                debriefAnswers = Json.CloneObj(d.Answers);
            rows.Add(new JsonObject
            {
                ["session_id"] = sid,
                ["participant_code"] = CodeOf(codes, s.ParticipantId),
                ["created_at"] = Ts(s.CreatedAt),
                ["status"] = s.Status.Value(),
                ["end_reason"] = s.EndReason,
                ["path"] = At(protocol, "path"),
                ["protocol_version"] = At(protocol, "version"),
                ["device_platform"] = s.Device["platform"]?.DeepClone(),
                ["device_model"] = s.Device["model"]?.DeepClone(),
                ["user_agent"] = s.Device["user_agent"]?.DeepClone(),
                ["screen"] = $"{PyText.Str(ScreenPart("w", null))}x{PyText.Str(ScreenPart("h", null))}@{PyText.Str(ScreenPart("dpr", 1))}",
                ["camera"] = $"{PyText.Str(s.Camera["w"])}x{PyText.Str(s.Camera["h"])}",
                ["camera_label"] = s.Camera["label"]?.DeepClone(),
                ["estimator"] = s.GazeModel["model_id"]?.DeepClone(),
                ["synthetic"] = s.Synthetic,
                ["calibration_residual_px"] = At(Json.Truthy(summary["calibration"]) ? summary["calibration"] : null, "residual_px_median"),
                ["validation_passed"] = At(val, "passed"),
                ["validation_correct_ratio"] = At(val, "correct_ratio"),
                ["validation_reasons"] = string.Join(";", Strings(At(val, "reasons"))),
                ["settings_version"] = At(val, "settings_version"),
                ["quality"] = quality["grade"]?.DeepClone(),
                ["quality_reasons"] = string.Join(";", Strings(quality["reasons"])),
                ["stages_completed"] = At(Json.Truthy(At(output, "number_task")) ? output!["number_task"] : null, "stages_completed"),
                ["stage_decisions"] = string.Join(";", stages.Select(st => $"{st.StageIndex}:{st.Decision}")),
                ["comfort_min"] = At(comfort, "min"),
                ["comfort_mean"] = At(comfort, "mean"),
                ["comfort_low_count"] = At(comfort, "low_count"),
                ["pauses"] = At(comfort, "pauses"),
                ["ended_early"] = At(comfort, "ended_early"),
                ["comprehension_share"] = At(Json.Truthy(At(output, "comprehension")) ? output!["comprehension"] : null, "share"),
                ["number_task_share"] = At(Json.Truthy(At(output, "number_task")) ? output!["number_task"] : null, "share"),
                ["debrief"] = d is not null && d.Skipped ? "skipped" : d is not null ? "answered" : "none",
                ["debrief_answers"] = debriefAnswers,
                ["observations"] = obs.Count,
                ["observations_major_or_stop"] = obs.Count(o => o.Severity is "major" or "stop"),
                ["reference_recordings"] = refs.GetValueOrDefault(sid),
                ["conversation_turns"] = At(conversation, "participant_turns"),
                ["conversation_on_topic_share"] = At(conversation, "on_topic_share"),
                ["conversation_distress"] = At(conversation, "distress"),
                ["conversation_end_reason"] = At(conversation, "end_reason"),
            });
            createdAt.Add(s.CreatedAt);
        }
        var keptObs = observations.Where(o => keptSessions.Contains(o.SessionId)).ToList();
        var obsMatrix = new JsonObject();
        foreach (var o in keptObs)
        {
            if (obsMatrix[o.Category] is not JsonObject bySeverity)
                obsMatrix[o.Category] = bySeverity = new JsonObject();
            bySeverity[o.Severity] = ((int?)bySeverity[o.Severity] ?? 0) + 1;
        }
        var codeBySession = new Dictionary<int, string>();
        foreach (var r in rows)
            codeBySession[(int)r["session_id"]!] = (string)r["participant_code"]!;
        var (debriefStats, comments) = DebriefStats(uow, studyId, debriefs.Where(p => keptSessions.Contains(p.Key)).Select(p => p.Value), codeBySession);
        var validated = rows.Where(r => r["validation_passed"] is not null).ToList();
        var byDevice = new Dictionary<string, (JsonNode Device, int[] Counts)>();
        foreach (var r in rows)
        {
            JsonNode dev = Json.Truthy(r["device_platform"]) ? r["device_platform"]!.DeepClone() : "unknown";
            var key = DictKey(dev);
            if (!byDevice.TryGetValue(key, out var entry))
                byDevice[key] = entry = (dev, new int[4]);
            entry.Counts[0]++;
            if (r["validation_passed"] is not null)
            {
                entry.Counts[1]++;
                entry.Counts[2] += Json.Truthy(r["validation_passed"]) ? 1 : 0;
            }
            entry.Counts[3] += Json.Str(r["quality"]) == "ok" ? 1 : 0;
        }
        var qualityCounts = new JsonObject();
        foreach (var g in new[] { "ok", "review", "exclude" })
            qualityCounts[g] = rows.Count(r => Json.Str(r["quality"]) == g);
        var comfortSorted = new JsonObject();
        foreach (var (k, v) in comfortValues.OrderBy(p => p.Key, StringComparer.Ordinal))
            comfortSorted[k] = v;
        var data = new JsonObject
        {
            ["study_id"] = studyId,
            ["settings"] = new JsonObject { ["version"] = settings.Version, ["values"] = PilotRules.SettingsValues(settings) },
            ["sessions"] = rows.Count,
            ["participants"] = rows.Select(r => (string)r["participant_code"]!).Distinct(StringComparer.Ordinal).Count(),
            ["skipped_synthetic"] = skippedSynthetic,
            ["includes_synthetic"] = includeSynthetic,
            ["validation"] = new JsonObject { ["validated"] = validated.Count, ["passed"] = validated.Count(r => Json.Truthy(r["validation_passed"])) },
            ["quality"] = qualityCounts,
            ["ended_early"] = rows.Count(r => Json.Truthy(r["ended_early"])),
            ["comfort_stage_values"] = comfortSorted,
            ["by_device"] = new JsonArray(byDevice.Values.OrderByDescending(e => e.Counts[0]).Select(e => (JsonNode?)new JsonObject
            {
                ["device_platform"] = e.Device.DeepClone(), ["sessions"] = e.Counts[0], ["validated"] = e.Counts[1],
                ["validation_passed"] = e.Counts[2], ["quality_ok"] = e.Counts[3],
            }).ToArray()),
            ["debrief"] = new JsonObject
            {
                ["answered"] = rows.Count(r => Json.Str(r["debrief"]) == "answered"),
                ["skipped"] = rows.Count(r => Json.Str(r["debrief"]) == "skipped"),
                ["questions"] = debriefStats,
                ["comments"] = comments,
            },
            ["observations"] = new JsonObject
            {
                ["total"] = keptObs.Count,
                ["by_category"] = obsMatrix,
                ["items"] = new JsonArray(keptObs.Select(o =>
                {
                    var item = ObsView(o);
                    item["participant_code"] = codeBySession.GetValueOrDefault(o.SessionId, "?");
                    return (JsonNode?)item;
                }).ToArray()),
            },
            ["rows"] = new JsonArray(rows.Select(r => (JsonNode?)r).ToArray()),
            ["note"] = "Pilot summary for the research team. Numbers from synthetic estimators are left out unless included on purpose.",
        };
        return (data, createdAt);
    }

    /// <summary>The texts of a JSON list (<c>";".join(...)</c> on lists of strings).</summary>
    private static IEnumerable<string> Strings(JsonNode? list) =>
        list is JsonArray a ? a.Select(x => Json.Str(x) ?? throw new InvalidOperationException("sequence item: expected str instance")) : [];

    public static JsonObject PilotReport(IUnitOfWork uow, Principal principal, int studyId, bool includeSynthetic)
    {
        var (data, _) = PilotReportData(uow, principal, studyId, includeSynthetic);
        ResearchUseCases.LogAccess(uow, principal, studyId, "pilot_report", new JsonObject { ["sessions"] = data["sessions"]!.DeepClone(), ["includes_synthetic"] = includeSynthetic });
        uow.Commit();
        return data;
    }

    /// <summary>One csv cell as Python writes it: None is empty, dicts and lists are json.dumps, the
    /// rest str().</summary>
    private static string Cell(JsonNode? v) => v switch
    {
        null => "",
        JsonObject or JsonArray => PyText.JsonDumps(v),
        _ => PyText.Str(v),
    };

    /// <summary>The session rows as CSV (UTF-8 with a BOM), one <c>debrief_&lt;key&gt;</c> column per answer key.</summary>
    public static ExportFile ExportPilotCsv(IUnitOfWork uow, Principal principal, int studyId, bool includeSynthetic)
    {
        var (data, createdAt) = PilotReportData(uow, principal, studyId, includeSynthetic);
        var rows = data["rows"]!.AsArray().Select(r => r!.AsObject()).ToList();
        var keys = rows.SelectMany(r => r["debrief_answers"]!.AsObject().Select(p => p.Key)).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToList();
        var baseCols = (rows.Count > 0 ? rows[0].Select(p => p.Key) : ["session_id"]).Where(k => k != "debrief_answers").ToList();
        var sb = new StringBuilder();
        PyText.CsvRow(sb, [.. baseCols, .. keys.Select(k => $"debrief_{k}")]);
        for (var i = 0; i < rows.Count; i++)
        {
            var r = rows[i];
            var answers = r["debrief_answers"]!.AsObject();
            var cells = baseCols.Select(c => c == "created_at" ? JsonFormat.Timestamp(createdAt[i]).Replace('T', ' ') : Cell(r[c]));
            PyText.CsvRow(sb, [.. cells, .. keys.Select(k => answers.TryGetPropertyValue(k, out var v) ? (v is null ? "" : PyText.Str(v)) : "")]);
        }
        ResearchUseCases.LogAccess(uow, principal, studyId, "export_pilot_csv", new JsonObject { ["sessions"] = data["sessions"]!.DeepClone(), ["includes_synthetic"] = includeSynthetic });
        uow.Commit();
        return new ExportFile($"pilot_sessions_study{studyId}.csv", PyText.Utf8Sig(sb.ToString()), "text/csv; charset=utf-8");
    }
}
