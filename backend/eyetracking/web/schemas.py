"""HTTP request/response shapes. They mirror the API contract used by the Flutter apps."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field


class LoginIn(BaseModel):
    email: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    role: str
    participant_code: str | None = None


class AcceptInvitationIn(BaseModel):
    email: str
    password: str


class ParticipantRef(BaseModel):
    code: str
    study_id: int


class MeOut(BaseModel):
    id: int
    email: str
    role: str
    participant: ParticipantRef | None = None


class ReadinessOut(BaseModel):
    ready: bool
    reasons: list[str]


class ConsentOut(BaseModel):
    sheet_version: int
    participate: bool
    audio_recording: bool
    video_recording: bool
    given_at: datetime
    withdrawn_at: datetime | None = None


class ConsentIn(BaseModel):
    sheet_version: int
    participate: bool
    audio_recording: bool = False
    video_recording: bool = False


class SheetIn(BaseModel):
    aims: str
    discomfort_sources: str
    benefits: str
    data_handling: str
    stop_rules: str


class SheetOut(SheetIn):
    version: int
    published_at: datetime


class ProfileIn(BaseModel):
    display_name: str | None = None
    response_mode: Literal["keyboard", "touch", "four_choice", "symbol"] | None = None
    voice_preference: str | None = None
    face_preference: str | None = None
    speed: Literal["slow", "normal", "fast"] | None = None
    accessibility_needs: list[str] | None = None
    interests: list[str] | None = None


class ProfileOut(BaseModel):
    display_name: str | None
    response_mode: str
    voice_preference: str | None
    face_preference: str | None
    speed: str
    accessibility_needs: list[str]
    interests: list[str]


class DemographicsField(BaseModel):
    key: str
    label: str
    type: Literal["number", "choice", "text", "boolean"]
    options: list[str] | None = None
    required: bool = False


class DemographicsFormIn(BaseModel):
    fields: list[DemographicsField]


class DemographicsFormOut(DemographicsFormIn):
    version: int
    published_at: datetime


class DemographicsAnswersIn(BaseModel):
    answers: dict[str, Any]


class DemographicsAnswersOut(BaseModel):
    form_version: int
    answers: dict[str, Any]
    updated_at: datetime


class ParticipantMeOut(BaseModel):
    code: str
    study_id: int
    readiness: ReadinessOut
    consent: ConsentOut | None = None


class ParticipantCodedOut(BaseModel):
    """Researcher/analyst view: research code and research data only, never the login email."""

    code: str
    readiness: ReadinessOut
    consent: ConsentOut | None = None
    profile: ProfileOut | None = None
    demographics: DemographicsAnswersOut | None = None


class IdentityOut(BaseModel):
    email: str


class StudyIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)


class StudyOut(BaseModel):
    id: int
    name: str


class UserIn(BaseModel):
    email: str
    password: str
    role: Literal["researcher", "analyst", "admin"]


class UserOut(BaseModel):
    id: int
    email: str
    role: str


class MemberIn(BaseModel):
    user_id: int
    study_role: Literal["researcher", "analyst"]
    can_link_identity: bool = False


class MemberOut(MemberIn):
    study_id: int


class InvitationIn(BaseModel):
    invitee_email: str | None = None
    expires_days: int = 14


class InvitationOut(BaseModel):
    token: str
    code: str
    expires_at: datetime
