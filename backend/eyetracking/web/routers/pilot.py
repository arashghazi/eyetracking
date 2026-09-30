"""Step 6 endpoints: supervised pilot (observations, live monitor, debrief, threshold review,
research-tracker comparison, pilot report)."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

from eyetracking.application import pilot_use_cases as uc
from eyetracking.application.authz import Principal
from eyetracking.domain.errors import Invalid

from ..deps import get_clock, get_principal, get_uow

router = APIRouter(tags=["pilot"])
MAX_REFERENCE_BYTES = 150 * 1024 * 1024


class ObservationIn(BaseModel):
    category: str
    severity: str = "info"
    text: str
    t_ms: int | None = None


class DebriefFormIn(BaseModel):
    questions: list[dict[str, Any]] | None = None
    enabled: bool | None = None


class DebriefAnswerIn(BaseModel):
    form_version: int
    answers: dict[str, Any] = Field(default_factory=dict)
    skipped: bool = False


class ThresholdReviewIn(BaseModel):
    changes: dict[str, Any] = Field(default_factory=dict)
    include_synthetic: bool = False


# ---- observations ----


@router.get("/studies/{study_id}/sessions/{session_id}/observations")
def list_observations(study_id: int, session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.list_observations(uow, principal, study_id, session_id)


@router.post("/studies/{study_id}/sessions/{session_id}/observations", status_code=201)
def add_observation(study_id: int, session_id: int, body: ObservationIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.add_observation(uow, principal, study_id, session_id, body.category, body.severity, body.text, body.t_ms)


# ---- live monitor ----


@router.get("/studies/{study_id}/pilot/active")
def active_sessions(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    return uc.active_sessions(uow, clock, principal, study_id)


@router.get("/studies/{study_id}/sessions/{session_id}/live")
def live_status(study_id: int, session_id: int, first: bool = False, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    return uc.live_status(uow, clock, principal, study_id, session_id, first)


# ---- debrief ----


@router.get("/studies/{study_id}/debrief-form")
def get_debrief_form(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.get_debrief_form(uow, principal, study_id)


@router.put("/studies/{study_id}/debrief-form")
def put_debrief_form(study_id: int, body: DebriefFormIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.put_debrief_form(uow, principal, study_id, body.questions, body.enabled)


@router.get("/me/sessions/{session_id}/debrief")
def my_debrief(session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.my_debrief(uow, principal, session_id)


@router.post("/me/sessions/{session_id}/debrief", status_code=201)
def submit_debrief(session_id: int, body: DebriefAnswerIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.submit_debrief(uow, principal, session_id, body.form_version, body.answers, body.skipped)


# ---- threshold review ----


@router.post("/studies/{study_id}/pilot/threshold-review")
def threshold_review(study_id: int, body: ThresholdReviewIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.threshold_review(uow, principal, study_id, body.changes, body.include_synthetic)


# ---- research eye tracker ----


@router.get("/studies/{study_id}/sessions/{session_id}/reference")
def list_references(study_id: int, session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.list_references(uow, principal, study_id, session_id)


@router.post("/studies/{study_id}/sessions/{session_id}/reference", status_code=201)
async def import_reference(
    study_id: int,
    session_id: int,
    file: UploadFile = File(...),
    source: str = Form(...),
    time_column: str = Form(...),
    x_column: str = Form(...),
    y_column: str = Form(...),
    valid_column: str | None = Form(None),
    valid_values: str | None = Form(None),
    time_unit: str = Form("ms"),
    offset: float = Form(0.0),
    coord_space: str = Form("css_px"),
    origin_x: float = Form(0.0),
    origin_y: float = Form(0.0),
    delimiter: str | None = Form(None),
    auto_align_window_ms: int = Form(0),
    principal: Principal = Depends(get_principal),
    uow=Depends(get_uow),
):
    data = await file.read(MAX_REFERENCE_BYTES + 1)
    if len(data) > MAX_REFERENCE_BYTES:
        raise Invalid("the file is larger than 150 MB")
    opts = {"time_column": time_column, "x_column": x_column, "y_column": y_column, "valid_column": valid_column, "valid_values": valid_values, "time_unit": time_unit,
            "offset": offset, "coord_space": coord_space, "origin_x": origin_x, "origin_y": origin_y, "delimiter": delimiter}
    return uc.import_reference(uow, principal, study_id, session_id, source, opts, auto_align_window_ms, data)


@router.get("/studies/{study_id}/sessions/{session_id}/reference/{recording_id}/compare")
def compare_reference(study_id: int, session_id: int, recording_id: int, tolerance_ms: int = Query(40), principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.compare_reference(uow, principal, study_id, session_id, recording_id, tolerance_ms)


# ---- pilot report ----


@router.get("/studies/{study_id}/pilot/report")
def pilot_report(study_id: int, include_synthetic: bool = False, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.pilot_report(uow, principal, study_id, include_synthetic)


@router.get("/studies/{study_id}/pilot/report.csv")
def pilot_report_csv(study_id: int, include_synthetic: bool = False, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    name, data, media = uc.export_pilot_csv(uow, principal, study_id, include_synthetic)
    return Response(content=data, media_type=media, headers={"Content-Disposition": f'attachment; filename="{name}"'})
