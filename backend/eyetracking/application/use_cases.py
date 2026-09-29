"""Use cases for build step 1. Pure orchestration over ports; no HTTP, no SQL."""
from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta

from eyetracking.domain.errors import AuthenticationFailed, Conflict, Invalid, NotFound
from eyetracking.domain.models import (
    Consent,
    DemographicsAnswer,
    DemographicsForm,
    InformationSheet,
    Invitation,
    Participant,
    Profile,
    Readiness,
    ResponseMode,
    Role,
    Study,
    StudyMembership,
    StudyRole,
    User,
    compute_readiness,
)

from .authz import Principal, require_identity_link, require_participant, require_role, require_study_access
from .ports import Clock, PasswordHasher, TokenIssuer, UnitOfWork


def _normalize_email(email: str) -> str:
    email = (email or "").strip().lower()
    if "@" not in email or len(email) < 5:
        raise Invalid("a valid email address is required")
    return email


def _check_password(password: str) -> None:
    if len(password or "") < 8:
        raise Invalid("password must be at least 8 characters")


# ---------- accounts ----------


def bootstrap_admin(uow: UnitOfWork, hasher: PasswordHasher, email: str, password: str) -> User | None:
    if uow.users.count() > 0:
        return None
    user = uow.users.add(User(email=_normalize_email(email), password_hash=hasher.hash(password), role=Role.admin))
    uow.commit()
    return user


def create_user(uow: UnitOfWork, hasher: PasswordHasher, principal: Principal, email: str, password: str, role: Role) -> User:
    require_role(principal, Role.admin)
    if role is Role.participant:
        raise Invalid("participants join through invitations, not admin creation")
    email = _normalize_email(email)
    _check_password(password)
    if uow.users.by_email(email):
        raise Conflict("email already registered")
    user = uow.users.add(User(email=email, password_hash=hasher.hash(password), role=role))
    uow.commit()
    return user


def login(uow: UnitOfWork, hasher: PasswordHasher, tokens: TokenIssuer, email: str, password: str) -> tuple[str, User]:
    user = uow.users.by_email((email or "").strip().lower())
    if user is None or not user.is_active or not hasher.verify(password, user.password_hash):
        raise AuthenticationFailed("invalid email or password")
    assert user.id is not None
    return tokens.issue(user.id, user.role.value), user


def load_principal(uow: UnitOfWork, user_id: int) -> Principal | None:
    user = uow.users.get(user_id)
    if user is None or not user.is_active:
        return None
    memberships = tuple(uow.memberships.for_user(user_id))
    participant = uow.participants.by_user(user_id) if user.role is Role.participant else None
    return Principal(user_id=user_id, role=user.role, memberships=memberships, participant=participant)


# ---------- studies and membership ----------


def create_study(uow: UnitOfWork, principal: Principal, name: str) -> Study:
    require_role(principal, Role.admin)
    if not (name or "").strip():
        raise Invalid("study name is required")
    study = uow.studies.add(Study(name=name.strip()))
    uow.commit()
    return study


def list_studies(uow: UnitOfWork, principal: Principal) -> list[Study]:
    if principal.role is Role.admin:
        return uow.studies.list_all()
    return uow.studies.list_ids([m.study_id for m in principal.memberships])


def add_member(
    uow: UnitOfWork, principal: Principal, study_id: int, user_id: int, study_role: StudyRole, can_link_identity: bool
) -> StudyMembership:
    require_role(principal, Role.admin)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    user = uow.users.get(user_id)
    if user is None or user.role not in (Role.researcher, Role.analyst, Role.admin):
        raise Invalid("only researcher, analyst or admin accounts can be study members")
    if uow.memberships.get(study_id, user_id):
        raise Conflict("already a member")
    m = uow.memberships.add(
        StudyMembership(study_id=study_id, user_id=user_id, study_role=study_role, can_link_identity=can_link_identity)
    )
    uow.commit()
    return m


# ---------- invitations ----------


def create_invitation(
    uow: UnitOfWork, clock: Clock, principal: Principal, study_id: int, invitee_email: str | None, expires_days: int = 14
) -> Invitation:
    require_study_access(principal, study_id, StudyRole.researcher)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    if not 1 <= expires_days <= 90:
        raise Invalid("expires_days must be between 1 and 90")
    number = uow.invitations.count_for_study(study_id) + 1
    inv = Invitation(
        token=secrets.token_urlsafe(24),
        study_id=study_id,
        code=f"P-{number:03d}",
        created_by=principal.user_id,
        expires_at=clock.now() + timedelta(days=expires_days),
        invitee_email=_normalize_email(invitee_email) if invitee_email else None,
    )
    inv = uow.invitations.add(inv)
    uow.commit()
    return inv


def accept_invitation(
    uow: UnitOfWork, hasher: PasswordHasher, tokens: TokenIssuer, clock: Clock, token: str, email: str, password: str
) -> tuple[str, Participant]:
    inv = uow.invitations.by_token(token)
    now = clock.now()
    if inv is None or not inv.is_usable(now):
        raise NotFound("invitation is invalid, used or expired")
    email = _normalize_email(email)
    _check_password(password)
    if inv.invitee_email and inv.invitee_email != email:
        raise Invalid("this invitation was issued for a different email address")
    if uow.users.by_email(email):
        raise Conflict("email already registered")
    user = uow.users.add(User(email=email, password_hash=hasher.hash(password), role=Role.participant))
    assert user.id is not None
    participant = uow.participants.add(Participant(code=inv.code, study_id=inv.study_id, user_id=user.id))
    inv.used_at = now
    uow.commit()
    return tokens.issue(user.id, user.role.value), participant


# ---------- information sheet and consent ----------


def publish_information_sheet(uow: UnitOfWork, principal: Principal, study_id: int, **sections: str) -> InformationSheet:
    require_study_access(principal, study_id, StudyRole.researcher)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    current = uow.sheets.current(study_id)
    sheet = InformationSheet(study_id=study_id, version=(current.version + 1) if current else 1, **sections)
    sheet.validate()
    sheet = uow.sheets.add(sheet)
    uow.commit()
    return sheet


def get_study_sheet(uow: UnitOfWork, principal: Principal, study_id: int) -> InformationSheet | None:
    require_study_access(principal, study_id)
    return uow.sheets.current(study_id)


def my_information_sheet(uow: UnitOfWork, principal: Principal) -> InformationSheet | None:
    p = require_participant(principal)
    return uow.sheets.current(p.study_id)


def give_consent(
    uow: UnitOfWork, clock: Clock, principal: Principal, sheet_version: int, participate: bool, audio: bool, video: bool
) -> Consent:
    p = require_participant(principal)
    sheet = uow.sheets.current(p.study_id)
    if sheet is None:
        raise Invalid("no information sheet has been published for this study yet")
    if sheet_version != sheet.version:
        raise Conflict(f"the information sheet has changed; please read version {sheet.version}")
    if not participate:
        raise Invalid("consent to participate is required to continue; you may stop at any time later")
    assert p.id is not None
    consent = uow.consents.add(
        Consent(
            participant_id=p.id,
            sheet_version=sheet.version,
            participate=True,
            audio_recording=audio,
            video_recording=video,
            given_at=clock.now(),
        )
    )
    uow.commit()
    return consent


def withdraw_consent(uow: UnitOfWork, clock: Clock, principal: Principal) -> Consent:
    p = require_participant(principal)
    assert p.id is not None
    latest = uow.consents.latest(p.id)
    if latest is None or latest.withdrawn_at is not None:
        raise Conflict("there is no active consent to withdraw")
    latest.withdrawn_at = clock.now()
    uow.commit()
    return latest


# ---------- profile ----------


def get_profile(uow: UnitOfWork, principal: Principal) -> Profile:
    p = require_participant(principal)
    assert p.id is not None
    return uow.profiles.get(p.id) or Profile(participant_id=p.id)


def update_profile(uow: UnitOfWork, principal: Principal, **changes) -> Profile:
    p = require_participant(principal)
    assert p.id is not None
    profile = uow.profiles.get(p.id) or Profile(participant_id=p.id)
    for key, value in changes.items():
        if value is None:
            continue
        if key == "response_mode":
            value = ResponseMode(value)
        if key in ("accessibility_needs", "interests"):
            value = [str(v).strip() for v in value if str(v).strip()]
        if key == "display_name":
            value = value.strip() or None
        setattr(profile, key, value)
    profile = uow.profiles.save(profile)
    uow.commit()
    return profile


# ---------- demographics ----------


def publish_demographics_form(uow: UnitOfWork, principal: Principal, study_id: int, fields: list[dict]) -> DemographicsForm:
    require_study_access(principal, study_id, StudyRole.researcher)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    current = uow.demographics.current_form(study_id)
    form = DemographicsForm(study_id=study_id, version=(current.version + 1) if current else 1, fields=fields)
    form.validate()
    form = uow.demographics.add_form(form)
    uow.commit()
    return form


def get_study_form(uow: UnitOfWork, principal: Principal, study_id: int) -> DemographicsForm | None:
    require_study_access(principal, study_id)
    return uow.demographics.current_form(study_id)


def my_demographics_form(uow: UnitOfWork, principal: Principal) -> DemographicsForm | None:
    p = require_participant(principal)
    return uow.demographics.current_form(p.study_id)


def submit_demographics(uow: UnitOfWork, clock: Clock, principal: Principal, answers: dict) -> DemographicsAnswer:
    p = require_participant(principal)
    assert p.id is not None
    form = uow.demographics.current_form(p.study_id)
    if form is None:
        raise Invalid("this study has no demographics form")
    form.validate_answers(answers)
    record = uow.demographics.answers(p.id) or DemographicsAnswer(participant_id=p.id, form_version=form.version)
    record.form_version = form.version
    record.answers = answers
    record.updated_at = clock.now()
    record = uow.demographics.save_answers(record)
    uow.commit()
    return record


# ---------- participant views ----------


@dataclass(frozen=True)
class ParticipantView:
    """Coded view: research code and research data, never the login email."""

    participant: Participant
    consent: Consent | None
    profile: Profile | None
    demographics: DemographicsAnswer | None
    readiness: Readiness


def _view(uow: UnitOfWork, p: Participant) -> ParticipantView:
    assert p.id is not None
    sheet = uow.sheets.current(p.study_id)
    consent = uow.consents.latest(p.id)
    form = uow.demographics.current_form(p.study_id)
    answers = uow.demographics.answers(p.id)
    return ParticipantView(
        participant=p,
        consent=consent,
        profile=uow.profiles.get(p.id),
        demographics=answers,
        readiness=compute_readiness(sheet, consent, form, answers),
    )


def my_participant_view(uow: UnitOfWork, principal: Principal) -> ParticipantView:
    return _view(uow, require_participant(principal))


def my_data_export(uow: UnitOfWork, principal: Principal) -> dict:
    """Everything stored about the participant, for the participant. Comment 9: raw data for the person."""
    p = require_participant(principal)
    assert p.id is not None
    user = uow.users.get(p.user_id)
    view = _view(uow, p)
    return {
        "account": {"email": user.email if user else None, "created_at": user.created_at.isoformat() if user else None},
        "participant": {"code": p.code, "study_id": p.study_id, "created_at": p.created_at.isoformat()},
        "consents": [c.__dict__ for c in uow.consents.history(p.id)],
        "profile": view.profile.__dict__ if view.profile else None,
        "demographics": view.demographics.__dict__ if view.demographics else None,
        "sessions": [],
    }


def list_participants(uow: UnitOfWork, principal: Principal, study_id: int) -> list[ParticipantView]:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    if uow.studies.get(study_id) is None:
        raise NotFound("study not found")
    return [_view(uow, p) for p in uow.participants.list_for_study(study_id)]


def get_participant(uow: UnitOfWork, principal: Principal, study_id: int, code: str) -> ParticipantView:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    p = uow.participants.by_code(study_id, code)
    if p is None:
        raise NotFound("participant not found")
    return _view(uow, p)


def get_participant_identity(uow: UnitOfWork, principal: Principal, study_id: int, code: str) -> str:
    require_study_access(principal, study_id, StudyRole.researcher, StudyRole.analyst)
    require_identity_link(principal, study_id)
    p = uow.participants.by_code(study_id, code)
    if p is None:
        raise NotFound("participant not found")
    user = uow.users.get(p.user_id)
    if user is None:
        raise NotFound("participant account not found")
    if hasattr(uow, "access_log"):
        from eyetracking.domain.research import AccessLogEntry

        uow.access_log.add(AccessLogEntry(study_id=study_id, user_id=principal.user_id, role=principal.role.value, action="identity_reveal", detail={"participant_code": code}))
        uow.commit()
    return user.email
