"""Use cases for build step 6, the supervised pilot (design p. 6).

Supervisors (researchers) observe sessions live and write observations; participants may answer a
short versioned debrief after a session; researchers review what candidate thresholds would change
before saving a new settings version; one comparison day with a research eye tracker is supported by
importing its export per session. Every read of study data here is an explicit, logged research
access, and only study members reach it.
"""
from __future__ import annotations

import copy
import csv
import io
import json
from datetime import timedelta

from eyetracking.domain.errors import Conflict, Invalid, NotFound
from eyetracking.domain.measurement import CLASSIFIABLE, MeasurementSettings, Session, SessionStatus, segments_from_events
from eyetracking.domain.models import StudyRole
from eyetracking.domain.pilot import (
    DEFAULT_DEBRIEF_QUESTIONS,
    SETTINGS_FIELDS,
    DebriefAnswer,
    DebriefForm,
    Observation,
    ReferenceRecording,
    compare_with_reference,
    distribution,
    estimate_offset,
    parse_reference_csv,
    revalidate,
    settings_values,
    validate_debrief_answers,
    validate_debrief_questions,
)
from eyetracking.domain.research import grade_quality

from .authz import Principal, require_participant, require_study_access
from .measurement_use_cases import settings_for_study, summarize
from .live_use_cases import monitor_block
from .ports import Clock, PilotUnitOfWork
from .research_use_cases import log_access

READERS = (StudyRole.researcher, StudyRole.analyst)
LIVE_WINDOW_MS = 10_000
ACTIVE_HOURS = 12


def _session_in_study(uow: PilotUnitOfWork, principal: Principal, study_id: int, session_id: int, *roles: StudyRole) -> Session:
    require_study_access(principal, study_id, *roles)
    s = uow.sessions.get(session_id)
    if s is None or s.study_id != study_id:
        raise NotFound("session not found")
    return s


def _codes(uow: PilotUnitOfWork, study_id: int) -> dict[int, str]:
    return {p.id: p.code for p in uow.participants.list_for_study(study_id)}


# ---------- supervisor observations ----------


def _obs_view(o: Observation) -> dict:
    return {"id": o.id, "session_id": o.session_id, "author_id": o.author_id, "category": o.category, "severity": o.severity, "text": o.text, "t_ms": o.t_ms, "created_at": o.created_at}


def add_observation(uow: PilotUnitOfWork, principal: Principal, study_id: int, session_id: int, category: str, severity: str, text: str, t_ms: int | None) -> dict:
    s = _session_in_study(uow, principal, study_id, session_id, StudyRole.researcher)
    o = Observation(study_id=study_id, session_id=s.id or 0, author_id=principal.user_id, category=category, severity=severity, text=text, t_ms=t_ms)
    o.validate()
    o = uow.observations.add(o)
    uow.commit()
    return _obs_view(o)


def list_observations(uow: PilotUnitOfWork, principal: Principal, study_id: int, session_id: int) -> list[dict]:
    s = _session_in_study(uow, principal, study_id, session_id, *READERS)
    return [_obs_view(o) for o in uow.observations.for_session(s.id or 0)]


# ---------- debrief ----------


def _current_form(uow: PilotUnitOfWork, study_id: int) -> DebriefForm:
    return uow.debrief_forms.current(study_id) or DebriefForm(study_id=study_id, version=0, questions=copy.deepcopy(DEFAULT_DEBRIEF_QUESTIONS), enabled=False)


def _form_view(f: DebriefForm) -> dict:
    return {"version": f.version, "enabled": f.enabled, "questions": f.questions, "saved": f.id is not None}


def get_debrief_form(uow: PilotUnitOfWork, principal: Principal, study_id: int) -> dict:
    require_study_access(principal, study_id, *READERS)
    return _form_view(_current_form(uow, study_id))


def put_debrief_form(uow: PilotUnitOfWork, principal: Principal, study_id: int, questions: list[dict] | None, enabled: bool | None) -> dict:
    """Questions are versioned; answers keep the version they were given for. `enabled` is a switch."""
    require_study_access(principal, study_id, StudyRole.researcher)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    cur = uow.debrief_forms.current(study_id)
    clean = validate_debrief_questions(questions) if questions is not None else None
    if cur is None or (clean is not None and clean != cur.questions):
        base = cur.questions if cur is not None else copy.deepcopy(DEFAULT_DEBRIEF_QUESTIONS)
        form = DebriefForm(
            study_id=study_id,
            version=(cur.version if cur else 0) + 1,
            questions=clean if clean is not None else base,
            enabled=bool(enabled) if enabled is not None else (cur.enabled if cur else False),
        )
        form = uow.debrief_forms.add(form)
    else:
        form = cur
        if enabled is not None:
            form.enabled = bool(enabled)
    uow.commit()
    return _form_view(form)


def _own_session(uow: PilotUnitOfWork, principal: Principal, session_id: int) -> Session:
    p = require_participant(principal)
    s = uow.sessions.get(session_id)
    if s is None or s.participant_id != p.id:
        raise NotFound("session not found")
    return s


def _answer_view(a: DebriefAnswer | None) -> dict | None:
    if a is None:
        return None
    return {"form_version": a.form_version, "answers": a.answers, "skipped": a.skipped, "created_at": a.created_at}


def my_debrief(uow: PilotUnitOfWork, principal: Principal, session_id: int) -> dict:
    s = _own_session(uow, principal, session_id)
    form = _current_form(uow, s.study_id)
    answer = uow.debrief_answers.for_session(s.id or 0)
    return {
        "enabled": bool(form.enabled and form.id is not None),
        "session_ended": s.status is SessionStatus.ended,
        "form": _form_view(form) if form.enabled and form.id is not None else None,
        "answer": _answer_view(answer),
    }


def submit_debrief(uow: PilotUnitOfWork, principal: Principal, session_id: int, form_version: int, answers: dict | None, skipped: bool) -> dict:
    s = _own_session(uow, principal, session_id)
    if s.status is not SessionStatus.ended:
        raise Conflict("the questions open when the session has ended")
    form = uow.debrief_forms.current(s.study_id)
    if form is None or not form.enabled:
        raise Conflict("this study does not ask questions after a session")
    if form_version != form.version:
        raise Conflict("the questions have changed; please reload them")
    if uow.debrief_answers.for_session(s.id or 0) is not None:
        raise Conflict("this session's questions are already answered")
    clean = {} if skipped else validate_debrief_answers(form.questions, answers or {})
    a = uow.debrief_answers.add(DebriefAnswer(study_id=s.study_id, session_id=s.id or 0, participant_id=s.participant_id, form_version=form.version, answers=clean, skipped=bool(skipped)))
    uow.commit()
    return _answer_view(a) or {}


# ---------- live monitor ----------


def active_sessions(uow: PilotUnitOfWork, clock: Clock, principal: Principal, study_id: int) -> list[dict]:
    require_study_access(principal, study_id, StudyRole.researcher)
    since = clock.now() - timedelta(hours=ACTIVE_HOURS)
    codes = _codes(uow, study_id)
    out = []
    for s in uow.sessions.list_for_study(study_id):
        if s.status is SessionStatus.ended or s.created_at < since:
            continue
        events = uow.events.for_session(s.id or 0)
        last = max(events, key=lambda e: (e.t_ms, e.id or 0)) if events else None
        out.append({
            "session_id": s.id,
            "participant_code": codes.get(s.participant_id, "?"),
            "status": s.status.value,
            "created_at": s.created_at,
            "device_platform": (s.device or {}).get("platform"),
            "protocol_id": s.protocol_id,
            "last_event": {"type": last.type, "t_ms": last.t_ms, "created_at": last.created_at} if last else None,
        })
    return sorted(out, key=lambda r: r["created_at"], reverse=True)


def live_status(uow: PilotUnitOfWork, clock: Clock, principal: Principal, study_id: int, session_id: int, first: bool) -> dict:
    """What a supervisor sitting next to the participant needs, polled every few seconds.

    The access is logged once per monitoring start (`first=true`), not on every poll.
    """
    s = _session_in_study(uow, principal, study_id, session_id, StudyRole.researcher)
    sid = s.id or 0
    samples = uow.samples.for_session(sid)
    events = uow.events.for_session(sid)
    last_t = max((x.t_ms for x in samples), default=None)
    counts = {r: 0 for r in (*CLASSIFIABLE, "uncertain")}
    recent_n = 0
    if last_t is not None:
        for x in samples:
            if x.t_ms >= last_t - LIVE_WINDOW_MS:
                recent_n += 1
                counts[x.region if x.region in counts else "uncertain"] += 1
    segs = segments_from_events(events, None)
    current = next((g["label"] for g in reversed(segs) if g["ended_ms"] is None), None)
    pause_state = [e.type for e in sorted(events, key=lambda e: (e.t_ms, e.id or 0)) if e.type in ("pause", "resume")]
    stages = uow.stage_results.for_session(sid)
    last_stage = stages[-1] if stages else None
    layout = uow.layouts.latest(sid)
    val = uow.validations.latest(sid)
    last_event_at = max((e.created_at for e in events), default=None)
    now = clock.now()
    result = {
        "session_id": sid,
        "participant_code": _codes(uow, study_id).get(s.participant_id, "?"),
        "status": s.status.value,
        "synthetic": s.synthetic,
        "estimator": (s.gaze_model or {}).get("model_id"),
        "calibration_valid": s.calibration_valid,
        "validation": {"passed": val.passed, "reasons": list(val.reasons)} if val else None,
        "current_segment": current,
        "paused": bool(pause_state) and pause_state[-1] == "pause",
        "pauses": pause_state.count("pause"),
        "stage_index": layout.stage_index if layout else None,
        "last_stage_result": (
            {"stage_index": last_stage.stage_index, "decision": last_stage.decision, "reason": last_stage.reason, "comfort_value": last_stage.comfort_value, "correct_ratio": last_stage.correct_ratio}
            if last_stage else None
        ),
        "samples_total": len(samples),
        "last_sample_t_ms": last_t,
        "recent_window_ms": LIVE_WINDOW_MS,
        "recent": {"samples": recent_n, "valid_share": round(1 - counts["uncertain"] / recent_n, 4) if recent_n else None, "regions": counts},
        "recent_events": [{"t_ms": e.t_ms, "type": e.type, "payload": e.payload} for e in sorted(events, key=lambda e: (e.t_ms, e.id or 0))[-8:]],
        "seconds_since_last_event": round((now - last_event_at).total_seconds(), 1) if last_event_at else None,
        "observations": len(uow.observations.for_session(sid)),
        "conversation": monitor_block(uow, sid),
        "end_reason": s.end_reason,
        "note": "Live view for the supervisor. Region counts come from the webcam estimate; with a synthetic estimator they mean nothing.",
    }
    if first:
        log_access(uow, principal, study_id, "live_monitor", {"session_id": sid})
        uow.commit()
    return result


# ---------- threshold review ----------


def threshold_review(uow: PilotUnitOfWork, principal: Principal, study_id: int, changes: dict, include_synthetic: bool) -> dict:
    """Show what candidate thresholds would change on the recorded sessions. Saves nothing."""
    require_study_access(principal, study_id, *READERS)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    current = settings_for_study(uow, study_id)
    candidate = MeasurementSettings(study_id=study_id, **settings_values(current))
    unknown = sorted(set(changes) - set(SETTINGS_FIELDS))
    if unknown:
        raise Invalid("unknown settings: " + ", ".join(unknown))
    for k, v in changes.items():
        if v is not None:
            setattr(candidate, k, v)
    candidate.validate()
    notes = []
    if candidate.gaze_conf_threshold != current.gaze_conf_threshold:
        notes.append("gaze_conf_threshold changes how each sample is classified; recorded sessions are not re-classified here and the change applies to new sessions only.")
    if candidate.calibration_points != current.calibration_points or candidate.allow_continue_without_validation != current.allow_continue_without_validation:
        notes.append("calibration_points and allow_continue_without_validation apply to new sessions only.")
    codes = _codes(uow, study_id)
    rows = []
    metrics: dict[str, list[float]] = {k: [] for k in ("correct_ratio", "uncertain_ratio", "size_ratio", "residual_px_median", "uncertain_share", "missing_share")}
    by_device: dict[str, dict] = {}
    skipped_synthetic = 0
    for s in uow.sessions.list_for_study(study_id):
        if s.synthetic and not include_synthetic:
            skipped_synthetic += 1
            continue
        summary = summarize(uow, s)
        val = summary.get("validation")
        cov = summary.get("coverage") or {}
        total = cov.get("total_ms") or 0
        observed = (cov.get("classifiable_ms") or 0) + (cov.get("uncertain_ms") or 0)
        cand_val = revalidate(val, candidate) if val else None
        cand_summary = dict(summary, validation=(dict(val, **cand_val) if val else None))
        cand_quality = grade_quality(cand_summary, candidate.quality_max_uncertain_share, candidate.quality_max_missing_share).as_dict()
        if val:
            for k in ("correct_ratio", "uncertain_ratio", "size_ratio"):
                metrics[k].append(val[k])
        if summary.get("calibration"):
            metrics["residual_px_median"].append(summary["calibration"]["residual_px_median"])
        if observed:
            metrics["uncertain_share"].append((cov.get("uncertain_ms") or 0) / observed)
        if total:
            metrics["missing_share"].append((cov.get("missing_ms") or 0) / total)
        device = (s.device or {}).get("platform") or "unknown"
        d = by_device.setdefault(device, {"device_platform": device, "sessions": 0, "validated": 0, "pass_current": 0, "pass_candidate": 0})
        d["sessions"] += 1
        if val:
            d["validated"] += 1
            d["pass_current"] += int(bool(val["passed"]))
            d["pass_candidate"] += int(cand_val["passed"])
        rows.append({
            "session_id": s.id,
            "participant_code": codes.get(s.participant_id, "?"),
            "created_at": s.created_at,
            "device_platform": device,
            "synthetic": s.synthetic,
            "settings_version": val.get("settings_version") if val else None,
            "validation_current": {"passed": val["passed"], "reasons": val["reasons"]} if val else None,
            "validation_candidate": cand_val,
            "quality_current": summary["quality"],
            "quality_candidate": cand_quality,
            "changed": bool(val and bool(val["passed"]) != cand_val["passed"]) or summary["quality"]["grade"] != cand_quality["grade"],
            "metrics": {"correct_ratio": val["correct_ratio"] if val else None, "uncertain_ratio": val["uncertain_ratio"] if val else None, "size_ratio": val["size_ratio"] if val else None,
                        "residual_px_median": (summary.get("calibration") or {}).get("residual_px_median")},
        })

    def grades(key: str) -> dict:
        out = {"ok": 0, "review": 0, "exclude": 0}
        for r in rows:
            out[r[key]["grade"]] = out.get(r[key]["grade"], 0) + 1
        return out

    validated = [r for r in rows if r["validation_current"]]
    result = {
        "current": {"version": current.version, "values": settings_values(current)},
        "candidate": {"values": settings_values(candidate), "changes": {k: v for k, v in changes.items() if v is not None}},
        "sessions": len(rows),
        "skipped_synthetic": skipped_synthetic,
        "includes_synthetic": include_synthetic,
        "validated_sessions": len(validated),
        "validation_pass": {"current": sum(1 for r in validated if r["validation_current"]["passed"]), "candidate": sum(1 for r in validated if r["validation_candidate"]["passed"])},
        "quality": {"current": grades("quality_current"), "candidate": grades("quality_candidate")},
        "changed_sessions": sum(1 for r in rows if r["changed"]),
        "distributions": {k: distribution(v) for k, v in metrics.items()},
        "by_device": sorted(by_device.values(), key=lambda d: -d["sessions"]),
        "rows": rows,
        "notes": notes + ["Nothing is saved. A researcher decides and saves a new settings version with a rationale."],
    }
    log_access(uow, principal, study_id, "threshold_review", {"changes": result["candidate"]["changes"], "sessions": len(rows), "includes_synthetic": include_synthetic})
    uow.commit()
    return result


# ---------- research eye tracker ----------

_IMPORT_KEYS = ("time_column", "x_column", "y_column", "valid_column", "valid_values", "time_unit", "offset", "coord_space", "origin_x", "origin_y", "delimiter")


def _rec_view(r: ReferenceRecording) -> dict:
    return {"id": r.id, "session_id": r.session_id, "source": r.source, "settings": r.settings, "sample_count": r.sample_count, "valid_count": r.valid_count, "uploaded_by": r.uploaded_by, "created_at": r.created_at}


def _webcam_points(uow: PilotUnitOfWork, session_id: int) -> list[dict]:
    return [{"t_ms": x.t_ms, "x": x.x, "y": x.y, "valid": x.valid, "region": x.region, "segment": x.segment, "layout_id": x.layout_id} for x in uow.samples.for_session(session_id)]


def import_reference(uow: PilotUnitOfWork, principal: Principal, study_id: int, session_id: int, source: str, opts: dict, auto_align_window_ms: int, data: bytes) -> dict:
    s = _session_in_study(uow, principal, study_id, session_id, StudyRole.researcher)
    source = (source or "").strip()
    if not source or len(source) > 120:
        raise Invalid("source (the tracker's name and model) is required, max 120 characters")
    if not data:
        raise Invalid("the file is empty")
    clean = {k: opts.get(k) for k in _IMPORT_KEYS if opts.get(k) not in (None, "")}
    rows = parse_reference_csv(data, clean, s.screen or {})
    clean["alignment"] = "given_offset"
    if auto_align_window_ms:
        shift = estimate_offset(_webcam_points(uow, s.id or 0), rows, int(auto_align_window_ms))
        rows = [(t + shift, x, y, v) for t, x, y, v in rows]
        clean.update({"alignment": "estimated_from_data", "auto_align_window_ms": int(auto_align_window_ms), "estimated_shift_ms": shift})
    rec = ReferenceRecording(study_id=study_id, session_id=s.id or 0, source=source, uploaded_by=principal.user_id, settings=clean, sample_count=len(rows), valid_count=sum(1 for r in rows if r[3]))
    rec = uow.references.add(rec, rows)
    log_access(uow, principal, study_id, "reference_import", {"session_id": s.id, "recording_id": rec.id, "rows": len(rows)})
    uow.commit()
    return _rec_view(rec)


def list_references(uow: PilotUnitOfWork, principal: Principal, study_id: int, session_id: int) -> list[dict]:
    s = _session_in_study(uow, principal, study_id, session_id, *READERS)
    return [_rec_view(r) for r in uow.references.for_session(s.id or 0)]


def compare_reference(uow: PilotUnitOfWork, principal: Principal, study_id: int, session_id: int, recording_id: int, tolerance_ms: int) -> dict:
    s = _session_in_study(uow, principal, study_id, session_id, *READERS)
    rec = uow.references.get(recording_id)
    if rec is None or rec.session_id != s.id:
        raise NotFound("reference recording not found")
    layouts = {l.id: l.layout for l in uow.layouts.session_all(s.id or 0)}
    result = compare_with_reference(_webcam_points(uow, s.id or 0), uow.references.samples(rec.id or 0), layouts, int(tolerance_ms))
    val = uow.validations.latest(s.id or 0)
    caveats = []
    if s.synthetic:
        caveats.append("The webcam side used a synthetic estimator; agreement numbers mean nothing.")
    if rec.settings.get("alignment") == "estimated_from_data":
        caveats.append("The time alignment was estimated from this same data, which makes the agreement optimistic.")
    if val is None or not val.passed:
        caveats.append("This session's regional validation did not pass.")
    result.update({
        "recording": _rec_view(rec),
        "session": {"id": s.id, "participant_code": _codes(uow, study_id).get(s.participant_id, "?"), "estimator": (s.gaze_model or {}).get("model_id"), "gaze_model_version": (s.gaze_model or {}).get("model_version"), "synthetic": s.synthetic, "validation_passed": bool(val and val.passed), "screen": s.screen},
        "caveats": caveats,
    })
    log_access(uow, principal, study_id, "reference_compare", {"session_id": s.id, "recording_id": rec.id})
    uow.commit()
    return result


# ---------- pilot report ----------


def _debrief_stats(uow: PilotUnitOfWork, study_id: int, answers: list[DebriefAnswer], codes_by_session: dict[int, str]) -> tuple[list[dict], list[dict]]:
    forms: dict[int, DebriefForm | None] = {}
    stats: dict[str, dict] = {}
    comments: list[dict] = []
    for a in answers:
        if a.skipped:
            continue
        if a.form_version not in forms:
            forms[a.form_version] = uow.debrief_forms.get_version(study_id, a.form_version)
        form = forms[a.form_version]
        for q in form.questions if form else []:
            v = a.answers.get(q["key"])
            if v is None:
                continue
            st = stats.setdefault(q["key"], {"key": q["key"], "type": q["type"], "prompt": q["prompt"], "answered": 0, "counts": {}})
            st["answered"] += 1
            if q["type"] == "text":
                comments.append({"session_id": a.session_id, "participant_code": codes_by_session.get(a.session_id, "?"), "key": q["key"], "text": v})
                continue
            label = str(v).lower() if isinstance(v, bool) else str(v)
            st["counts"][label] = st["counts"].get(label, 0) + 1
            if q["type"] == "scale":
                st.setdefault("_values", []).append(int(v))
    for st in stats.values():
        vals = st.pop("_values", None)
        if vals:
            st["mean"] = round(sum(vals) / len(vals), 3)
    return list(stats.values()), comments


def pilot_report_data(uow: PilotUnitOfWork, principal: Principal, study_id: int, include_synthetic: bool) -> dict:
    require_study_access(principal, study_id, *READERS)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    codes = _codes(uow, study_id)
    settings = settings_for_study(uow, study_id)
    observations = uow.observations.for_study(study_id)
    obs_by_session: dict[int, list[Observation]] = {}
    for o in observations:
        obs_by_session.setdefault(o.session_id, []).append(o)
    debriefs = {a.session_id: a for a in uow.debrief_answers.for_study(study_id)}
    refs: dict[int, int] = {}
    for r in uow.references.for_study(study_id):
        refs[r.session_id] = refs.get(r.session_id, 0) + 1
    rows = []
    comfort_values: dict[str, int] = {}
    skipped_synthetic = 0
    kept_sessions: set[int] = set()
    for s in uow.sessions.list_for_study(study_id):
        if s.synthetic and not include_synthetic:
            skipped_synthetic += 1
            continue
        sid = s.id or 0
        kept_sessions.add(sid)
        summary = summarize(uow, s)
        out = summary.get("outcomes") or {}
        comfort = out.get("comfort") or {}
        stages = uow.stage_results.for_session(sid)
        for st in stages:
            if st.comfort_value is not None:
                comfort_values[str(st.comfort_value)] = comfort_values.get(str(st.comfort_value), 0) + 1
        obs = obs_by_session.get(sid, [])
        d = debriefs.get(sid)
        val = summary.get("validation") or {}
        rows.append({
            "session_id": sid,
            "participant_code": codes.get(s.participant_id, "?"),
            "created_at": s.created_at,
            "status": s.status.value,
            "end_reason": s.end_reason,
            "path": (summary.get("protocol") or {}).get("path"),
            "protocol_version": (summary.get("protocol") or {}).get("version"),
            "device_platform": (s.device or {}).get("platform"),
            "device_model": (s.device or {}).get("model"),
            "user_agent": (s.device or {}).get("user_agent"),
            "screen": f"{(s.screen or {}).get('w')}x{(s.screen or {}).get('h')}@{(s.screen or {}).get('dpr', 1)}",
            "camera": f"{(s.camera or {}).get('w')}x{(s.camera or {}).get('h')}",
            "camera_label": (s.camera or {}).get("label"),
            "estimator": (s.gaze_model or {}).get("model_id"),
            "synthetic": s.synthetic,
            "calibration_residual_px": (summary.get("calibration") or {}).get("residual_px_median"),
            "validation_passed": val.get("passed"),
            "validation_correct_ratio": val.get("correct_ratio"),
            "validation_reasons": ";".join(val.get("reasons") or []),
            "settings_version": val.get("settings_version"),
            "quality": summary["quality"]["grade"],
            "quality_reasons": ";".join(summary["quality"]["reasons"]),
            "stages_completed": (out.get("number_task") or {}).get("stages_completed"),
            "stage_decisions": ";".join(f"{st.stage_index}:{st.decision}" for st in stages),
            "comfort_min": comfort.get("min"),
            "comfort_mean": comfort.get("mean"),
            "comfort_low_count": comfort.get("low_count"),
            "pauses": comfort.get("pauses"),
            "ended_early": comfort.get("ended_early"),
            "comprehension_share": (out.get("comprehension") or {}).get("share"),
            "number_task_share": (out.get("number_task") or {}).get("share"),
            "debrief": "skipped" if d and d.skipped else ("answered" if d else "none"),
            "debrief_answers": dict(d.answers) if d and not d.skipped else {},
            "observations": len(obs),
            "observations_major_or_stop": sum(1 for o in obs if o.severity in ("major", "stop")),
            "reference_recordings": refs.get(sid, 0),
            "conversation_turns": (out.get("conversation") or {}).get("participant_turns"),
            "conversation_on_topic_share": (out.get("conversation") or {}).get("on_topic_share"),
            "conversation_distress": (out.get("conversation") or {}).get("distress"),
            "conversation_end_reason": (out.get("conversation") or {}).get("end_reason"),
        })
    kept_obs = [o for o in observations if o.session_id in kept_sessions]
    obs_matrix: dict[str, dict[str, int]] = {}
    for o in kept_obs:
        obs_matrix.setdefault(o.category, {}).setdefault(o.severity, 0)
        obs_matrix[o.category][o.severity] += 1
    code_by_session = {r["session_id"]: r["participant_code"] for r in rows}
    debrief_stats, comments = _debrief_stats(uow, study_id, [a for sid, a in debriefs.items() if sid in kept_sessions], code_by_session)
    validated = [r for r in rows if r["validation_passed"] is not None]
    by_device: dict[str, dict] = {}
    for r in rows:
        dev = r["device_platform"] or "unknown"
        d = by_device.setdefault(dev, {"device_platform": dev, "sessions": 0, "validated": 0, "validation_passed": 0, "quality_ok": 0})
        d["sessions"] += 1
        if r["validation_passed"] is not None:
            d["validated"] += 1
            d["validation_passed"] += int(bool(r["validation_passed"]))
        d["quality_ok"] += int(r["quality"] == "ok")
    return {
        "study_id": study_id,
        "settings": {"version": settings.version, "values": settings_values(settings)},
        "sessions": len(rows),
        "participants": len({r["participant_code"] for r in rows}),
        "skipped_synthetic": skipped_synthetic,
        "includes_synthetic": include_synthetic,
        "validation": {"validated": len(validated), "passed": sum(1 for r in validated if r["validation_passed"])},
        "quality": {g: sum(1 for r in rows if r["quality"] == g) for g in ("ok", "review", "exclude")},
        "ended_early": sum(1 for r in rows if r["ended_early"]),
        "comfort_stage_values": dict(sorted(comfort_values.items())),
        "by_device": sorted(by_device.values(), key=lambda d: -d["sessions"]),
        "debrief": {"answered": sum(1 for r in rows if r["debrief"] == "answered"), "skipped": sum(1 for r in rows if r["debrief"] == "skipped"), "questions": debrief_stats, "comments": comments},
        "observations": {"total": len(kept_obs), "by_category": obs_matrix, "items": [dict(_obs_view(o), participant_code=code_by_session.get(o.session_id, "?")) for o in kept_obs]},
        "rows": rows,
        "note": "Pilot summary for the research team. Numbers from synthetic estimators are left out unless included on purpose.",
    }


def pilot_report(uow: PilotUnitOfWork, principal: Principal, study_id: int, include_synthetic: bool) -> dict:
    data = pilot_report_data(uow, principal, study_id, include_synthetic)
    log_access(uow, principal, study_id, "pilot_report", {"sessions": data["sessions"], "includes_synthetic": include_synthetic})
    uow.commit()
    return data


def export_pilot_csv(uow: PilotUnitOfWork, principal: Principal, study_id: int, include_synthetic: bool) -> tuple[str, bytes, str]:
    data = pilot_report_data(uow, principal, study_id, include_synthetic)
    keys = sorted({k for r in data["rows"] for k in r["debrief_answers"]})
    buf = io.StringIO()
    base_cols = [k for k in (data["rows"][0].keys() if data["rows"] else ["session_id"]) if k != "debrief_answers"]
    w = csv.writer(buf)
    w.writerow(base_cols + [f"debrief_{k}" for k in keys])
    for r in data["rows"]:
        w.writerow([r[c] if not isinstance(r[c], (dict, list)) else json.dumps(r[c]) for c in base_cols] + [r["debrief_answers"].get(k, "") for k in keys])
    log_access(uow, principal, study_id, "export_pilot_csv", {"sessions": data["sessions"], "includes_synthetic": include_synthetic})
    uow.commit()
    return f"pilot_sessions_study{study_id}.csv", ("﻿" + buf.getvalue()).encode("utf-8"), "text/csv; charset=utf-8"
