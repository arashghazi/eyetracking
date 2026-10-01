"""Step 7 endpoints: the live interactive avatar."""
from __future__ import annotations

from importlib import resources

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel

from eyetracking.application import live_use_cases as uc
from eyetracking.application.authz import Principal
from eyetracking.domain.errors import Invalid
from eyetracking.domain.live import MAX_AUDIO_BYTES

from ..deps import get_clock, get_principal, get_uow

router = APIRouter(tags=["live"])


def get_live_providers(request: Request) -> uc.LiveProviders:
    return request.app.state.live_providers


class StartIn(BaseModel):
    input_mode: str = "typed"
    allow_transcript: bool = False
    t_ms: int | None = None


class TurnIn(BaseModel):
    expect_turn: int
    text: str
    t_ms: int | None = None


class EndIn(BaseModel):
    t_ms: int | None = None


@router.get("/static/live/sample-face.webm", include_in_schema=False)
def sample_face():
    """The development avatar: a generated sample face, no personal data."""
    data = resources.files("eyetracking.infrastructure.ai").joinpath("assets/sample-face.webm").read_bytes()
    return Response(content=data, media_type="video/webm", headers={"Cache-Control": "public, max-age=3600"})


@router.get("/studies/{study_id}/live/status")
def live_status(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), providers=Depends(get_live_providers)):
    return uc.status(uow, providers, principal, study_id)


@router.get("/studies/{study_id}/sessions/{session_id}/conversation")
def staff_conversation(study_id: int, session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.staff_conversation(uow, principal, study_id, session_id)


@router.get("/me/sessions/{session_id}/live")
def my_conversation(session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.my_conversation(uow, principal, session_id)


@router.post("/me/sessions/{session_id}/live/start")
def start(session_id: int, body: StartIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock), providers=Depends(get_live_providers)):
    return uc.start(uow, providers, clock, principal, session_id, body.input_mode, body.allow_transcript, body.t_ms)


@router.post("/me/sessions/{session_id}/live/turn")
def turn(session_id: int, body: TurnIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock), providers=Depends(get_live_providers)):
    return uc.take_turn(uow, providers, clock, principal, session_id, body.expect_turn, body.t_ms, text=body.text)


@router.post("/me/sessions/{session_id}/live/turn-audio")
async def turn_audio(
    session_id: int,
    file: UploadFile = File(...),
    expect_turn: int = Form(...),
    t_ms: int | None = Form(None),
    principal: Principal = Depends(get_principal),
    uow=Depends(get_uow),
    clock=Depends(get_clock),
    providers=Depends(get_live_providers),
):
    audio = await file.read(MAX_AUDIO_BYTES + 1)
    if len(audio) > MAX_AUDIO_BYTES:
        raise Invalid("the recording is too long; please say it in a shorter way")
    return uc.take_turn(uow, providers, clock, principal, session_id, expect_turn, t_ms, audio=audio, content_type=file.content_type or "")


@router.post("/me/sessions/{session_id}/live/end")
def end(session_id: int, body: EndIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    return uc.end(uow, clock, principal, session_id, body.t_ms)
