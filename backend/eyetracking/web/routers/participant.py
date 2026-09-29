"""Endpoints a participant uses for their own data. Everything is scoped to the caller."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from eyetracking.application import use_cases
from eyetracking.application.authz import Principal

from .. import schemas as s
from ..deps import get_clock, get_principal, get_uow
from . import mappers as m

router = APIRouter(prefix="/me", tags=["participant"])


@router.get("/participant", response_model=s.ParticipantMeOut)
def my_participant(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    view = use_cases.my_participant_view(uow, principal)
    return s.ParticipantMeOut(
        code=view.participant.code,
        study_id=view.participant.study_id,
        readiness=m.readiness_out(view),
        consent=m.consent_out(view.consent),
    )


@router.get("/information-sheet", response_model=s.SheetOut)
def my_sheet(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    sheet = use_cases.my_information_sheet(uow, principal)
    if sheet is None:
        raise HTTPException(status_code=404, detail="no information sheet has been published yet")
    return m.sheet_out(sheet)


@router.post("/consent", response_model=s.ConsentOut)
def give_consent(body: s.ConsentIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    c = use_cases.give_consent(uow, clock, principal, body.sheet_version, body.participate, body.audio_recording, body.video_recording)
    return m.consent_out(c)


@router.post("/consent/withdraw", response_model=s.ConsentOut)
def withdraw_consent(principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)):
    return m.consent_out(use_cases.withdraw_consent(uow, clock, principal))


@router.get("/profile", response_model=s.ProfileOut)
def my_profile(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return m.profile_out(use_cases.get_profile(uow, principal))


@router.put("/profile", response_model=s.ProfileOut)
def update_profile(body: s.ProfileIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return m.profile_out(use_cases.update_profile(uow, principal, **body.model_dump(exclude_unset=True)))


@router.get("/demographics-form", response_model=s.DemographicsFormOut)
def my_form(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    form = use_cases.my_demographics_form(uow, principal)
    if form is None:
        raise HTTPException(status_code=404, detail="this study has no demographics form")
    return m.form_out(form)


@router.get("/demographics", response_model=s.DemographicsAnswersOut)
def my_demographics(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    view = use_cases.my_participant_view(uow, principal)
    if view.demographics is None:
        raise HTTPException(status_code=404, detail="no demographics answers yet")
    return m.answers_out(view.demographics)


@router.put("/demographics", response_model=s.DemographicsAnswersOut)
def submit_demographics(
    body: s.DemographicsAnswersIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)
):
    return m.answers_out(use_cases.submit_demographics(uow, clock, principal, body.answers))

