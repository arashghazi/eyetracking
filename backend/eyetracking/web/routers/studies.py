"""Research Admin endpoints. Access is checked in the application layer for every call."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from eyetracking.application import use_cases
from eyetracking.application.authz import Principal
from eyetracking.domain.models import Role, StudyRole

from .. import schemas as s
from ..deps import get_clock, get_hasher, get_principal, get_uow
from . import mappers as m

router = APIRouter(tags=["research-admin"])


@router.post("/users", response_model=s.UserOut, status_code=201)
def create_user(body: s.UserIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), hasher=Depends(get_hasher)):
    user = use_cases.create_user(uow, hasher, principal, body.email, body.password, Role(body.role))
    return s.UserOut(id=user.id, email=user.email, role=user.role.value)


@router.get("/studies", response_model=list[s.StudyOut])
def list_studies(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return [s.StudyOut(id=x.id, name=x.name) for x in use_cases.list_studies(uow, principal)]


@router.post("/studies", response_model=s.StudyOut, status_code=201)
def create_study(body: s.StudyIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    study = use_cases.create_study(uow, principal, body.name)
    return s.StudyOut(id=study.id, name=study.name)


@router.post("/studies/{study_id}/members", response_model=s.MemberOut, status_code=201)
def add_member(study_id: int, body: s.MemberIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    mem = use_cases.add_member(uow, principal, study_id, body.user_id, StudyRole(body.study_role), body.can_link_identity)
    return s.MemberOut(study_id=mem.study_id, user_id=mem.user_id, study_role=mem.study_role.value, can_link_identity=mem.can_link_identity)


@router.post("/studies/{study_id}/invitations", response_model=s.InvitationOut, status_code=201)
def create_invitation(
    study_id: int, body: s.InvitationIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow), clock=Depends(get_clock)
):
    inv = use_cases.create_invitation(uow, clock, principal, study_id, body.invitee_email, body.expires_days)
    return s.InvitationOut(token=inv.token, code=inv.code, expires_at=inv.expires_at)


@router.get("/studies/{study_id}/participants", response_model=list[s.ParticipantCodedOut])
def list_participants(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return [m.coded_out(v) for v in use_cases.list_participants(uow, principal, study_id)]


@router.get("/studies/{study_id}/participants/{code}", response_model=s.ParticipantCodedOut)
def get_participant(study_id: int, code: str, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return m.coded_out(use_cases.get_participant(uow, principal, study_id, code))


@router.get("/studies/{study_id}/participants/{code}/identity", response_model=s.IdentityOut)
def get_identity(study_id: int, code: str, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return s.IdentityOut(email=use_cases.get_participant_identity(uow, principal, study_id, code))


@router.get("/studies/{study_id}/information-sheet", response_model=s.SheetOut)
def get_sheet(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    sheet = use_cases.get_study_sheet(uow, principal, study_id)
    if sheet is None:
        raise HTTPException(status_code=404, detail="no information sheet has been published yet")
    return m.sheet_out(sheet)


@router.put("/studies/{study_id}/information-sheet", response_model=s.SheetOut)
def publish_sheet(study_id: int, body: s.SheetIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    return m.sheet_out(use_cases.publish_information_sheet(uow, principal, study_id, **body.model_dump()))


@router.get("/studies/{study_id}/demographics-form", response_model=s.DemographicsFormOut)
def get_form(study_id: int, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    form = use_cases.get_study_form(uow, principal, study_id)
    if form is None:
        raise HTTPException(status_code=404, detail="this study has no demographics form")
    return m.form_out(form)


@router.put("/studies/{study_id}/demographics-form", response_model=s.DemographicsFormOut)
def publish_form(study_id: int, body: s.DemographicsFormIn, principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    fields = [f.model_dump(exclude_none=True) for f in body.fields]
    return m.form_out(use_cases.publish_demographics_form(uow, principal, study_id, fields))
