using System.Text.Json.Nodes;
using EyeTracking.Domain;
using static EyeTracking.Application.Authz;

namespace EyeTracking.Application;

/// <summary>Settings fields a researcher may change; null means "not sent" (left as it is).</summary>
public sealed record SettingsChanges(
    double? ValidationMinCorrect = null,
    double? ValidationMaxUncertain = null,
    double? MinRegionToErrorRatio = null,
    double? GazeConfThreshold = null,
    int? CalibrationPoints = null,
    bool? AllowContinueWithoutValidation = null,
    double? QualityMaxUncertainShare = null,
    double? QualityMaxMissingShare = null);

/// <summary>Use cases for build step 2 (measurement_use_cases.py). Sessions belong to a
/// participant; staff read them coded by study. Summaries are free-form JSON because later
/// steps add to them.</summary>
public static class MeasurementUseCases
{
    public const int MaxBatch = 500;

    private static JsonNode? Ts(DateTime? t) => t is null ? null : JsonFormat.Timestamp(t.Value);

    private static JsonNode? F(double? v) => v is null ? null : Json.Float(v.Value);

    /// <summary>Python's <c>text[:n]</c> (code points, not UTF-16 units).</summary>
    private static string Head(string text, int n)
    {
        var runes = text.EnumerateRunes().Take(n).ToList();
        return string.Concat(runes.Select(r => r.ToString()));
    }

    // ---------- settings ----------

    public static MeasurementSettings SettingsForStudy(IUnitOfWork uow, int studyId) =>
        uow.MeasurementSettings.Get(studyId) ?? new MeasurementSettings { StudyId = studyId };

    public static MeasurementSettings MySettings(IUnitOfWork uow, Principal principal) =>
        SettingsForStudy(uow, RequireParticipant(principal).StudyId);

    public static MeasurementSettings GetStudySettings(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId);
        return SettingsForStudy(uow, studyId);
    }

    /// <summary>Thresholds are versioned: every real change gets a new version with who and why.
    /// New validations record the version they were judged with. Nothing already recorded is
    /// re-judged silently; the threshold review shows what a change would do before it is saved.</summary>
    public static MeasurementSettings UpdateStudySettings(IUnitOfWork uow, Principal principal, int studyId, string? rationale, SettingsChanges changes)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var s = SettingsForStudy(uow, studyId);
        var before = PilotRules.SettingsValues(s);
        var previous = s.Copy();
        if (changes.ValidationMinCorrect is { } validationMinCorrect) s.ValidationMinCorrect = validationMinCorrect;
        if (changes.ValidationMaxUncertain is { } validationMaxUncertain) s.ValidationMaxUncertain = validationMaxUncertain;
        if (changes.MinRegionToErrorRatio is { } minRegionToErrorRatio) s.MinRegionToErrorRatio = minRegionToErrorRatio;
        if (changes.GazeConfThreshold is { } gazeConfThreshold) s.GazeConfThreshold = gazeConfThreshold;
        if (changes.CalibrationPoints is { } calibrationPoints) s.CalibrationPoints = calibrationPoints;
        if (changes.AllowContinueWithoutValidation is { } allowContinue) s.AllowContinueWithoutValidation = allowContinue;
        if (changes.QualityMaxUncertainShare is { } qualityMaxUncertainShare) s.QualityMaxUncertainShare = qualityMaxUncertainShare;
        if (changes.QualityMaxMissingShare is { } qualityMaxMissingShare) s.QualityMaxMissingShare = qualityMaxMissingShare;
        try
        {
            s.Validate();
        }
        catch (Invalid)
        {
            s.CopyValuesFrom(previous);
            throw;
        }
        if (s.SameValues(previous))
            return s;
        var after = PilotRules.SettingsValues(s);
        var note = (rationale ?? "").Trim();
        if (note.EnumerateRunes().Count() > PilotRules.MaxRationaleChars)
            throw new Invalid($"rationale is limited to {PilotRules.MaxRationaleChars} characters");
        if (uow.SettingsVersions.ListForStudy(studyId).Count == 0)
        {
            uow.SettingsVersions.Add(new SettingsVersion
            {
                StudyId = studyId, Version = s.Version == 0 ? 1 : s.Version, Values = before,
                Rationale = "Values in use before the first recorded change", ChangedBy = null,
            });
        }
        s.Version = (s.Version == 0 ? 1 : s.Version) + 1;
        s = uow.MeasurementSettings.Save(s);
        uow.SettingsVersions.Add(new SettingsVersion { StudyId = studyId, Version = s.Version, Values = after, Rationale = note, ChangedBy = principal.UserId });
        uow.Commit();
        return s;
    }

    public static JsonArray SettingsHistory(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId);
        var rows = uow.SettingsVersions.ListForStudy(studyId);
        if (rows.Count == 0)
        {
            var s = SettingsForStudy(uow, studyId);
            return
            [
                new JsonObject
                {
                    ["version"] = s.Version,
                    ["values"] = PilotRules.SettingsValues(s),
                    ["rationale"] = s.Id == 0 ? "Defaults; no change recorded yet" : "Saved before the settings history existed",
                    ["changed_by"] = null,
                    ["created_at"] = null,
                },
            ];
        }
        return new JsonArray(Enumerable.Reverse(rows).Select(r => (JsonNode?)new JsonObject
        {
            ["version"] = r.Version,
            ["values"] = Json.CloneObj(r.Values),
            ["rationale"] = r.Rationale,
            ["changed_by"] = r.ChangedBy,
            ["created_at"] = Ts(r.CreatedAt),
        }).ToArray());
    }

    // ---------- sessions (participant side) ----------

    public static Session CreateSession(
        IUnitOfWork uow, Principal principal, JsonObject device, JsonObject screen, JsonObject camera, JsonObject gazeModel, int? assignmentId = null)
    {
        var p = RequireParticipant(principal);
        var readiness = ReadinessRules.Compute(
            uow.Sheets.Current(p.StudyId),
            uow.Consents.Latest(p.Id),
            uow.Demographics.CurrentForm(p.StudyId),
            uow.Demographics.Answers(p.Id));
        if (!readiness.Ready)
            throw new Forbidden("participant is not ready for a session: " + string.Join(", ", readiness.Reasons));
        if (!Json.Truthy(screen["w"]) || !Json.Truthy(screen["h"]))
            throw new Invalid("screen.w and screen.h are required");
        var synthetic = !gazeModel.TryGetPropertyValue("synthetic", out var flag) || Json.Truthy(flag);
        var s = new Session
        {
            ParticipantId = p.Id,
            StudyId = p.StudyId,
            Device = device,
            Screen = screen,
            Camera = camera,
            GazeModel = gazeModel,
            Synthetic = synthetic,
            Notes = synthetic ? ["synthetic_estimator"] : [],
        };
        if (assignmentId is not null)
            PracticeUseCases.BindAssignment(uow, principal, s, assignmentId.Value);
        s = uow.Sessions.Add(s);
        uow.Commit();
        return s;
    }

    private static Session OwnSession(IUnitOfWork uow, Principal principal, int sessionId)
    {
        var p = RequireParticipant(principal);
        var s = uow.Sessions.Get(sessionId);
        if (s is null || s.ParticipantId != p.Id)
            throw new NotFound("session not found");
        return s;
    }

    public static Session CameraCheck(
        IUnitOfWork uow, Principal principal, int sessionId, bool faceDetected, double faceConf, bool lightingOk, int frameW, int frameH, string? cameraLabel = null)
    {
        var s = OwnSession(uow, principal, sessionId);
        s.EnsureOpen();
        var settings = SettingsForStudy(uow, s.StudyId);
        var ok = faceDetected && faceConf >= settings.GazeConfThreshold && lightingOk;
        if (ok && s.Status == SessionStatus.Created)
            s.Status = SessionStatus.CameraOk;
        if (!ok)
            s.Notes = [.. s.Notes, "camera_check_failed"];
        var check = new JsonObject
        {
            ["face_detected"] = faceDetected, ["face_conf"] = Json.Float(faceConf), ["lighting_ok"] = lightingOk,
            ["frame_w"] = frameW, ["frame_h"] = frameH, ["ok"] = ok,
        };
        var label = Head((cameraLabel ?? "").Trim(), 200);
        if (label.Length > 0)
        {
            // The participant may pick another camera before checking it: the
            // session keeps the camera that was actually checked.
            check["camera_label"] = label;
            if (label != Json.Str(s.Camera["label"]))
            {
                if (s.CalibrationValid)
                {
                    s.CalibrationValid = false;
                    s.Notes = [.. s.Notes, "calibration_invalidated:camera_changed"];
                }
                var camera = Json.CloneObj(s.Camera);
                camera["label"] = label;
                if (frameW > 0 && frameH > 0)
                {
                    camera["w"] = frameW;
                    camera["h"] = frameH;
                }
                s.Camera = camera;
            }
        }
        uow.Events.Add(new SessionEvent { SessionId = s.Id, TMs = 0, Type = "note", Payload = new JsonObject { ["camera_check"] = check } });
        uow.Commit();
        return s;
    }

    public static Calibration SubmitCalibration(IUnitOfWork uow, Principal principal, int sessionId, IReadOnlyList<CalibrationTarget> targets)
    {
        var s = OwnSession(uow, principal, sessionId);
        s.EnsureOpen();
        if (s.Status == SessionStatus.Created)
            throw new Conflict("complete the camera check before calibrating");
        var settings = SettingsForStudy(uow, s.StudyId);
        var c = MeasurementRules.FitCalibration(targets, settings.GazeConfThreshold);
        c.SessionId = s.Id;
        c = uow.Calibrations.Add(c);
        s.CalibrationValid = true;
        if (s.Status is SessionStatus.CameraOk or SessionStatus.Calibrated or SessionStatus.Validated)
            s.Status = SessionStatus.Calibrated;
        uow.Commit();
        return c;
    }

    public static Validation SubmitValidation(IUnitOfWork uow, Principal principal, int sessionId, JsonObject layout, IReadOnlyList<ValidationTarget> targets)
    {
        var s = OwnSession(uow, principal, sessionId);
        s.EnsureOpen();
        var cal = uow.Calibrations.Latest(s.Id);
        if (cal is null || !s.CalibrationValid)
            throw new Conflict("a valid calibration is required before validation");
        var settings = SettingsForStudy(uow, s.StudyId);
        var v = MeasurementRules.EvaluateValidation(cal, layout, targets, settings);
        v.SessionId = s.Id;
        v.CalibrationId = cal.Id;
        v = uow.Validations.Add(v);
        if (s.Status is SessionStatus.Calibrated or SessionStatus.Validated)
            s.Status = SessionStatus.Validated;
        uow.Commit();
        return v;
    }

    public static StimulusLayout SetLayout(IUnitOfWork uow, Principal principal, int sessionId, string segment, JsonObject layout, int? stageIndex = null)
    {
        var s = OwnSession(uow, principal, sessionId);
        s.EnsureOpen();
        if (!MeasurementRules.Segments.Contains(segment))
            throw new Invalid($"segment must be one of {MeasurementRules.TupleText(MeasurementRules.Segments)}");
        MeasurementRules.ValidateLayout(layout);
        var l = uow.Layouts.Add(new StimulusLayout { SessionId = s.Id, Segment = segment, Layout = layout, StageIndex = stageIndex });
        uow.Commit();
        return l;
    }

    public static (int Stored, int Invalid) AddSamples(IUnitOfWork uow, Principal principal, int sessionId, IReadOnlyList<RawSample> raws)
    {
        var s = OwnSession(uow, principal, sessionId);
        s.EnsureOpen();
        if (raws.Count > MaxBatch)
            throw new Invalid($"at most {MaxBatch} samples per batch");
        if (s.Status != SessionStatus.Running)
            throw new Conflict($"session is not running (status: {s.Status.Value()})");
        if (!s.CalibrationValid)
            throw new Conflict("calibration is no longer valid; calibrate again before recording");
        var cal = uow.Calibrations.Latest(s.Id);
        var layout = uow.Layouts.Latest(s.Id);
        if (cal is null || layout is null)
            throw new Conflict("calibration and a stimulus layout are required before recording");
        var settings = SettingsForStudy(uow, s.StudyId);
        var rows = new List<GazeSample>();
        var invalid = 0;
        foreach (var raw in raws)
        {
            var (point, conf, region) = MeasurementRules.ClassifyRaw(cal.Params, raw, layout.Layout, settings.GazeConfThreshold);
            var valid = region != "uncertain";
            invalid += valid ? 0 : 1;
            rows.Add(new GazeSample
            {
                SessionId = s.Id, TMs = raw.TMs, X = point?.X, Y = point?.Y, Conf = conf, Valid = valid,
                Region = region, Segment = layout.Segment, LayoutId = layout.Id,
            });
        }
        var stored = uow.Samples.AddMany(rows);
        uow.Commit();
        return (stored, invalid);
    }

    public static Session AddEvent(IUnitOfWork uow, IClock clock, Principal principal, int sessionId, int tMs, string type, JsonObject? payload)
    {
        var s = OwnSession(uow, principal, sessionId);
        s.EnsureOpen();
        payload = payload is { Count: > 0 } ? payload : [];
        if (!MeasurementRules.EventTypes.Contains(type))
            throw new Invalid($"event type must be one of {MeasurementRules.TupleText(MeasurementRules.EventTypes)}");
        var settings = SettingsForStudy(uow, s.StudyId);
        if (type == "segment_start")
        {
            var layout = uow.Layouts.Latest(s.Id) ?? throw new Conflict("set a stimulus layout before starting a segment");
            if (s.Status is SessionStatus.Created or SessionStatus.CameraOk || !s.CalibrationValid)
                throw new Conflict("calibrate before starting a segment");
            var v = uow.Validations.Latest(s.Id);
            if ((v is null || !v.Passed) && !settings.AllowContinueWithoutValidation)
                throw new Conflict("validation must pass before a segment can start");
            if (!payload.ContainsKey("segment"))
                payload["segment"] = layout.Segment;
            s.Status = SessionStatus.Running;
        }
        else if (type == "pause")
        {
            if (s.Status != SessionStatus.Running)
                throw new Conflict("only a running session can be paused");
            s.Status = SessionStatus.Paused;
        }
        else if (type == "resume")
        {
            if (s.Status != SessionStatus.Paused)
                throw new Conflict("only a paused session can be resumed");
            s.Status = SessionStatus.Running;
        }
        else if (MeasurementRules.InvalidatingEvents.Contains(type))
        {
            s.CalibrationValid = false;
            s.Notes = [.. s.Notes, $"calibration_invalidated:{type}"];
        }
        else if (type == "end")
        {
            var reason = Json.Str(payload["reason"]);
            if (reason is not ("completed" or "ended_early"))
                throw new Invalid("end.payload.reason must be completed or ended_early");
            s.Status = SessionStatus.Ended;
            s.EndedAt = clock.Now();
            s.EndReason = reason;
            PracticeUseCases.OnSessionEnd(uow, s);
            LiveUseCases.CloseOnSessionEnd(uow, clock, s);
        }
        else if (type == "comfort_answer")
        {
            PracticeUseCases.ValidateComfortPayload(uow, s, payload);
        }
        uow.Events.Add(new SessionEvent { SessionId = s.Id, TMs = tMs, Type = type, Payload = payload });
        uow.Commit();
        return s;
    }

    // ---------- summaries ----------

    public static JsonObject Summarize(IUnitOfWork uow, Session s)
    {
        var sid = s.Id;
        var cal = uow.Calibrations.Latest(sid);
        var val = uow.Validations.Latest(sid);
        var notes = s.Notes.ToList();
        if (val is not null && cal is not null && val.CalibrationId != cal.Id)
        {
            notes.Add("validation_predates_latest_calibration");
            val = null;
        }
        var samples = uow.Samples.ForSession(sid);
        var events = uow.Events.ForSession(sid);
        int? lastT = samples.Count == 0 ? null : samples.Max(x => x.TMs);
        var segments = MeasurementRules.SegmentsFromEvents(events, lastT);
        var cov = MeasurementRules.Coverage(samples, segments);
        var shares = MeasurementRules.RegionShares(cov);
        var summary = new JsonObject
        {
            ["id"] = s.Id,
            ["status"] = s.Status.Value(),
            ["created_at"] = Ts(s.CreatedAt),
            ["ended_at"] = Ts(s.EndedAt),
            ["end_reason"] = s.EndReason,
            ["synthetic"] = s.Synthetic,
            ["calibration_valid"] = s.CalibrationValid,
            ["calibration"] = cal is null ? null : new JsonObject
            {
                ["residual_px_median"] = Json.Float(cal.ResidualPxMedian),
                ["residual_px_p90"] = Json.Float(cal.ResidualPxP90),
                ["points"] = cal.Points,
            },
            ["validation"] = val is null ? null : new JsonObject
            {
                ["passed"] = val.Passed,
                ["correct_ratio"] = Json.Float(val.CorrectRatio),
                ["uncertain_ratio"] = Json.Float(val.UncertainRatio),
                ["size_ratio"] = Json.Float(val.SizeRatio),
                ["reasons"] = Json.Array(val.Reasons),
                ["settings_version"] = val.SettingsVersion,
            },
            ["coverage"] = new JsonObject
            {
                ["total_ms"] = cov.TotalMs,
                ["classifiable_ms"] = cov.ClassifiableMs,
                ["uncertain_ms"] = cov.UncertainMs,
                ["missing_ms"] = cov.MissingMs,
            },
            ["region_shares"] = MeasurementRules.SharesJson(shares),
            ["face_region_attention"] = MeasurementRules.FaceRegionAttention(shares),
            ["eye_region_attention"] = MeasurementRules.EyeRegionAttention(s, val, shares),
            ["segments"] = new JsonArray(segments.Select(g => (JsonNode?)g.ToJson()).ToArray()),
            ["events_count"] = events.Count,
            ["notes"] = Json.Array(notes),
        };
        var output = PracticeUseCases.PracticeSummary(uow, s, summary);
        var settings = SettingsForStudy(uow, s.StudyId);
        output["quality"] = ResearchRules.GradeQuality(output, settings.QualityMaxUncertainShare, settings.QualityMaxMissingShare).AsDict();
        return output;
    }

    public static JsonObject MySession(IUnitOfWork uow, Principal principal, int sessionId) =>
        Summarize(uow, OwnSession(uow, principal, sessionId));

    public static JsonArray MySessions(IUnitOfWork uow, Principal principal)
    {
        var p = RequireParticipant(principal);
        return new JsonArray(uow.Sessions.ListForParticipant(p.Id).Select(s => (JsonNode?)Summarize(uow, s)).ToArray());
    }

    private static Session StudySession(IUnitOfWork uow, Principal principal, int studyId, int sessionId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        var s = uow.Sessions.Get(sessionId);
        if (s is null || s.StudyId != studyId)
            throw new NotFound("session not found");
        return s;
    }

    private static string ParticipantCode(IUnitOfWork uow, int studyId, int participantId) =>
        uow.Participants.ListForStudy(studyId).FirstOrDefault(x => x.Id == participantId)?.Code ?? "?";

    public static JsonArray ListStudySessions(IUnitOfWork uow, Principal principal, int studyId)
    {
        RequireStudyAccess(principal, studyId, StudyRole.Researcher, StudyRole.Analyst);
        if (uow.Studies.Get(studyId) is null)
            throw new NotFound("study not found");
        var output = new JsonArray();
        foreach (var s in uow.Sessions.ListForStudy(studyId))
        {
            var summary = Summarize(uow, s);
            var protocol = summary["protocol"];
            output.Add(new JsonObject
            {
                ["id"] = s.Id,
                ["participant_code"] = ParticipantCode(uow, studyId, s.ParticipantId),
                ["status"] = summary["status"]?.DeepClone(),
                ["created_at"] = Ts(s.CreatedAt),
                ["ended_at"] = Ts(s.EndedAt),
                ["synthetic"] = s.Synthetic,
                ["device_platform"] = s.Device["platform"]?.DeepClone(),
                ["calibration_residual_px"] = Json.Truthy(summary["calibration"]) ? summary["calibration"]!["residual_px_median"]?.DeepClone() : null,
                ["validation_passed"] = Json.Truthy(summary["validation"]) ? summary["validation"]!["passed"]?.DeepClone() : null,
                ["coverage"] = summary["coverage"]?.DeepClone(),
                ["eye_region_attention"] = summary["eye_region_attention"]?.DeepClone(),
                ["quality"] = summary["quality"]?.DeepClone(),
                ["protocol"] = Json.Truthy(protocol)
                    ? new JsonObject
                    {
                        ["id"] = protocol!["id"]?.DeepClone(),
                        ["name"] = protocol["name"]?.DeepClone(),
                        ["version"] = protocol["version"]?.DeepClone(),
                        ["path"] = protocol["path"]?.DeepClone(),
                    }
                    : protocol?.DeepClone(),
            });
        }
        return output;
    }

    public static JsonObject GetStudySession(IUnitOfWork uow, Principal principal, int studyId, int sessionId)
    {
        var s = StudySession(uow, principal, studyId, sessionId);
        var summary = Summarize(uow, s);
        var val = uow.Validations.Latest(s.Id);
        summary["participant_code"] = ParticipantCode(uow, studyId, s.ParticipantId);
        summary["device"] = Json.CloneObj(s.Device);
        summary["screen"] = Json.CloneObj(s.Screen);
        summary["camera"] = Json.CloneObj(s.Camera);
        summary["gaze_model"] = Json.CloneObj(s.GazeModel);
        summary["validation_targets"] = val is null ? new JsonArray() : Json.CloneArr(val.Targets);
        summary["events"] = new JsonArray(uow.Events.ForSession(s.Id)
            .Select(e => (JsonNode?)new JsonObject { ["t_ms"] = e.TMs, ["type"] = e.Type, ["payload"] = Json.CloneObj(e.Payload) })
            .ToArray());
        foreach (var (key, value) in PracticeUseCases.PracticeDetail(uow, s))
            summary[key] = value?.DeepClone();
        return summary;
    }

    public static (int Total, JsonArray Items) StudySessionSamples(IUnitOfWork uow, Principal principal, int studyId, int sessionId, int offset, int limit)
    {
        var s = StudySession(uow, principal, studyId, sessionId);
        if (!(1 <= limit && limit <= 5000) || offset < 0)
            throw new Invalid("limit must be 1..5000 and offset >= 0");
        var (total, items) = uow.Samples.Page(s.Id, offset, limit);
        return (total, new JsonArray(items.Select(x => (JsonNode?)new JsonObject
        {
            ["t_ms"] = x.TMs, ["x"] = F(x.X), ["y"] = F(x.Y), ["conf"] = Json.Float(x.Conf),
            ["valid"] = x.Valid, ["region"] = x.Region, ["segment"] = x.Segment,
        }).ToArray()));
    }
}
