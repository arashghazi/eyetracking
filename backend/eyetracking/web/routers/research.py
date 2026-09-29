"""Step 4 endpoints: replay, analysis, exports, data dictionary, access log, raw data, deletion, study policy."""
from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, Query, Response
from pydantic import BaseModel

from eyetracking.application import research_use_cases as uc
from eyetracking.application.authz import Principal

from ..deps import get_clock, get_principal, get_uow
from .practice import get_media_signer

router = APIRouter(tags=["research"])


class EraseIn(BaseModel):
    confirm: str


class DeleteDataIn(BaseModel):
    confirm: str


class StudyPatch(BaseModel):
    retention_policy: Literal["delete_all", "keep_coded"] | None = None


def _filters(participant, path, protocol_version, device, from_, to, quality, include_synthetic) -> dict:
    return {"participant": participant, "path": path, "protocol_version": protocol_version, "device": device, "from": from_, "to": to, "quality": quality, "include_synthetic": include_synthetic}


def _file(name: str, data: bytes, media_type: str) -> Response:
    return Response(content=data, media_type=media_type, headers={"Content-Disposition": f'attachment; filename="{name}"'})


@router.get("/studies/{study_id}/sessions/{session_id}/replay")
def replay(study_id: int, session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), signer=Depends(get_media_signer)):
    return uc.replay(uow, signer, principal, study_id, session_id)


@router.get("/studies/{study_id}/analysis")
def analysis(
    study_id: int,
    participant: str | None = None,
    path: str | None = None,
    protocol_version: str | None = None,
    device: str | None = None,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    quality: str | None = None,
    include_synthetic: bool = False,
    principal: Principal = Depends(get_principal),
    uow=Depends(get_uow),
):
    return uc.analysis(uow, principal, study_id, _filters(participant, path, protocol_version, device, from_, to, quality, include_synthetic))


@router.get("/studies/{study_id}/exports/sessions.{fmt}")
def export_sessions(
    study_id: int,
    fmt: Literal["csv", "json"],
    participant: str | None = None,
    path: str | None = None,
    protocol_version: str | None = None,
    device: str | None = None,
    from_: str | None = Query(None, alias="from"),
    to: str | None = None,
    quality: str | None = None,
    include_synthetic: bool = False,
    principal: Principal = Depends(get_principal),
    uow=Depends(get_uow),
):
    name, data, media_type = uc.export_sessions(uow, principal, study_id, _filters(participant, path, protocol_version, device, from_, to, quality, include_synthetic), fmt)
    return _file(name, data, media_type)


@router.get("/studies/{study_id}/exports/samples.csv")
def export_samples(study_id: int, session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _file(*uc.export_samples(uow, principal, study_id, session_id))


@router.get("/studies/{study_id}/exports/events.csv")
def export_events(study_id: int, session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _file(*uc.export_events(uow, principal, study_id, session_id))


@router.get("/studies/{study_id}/exports/data-dictionary.json")
def data_dictionary(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    uc.get_study(uow, principal, study_id)
    return {"export_version": uc.EXPORT_VERSION, "fields": uc.data_dictionary()}


@router.get("/studies/{study_id}/access-log")
def access_log(study_id: int, limit: int = Query(200, ge=1, le=1000), principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.access_log(uow, principal, study_id, limit)


@router.get("/studies/{study_id}")
def get_study(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.get_study(uow, principal, study_id)


@router.put("/studies/{study_id}")
def update_study(study_id: int, body: StudyPatch, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.update_study(uow, principal, study_id, body.retention_policy)


@router.delete("/studies/{study_id}/participants/{code}/data")
def delete_participant_data(study_id: int, code: str, body: DeleteDataIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.delete_participant_data(uow, principal, study_id, code, body.confirm)


@router.get("/me/data")
def my_data(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.my_full_data(uow, principal)


@router.post("/me/erase")
def erase_me(body: EraseIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    return uc.erase_me(uow, clock, principal, body.confirm)
