"""Use cases for build step 3: protocols, content, assignments and the two practice paths."""
from __future__ import annotations

from datetime import datetime

from eyetracking.domain.errors import Conflict, Forbidden, Invalid, NotFound
from eyetracking.domain.measurement import Session, coverage, region_shares, segments_from_events
from eyetracking.domain.models import StudyRole
from eyetracking.domain.practice import (
    ANSWER_KINDS,
    MAX_MEDIA_BYTES,
    MEDIA_TYPES,
    ZONES,
    Answer,
    Assignment,
    AssignmentStatus,
    ContentItem,
    ContentMedia,
    ContentStatus,
    Protocol,
    ProtocolStatus,
    StageResult,
    Trial,
    comfort_outcome,
    comprehension_correct,
    evaluate_stage,
    improvement,
    next_segment,
    personalize,
    validate_content,
    validate_protocol,
)

from .authz import Principal, require_participant, require_study_access
from .ports import Clock, MediaSigner, MediaStore, PracticeUnitOfWork

MAX_TRIAL_BATCH = 200


# ---------- protocols ----------


def _protocol_in_study(uow: PracticeUnitOfWork, study_id: int, protocol_id: int) -> Protocol:
    p = uow.protocols.get(protocol_id)
    if p is None or p.study_id != study_id:
        raise NotFound("protocol not found")
    return p


def list_protocols(uow: PracticeUnitOfWork, principal: Principal, study_id: int) -> list[Protocol]:
    require_study_access(principal, study_id)
    return uow.protocols.list_for_study(study_id)


def get_protocol(uow: PracticeUnitOfWork, principal: Principal, study_id: int, protocol_id: int) -> Protocol:
    require_study_access(principal, study_id)
    return _protocol_in_study(uow, study_id, protocol_id)


def create_protocol(uow: PracticeUnitOfWork, principal: Principal, study_id: int, name: str, definition: dict) -> Protocol:
    require_study_access(principal, study_id, StudyRole.researcher)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    if not (name or "").strip():
        raise Invalid("name is required")
    validate_protocol(definition)
    p = uow.protocols.add(Protocol(study_id=study_id, name=name.strip(), definition=definition))
    uow.commit()
    return p


def update_protocol(uow: PracticeUnitOfWork, principal: Principal, study_id: int, protocol_id: int, name: str | None, definition: dict | None) -> Protocol:
    require_study_access(principal, study_id, StudyRole.researcher)
    p = _protocol_in_study(uow, study_id, protocol_id)
    p.ensure_draft()
    if name is not None:
        if not name.strip():
            raise Invalid("name is required")
        p.name = name.strip()
    if definition is not None:
        validate_protocol(definition)
        p.definition = definition
    uow.commit()
    return p


def publish_protocol(uow: PracticeUnitOfWork, clock: Clock, principal: Principal, study_id: int, protocol_id: int) -> Protocol:
    require_study_access(principal, study_id, StudyRole.researcher)
    p = _protocol_in_study(uow, study_id, protocol_id)
    p.ensure_draft()
    validate_protocol(p.definition)
    p.status = ProtocolStatus.published
    p.version = uow.protocols.max_version(study_id) + 1
    p.published_at = clock.now()
    uow.commit()
    return p


def new_draft_from(uow: PracticeUnitOfWork, principal: Principal, study_id: int, protocol_id: int) -> Protocol:
    require_study_access(principal, study_id, StudyRole.researcher)
    src = _protocol_in_study(uow, study_id, protocol_id)
    p = uow.protocols.add(Protocol(study_id=study_id, name=src.name, definition=dict(src.definition)))
    uow.commit()
    return p


# ---------- content ----------


def _content_in_study(uow: PracticeUnitOfWork, study_id: int, content_id: int) -> ContentItem:
    c = uow.content.get(content_id)
    if c is None or c.study_id != study_id:
        raise NotFound("content not found")
    return c


def missing_media(uow: PracticeUnitOfWork, c: ContentItem) -> list[str]:
    present = {m.key for m in uow.media.list_for_content(c.id or 0)}
    return sorted(set(c.media_keys()) - present)


def list_content(uow: PracticeUnitOfWork, principal: Principal, study_id: int) -> list[tuple[ContentItem, list[str]]]:
    require_study_access(principal, study_id)
    return [(c, missing_media(uow, c)) for c in uow.content.list_for_study(study_id)]


def get_content(uow: PracticeUnitOfWork, principal: Principal, study_id: int, content_id: int) -> tuple[ContentItem, list[str]]:
    require_study_access(principal, study_id)
    c = _content_in_study(uow, study_id, content_id)
    return c, missing_media(uow, c)


def create_content(uow: PracticeUnitOfWork, clock: Clock, principal: Principal, study_id: int, title: str, definition: dict, topic_tags: list[str], face_id: str, voice_id: str) -> ContentItem:
    require_study_access(principal, study_id, StudyRole.researcher)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    if not (title or "").strip():
        raise Invalid("title is required")
    validate_content(definition)
    c = ContentItem(study_id=study_id, title=title.strip(), definition=definition, topic_tags=[t.strip().lower() for t in topic_tags if t.strip()], face_id=face_id or "", voice_id=voice_id or "", created_at=clock.now(), updated_at=clock.now())
    c = uow.content.add(c)
    uow.commit()
    return c


def update_content(uow: PracticeUnitOfWork, clock: Clock, principal: Principal, study_id: int, content_id: int, **changes) -> ContentItem:
    require_study_access(principal, study_id, StudyRole.researcher)
    c = _content_in_study(uow, study_id, content_id)
    c.ensure_draft()
    if changes.get("definition") is not None:
        validate_content(changes["definition"])
        c.definition = changes["definition"]
        c.text_reviewed = False
    if changes.get("title") is not None:
        c.title = changes["title"].strip() or c.title
    if changes.get("topic_tags") is not None:
        c.topic_tags = [t.strip().lower() for t in changes["topic_tags"] if t.strip()]
    for key in ("face_id", "voice_id"):
        if changes.get(key) is not None:
            setattr(c, key, changes[key])
    c.updated_at = clock.now()
    uow.commit()
    return c


def approve_content(uow: PracticeUnitOfWork, clock: Clock, principal: Principal, study_id: int, content_id: int) -> ContentItem:
    require_study_access(principal, study_id, StudyRole.researcher)
    c = _content_in_study(uow, study_id, content_id)
    c.ensure_draft()
    validate_content(c.definition)
    missing = missing_media(uow, c)
    if missing:
        raise Invalid("missing media: " + ", ".join(missing))
    c.status = ContentStatus.approved
    c.updated_at = clock.now()
    uow.commit()
    return c


def upload_media(uow: PracticeUnitOfWork, store: MediaStore, principal: Principal, study_id: int, content_id: int, key: str, content_type: str, data: bytes) -> ContentMedia:
    from eyetracking.infrastructure.media import safe_key  # pure string rule; kept next to the store

    require_study_access(principal, study_id, StudyRole.researcher)
    c = _content_in_study(uow, study_id, content_id)
    c.ensure_draft()
    try:
        key = safe_key(key)
    except ValueError as exc:
        raise Invalid(str(exc)) from exc
    if content_type not in MEDIA_TYPES:
        raise Invalid(f"content type must be one of {sorted(MEDIA_TYPES)}")
    if not data:
        raise Invalid("empty file")
    if len(data) > MAX_MEDIA_BYTES:
        raise Invalid("file is larger than 200 MB")
    rel = store.save(f"study-{study_id}/content-{content_id}/{key}", data)
    existing = uow.media.by_key(content_id, key)
    if existing:
        existing.path, existing.content_type, existing.size = rel, content_type, len(data)
        media = existing
    else:
        media = uow.media.add(ContentMedia(content_id=content_id, key=key, path=rel, content_type=content_type, size=len(data)))
    uow.commit()
    return media


def list_media(uow: PracticeUnitOfWork, signer: MediaSigner, principal: Principal, study_id: int, content_id: int) -> list[dict]:
    require_study_access(principal, study_id)
    c = _content_in_study(uow, study_id, content_id)
    return [{"key": m.key, "content_type": m.content_type, "size": m.size, "url": f"/media/{signer.sign(m.id or 0)}"} for m in uow.media.list_for_content(c.id or 0)]


def resolve_media(uow: PracticeUnitOfWork, signer: MediaSigner, token: str) -> ContentMedia:
    media_id = signer.verify(token)
    m = uow.media.get(media_id) if media_id is not None else None
    if m is None:
        raise NotFound("media link is invalid or has expired")
    return m


# ---------- assignments ----------


def _participant_in_study(uow: PracticeUnitOfWork, study_id: int, code: str):
    p = uow.participants.by_code(study_id, code)
    if p is None:
        raise NotFound("participant not found")
    return p


def _assignment_view(uow: PracticeUnitOfWork, a: Assignment) -> dict:
    proto = uow.protocols.get(a.protocol_id)
    content = uow.content.get(a.content_id) if a.content_id else None
    return {
        "id": a.id,
        "order_index": a.order_index,
        "status": a.status.value,
        "protocol": {"id": proto.id, "name": proto.name, "version": proto.version, "path": proto.path} if proto else None,
        "topic": a.topic,
        "topic_free_text": a.topic_free_text,
        "content_id": a.content_id,
        "content_title": content.title if content else None,
        "created_at": a.created_at,
    }


def list_assignments(uow: PracticeUnitOfWork, principal: Principal, study_id: int, code: str) -> list[dict]:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    p = _participant_in_study(uow, study_id, code)
    return [_assignment_view(uow, a) for a in uow.assignments.list_for_participant(p.id or 0)]


def create_assignment(uow: PracticeUnitOfWork, principal: Principal, study_id: int, code: str, protocol_id: int, order_index: int | None) -> dict:
    require_study_access(principal, study_id, StudyRole.researcher)
    p = _participant_in_study(uow, study_id, code)
    proto = _protocol_in_study(uow, study_id, protocol_id)
    if proto.status is not ProtocolStatus.published:
        raise Invalid("only published protocol versions can be assigned")
    existing = uow.assignments.list_for_participant(p.id or 0)
    status = AssignmentStatus.pending_topic if proto.path in ("interest_conversation", "live_conversation") else AssignmentStatus.ready
    a = uow.assignments.add(
        Assignment(participant_id=p.id or 0, study_id=study_id, protocol_id=proto.id or 0, order_index=order_index if order_index is not None else len(existing), status=status)
    )
    uow.commit()
    return _assignment_view(uow, a)


def update_assignment(uow: PracticeUnitOfWork, principal: Principal, study_id: int, code: str, assignment_id: int, content_id: int | None, status: str | None) -> dict:
    require_study_access(principal, study_id, StudyRole.researcher)
    p = _participant_in_study(uow, study_id, code)
    a = uow.assignments.get(assignment_id)
    if a is None or a.participant_id != p.id:
        raise NotFound("assignment not found")
    if a.status in (AssignmentStatus.completed, AssignmentStatus.cancelled):
        raise Conflict("this assignment is closed")
    if content_id is not None:
        c = _content_in_study(uow, study_id, content_id)
        if c.status is not ContentStatus.approved:
            raise Invalid("content must be approved before it is attached")
        proto = uow.protocols.get(a.protocol_id)
        if proto is None or proto.path != "interest_conversation":
            raise Invalid("content is only used by the interest_conversation path")
        a.content_id = c.id
        if a.status in (AssignmentStatus.pending_topic, AssignmentStatus.content_pending):
            a.status = AssignmentStatus.ready
    if status is not None:
        if status != "cancelled":
            raise Invalid("status can only be set to cancelled")
        a.status = AssignmentStatus.cancelled
    uow.commit()
    return _assignment_view(uow, a)


def my_assignments(uow: PracticeUnitOfWork, principal: Principal) -> list[dict]:
    p = require_participant(principal)
    return [_assignment_view(uow, a) for a in uow.assignments.list_for_participant(p.id or 0)]


def _own_assignment(uow: PracticeUnitOfWork, principal: Principal, assignment_id: int) -> Assignment:
    p = require_participant(principal)
    a = uow.assignments.get(assignment_id)
    if a is None or a.participant_id != p.id:
        raise NotFound("assignment not found")
    return a


def confirm_topic(uow: PracticeUnitOfWork, principal: Principal, assignment_id: int, topic: str, free_text: str | None) -> dict:
    a = _own_assignment(uow, principal, assignment_id)
    if a.status not in (AssignmentStatus.pending_topic, AssignmentStatus.content_pending):
        raise Conflict("the topic can no longer be changed for this assignment")
    if not (topic or "").strip() or len(topic) > 200:
        raise Invalid("topic is required (up to 200 characters)")
    a.topic = topic.strip()
    a.topic_free_text = (free_text or "").strip()[:2000] or None
    proto = uow.protocols.get(a.protocol_id)
    # the live avatar needs no prepared content: the confirmed topic is what it may talk about
    a.status = AssignmentStatus.ready if proto is not None and proto.path == "live_conversation" else AssignmentStatus.content_pending
    uow.commit()
    return _assignment_view(uow, a)


def my_assignment_content(uow: PracticeUnitOfWork, signer: MediaSigner, principal: Principal, assignment_id: int) -> dict:
    a = _own_assignment(uow, principal, assignment_id)
    if a.status not in (AssignmentStatus.ready, AssignmentStatus.in_progress) or a.content_id is None:
        raise NotFound("content is not ready yet")
    c = uow.content.get(a.content_id)
    if c is None or c.status is not ContentStatus.approved:
        raise NotFound("content is not ready yet")
    profile = uow.profiles.get(a.participant_id)
    name = profile.display_name if profile else None
    media = {m.key: m for m in uow.media.list_for_content(c.id or 0)}
    segments = []
    for seg in c.definition.get("segments", []):
        m = media.get(seg.get("media_key") or "")
        q = seg.get("question")
        segments.append(
            {
                "id": seg["id"],
                "text": personalize(seg.get("text", ""), name, a.topic),
                "media_key": seg.get("media_key"),
                "media_url": f"/media/{signer.sign(m.id or 0)}" if m else None,
                "duration_s": seg.get("duration_s"),
                "face_layout": seg.get("face_layout"),
                "question": {"id": q["id"], "prompt": personalize(q["prompt"], name, a.topic), "options": [personalize(o, name, a.topic) for o in q["options"]]} if q else None,
            }
        )
    return {
        "title": c.title,
        "face_id": c.face_id,
        "voice_id": c.voice_id,
        "start_segment": c.definition.get("start_segment"),
        "post_segment": c.definition.get("post_segment"),
        "segments": segments,
        "comprehension": [{"id": q["id"], "prompt": personalize(q["prompt"], name, a.topic), "options": [personalize(o, name, a.topic) for o in q["options"]]} for q in c.definition.get("comprehension", [])],
    }


# ---------- session hooks (called from the measurement use cases) ----------


def bind_assignment(uow: PracticeUnitOfWork, principal: Principal, session: Session, assignment_id: int) -> None:
    a = _own_assignment(uow, principal, assignment_id)
    if a.status not in (AssignmentStatus.ready, AssignmentStatus.in_progress):
        raise Conflict(f"assignment is not ready (status: {a.status.value})")
    proto = uow.protocols.get(a.protocol_id)
    if proto is None or proto.status is not ProtocolStatus.published:
        raise Conflict("the assigned protocol is not published")
    session.assignment_id = a.id
    session.protocol_id = proto.id
    a.status = AssignmentStatus.in_progress


def on_session_end(uow: PracticeUnitOfWork, session: Session) -> None:
    if session.assignment_id and session.end_reason == "completed":
        a = uow.assignments.get(session.assignment_id)
        if a is not None and a.status is AssignmentStatus.in_progress:
            a.status = AssignmentStatus.completed


def validate_comfort_payload(uow: PracticeUnitOfWork, session: Session, payload: dict) -> None:
    if session.protocol_id is None:
        return
    proto = uow.protocols.get(session.protocol_id)
    scale_max = int((proto.definition.get("comfort") or {}).get("scale_max", 5)) if proto else 5
    value = payload.get("value")
    if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= scale_max:
        raise Invalid(f"comfort value must be an integer between 1 and {scale_max}")


def _session_protocol(uow: PracticeUnitOfWork, session: Session) -> Protocol:
    if session.protocol_id is None:
        raise Conflict("this session runs no protocol")
    proto = uow.protocols.get(session.protocol_id)
    if proto is None:
        raise Conflict("protocol not found")
    return proto


def _own_open_session(uow: PracticeUnitOfWork, principal: Principal, session_id: int) -> Session:
    p = require_participant(principal)
    s = uow.sessions.get(session_id)
    if s is None or s.participant_id != p.id:
        raise NotFound("session not found")
    s.ensure_open()
    return s


def add_trials(uow: PracticeUnitOfWork, principal: Principal, session_id: int, items: list[dict]) -> tuple[int, int]:
    s = _own_open_session(uow, principal, session_id)
    proto = _session_protocol(uow, s)
    if proto.path != "gradual_face":
        raise Conflict("trials belong to the gradual_face path")
    if not 1 <= len(items) <= MAX_TRIAL_BATCH:
        raise Invalid(f"1 to {MAX_TRIAL_BATCH} trials per batch")
    stages = proto.definition["gradual"]["stages"]
    rows: list[Trial] = []
    for it in items:
        idx = int(it.get("stage_index", -1))
        if not 0 <= idx < len(stages):
            raise Invalid("stage_index is out of range")
        stage = stages[idx]
        zone = it.get("zone")
        if zone != stage["number_zone"] or zone not in ZONES:
            raise Invalid(f"trial zone {zone} does not match stage {idx} ({stage['number_zone']})")
        if int(it.get("face_level", -1)) != int(stage["face_level"]):
            raise Invalid(f"trial face_level does not match stage {idx}")
        shown = str(it.get("number_shown", "")).strip()
        if not shown:
            raise Invalid("number_shown is required")
        response = it.get("response")
        response = str(response).strip() if response is not None else None
        rows.append(
            Trial(
                session_id=s.id or 0,
                stage_index=idx,
                trial_index=int(it.get("trial_index", 0)),
                t_ms=int(it.get("t_ms", 0)),
                number_shown=shown,
                zone=zone,
                position=dict(it.get("position") or {}),
                face_level=int(stage["face_level"]),
                response=response,
                correct=(response == shown),
                response_ms=int(it["response_ms"]) if it.get("response_ms") is not None else None,
            )
        )
    stored = uow.trials.add_many(rows)
    uow.commit()
    return stored, sum(1 for r in rows if r.correct)


def stage_result(uow: PracticeUnitOfWork, principal: Principal, session_id: int, stage_index: int, comfort_value: int | None) -> StageResult:
    s = _own_open_session(uow, principal, session_id)
    proto = _session_protocol(uow, s)
    if proto.path != "gradual_face":
        raise Conflict("stage results belong to the gradual_face path")
    if comfort_value is not None:
        validate_comfort_payload(uow, s, {"value": comfort_value})
    results = uow.stage_results.for_session(s.id or 0)
    all_trials = uow.trials.for_session(s.id or 0)
    last_id = results[-1].id if results else 0
    attempt = [t for t in all_trials if t.stage_index == stage_index and (t.id or 0) > _trial_marker(results, all_trials)]
    last_trial_id = max((t.id or 0 for t in all_trials), default=0)
    invalid_share = 0.0
    if attempt:
        t0 = min(t.t_ms for t in attempt)
        seconds = float(proto.definition["gradual"]["stages"][stage_index].get("trial_seconds", 8))
        t1 = max(t.t_ms for t in attempt) + int(seconds * 1000)
        window = [x for x in uow.samples.for_session(s.id or 0) if x.segment == "practice" and t0 <= x.t_ms <= t1]
        if window:
            invalid_share = sum(1 for x in window if x.region == "uncertain") / len(window)
    min_ok = int((proto.definition.get("comfort") or {}).get("min_ok", 3))
    streak = 0
    for r in reversed(results):
        if r.comfort_value is not None and r.comfort_value < min_ok:
            streak += 1
        else:
            break
    decision = evaluate_stage(proto.definition, stage_index, attempt, comfort_value, round(invalid_share, 4), streak)
    r = uow.stage_results.add(
        StageResult(
            session_id=s.id or 0,
            stage_index=stage_index,
            decision=decision.decision,
            reason=decision.reason,
            correct_ratio=decision.correct_ratio,
            invalid_share=decision.invalid_share,
            comfort_value=comfort_value,
            trials=decision.trials,
            next_stage_index=decision.next_stage_index,
            last_trial_id=last_trial_id,
        )
    )
    uow.commit()
    return r


def _trial_marker(results: list[StageResult], trials: list[Trial]) -> int:
    """Id of the last trial that belongs to an earlier, already evaluated attempt."""
    if not results:
        return 0
    return max((t.id or 0 for t in trials if _trial_created_before(t, results[-1])), default=0)


def _trial_created_before(trial: Trial, last: StageResult) -> bool:
    return (trial.id or 0) <= (last.last_trial_id or 0)


def answer(uow: PracticeUnitOfWork, principal: Principal, session_id: int, segment_id: str, question_id: str, kind: str, option: str, t_ms: int) -> Answer:
    s = _own_open_session(uow, principal, session_id)
    proto = _session_protocol(uow, s)
    if proto.path != "interest_conversation":
        raise Conflict("answers belong to the interest_conversation path")
    if kind not in ANSWER_KINDS:
        raise Invalid(f"kind must be one of {ANSWER_KINDS}")
    a = uow.assignments.get(s.assignment_id or 0)
    c = uow.content.get(a.content_id) if a and a.content_id else None
    if c is None:
        raise Conflict("no content is attached to this session")
    profile = uow.profiles.get(s.participant_id)
    name = profile.display_name if profile else None
    if kind == "interaction":
        nxt = next_segment(c.definition, segment_id, option, name, a.topic)
        correct = None
    else:
        nxt = None
        correct = comprehension_correct(c.definition, question_id, option, name, a.topic)
    row = uow.answers.add(Answer(session_id=s.id or 0, segment_id=segment_id, question_id=question_id, kind=kind, option=option, correct=correct, t_ms=int(t_ms), next_segment_id=nxt))
    uow.commit()
    return row


# ---------- outcomes ----------


def _segment_eye_share(samples, events, label: str) -> float | None:
    last_t = max((x.t_ms for x in samples), default=None)
    segs = [sg for sg in segments_from_events(events, last_t) if sg["label"] == label]
    if not segs:
        return None
    cov = coverage([x for x in samples if x.segment == label], segs)
    shares = region_shares(cov)
    return shares["eye"] if shares else None


def practice_summary(uow: PracticeUnitOfWork, s: Session, base: dict) -> dict:
    """Adds protocol, outcomes and stages to a session summary. Safe for sessions without a protocol."""
    proto = uow.protocols.get(s.protocol_id) if s.protocol_id else None
    definition = proto.definition if proto else {}
    samples = uow.samples.for_session(s.id or 0)
    events = uow.events.for_session(s.id or 0)
    eye = base.get("eye_region_attention") or {}
    b_share = _segment_eye_share(samples, events, "baseline")
    p_share = _segment_eye_share(samples, events, "post")
    gaze = {
        "baseline_eye_share": b_share,
        "post_eye_share": p_share,
        "evaluable": bool(eye.get("evaluable")) and b_share is not None and p_share is not None,
        "reason": eye.get("reason") or (None if (b_share is not None and p_share is not None) else "baseline_or_post_missing"),
    }
    answers = uow.answers.for_session(s.id or 0)
    comp = [a for a in answers if a.kind == "comprehension"]
    comprehension = {"answered": len(comp), "correct": sum(1 for a in comp if a.correct), "share": round(sum(1 for a in comp if a.correct) / len(comp), 4) if comp else None}
    trials = uow.trials.for_session(s.id or 0)
    stage_rows = uow.stage_results.for_session(s.id or 0)
    number_task = {
        "trials": len(trials),
        "correct": sum(1 for t in trials if t.correct),
        "share": round(sum(1 for t in trials if t.correct) / len(trials), 4) if trials else None,
        "stages_completed": sum(1 for r in stage_rows if r.decision in ("advance", "complete")),
    }
    comfort_values = [int(e.payload.get("value")) for e in events if e.type == "comfort_answer" and isinstance(e.payload.get("value"), int)]
    min_ok = int((definition.get("comfort") or {}).get("min_ok", 3))
    comfort = comfort_outcome(comfort_values, min_ok, sum(1 for e in events if e.type == "pause"), s.end_reason == "ended_early")
    out = dict(base)
    out["assignment_id"] = s.assignment_id
    out["protocol"] = {"id": proto.id, "name": proto.name, "version": proto.version, "path": proto.path, "definition": proto.definition} if proto else None
    conversation = None
    if proto is not None and proto.path == "live_conversation" and getattr(uow, "live", None) is not None:
        from eyetracking.domain.live import conversation_outcome

        conv = uow.live.conversation_for_session(s.id or 0)
        conversation = conversation_outcome(uow.live.turns(conv.id or 0), conv.end_reason) if conv else conversation_outcome([], None)
    out["outcomes"] = {
        "gaze": gaze,
        "comprehension": comprehension,
        "number_task": number_task,
        "comfort": comfort,
        "conversation": conversation,
        "improvement": improvement(gaze, comprehension, number_task, comfort_values, min_ok, proto.path if proto else None, conversation),
    }
    out["stages"] = [
        {"stage_index": r.stage_index, "decision": r.decision, "reason": r.reason, "correct_ratio": r.correct_ratio, "invalid_share": r.invalid_share, "comfort_value": r.comfort_value, "trials": r.trials, "next_stage_index": r.next_stage_index}
        for r in stage_rows
    ]
    return out


def practice_detail(uow: PracticeUnitOfWork, s: Session) -> dict:
    events = uow.events.for_session(s.id or 0)
    return {
        "trials": [
            {"stage_index": t.stage_index, "trial_index": t.trial_index, "t_ms": t.t_ms, "number_shown": t.number_shown, "zone": t.zone, "position": t.position, "face_level": t.face_level, "response": t.response, "correct": t.correct, "response_ms": t.response_ms}
            for t in uow.trials.for_session(s.id or 0)[:500]
        ],
        "answers": [
            {"segment_id": a.segment_id, "question_id": a.question_id, "kind": a.kind, "option": a.option, "correct": a.correct, "t_ms": a.t_ms, "next_segment_id": a.next_segment_id}
            for a in uow.answers.for_session(s.id or 0)
        ],
        "comfort_answers": [{"t_ms": e.t_ms, **{k: v for k, v in e.payload.items() if k in ("value", "stage_index", "segment")}} for e in events if e.type == "comfort_answer"],
    }
