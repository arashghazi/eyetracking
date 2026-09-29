"""Use cases for build step 5: AI text and video generation jobs, review flow, budget and worker."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from eyetracking.domain.ai import AiBudget, GenerationJob, TextRequest, assign_media_keys, branches_to_dict
from eyetracking.domain.errors import Conflict, Invalid, NotFound
from eyetracking.domain.models import Role, StudyRole
from eyetracking.domain.practice import AssignmentStatus, ContentItem, ContentMedia, ContentStatus, validate_content

from .authz import Principal, require_role, require_study_access
from .ports import AiUnitOfWork, Clock, MediaStore, TextGenerator, VideoGenerator
from .research_use_cases import log_access


@dataclass
class Providers:
    text: TextGenerator
    video: VideoGenerator
    worker_enabled: bool = False
    worker_interval_s: int = 5


# ---------- status and budget ----------


def budget_for(uow: AiUnitOfWork, study_id: int) -> AiBudget:
    return uow.ai_budgets.get(study_id) or AiBudget(study_id=study_id)


def status(uow: AiUnitOfWork, providers: Providers, principal: Principal, study_id: int) -> dict:
    require_study_access(principal, study_id)
    b = budget_for(uow, study_id)
    return {
        "text_provider": providers.text.info(),
        "video_provider": providers.video.info(),
        "budget": {"cost_cap_units": b.cost_cap_units, "spent_units": round(b.spent_units, 4), "remaining_units": round(b.remaining(), 4), "unit": "usd_estimate"},
        "worker": {"enabled": providers.worker_enabled, "interval_s": providers.worker_interval_s},
        "send_free_text": b.send_free_text,
    }


def set_budget(uow: AiUnitOfWork, principal: Principal, study_id: int, cost_cap_units: float | None, send_free_text: bool | None) -> dict:
    require_role(principal, Role.admin)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    b = budget_for(uow, study_id)
    if cost_cap_units is not None:
        if cost_cap_units < 0 or cost_cap_units > 1_000_000:
            raise Invalid("cost_cap_units must be between 0 and 1000000")
        b.cost_cap_units = float(cost_cap_units)
    if send_free_text is not None:
        b.send_free_text = bool(send_free_text)
    b = uow.ai_budgets.save(b)
    log_access(uow, principal, study_id, "ai_budget_changed", {"cost_cap_units": b.cost_cap_units, "send_free_text": b.send_free_text})
    uow.commit()
    return {"cost_cap_units": b.cost_cap_units, "spent_units": round(b.spent_units, 4), "remaining_units": round(b.remaining(), 4), "unit": "usd_estimate", "send_free_text": b.send_free_text}


# ---------- jobs ----------


def _job_view(uow: AiUnitOfWork, j: GenerationJob) -> dict:
    content = uow.content.get(j.content_id)
    return {
        "id": j.id,
        "kind": j.kind,
        "status": j.status,
        "provider": j.provider,
        "content_id": j.content_id,
        "content_title": content.title if content else None,
        "assignment_id": j.assignment_id,
        "segment_id": j.segment_id,
        "attempts": j.attempts,
        "max_attempts": j.max_attempts,
        "cost_estimate_units": j.cost_estimate_units,
        "cost_actual_units": j.cost_actual_units,
        "error": j.error,
        "created_at": j.created_at,
        "started_at": j.started_at,
        "finished_at": j.finished_at,
        "next_attempt_at": j.next_attempt_at,
        "request": j.request,
        "result": j.result,
    }


def create_text_job(
    uow: AiUnitOfWork, providers: Providers, clock: Clock, principal: Principal, study_id: int, assignment_id: int | None, topic: str | None, display_name: str | None,
    interests: list[str] | None, interaction_points: int, length_seconds: int, title: str | None, face_id: str, voice_id: str,
) -> dict:
    require_study_access(principal, study_id, StudyRole.researcher)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    info = providers.text.info()
    if not info.get("configured"):
        raise Invalid(f"provider_not_configured: text provider {info.get('name')} has no key")
    b = budget_for(uow, study_id)
    free_text = None
    if assignment_id is not None:
        a = uow.assignments.get(assignment_id)
        if a is None or a.study_id != study_id:
            raise NotFound("assignment not found")
        if a.status not in (AssignmentStatus.pending_topic, AssignmentStatus.content_pending):
            raise Conflict(f"assignment is {a.status.value}; text is generated only while content is pending")
        profile = uow.profiles.get(a.participant_id)
        topic = topic or a.topic
        display_name = display_name if display_name is not None else (profile.display_name if profile else None)
        interests = interests if interests is not None else (list(profile.interests) if profile else [])
        if b.send_free_text:
            free_text = a.topic_free_text
    req = TextRequest(topic=(topic or "").strip(), display_name=(display_name or None), interests=tuple(i.strip() for i in (interests or []) if i.strip()), interaction_points=int(interaction_points), length_seconds=int(length_seconds), free_text=free_text)
    req.validate()
    estimate = providers.text.estimate_cost(req)
    b.assert_affordable(estimate)
    content = uow.content.add(
        ContentItem(study_id=study_id, title=(title or f"AI draft: {req.topic}")[:200], definition={"start_segment": "s1", "post_segment": "s1", "segments": [{"id": "s1", "text": "(generating…)", "duration_s": 10, "question": None}], "comprehension": []}, topic_tags=[req.topic.lower()], face_id=face_id or "", voice_id=voice_id or "", created_at=clock.now(), updated_at=clock.now())
    )
    job = uow.jobs.add(GenerationJob(study_id=study_id, kind="text", provider=info["name"], content_id=content.id or 0, assignment_id=assignment_id, cost_estimate_units=estimate, request=req.minimized()))
    log_access(uow, principal, study_id, "ai_job_created", {"job_id": job.id, "kind": "text", "provider": info["name"], "estimate": estimate})
    uow.commit()
    return _job_view(uow, job)


def create_video_jobs(uow: AiUnitOfWork, providers: Providers, clock: Clock, principal: Principal, study_id: int, content_id: int, segment_ids: list[str] | None, face_id: str | None, voice_id: str | None) -> list[dict]:
    require_study_access(principal, study_id, StudyRole.researcher)
    c = uow.content.get(content_id)
    if c is None or c.study_id != study_id:
        raise NotFound("content not found")
    c.ensure_draft()
    if not c.text_reviewed:
        raise Conflict("mark the text as reviewed before generating videos")
    info = providers.video.info()
    if not info.get("configured"):
        raise Invalid(f"provider_not_configured: video provider {info.get('name')} has no key")
    face = face_id or c.face_id
    voice = voice_id or c.voice_id
    if face_id or voice_id:
        c.face_id, c.voice_id = face, voice
    present = {m.key for m in uow.media.list_for_content(c.id or 0)}
    wanted = set(segment_ids or [])
    targets = [seg for seg in c.definition.get("segments", []) if seg.get("media_key") and seg["media_key"] not in present and (not wanted or seg["id"] in wanted)]
    if not targets:
        raise Invalid("every selected segment already has media")
    b = budget_for(uow, study_id)
    total = sum(providers.video.estimate_cost(seg.get("text", ""), float(seg.get("duration_s") or 0)) for seg in targets)
    b.assert_affordable(total)
    jobs = []
    for seg in targets:
        est = providers.video.estimate_cost(seg.get("text", ""), float(seg.get("duration_s") or 0))
        j = uow.jobs.add(GenerationJob(study_id=study_id, kind="video", provider=info["name"], content_id=c.id or 0, segment_id=seg["id"], cost_estimate_units=est, request={"segment_id": seg["id"], "media_key": seg["media_key"], "face_id": face, "voice_id": voice, "chars": len(seg.get("text", ""))}))
        jobs.append(j)
    log_access(uow, principal, study_id, "ai_job_created", {"job_ids": [j.id for j in jobs], "kind": "video", "provider": info["name"], "estimate": round(total, 4)})
    uow.commit()
    return [_job_view(uow, j) for j in jobs]


def list_jobs(uow: AiUnitOfWork, principal: Principal, study_id: int, status_: str | None, content_id: int | None) -> list[dict]:
    require_study_access(principal, study_id)
    return [_job_view(uow, j) for j in uow.jobs.list_for_study(study_id, status_, content_id)]


def _study_job(uow: AiUnitOfWork, principal: Principal, study_id: int, job_id: int) -> GenerationJob:
    require_study_access(principal, study_id, StudyRole.researcher)
    j = uow.jobs.get(job_id)
    if j is None or j.study_id != study_id:
        raise NotFound("job not found")
    return j


def get_job(uow: AiUnitOfWork, principal: Principal, study_id: int, job_id: int) -> dict:
    require_study_access(principal, study_id)
    j = uow.jobs.get(job_id)
    if j is None or j.study_id != study_id:
        raise NotFound("job not found")
    return _job_view(uow, j)


def cancel_job(uow: AiUnitOfWork, principal: Principal, study_id: int, job_id: int) -> dict:
    j = _study_job(uow, principal, study_id, job_id)
    j.cancel()
    uow.commit()
    return _job_view(uow, j)


def retry_job(uow: AiUnitOfWork, clock: Clock, principal: Principal, study_id: int, job_id: int) -> dict:
    j = _study_job(uow, principal, study_id, job_id)
    j.retry(clock.now())
    uow.commit()
    return _job_view(uow, j)


def mark_text_reviewed(uow: AiUnitOfWork, clock: Clock, principal: Principal, study_id: int, content_id: int) -> ContentItem:
    require_study_access(principal, study_id, StudyRole.researcher)
    c = uow.content.get(content_id)
    if c is None or c.study_id != study_id:
        raise NotFound("content not found")
    c.ensure_draft()
    validate_content(c.definition)
    c.text_reviewed = True
    c.updated_at = clock.now()
    uow.commit()
    return c


# ---------- worker ----------


def run_jobs(uow: AiUnitOfWork, providers: Providers, store: MediaStore, clock: Clock, max_jobs: int = 5, principal: Principal | None = None, study_id: int | None = None) -> dict:
    """Process queued jobs whose backoff has passed. Safe to call from the worker thread or the API."""
    if principal is not None and study_id is not None:
        require_study_access(principal, study_id, StudyRole.researcher)
    processed = succeeded = failed = 0
    while processed < max_jobs:
        now = clock.now()
        j = uow.jobs.next_queued(now)
        if j is None or (study_id is not None and j.study_id != study_id):
            break
        j.status = "running"
        j.started_at = now
        uow.commit()
        processed += 1
        try:
            _execute(uow, providers, store, j)
            j.status = "succeeded"
            j.finished_at = clock.now()
            b = budget_for(uow, j.study_id)
            b.spent_units = round(b.spent_units + float(j.cost_actual_units or 0), 4)
            uow.ai_budgets.save(b)
            succeeded += 1
        except Exception as exc:  # noqa: BLE001 - every failure is recorded on the job
            from eyetracking.infrastructure.ai.fake import TerminalGenerationError

            terminal = isinstance(exc, (TerminalGenerationError, Invalid))
            j.mark_failure(f"{type(exc).__name__}: {exc}", clock.now(), terminal=terminal)
            if j.status == "failed":
                failed += 1
        uow.access_log.add(__import__("eyetracking.domain.research", fromlist=["AccessLogEntry"]).AccessLogEntry(study_id=j.study_id, user_id=principal.user_id if principal else 0, role=principal.role.value if principal else "worker", action="ai_job_run", detail={"job_id": j.id, "kind": j.kind, "status": j.status, "provider": j.provider, "cost_actual_units": j.cost_actual_units}))
        uow.commit()
    return {"processed": processed, "succeeded": succeeded, "failed": failed}


def _execute(uow: AiUnitOfWork, providers: Providers, store: MediaStore, j: GenerationJob) -> None:
    c = uow.content.get(j.content_id)
    if c is None:
        raise Invalid("content of this job no longer exists")
    if j.kind == "text":
        req = TextRequest(topic=j.request["topic"], display_name=j.request.get("display_name"), interests=tuple(j.request.get("interests") or []), interaction_points=int(j.request.get("interaction_points", 2)), length_seconds=int(j.request.get("length_seconds", 90)), free_text=None)
        if j.request.get("free_text_included") and j.assignment_id:
            a = uow.assignments.get(j.assignment_id)
            req = TextRequest(req.topic, req.display_name, req.interests, req.interaction_points, req.length_seconds, a.topic_free_text if a else None)
        raw, meta = providers.text.generate(req)
        definition = assign_media_keys(branches_to_dict(raw))
        validate_content(definition)
        c.ensure_draft()
        c.definition = definition
        c.text_reviewed = False
        c.updated_at = datetime.utcnow()
        j.cost_actual_units = float(meta.get("cost_actual_units") or 0)
        j.result = {"segments": len(definition.get("segments", [])), "comprehension": len(definition.get("comprehension", [])), "model": meta.get("model"), "input_tokens": meta.get("input_tokens"), "output_tokens": meta.get("output_tokens")}
    else:
        seg = next((s for s in c.definition.get("segments", []) if s["id"] == j.segment_id), None)
        if seg is None:
            raise Invalid("segment no longer exists in the content")
        data, ctype, meta = providers.video.generate(seg.get("text", ""), j.request.get("face_id", ""), j.request.get("voice_id", ""))
        key = seg.get("media_key") or f"{seg['id']}.webm"
        rel = store.save(f"study-{c.study_id}/content-{c.id}/{key}", data)
        existing = uow.media.by_key(c.id or 0, key)
        if existing:
            existing.path, existing.content_type, existing.size = rel, ctype, len(data)
        else:
            uow.media.add(ContentMedia(content_id=c.id or 0, key=key, path=rel, content_type=ctype, size=len(data)))
        j.cost_actual_units = float(meta.get("cost_actual_units") or 0)
        j.result = {"media_key": key, "content_type": ctype, "size": len(data), "duration_s": meta.get("duration_s"), "note": meta.get("note")}
