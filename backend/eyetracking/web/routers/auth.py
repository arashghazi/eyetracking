from __future__ import annotations

from fastapi import APIRouter, Depends

from eyetracking.application import use_cases
from eyetracking.application.authz import Principal

from .. import schemas as s
from ..deps import get_clock, get_hasher, get_principal, get_tokens, get_uow

router = APIRouter(tags=["auth"])


@router.post("/auth/login", response_model=s.TokenOut)
def login(body: s.LoginIn, uow=Depends(get_uow), hasher=Depends(get_hasher), tokens=Depends(get_tokens)):
    token, user = use_cases.login(uow, hasher, tokens, body.email, body.password)
    participant = uow.participants.by_user(user.id) if user.role.value == "participant" else None
    return s.TokenOut(access_token=token, role=user.role.value, participant_code=participant.code if participant else None)


@router.post("/invitations/{token}/accept", response_model=s.TokenOut)
def accept_invitation(
    token: str,
    body: s.AcceptInvitationIn,
    uow=Depends(get_uow),
    hasher=Depends(get_hasher),
    tokens=Depends(get_tokens),
    clock=Depends(get_clock),
):
    access, participant = use_cases.accept_invitation(uow, hasher, tokens, clock, token, body.email, body.password)
    return s.TokenOut(access_token=access, role="participant", participant_code=participant.code)


@router.get("/me", response_model=s.MeOut)
def me(principal: Principal = Depends(get_principal), uow=Depends(get_uow)):
    user = uow.users.get(principal.user_id)
    p = principal.participant
    return s.MeOut(
        id=user.id,
        email=user.email,
        role=user.role.value,
        participant=s.ParticipantRef(code=p.code, study_id=p.study_id) if p else None,
    )
