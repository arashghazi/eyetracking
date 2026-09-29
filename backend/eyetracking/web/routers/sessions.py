"""Step 2 endpoints: measurement settings, sessions, calibration, validation, samples, events."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from eyetracking.application import measurement_use_cases as uc
from eyetracking.application.authz import Principal
from eyetracking.domain.measurement import MeasurementSettings

from ..deps import get_clock, get_principal, get_uow

router = APIRouter(tags=["measurement"])


# ---------- schemas ----------


class SettingsOut(BaseModel):
    validation_min_correct: float
    validation_max_uncertain: float
    min_region_to_error_ratio: float
    gaze_conf_threshold: float
    calibration_points: int
    allow_continue_without_validation: bool


class SettingsIn(BaseModel):
    validation_min_correct: float | None = None
    validation_max_uncertain: float | None = None
    min_region_to_error_ratio: float | None = None
    gaze_conf_threshold: float | None = None
    calibration_points: int | None = None
    allow_continue_without_validation: bool | None = None


class RawSample(BaseModel):
    t_ms: int
    face_detected: bool = False
    face_box: list[float] | None = None
    face_conf: float = 0.0
    yaw_deg: float | None = None
    pitch_deg: float | None = None
    gaze_conf: float = 0.0
    frame_w: int = 0
    frame_h: int = 0


class SessionCreateIn(BaseModel):
    device: dict[str, Any] = Field(default_factory=dict)
    screen: dict[str, Any]
    camera: dict[str, Any] = Field(default_factory=dict)
    gaze_model: dict[str, Any] = Field(default_factory=dict)


class CameraCheckIn(BaseModel):
    face_detected: bool
    face_conf: float = 0.0
    lighting_ok: bool = True
    frame_w: int = 0
    frame_h: int = 0


class CalibrationTarget(BaseModel):
    x: float
    y: float
    samples: list[RawSample]


class CalibrationIn(BaseModel):
    targets: list[CalibrationTarget] = Field(min_length=1, max_length=16)


class CalibrationOut(BaseModel):
    calibration_id: int
    residual_px_median: float
    residual_px_p90: float
    per_target: list[dict]
    accepted: bool
    reasons: list[str]


class ValidationTarget(BaseModel):
    region: Literal["eye", "mouth", "outside"]
    x: float
    y: float
    samples: list[RawSample]


class ValidationIn(BaseModel):
    layout: dict[str, Any]
    targets: list[ValidationTarget] = Field(min_length=1, max_length=20)


class ValidationOut(BaseModel):
    validation_id: int
    passed: bool
    correct_ratio: float
    uncertain_ratio: float
    size_ratio: float
    reasons: list[str]
    targets: list[dict]


class LayoutIn(BaseModel):
    segment: Literal["baseline", "practice", "post", "free"]
    layout: dict[str, Any]


class SamplesIn(BaseModel):
    samples: list[RawSample] = Field(min_length=1, max_length=500)


class EventIn(BaseModel):
    t_ms: int
    type: str
    payload: dict[str, Any] | None = None


class SamplesPage(BaseModel):
    total: int
    items: list[dict]


def _settings_out(s: MeasurementSettings) -> SettingsOut:
    return SettingsOut(
        validation_min_correct=s.validation_min_correct,
        validation_max_uncertain=s.validation_max_uncertain,
        min_region_to_error_ratio=s.min_region_to_error_ratio,
        gaze_conf_threshold=s.gaze_conf_threshold,
        calibration_points=s.calibration_points,
        allow_continue_without_validation=s.allow_continue_without_validation,
    )


def _raws(samples: list[RawSample]) -> list[dict]:
    return [s.model_dump() for s in samples]


# ---------- participant ----------


@router.get("/me/measurement-settings", response_model=SettingsOut)
def my_settings(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _settings_out(uc.my_settings(uow, principal))


@router.get("/me/sessions")
def my_sessions(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.my_sessions(uow, principal)


@router.post("/me/sessions", status_code=201)
def create_session(body: SessionCreateIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    s = uc.create_session(uow, principal, body.device, body.screen, body.camera, body.gaze_model)
    return uc.summarize(uow, s)


@router.get("/me/sessions/{session_id}")
def my_session(session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.my_session(uow, principal, session_id)


@router.post("/me/sessions/{session_id}/camera-check")
def camera_check(session_id: int, body: CameraCheckIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    s = uc.camera_check(uow, principal, session_id, body.face_detected, body.face_conf, body.lighting_ok, body.frame_w, body.frame_h)
    return uc.summarize(uow, s)


@router.post("/me/sessions/{session_id}/calibration", response_model=CalibrationOut)
def calibration(session_id: int, body: CalibrationIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    targets = [{"x": t.x, "y": t.y, "samples": _raws(t.samples)} for t in body.targets]
    c = uc.submit_calibration(uow, principal, session_id, targets)
    return CalibrationOut(
        calibration_id=c.id or 0,
        residual_px_median=round(c.residual_px_median, 2),
        residual_px_p90=round(c.residual_px_p90, 2),
        per_target=c.per_target,
        accepted=c.accepted,
        reasons=[],
    )


@router.post("/me/sessions/{session_id}/validation", response_model=ValidationOut)
def validation(session_id: int, body: ValidationIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    targets = [{"region": t.region, "x": t.x, "y": t.y, "samples": _raws(t.samples)} for t in body.targets]
    v = uc.submit_validation(uow, principal, session_id, body.layout, targets)
    return ValidationOut(
        validation_id=v.id or 0,
        passed=v.passed,
        correct_ratio=v.correct_ratio,
        uncertain_ratio=v.uncertain_ratio,
        size_ratio=v.size_ratio,
        reasons=list(v.reasons),
        targets=list(v.targets),
    )


@router.post("/me/sessions/{session_id}/layout")
def set_layout(session_id: int, body: LayoutIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    l = uc.set_layout(uow, principal, session_id, body.segment, body.layout)
    return {"layout_id": l.id}


@router.post("/me/sessions/{session_id}/samples")
def add_samples(session_id: int, body: SamplesIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    stored, invalid = uc.add_samples(uow, principal, session_id, _raws(body.samples))
    return {"stored": stored, "invalid": invalid}


@router.post("/me/sessions/{session_id}/events")
def add_event(session_id: int, body: EventIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    s = uc.add_event(uow, clock, principal, session_id, body.t_ms, body.type, body.payload)
    return uc.summarize(uow, s)


# ---------- research admin ----------


@router.get("/studies/{study_id}/measurement-settings", response_model=SettingsOut)
def study_settings(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _settings_out(uc.get_study_settings(uow, principal, study_id))


@router.put("/studies/{study_id}/measurement-settings", response_model=SettingsOut)
def update_study_settings(study_id: int, body: SettingsIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return _settings_out(uc.update_study_settings(uow, principal, study_id, **body.model_dump(exclude_unset=True)))


@router.get("/studies/{study_id}/sessions")
def study_sessions(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.list_study_sessions(uow, principal, study_id)


@router.get("/studies/{study_id}/sessions/{session_id}")
def study_session(study_id: int, session_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return uc.get_study_session(uow, principal, study_id, session_id)


@router.get("/studies/{study_id}/sessions/{session_id}/samples", response_model=SamplesPage)
def study_session_samples(
    study_id: int,
    session_id: int,
    offset: int = Query(0, ge=0),
    limit: int = Query(2000, ge=1, le=5000),
    principal: Principal = Depends(get_principal),
    uow=Depends(get_uow),
):
    total, items = uc.study_session_samples(uow, principal, study_id, session_id, offset, limit)
    return SamplesPage(total=total, items=items)
