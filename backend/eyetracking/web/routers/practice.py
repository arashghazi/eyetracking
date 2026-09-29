"""Step 3 endpoints: protocols, content and media, assignments, trials, stage results, answers."""
from __future__ import annotations

import os
from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter, Depends, File, Request, UploadFile
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

from eyetracking.application import practice_use_cases as uc
from eyetracking.application.authz import Principal
from eyetracking.domain.errors import Invalid
from eyetracking.domain.practice import ContentItem, Protocol

from ..deps import get_clock, get_principal, get_uow

router = APIRouter(tags=["practice"])


def get_media_store(request: Request):
    return request.app.state.media_store


def get_media_signer(request: Request):
    return request.app.state.media_signer


# ---------- schemas ----------


class ProtocolIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    definition: dict[str, Any]


class ProtocolPatch(BaseModel):
    name: str | None = None
    definition: dict[str, Any] | None = None


class ProtocolOut(BaseModel):
    id: int
    name: str
    version: int
    status: str
    path: str
    created_at: datetime
    published_at: datetime | None
    definition: dict[str, Any] | None = None


class ContentIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    definition: dict[str, Any]
    topic_tags: list[str] = Field(default_factory=list)
    face_id: str = ""
    voice_id: str = ""


class ContentPatch(BaseModel):
    title: str | None = None
    definition: dict[str, Any] | None = None
    topic_tags: list[str] | None = None
    face_id: str | None = None
    voice_id: str | None = None


class ContentOut(BaseModel):
    id: int
    title: str
    topic_tags: list[str]
    face_id: str
    voice_id: str
    status: str
    text_reviewed: bool = False
    media_keys: list[str]
    missing_media: list[str]
    definition: dict[str, Any] | None = None


class AssignmentIn(BaseModel):
    protocol_id: int
    order_index: int | None = None


class AssignmentPatch(BaseModel):
    content_id: int | None = None
    status: Literal["cancelled"] | None = None


class TopicIn(BaseModel):
    topic: str = Field(min_length=1, max_length=200)
    free_text: str | None = None


class TrialIn(BaseModel):
    stage_index: int
    trial_index: int = 0
    t_ms: int
    number_shown: str
    zone: str
    position: dict[str, Any] = Field(default_factory=dict)
    face_level: int
    response: str | None = None
    response_ms: int | None = None


class TrialsIn(BaseModel):
    trials: list[TrialIn] = Field(min_length=1, max_length=200)


class StageResultIn(BaseModel):
    stage_index: int
    comfort_value: int | None = None


class StageResultOut(BaseModel):
    decision: str
    next_stage_index: int | None
    reason: str
    correct_ratio: float | None
    invalid_share: float
    trials: int


class AnswerIn(BaseModel):
    segment_id: str
    question_id: str
    kind: Literal["interaction", "comprehension"]
    option: str
    t_ms: int


class AnswerOut(BaseModel):
    correct: bool | None
    next_segment_id: str | None


def _protocol_out(p: Protocol, with_definition: bool) -> ProtocolOut:
    return ProtocolOut(id=p.id or 0, name=p.name, version=p.version, status=p.status.value, path=p.path, created_at=p.created_at, published_at=p.published_at, definition=p.definition if with_definition else None)


def _content_out(c: ContentItem, missing: list[str], with_definition: bool) -> ContentOut:
    return ContentOut(id=c.id or 0, title=c.title, topic_tags=list(c.topic_tags), face_id=c.face_id, voice_id=c.voice_id, status=c.status.value, text_reviewed=bool(c.text_reviewed), media_keys=c.media_keys(), missing_media=missing, definition=c.definition if with_definition else None)


# ---------- protocols ----------


@router.get("/studies/{study_id}/protocols", response_model=list[ProtocolOut])
def list_protocols(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return [_protocol_out(p, False) for p in uc.list_protocols(uow, principal, study_id)]


@router.post("/studies/{study_id}/protocols", response_model=ProtocolOut, status_code=201)
def create_protocol(study_id: int, body: ProtocolIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _protocol_out(uc.create_protocol(uow, principal, study_id, body.name, body.definition), True)


@router.get("/studies/{study_id}/protocols/{protocol_id}", response_model=ProtocolOut)
def get_protocol(study_id: int, protocol_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _protocol_out(uc.get_protocol(uow, principal, study_id, protocol_id), True)


@router.put("/studies/{study_id}/protocols/{protocol_id}", response_model=ProtocolOut)
def update_protocol(study_id: int, protocol_id: int, body: ProtocolPatch, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _protocol_out(uc.update_protocol(uow, principal, study_id, protocol_id, body.name, body.definition), True)


@router.post("/studies/{study_id}/protocols/{protocol_id}/publish", response_model=ProtocolOut)
def publish_protocol(study_id: int, protocol_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    return _protocol_out(uc.publish_protocol(uow, clock, principal, study_id, protocol_id), True)


@router.post("/studies/{study_id}/protocols/{protocol_id}/new-draft", response_model=ProtocolOut, status_code=201)
def new_draft(study_id: int, protocol_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _protocol_out(uc.new_draft_from(uow, principal, study_id, protocol_id), True)


# ---------- content and media ----------


@router.get("/studies/{study_id}/content", response_model=list[ContentOut])
def list_content(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return [_content_out(c, missing, False) for c, missing in uc.list_content(uow, principal, study_id)]


@router.post("/studies/{study_id}/content", response_model=ContentOut, status_code=201)
def create_content(study_id: int, body: ContentIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    c = uc.create_content(uow, clock, principal, study_id, body.title, body.definition, body.topic_tags, body.face_id, body.voice_id)
    return _content_out(c, uc.missing_media(uow, c), True)


@router.get("/studies/{study_id}/content/{content_id}", response_model=ContentOut)
def get_content(study_id: int, content_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    c, missing = uc.get_content(uow, principal, study_id, content_id)
    return _content_out(c, missing, True)


@router.put("/studies/{study_id}/content/{content_id}", response_model=ContentOut)
def update_content(study_id: int, content_id: int, body: ContentPatch, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    c = uc.update_content(uow, clock, principal, study_id, content_id, **body.model_dump(exclude_unset=True))
    return _content_out(c, uc.missing_media(uow, c), True)


@router.post("/studies/{study_id}/content/{content_id}/approve", response_model=ContentOut)
def approve_content(study_id: int, content_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    c = uc.approve_content(uow, clock, principal, study_id, content_id)
    return _content_out(c, [], True)


@router.post("/studies/{study_id}/content/{content_id}/media/{key}", status_code=201)
async def upload_media(study_id: int, content_id: int, key: str, file: UploadFile = File(...), principal: Principal = Depends(get_principal), uow=Depends(get_uow), store=Depends(get_media_store)):
    data = await file.read()
    m = uc.upload_media(uow, store, principal, study_id, content_id, key, file.content_type or "", data)
    return {"key": m.key, "content_type": m.content_type, "size": m.size}


@router.get("/studies/{study_id}/content/{content_id}/media")
def list_media(study_id: int, content_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), signer=Depends(get_media_signer)):
    return uc.list_media(uow, signer, principal, study_id, content_id)


@router.get("/media/{token}")
def stream_media(token: str, request: Request, uow=Depends(get_uow), signer=Depends(get_media_signer), store=Depends(get_media_store)):
    m = uc.resolve_media(uow, signer, token)
    path = store.absolute(m.path)
    if not os.path.exists(path):
        raise Invalid("media file is missing on disk")
    size = os.path.getsize(path)
    start, end = 0, size - 1
    rng = request.headers.get("range")
    status = 200
    if rng and rng.startswith("bytes="):
        spec = rng[6:].split(",")[0].strip()
        a, _, b = spec.partition("-")
        try:
            if a:
                start = int(a)
                end = int(b) if b else size - 1
            else:
                start = max(0, size - int(b))
        except ValueError:
            start, end = 0, size - 1
        end = min(end, size - 1)
        if start > end or start >= size:
            return Response(status_code=416, headers={"Content-Range": f"bytes */{size}"})
        status = 206
    length = end - start + 1

    def iterate(chunk: int = 1024 * 256):
        with open(path, "rb") as fh:
            fh.seek(start)
            remaining = length
            while remaining > 0:
                data = fh.read(min(chunk, remaining))
                if not data:
                    break
                remaining -= len(data)
                yield data

    headers = {"Accept-Ranges": "bytes", "Content-Length": str(length), "Cache-Control": "private, max-age=3600"}
    if status == 206:
        headers["Content-Range"] = f"bytes {start}-{end}/{size}"
    return StreamingResponse(iterate(), status_code=status, media_type=m.content_type, headers=headers)


# ---------- assignments ----------


@router.get("/studies/{study_id}/participants/{code}/assignments")
def list_assignments(study_id: int, code: str, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.list_assignments(uow, principal, study_id, code)


@router.post("/studies/{study_id}/participants/{code}/assignments", status_code=201)
def create_assignment(study_id: int, code: str, body: AssignmentIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.create_assignment(uow, principal, study_id, code, body.protocol_id, body.order_index)


@router.put("/studies/{study_id}/participants/{code}/assignments/{assignment_id}")
def update_assignment(study_id: int, code: str, assignment_id: int, body: AssignmentPatch, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.update_assignment(uow, principal, study_id, code, assignment_id, body.content_id, body.status)


@router.get("/me/assignments")
def my_assignments(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.my_assignments(uow, principal)


@router.post("/me/assignments/{assignment_id}/topic")
def confirm_topic(assignment_id: int, body: TopicIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.confirm_topic(uow, principal, assignment_id, body.topic, body.free_text)


@router.get("/me/assignments/{assignment_id}/content")
def my_content(assignment_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), signer=Depends(get_media_signer)):
    return uc.my_assignment_content(uow, signer, principal, assignment_id)


# ---------- practice recording ----------


@router.post("/me/sessions/{session_id}/trials")
def add_trials(session_id: int, body: TrialsIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    stored, correct = uc.add_trials(uow, principal, session_id, [t.model_dump() for t in body.trials])
    return {"stored": stored, "correct": correct}


@router.post("/me/sessions/{session_id}/stage-result", response_model=StageResultOut)
def stage_result(session_id: int, body: StageResultIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    r = uc.stage_result(uow, principal, session_id, body.stage_index, body.comfort_value)
    return StageResultOut(decision=r.decision, next_stage_index=r.next_stage_index, reason=r.reason, correct_ratio=r.correct_ratio, invalid_share=r.invalid_share, trials=r.trials)


@router.post("/me/sessions/{session_id}/answers", response_model=AnswerOut)
def answer(session_id: int, body: AnswerIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    a = uc.answer(uow, principal, session_id, body.segment_id, body.question_id, body.kind, body.option, body.t_ms)
    return AnswerOut(correct=a.correct, next_segment_id=a.next_segment_id)
