"""Use cases for build step 2. Sessions belong to a participant; staff read them coded by study."""
from __future__ import annotations

from dataclasses import asdict

from eyetracking.domain.errors import Conflict, Forbidden, Invalid, NotFound
from eyetracking.domain.measurement import (
    EVENT_TYPES,
    INVALIDATING_EVENTS,
    SEGMENTS,
    Calibration,
    GazeSample,
    MeasurementSettings,
    Session,
    SessionEvent,
    SessionStatus,
    StimulusLayout,
    Validation,
    classify_raw,
    coverage,
    evaluate_validation,
    eye_region_attention,
    face_region_attention,
    fit_calibration,
    region_shares,
    segments_from_events,
    validate_layout,
)
from eyetracking.domain.models import StudyRole, compute_readiness

from .authz import Principal, require_participant, require_study_access
from .ports import Clock, MeasurementUnitOfWork

MAX_BATCH = 500


# ---------- settings ----------


def settings_for_study(uow: MeasurementUnitOfWork, study_id: int) -> MeasurementSettings:
    return uow.measurement_settings.get(study_id) or MeasurementSettings(study_id=study_id)


def my_settings(uow: MeasurementUnitOfWork, principal: Principal) -> MeasurementSettings:
    return settings_for_study(uow, require_participant(principal).study_id)


def get_study_settings(uow: MeasurementUnitOfWork, principal: Principal, study_id: int) -> MeasurementSettings:
    require_study_access(principal, study_id)
    return settings_for_study(uow, study_id)


def update_study_settings(uow: MeasurementUnitOfWork, principal: Principal, study_id: int, rationale: str | None = None, **changes) -> MeasurementSettings:
    """Thresholds are versioned: every real change gets a new version with who and why.

    New validations record the version they were judged with. Nothing already recorded is
    re-judged silently; the threshold review shows what a change would do before it is saved.
    """
    from eyetracking.domain.pilot import MAX_RATIONALE_CHARS, SETTINGS_FIELDS, SettingsVersion, settings_values

    require_study_access(principal, study_id, StudyRole.researcher)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    s = settings_for_study(uow, study_id)
    before = settings_values(s)
    for k, v in changes.items():
        if v is not None and k in SETTINGS_FIELDS:
            setattr(s, k, v)
    try:
        s.validate()
    except Invalid:
        for k, v in before.items():
            setattr(s, k, v)
        raise
    after = settings_values(s)
    if after == before:
        return s
    note = (rationale or "").strip()
    if len(note) > MAX_RATIONALE_CHARS:
        raise Invalid(f"rationale is limited to {MAX_RATIONALE_CHARS} characters")
    if not uow.settings_versions.list_for_study(study_id):
        uow.settings_versions.add(SettingsVersion(study_id=study_id, version=s.version or 1, values=before, rationale="Values in use before the first recorded change", changed_by=None))
    s.version = (s.version or 1) + 1
    s = uow.measurement_settings.save(s)
    uow.settings_versions.add(SettingsVersion(study_id=study_id, version=s.version, values=after, rationale=note, changed_by=principal.user_id))
    uow.commit()
    return s


def settings_history(uow: MeasurementUnitOfWork, principal: Principal, study_id: int) -> list[dict]:
    from eyetracking.domain.pilot import settings_values

    require_study_access(principal, study_id)
    rows = uow.settings_versions.list_for_study(study_id)
    if not rows:
        s = settings_for_study(uow, study_id)
        return [{"version": s.version, "values": settings_values(s), "rationale": "Defaults; no change recorded yet" if s.id is None else "Saved before the settings history existed", "changed_by": None, "created_at": None}]
    return [{"version": r.version, "values": r.values, "rationale": r.rationale, "changed_by": r.changed_by, "created_at": r.created_at} for r in reversed(rows)]


# ---------- sessions (participant side) ----------


def create_session(
    uow: MeasurementUnitOfWork, principal: Principal, device: dict, screen: dict, camera: dict, gaze_model: dict, assignment_id: int | None = None
) -> Session:
    p = require_participant(principal)
    assert p.id is not None
    readiness = compute_readiness(
        uow.sheets.current(p.study_id),
        uow.consents.latest(p.id),
        uow.demographics.current_form(p.study_id),
        uow.demographics.answers(p.id),
    )
    if not readiness.ready:
        raise Forbidden("participant is not ready for a session: " + ", ".join(readiness.reasons))
    if not screen.get("w") or not screen.get("h"):
        raise Invalid("screen.w and screen.h are required")
    synthetic = bool(gaze_model.get("synthetic", True))
    s = Session(
        participant_id=p.id,
        study_id=p.study_id,
        device=device,
        screen=screen,
        camera=camera,
        gaze_model=gaze_model,
        synthetic=synthetic,
        notes=["synthetic_estimator"] if synthetic else [],
    )
    if assignment_id is not None:
        from .practice_use_cases import bind_assignment

        bind_assignment(uow, principal, s, assignment_id)
    s = uow.sessions.add(s)
    uow.commit()
    return s


def _own_session(uow: MeasurementUnitOfWork, principal: Principal, session_id: int) -> Session:
    p = require_participant(principal)
    s = uow.sessions.get(session_id)
    if s is None or s.participant_id != p.id:
        raise NotFound("session not found")
    return s


def camera_check(
    uow: MeasurementUnitOfWork, principal: Principal, session_id: int, face_detected: bool, face_conf: float, lighting_ok: bool, frame_w: int, frame_h: int
) -> Session:
    s = _own_session(uow, principal, session_id)
    s.ensure_open()
    settings = settings_for_study(uow, s.study_id)
    ok = face_detected and face_conf >= settings.gaze_conf_threshold and lighting_ok
    if ok and s.status is SessionStatus.created:
        s.status = SessionStatus.camera_ok
    if not ok:
        s.notes = list(s.notes) + ["camera_check_failed"]
    uow.events.add(
        SessionEvent(
            session_id=s.id or 0,
            t_ms=0,
            type="note",
            payload={"camera_check": {"face_detected": face_detected, "face_conf": face_conf, "lighting_ok": lighting_ok, "frame_w": frame_w, "frame_h": frame_h, "ok": ok}},
        )
    )
    uow.commit()
    return s


def submit_calibration(uow: MeasurementUnitOfWork, principal: Principal, session_id: int, targets: list[dict]) -> Calibration:
    s = _own_session(uow, principal, session_id)
    s.ensure_open()
    if s.status is SessionStatus.created:
        raise Conflict("complete the camera check before calibrating")
    settings = settings_for_study(uow, s.study_id)
    c = fit_calibration(targets, settings.gaze_conf_threshold)
    c.session_id = s.id or 0
    c = uow.calibrations.add(c)
    s.calibration_valid = True
    if s.status in (SessionStatus.camera_ok, SessionStatus.calibrated, SessionStatus.validated):
        s.status = SessionStatus.calibrated
    uow.commit()
    return c


def submit_validation(uow: MeasurementUnitOfWork, principal: Principal, session_id: int, layout: dict, targets: list[dict]) -> Validation:
    s = _own_session(uow, principal, session_id)
    s.ensure_open()
    cal = uow.calibrations.latest(s.id or 0)
    if cal is None or not s.calibration_valid:
        raise Conflict("a valid calibration is required before validation")
    settings = settings_for_study(uow, s.study_id)
    v = evaluate_validation(cal, layout, targets, settings)
    v.session_id = s.id or 0
    v.calibration_id = cal.id or 0
    v = uow.validations.add(v)
    if s.status in (SessionStatus.calibrated, SessionStatus.validated):
        s.status = SessionStatus.validated
    uow.commit()
    return v


def set_layout(uow: MeasurementUnitOfWork, principal: Principal, session_id: int, segment: str, layout: dict, stage_index: int | None = None) -> StimulusLayout:
    s = _own_session(uow, principal, session_id)
    s.ensure_open()
    if segment not in SEGMENTS:
        raise Invalid(f"segment must be one of {SEGMENTS}")
    validate_layout(layout)
    l = uow.layouts.add(StimulusLayout(session_id=s.id or 0, segment=segment, layout=layout, stage_index=stage_index))
    uow.commit()
    return l


def add_samples(uow: MeasurementUnitOfWork, principal: Principal, session_id: int, raws: list[dict]) -> tuple[int, int]:
    s = _own_session(uow, principal, session_id)
    s.ensure_open()
    if len(raws) > MAX_BATCH:
        raise Invalid(f"at most {MAX_BATCH} samples per batch")
    if s.status is not SessionStatus.running:
        raise Conflict(f"session is not running (status: {s.status.value})")
    if not s.calibration_valid:
        raise Conflict("calibration is no longer valid; calibrate again before recording")
    cal = uow.calibrations.latest(s.id or 0)
    layout = uow.layouts.latest(s.id or 0)
    if cal is None or layout is None:
        raise Conflict("calibration and a stimulus layout are required before recording")
    settings = settings_for_study(uow, s.study_id)
    rows: list[GazeSample] = []
    invalid = 0
    for raw in raws:
        point, conf, region = classify_raw(cal.params, raw, layout.layout, settings.gaze_conf_threshold)
        valid = region != "uncertain"
        invalid += int(not valid)
        rows.append(
            GazeSample(
                session_id=s.id or 0,
                t_ms=int(raw.get("t_ms", 0)),
                x=point[0] if point else None,
                y=point[1] if point else None,
                conf=conf,
                valid=valid,
                region=region,
                segment=layout.segment,
                layout_id=layout.id,
            )
        )
    stored = uow.samples.add_many(rows)
    uow.commit()
    return stored, invalid


def add_event(uow: MeasurementUnitOfWork, clock: Clock, principal: Principal, session_id: int, t_ms: int, type_: str, payload: dict | None) -> Session:
    s = _own_session(uow, principal, session_id)
    s.ensure_open()
    payload = payload or {}
    if type_ not in EVENT_TYPES:
        raise Invalid(f"event type must be one of {EVENT_TYPES}")
    settings = settings_for_study(uow, s.study_id)
    if type_ == "segment_start":
        layout = uow.layouts.latest(s.id or 0)
        if layout is None:
            raise Conflict("set a stimulus layout before starting a segment")
        if s.status in (SessionStatus.created, SessionStatus.camera_ok) or not s.calibration_valid:
            raise Conflict("calibrate before starting a segment")
        v = uow.validations.latest(s.id or 0)
        if (v is None or not v.passed) and not settings.allow_continue_without_validation:
            raise Conflict("validation must pass before a segment can start")
        payload = dict(payload, segment=payload.get("segment", layout.segment))
        s.status = SessionStatus.running
    elif type_ == "pause":
        if s.status is not SessionStatus.running:
            raise Conflict("only a running session can be paused")
        s.status = SessionStatus.paused
    elif type_ == "resume":
        if s.status is not SessionStatus.paused:
            raise Conflict("only a paused session can be resumed")
        s.status = SessionStatus.running
    elif type_ in INVALIDATING_EVENTS:
        s.calibration_valid = False
        s.notes = list(s.notes) + [f"calibration_invalidated:{type_}"]
    elif type_ == "end":
        reason = payload.get("reason")
        if reason not in ("completed", "ended_early"):
            raise Invalid("end.payload.reason must be completed or ended_early")
        s.status = SessionStatus.ended
        s.ended_at = clock.now()
        s.end_reason = reason
        from .practice_use_cases import on_session_end

        on_session_end(uow, s)
    elif type_ == "comfort_answer":
        from .practice_use_cases import validate_comfort_payload

        validate_comfort_payload(uow, s, payload)
    uow.events.add(SessionEvent(session_id=s.id or 0, t_ms=int(t_ms), type=type_, payload=payload))
    uow.commit()
    return s


# ---------- summaries ----------


def summarize(uow: MeasurementUnitOfWork, s: Session) -> dict:
    sid = s.id or 0
    cal = uow.calibrations.latest(sid)
    val = uow.validations.latest(sid)
    notes = list(s.notes)
    if val is not None and cal is not None and val.calibration_id != cal.id:
        notes.append("validation_predates_latest_calibration")
        val = None
    samples = uow.samples.for_session(sid)
    events = uow.events.for_session(sid)
    last_t = max((x.t_ms for x in samples), default=None)
    segments = segments_from_events(events, last_t)
    cov = coverage(samples, segments)
    shares = region_shares(cov)
    base = {
        "id": s.id,
        "status": s.status.value,
        "created_at": s.created_at,
        "ended_at": s.ended_at,
        "end_reason": s.end_reason,
        "synthetic": s.synthetic,
        "calibration_valid": s.calibration_valid,
        "calibration": (
            {"residual_px_median": cal.residual_px_median, "residual_px_p90": cal.residual_px_p90, "points": cal.points} if cal else None
        ),
        "validation": (
            {
                "passed": val.passed,
                "correct_ratio": val.correct_ratio,
                "uncertain_ratio": val.uncertain_ratio,
                "size_ratio": val.size_ratio,
                "reasons": list(val.reasons),
                "settings_version": val.settings_version,
            }
            if val
            else None
        ),
        "coverage": {
            "total_ms": cov.total_ms,
            "classifiable_ms": cov.classifiable_ms,
            "uncertain_ms": cov.uncertain_ms,
            "missing_ms": cov.missing_ms,
        },
        "region_shares": shares,
        "face_region_attention": face_region_attention(shares),
        "eye_region_attention": eye_region_attention(s, val, shares),
        "segments": segments,
        "events_count": len(events),
        "notes": notes,
    }
    from eyetracking.domain.research import grade_quality

    from .practice_use_cases import practice_summary

    out = practice_summary(uow, s, base)
    settings = settings_for_study(uow, s.study_id)
    out["quality"] = grade_quality(out, settings.quality_max_uncertain_share, settings.quality_max_missing_share).as_dict()
    return out


def my_session(uow: MeasurementUnitOfWork, principal: Principal, session_id: int) -> dict:
    return summarize(uow, _own_session(uow, principal, session_id))


def my_sessions(uow: MeasurementUnitOfWork, principal: Principal) -> list[dict]:
    p = require_participant(principal)
    return [summarize(uow, s) for s in uow.sessions.list_for_participant(p.id or 0)]


def _study_session(uow: MeasurementUnitOfWork, principal: Principal, study_id: int, session_id: int) -> Session:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    s = uow.sessions.get(session_id)
    if s is None or s.study_id != study_id:
        raise NotFound("session not found")
    return s


def list_study_sessions(uow: MeasurementUnitOfWork, principal: Principal, study_id: int) -> list[dict]:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    out = []
    for s in uow.sessions.list_for_study(study_id):
        summary = summarize(uow, s)
        participant = next((x for x in uow.participants.list_for_study(study_id) if x.id == s.participant_id), None)
        out.append(
            {
                "id": s.id,
                "participant_code": participant.code if participant else "?",
                "status": summary["status"],
                "created_at": s.created_at,
                "ended_at": s.ended_at,
                "synthetic": s.synthetic,
                "device_platform": (s.device or {}).get("platform"),
                "calibration_residual_px": summary["calibration"]["residual_px_median"] if summary["calibration"] else None,
                "validation_passed": summary["validation"]["passed"] if summary["validation"] else None,
                "coverage": summary["coverage"],
                "eye_region_attention": summary["eye_region_attention"],
                "quality": summary["quality"],
                "protocol": summary.get("protocol") and {k: summary["protocol"][k] for k in ("id", "name", "version", "path")},
            }
        )
    return out


def get_study_session(uow: MeasurementUnitOfWork, principal: Principal, study_id: int, session_id: int) -> dict:
    s = _study_session(uow, principal, study_id, session_id)
    summary = summarize(uow, s)
    participant = next((x for x in uow.participants.list_for_study(study_id) if x.id == s.participant_id), None)
    val = uow.validations.latest(s.id or 0)
    summary.update(
        {
            "participant_code": participant.code if participant else "?",
            "device": s.device,
            "screen": s.screen,
            "camera": s.camera,
            "gaze_model": s.gaze_model,
            "validation_targets": list(val.targets) if val else [],
            "events": [{"t_ms": e.t_ms, "type": e.type, "payload": e.payload} for e in uow.events.for_session(s.id or 0)],
        }
    )
    from .practice_use_cases import practice_detail

    summary.update(practice_detail(uow, s))
    return summary


def study_session_samples(uow: MeasurementUnitOfWork, principal: Principal, study_id: int, session_id: int, offset: int, limit: int) -> tuple[int, list[dict]]:
    s = _study_session(uow, principal, study_id, session_id)
    if not 1 <= limit <= 5000 or offset < 0:
        raise Invalid("limit must be 1..5000 and offset >= 0")
    total, items = uow.samples.page(s.id or 0, offset, limit)
    return total, [
        {"t_ms": x.t_ms, "x": x.x, "y": x.y, "conf": x.conf, "valid": x.valid, "region": x.region, "segment": x.segment} for x in items
    ]
