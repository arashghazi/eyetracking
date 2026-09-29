"""Step 5 endpoints: AI status and budget, text and video jobs, review flow, run queued jobs."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field

from eyetracking.application import ai_use_cases as uc
from eyetracking.application.authz import Principal

from ..deps import get_clock, get_principal, get_uow
from .practice import _content_out, get_media_store

router = APIRouter(tags=["ai"])


def get_providers(request: Request) -> uc.Providers:
    return request.app.state.ai_providers


class BudgetIn(BaseModel):
    cost_cap_units: float | None = None
    send_free_text: bool | None = None


class TextJobIn(BaseModel):
    assignment_id: int | None = None
    topic: str | None = None
    display_name: str | None = None
    interests: list[str] | None = None
    interaction_points: int = 2
    length_seconds: int = 90
    title: str | None = None
    face_id: str = ""
    voice_id: str = ""


class VideoJobsIn(BaseModel):
    content_id: int
    segment_ids: list[str] | None = None
    face_id: str | None = None
    voice_id: str | None = None


@router.get("/studies/{study_id}/ai/status")
def ai_status(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), providers=Depends(get_providers)):
    return uc.status(uow, providers, principal, study_id)


@router.put("/studies/{study_id}/ai/budget")
def set_budget(study_id: int, body: BudgetIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.set_budget(uow, principal, study_id, body.cost_cap_units, body.send_free_text)


@router.post("/studies/{study_id}/ai/text-jobs", status_code=201)
def create_text_job(study_id: int, body: TextJobIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), providers=Depends(get_providers), clock=Depends(get_clock)):
    return uc.create_text_job(uow, providers, clock, principal, study_id, body.assignment_id, body.topic, body.display_name, body.interests, body.interaction_points, body.length_seconds, body.title, body.face_id, body.voice_id)


@router.post("/studies/{study_id}/ai/video-jobs", status_code=201)
def create_video_jobs(study_id: int, body: VideoJobsIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), providers=Depends(get_providers), clock=Depends(get_clock)):
    return uc.create_video_jobs(uow, providers, clock, principal, study_id, body.content_id, body.segment_ids, body.face_id, body.voice_id)


@router.get("/studies/{study_id}/ai/jobs")
def list_jobs(study_id: int, status: str | None = None, content_id: int | None = None, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.list_jobs(uow, principal, study_id, status, content_id)


@router.get("/studies/{study_id}/ai/jobs/{job_id}")
def get_job(study_id: int, job_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.get_job(uow, principal, study_id, job_id)


@router.post("/studies/{study_id}/ai/jobs/{job_id}/cancel")
def cancel_job(study_id: int, job_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.cancel_job(uow, principal, study_id, job_id)


@router.post("/studies/{study_id}/ai/jobs/{job_id}/retry")
def retry_job(study_id: int, job_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    return uc.retry_job(uow, clock, principal, study_id, job_id)


@router.post("/studies/{study_id}/ai/run")
def run_jobs(study_id: int, max_jobs: int = Query(5, ge=1, le=50), principal: Principal = Depends(get_principal), uow=Depends(get_uow), providers=Depends(get_providers), store=Depends(get_media_store), clock=Depends(get_clock)):
    return uc.run_jobs(uow, providers, store, clock, max_jobs=max_jobs, principal=principal, study_id=study_id)


@router.post("/studies/{study_id}/content/{content_id}/text-reviewed")
def text_reviewed(study_id: int, content_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    from eyetracking.application.practice_use_cases import missing_media

    c = uc.mark_text_reviewed(uow, clock, principal, study_id, content_id)
    return _content_out(c, missing_media(uow, c), True)
