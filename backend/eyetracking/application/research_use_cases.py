"""Use cases for build step 4: replay, quality, analysis, exports, access log, raw data and deletion."""
from __future__ import annotations

import csv
import io
import json
from datetime import date, datetime

from eyetracking.domain.errors import Conflict, Forbidden, Invalid, NotFound
from eyetracking.domain.measurement import Session, segments_from_events
from eyetracking.domain.models import RETENTION_POLICIES, Role, StudyRole
from eyetracking.domain.research import (
    DATA_DICTIONARY,
    EXPORT_VERSION,
    AccessLogEntry,
    compact_samples,
    group_key,
    layout_ranges,
    pause_intervals,
    quality_strip,
    sample_gaps,
)

from .authz import Principal, require_participant, require_role, require_study_access
from .measurement_use_cases import summarize
from .ports import Clock, MediaSigner, ResearchUnitOfWork

ANALYSIS_COLUMNS = [
    "session_id", "participant_code", "created_at", "path", "protocol_name", "protocol_version", "sheet_version",
    "device_platform", "screen", "estimator", "gaze_model_version", "synthetic", "quality", "quality_reasons",
    "calibration_residual_px", "validation_passed", "size_ratio", "total_ms", "classifiable_share", "uncertain_share",
    "missing_share", "face_share", "eye_share", "baseline_eye_share", "post_eye_share", "eye_share_delta",
    "comprehension_share", "number_task_share", "stages_completed", "comfort_min", "comfort_mean", "comfort_low_count",
    "pauses", "ended_early", "improvement", "group_key",
]


def log_access(uow: ResearchUnitOfWork, principal: Principal, study_id: int | None, action: str, detail: dict | None = None) -> None:
    uow.access_log.add(AccessLogEntry(study_id=study_id, user_id=principal.user_id, role=principal.role.value, action=action, detail=detail or {}))


# ---------- replay ----------


def _study_session(uow: ResearchUnitOfWork, principal: Principal, study_id: int, session_id: int) -> Session:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    s = uow.sessions.get(session_id)
    if s is None or s.study_id != study_id:
        raise NotFound("session not found")
    return s


def _code_of(uow: ResearchUnitOfWork, study_id: int, participant_id: int) -> str:
    p = next((x for x in uow.participants.list_for_study(study_id) if x.id == participant_id), None)
    return p.code if p else "?"


def replay(uow: ResearchUnitOfWork, signer: MediaSigner, principal: Principal, study_id: int, session_id: int) -> dict:
    s = _study_session(uow, principal, study_id, session_id)
    summary = summarize(uow, s)
    sid = s.id or 0
    samples = uow.samples.for_session(sid)
    events = uow.events.for_session(sid)
    last_t = max((x.t_ms for x in samples), default=None)
    segments = segments_from_events(events, last_t)
    start_ms = min([sg["started_ms"] for sg in segments] + [x.t_ms for x in samples[:1]], default=0)
    end_ms = max([sg.get("ended_ms") or 0 for sg in segments] + [last_t or 0], default=0)
    ranges = layout_ranges(samples)
    layouts = []
    for lid, (lo, hi) in ranges.items():
        l = next((x for x in _all_layouts(uow, sid) if x.id == lid), None)
        if l:
            layouts.append({"id": l.id, "segment": l.segment, "stage_index": l.stage_index, "layout": l.layout, "from_ms": lo, "to_ms": hi})
    layouts.sort(key=lambda x: x["from_ms"])
    media = []
    if s.assignment_id:
        a = uow.assignments.get(s.assignment_id)
        content = uow.content.get(a.content_id) if a and a.content_id else None
        by_key = {m.key: m for m in uow.media.list_for_content(content.id or 0)} if content else {}
        for e in events:
            if e.type == "media_start":
                m = by_key.get(str(e.payload.get("media_key", "")))
                media.append({"segment_id": e.payload.get("segment_id"), "media_key": e.payload.get("media_key"), "start_ms": e.t_ms, "url": f"/media/{signer.sign(m.id or 0)}" if m else None})
    log_access(uow, principal, study_id, "replay", {"session_id": sid})
    uow.commit()
    return {
        "session": {
            "id": s.id,
            "participant_code": _code_of(uow, study_id, s.participant_id),
            "status": s.status.value,
            "created_at": s.created_at,
            "synthetic": s.synthetic,
            "quality": summary["quality"],
            "protocol": summary.get("protocol") and {k: summary["protocol"][k] for k in ("name", "version", "path")},
        },
        "screen": s.screen,
        "segments": segments,
        "layouts": layouts,
        "samples": compact_samples(samples),
        "events": [{"t_ms": e.t_ms, "type": e.type, "payload": e.payload} for e in events],
        "trials": [
            {"stage_index": t.stage_index, "trial_index": t.trial_index, "t_ms": t.t_ms, "number_shown": t.number_shown, "zone": t.zone, "position": t.position, "face_level": t.face_level, "response": t.response, "correct": t.correct, "response_ms": t.response_ms}
            for t in uow.trials.for_session(sid)
        ],
        "answers": [{"segment_id": a.segment_id, "question_id": a.question_id, "kind": a.kind, "option": a.option, "correct": a.correct, "t_ms": a.t_ms} for a in uow.answers.for_session(sid)],
        "quality_strip": quality_strip(samples, start_ms, end_ms),
        "gaps": sample_gaps(samples),
        "pauses": pause_intervals(events, end_ms),
        "media": media,
    }


def _all_layouts(uow: ResearchUnitOfWork, session_id: int):
    return uow.layouts.session_all(session_id)


# ---------- analysis and exports ----------


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value[:10])
    except ValueError as exc:
        raise Invalid("dates must be YYYY-MM-DD") from exc


def _share(part: int | None, total: int | None) -> float | None:
    if not total:
        return None
    return round((part or 0) / total, 4)


def analysis_rows(uow: ResearchUnitOfWork, principal: Principal, study_id: int, filters: dict) -> dict:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    participants = {p.id: p for p in uow.participants.list_for_study(study_id)}
    sheet = uow.sheets.current(study_id)
    quality_filter = set((filters.get("quality") or "ok,review").split(",")) - {""}
    include_synthetic = bool(filters.get("include_synthetic"))
    d_from, d_to = _parse_date(filters.get("from")), _parse_date(filters.get("to"))
    rows: list[dict] = []
    excluded = 0
    for s in uow.sessions.list_for_study(study_id):
        p = participants.get(s.participant_id)
        code = p.code if p else "?"
        if filters.get("participant") and code != filters["participant"]:
            continue
        summary = summarize(uow, s)
        proto = summary.get("protocol") or {}
        if filters.get("path") and proto.get("path") != filters["path"]:
            continue
        if filters.get("protocol_version") and str(proto.get("version")) != str(filters["protocol_version"]):
            continue
        if filters.get("device") and (s.device or {}).get("platform") != filters["device"]:
            continue
        day = s.created_at.date()
        if d_from and day < d_from:
            continue
        if d_to and day > d_to:
            continue
        if s.synthetic and not include_synthetic:
            excluded += 1
            continue
        if summary["quality"]["grade"] not in quality_filter:
            excluded += 1
            continue
        val = uow.validations.latest(s.id or 0)
        eye_h = float(val.layout["eye_region"][3]) if val and val.layout.get("eye_region") else None
        gk = group_key((s.device or {}).get("platform"), str(proto.get("version")) if proto else None, (s.gaze_model or {}).get("model_id"), s.screen or {}, eye_h)
        cov = summary["coverage"]
        out = summary["outcomes"]
        shares = summary.get("region_shares") or {}
        eye_attention = summary.get("eye_region_attention") or {}
        demo = uow.demographics.answers(s.participant_id)
        rows.append(
            {
                "session_id": s.id,
                "participant_code": code,
                "created_at": s.created_at,
                "path": proto.get("path"),
                "protocol_name": proto.get("name"),
                "protocol_version": proto.get("version"),
                "sheet_version": sheet.version if sheet else None,
                "device_platform": (s.device or {}).get("platform"),
                "screen": f"{(s.screen or {}).get('w')}x{(s.screen or {}).get('h')}@{(s.screen or {}).get('dpr', 1)}",
                "estimator": (s.gaze_model or {}).get("model_id"),
                "gaze_model_version": (s.gaze_model or {}).get("model_version"),
                "synthetic": s.synthetic,
                "quality": summary["quality"]["grade"],
                "quality_reasons": ";".join(summary["quality"]["reasons"]),
                "calibration_residual_px": (summary.get("calibration") or {}).get("residual_px_median"),
                "validation_passed": (summary.get("validation") or {}).get("passed"),
                "size_ratio": (summary.get("validation") or {}).get("size_ratio"),
                "total_ms": cov["total_ms"],
                "classifiable_share": _share(cov["classifiable_ms"], cov["total_ms"]),
                "uncertain_share": _share(cov["uncertain_ms"], cov["total_ms"]),
                "missing_share": _share(cov["missing_ms"], cov["total_ms"]),
                "face_share": (summary.get("face_region_attention") or {}).get("share"),
                "eye_share": eye_attention.get("share") if eye_attention.get("evaluable") else None,
                "baseline_eye_share": out["gaze"]["baseline_eye_share"] if out["gaze"]["evaluable"] else None,
                "post_eye_share": out["gaze"]["post_eye_share"] if out["gaze"]["evaluable"] else None,
                "eye_share_delta": (
                    round(out["gaze"]["post_eye_share"] - out["gaze"]["baseline_eye_share"], 4)
                    if out["gaze"]["evaluable"] and out["gaze"]["post_eye_share"] is not None and out["gaze"]["baseline_eye_share"] is not None
                    else None
                ),
                "comprehension_share": out["comprehension"]["share"],
                "number_task_share": out["number_task"]["share"],
                "stages_completed": out["number_task"]["stages_completed"],
                "comfort_min": out["comfort"]["min"],
                "comfort_mean": out["comfort"]["mean"],
                "comfort_low_count": out["comfort"]["low_count"],
                "pauses": out["comfort"]["pauses"],
                "ended_early": out["comfort"]["ended_early"],
                "improvement": out["improvement"]["result"],
                "group_key": gk,
                "demographics": dict(demo.answers) if demo else {},
            }
        )
    groups: dict[str, dict] = {}
    for r in rows:
        g = groups.setdefault(r["group_key"], {"group_key": r["group_key"], "sessions": 0, "participants": set()})
        g["sessions"] += 1
        g["participants"].add(r["participant_code"])
    group_list = []
    for g in groups.values():
        parts = g["group_key"].split("|")
        group_list.append({"group_key": g["group_key"], "device_platform": parts[0], "protocol_version": parts[1], "estimator": parts[2], "screen_bucket": parts[3], "stimulus_bucket_px": parts[4], "sessions": g["sessions"], "participants": len(g["participants"])})
    trends: dict[tuple[str, str], list[dict]] = {}
    for r in sorted(rows, key=lambda r: r["created_at"]):
        trends.setdefault((r["participant_code"], r["group_key"]), []).append(
            {"session_id": r["session_id"], "created_at": r["created_at"], "baseline_eye_share": r["baseline_eye_share"], "post_eye_share": r["post_eye_share"], "comfort_mean": r["comfort_mean"], "comprehension_share": r["comprehension_share"], "number_task_share": r["number_task_share"], "quality": r["quality"]}
        )
    return {
        "filters": {k: v for k, v in filters.items() if v not in (None, "")},
        "rows": rows,
        "groups": sorted(group_list, key=lambda g: -g["sessions"]),
        "trends": [{"participant_code": k[0], "group_key": k[1], "points": v} for k, v in trends.items()],
        "excluded": excluded,
        "note": "Sessions from different groups are never pooled into one trend by default.",
    }


def analysis(uow: ResearchUnitOfWork, principal: Principal, study_id: int, filters: dict) -> dict:
    result = analysis_rows(uow, principal, study_id, filters)
    log_access(uow, principal, study_id, "analysis", {"filters": result["filters"], "rows": len(result["rows"])})
    uow.commit()
    return result


def _flatten(row: dict, demo_keys: list[str]) -> dict:
    flat = {k: row.get(k) for k in ANALYSIS_COLUMNS}
    flat["created_at"] = row["created_at"].isoformat() if isinstance(row["created_at"], datetime) else row["created_at"]
    for k in demo_keys:
        flat[f"demo_{k}"] = row["demographics"].get(k)
    flat["export_version"] = EXPORT_VERSION
    return flat


def export_sessions(uow: ResearchUnitOfWork, principal: Principal, study_id: int, filters: dict, fmt: str) -> tuple[str, bytes, str]:
    result = analysis_rows(uow, principal, study_id, filters)
    demo_keys = sorted({k for r in result["rows"] for k in r["demographics"]})
    flat = [_flatten(r, demo_keys) for r in result["rows"]]
    columns = ANALYSIS_COLUMNS + [f"demo_{k}" for k in demo_keys] + ["export_version"]
    if fmt == "json":
        payload = {"export_version": EXPORT_VERSION, "study_id": study_id, "filters": result["filters"], "generated_at": datetime.utcnow().isoformat(), "rows": flat}
        data, media_type, name = json.dumps(payload, indent=1, default=str).encode(), "application/json", f"study-{study_id}-sessions.json"
    else:
        buf = io.StringIO()
        w = csv.DictWriter(buf, fieldnames=columns)
        w.writeheader()
        for r in flat:
            w.writerow({k: ("" if v is None else v) for k, v in r.items()})
        data, media_type, name = buf.getvalue().encode("utf-8-sig"), "text/csv", f"study-{study_id}-sessions.csv"
    log_access(uow, principal, study_id, f"export_sessions_{fmt}", {"filters": result["filters"], "rows": len(flat)})
    uow.commit()
    return name, data, media_type


def export_samples(uow: ResearchUnitOfWork, principal: Principal, study_id: int, session_id: int) -> tuple[str, bytes, str]:
    s = _study_session(uow, principal, study_id, session_id)
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["t_ms", "x", "y", "conf", "valid", "region", "segment", "layout_id"])
    for x in uow.samples.for_session(s.id or 0):
        w.writerow([x.t_ms, "" if x.x is None else round(x.x, 2), "" if x.y is None else round(x.y, 2), round(x.conf, 3), int(x.valid), x.region, x.segment, x.layout_id or ""])
    log_access(uow, principal, study_id, "export_samples_csv", {"session_id": s.id})
    uow.commit()
    return f"session-{s.id}-samples.csv", buf.getvalue().encode("utf-8-sig"), "text/csv"


def export_events(uow: ResearchUnitOfWork, principal: Principal, study_id: int, session_id: int) -> tuple[str, bytes, str]:
    s = _study_session(uow, principal, study_id, session_id)
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["t_ms", "type", "payload_json"])
    for e in uow.events.for_session(s.id or 0):
        w.writerow([e.t_ms, e.type, json.dumps(e.payload, ensure_ascii=False)])
    log_access(uow, principal, study_id, "export_events_csv", {"session_id": s.id})
    uow.commit()
    return f"session-{s.id}-events.csv", buf.getvalue().encode("utf-8-sig"), "text/csv"


def data_dictionary() -> list[dict]:
    return list(DATA_DICTIONARY)


def access_log(uow: ResearchUnitOfWork, principal: Principal, study_id: int, limit: int) -> list[dict]:
    require_study_access(principal, study_id, StudyRole.researcher)
    if not 1 <= limit <= 1000:
        raise Invalid("limit must be 1..1000")
    return [{"at": e.created_at, "user_id": e.user_id, "role": e.role, "action": e.action, "detail": e.detail} for e in uow.access_log.list_for_study(study_id, limit)]


# ---------- participant raw data and deletion ----------


def my_full_data(uow: ResearchUnitOfWork, principal: Principal) -> dict:
    from .use_cases import my_data_export

    p = require_participant(principal)
    data = my_data_export(uow, principal)
    sessions = []
    for s in uow.sessions.list_for_participant(p.id or 0):
        sid = s.id or 0
        sessions.append(
            {
                "summary": summarize(uow, s),
                "samples": compact_samples(uow.samples.for_session(sid)),
                "events": [{"t_ms": e.t_ms, "type": e.type, "payload": e.payload} for e in uow.events.for_session(sid)],
                "trials": [{"stage_index": t.stage_index, "trial_index": t.trial_index, "t_ms": t.t_ms, "number_shown": t.number_shown, "zone": t.zone, "response": t.response, "correct": t.correct} for t in uow.trials.for_session(sid)],
                "answers": [{"segment_id": a.segment_id, "question_id": a.question_id, "kind": a.kind, "option": a.option, "correct": a.correct, "t_ms": a.t_ms} for a in uow.answers.for_session(sid)],
            }
        )
    data["sessions"] = sessions
    data["export_version"] = EXPORT_VERSION
    data["note"] = "Gaze estimates and session events are the raw data. No camera video exists."
    log_access(uow, principal, p.study_id, "self_export", {"participant_id": p.id})
    uow.commit()
    return data


def erase_me(uow: ResearchUnitOfWork, clock: Clock, principal: Principal, confirm: str) -> dict:
    p = require_participant(principal)
    if confirm != "DELETE MY DATA":
        raise Invalid('confirmation phrase must be exactly "DELETE MY DATA"')
    study = uow.studies.get(p.study_id)
    policy = study.retention_policy if study else "delete_all"
    deleted = uow.purge_participant_research_data(p.id or 0) if policy == "delete_all" else {}
    user = uow.users.get(p.user_id)
    if user is not None:
        user.email = f"erased-{user.id}@erased.invalid"
        user.password_hash = "!"
        user.is_active = False
    if policy == "delete_all":
        uow.delete_participant(p.id or 0)
    log_access(uow, principal, p.study_id, "erasure", {"participant_id": p.id, "policy": policy, "deleted": deleted})
    uow.commit()
    return {"policy": policy, "deleted": deleted, "identity_removed": True}


def delete_participant_data(uow: ResearchUnitOfWork, principal: Principal, study_id: int, code: str, confirm: str) -> dict:
    require_study_access(principal, study_id, StudyRole.researcher)
    p = uow.participants.by_code(study_id, code)
    if p is None:
        raise NotFound("participant not found")
    if confirm != code:
        raise Invalid("confirmation must repeat the research code")
    deleted = uow.purge_participant_research_data(p.id or 0)
    log_access(uow, principal, study_id, "participant_data_deleted", {"participant_code": code, "deleted": deleted})
    uow.commit()
    return {"participant_code": code, "deleted": deleted}


# ---------- study policy ----------


def get_study(uow: ResearchUnitOfWork, principal: Principal, study_id: int) -> dict:
    require_study_access(principal, study_id)
    st = uow.studies.get(study_id)
    if st is None:
        raise NotFound("study not found")
    return {"id": st.id, "name": st.name, "retention_policy": st.retention_policy}


def update_study(uow: ResearchUnitOfWork, principal: Principal, study_id: int, retention_policy: str | None) -> dict:
    require_role(principal, Role.admin)
    st = uow.studies.get(study_id)
    if st is None:
        raise NotFound("study not found")
    if retention_policy is not None:
        if retention_policy not in RETENTION_POLICIES:
            raise Invalid(f"retention_policy must be one of {RETENTION_POLICIES}")
        st.retention_policy = retention_policy
    uow.commit()
    return {"id": st.id, "name": st.name, "retention_policy": st.retention_policy}
