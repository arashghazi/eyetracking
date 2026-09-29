"""Framework-free entities and rules for build step 1.

Identity (login email) and research code are deliberately separate objects:
`User` holds the login identity, `Participant` holds the research code and all
research data hangs off the participant, never off the user.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum

from .errors import Invalid


class Role(str, Enum):
    participant = "participant"
    researcher = "researcher"
    analyst = "analyst"
    admin = "admin"


class StudyRole(str, Enum):
    researcher = "researcher"
    analyst = "analyst"


class ResponseMode(str, Enum):
    keyboard = "keyboard"
    touch = "touch"
    four_choice = "four_choice"
    symbol = "symbol"


FIELD_TYPES = {"number", "choice", "text", "boolean"}


@dataclass
class User:
    email: str
    password_hash: str
    role: Role
    is_active: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class Study:
    name: str
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class StudyMembership:
    study_id: int
    user_id: int
    study_role: StudyRole
    can_link_identity: bool = False
    id: int | None = None


@dataclass
class Participant:
    code: str
    study_id: int
    user_id: int
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class Invitation:
    token: str
    study_id: int
    code: str
    created_by: int
    expires_at: datetime
    invitee_email: str | None = None
    used_at: datetime | None = None
    id: int | None = None

    def is_usable(self, now: datetime) -> bool:
        return self.used_at is None and now < self.expires_at


@dataclass
class InformationSheet:
    """The three mandatory sections come from the reviewer's comment 9."""

    study_id: int
    version: int
    aims: str
    discomfort_sources: str
    benefits: str
    data_handling: str
    stop_rules: str
    published_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None

    def validate(self) -> None:
        missing = [
            name
            for name, value in (
                ("aims", self.aims),
                ("discomfort_sources", self.discomfort_sources),
                ("benefits", self.benefits),
                ("data_handling", self.data_handling),
                ("stop_rules", self.stop_rules),
            )
            if not (value or "").strip()
        ]
        if missing:
            raise Invalid(f"information sheet is missing required sections: {', '.join(missing)}")


@dataclass
class Consent:
    participant_id: int
    sheet_version: int
    participate: bool
    audio_recording: bool = False
    video_recording: bool = False
    given_at: datetime = field(default_factory=datetime.utcnow)
    withdrawn_at: datetime | None = None
    id: int | None = None

    def is_active_for(self, sheet_version: int) -> bool:
        return self.participate and self.withdrawn_at is None and self.sheet_version == sheet_version


@dataclass
class Profile:
    participant_id: int
    display_name: str | None = None
    response_mode: ResponseMode = ResponseMode.touch
    voice_preference: str | None = None
    face_preference: str | None = None
    speed: str = "normal"
    accessibility_needs: list[str] = field(default_factory=list)
    interests: list[str] = field(default_factory=list)
    id: int | None = None


@dataclass
class DemographicsForm:
    """Configurable per study; answers are stored under the research code."""

    study_id: int
    version: int
    fields: list[dict] = field(default_factory=list)
    published_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None

    def validate(self) -> None:
        keys: set[str] = set()
        for f in self.fields:
            key = f.get("key")
            if not key or not isinstance(key, str):
                raise Invalid("every demographics field needs a string key")
            if key in keys:
                raise Invalid(f"duplicate demographics field key: {key}")
            keys.add(key)
            if f.get("type") not in FIELD_TYPES:
                raise Invalid(f"field {key}: type must be one of {sorted(FIELD_TYPES)}")
            if f["type"] == "choice" and not f.get("options"):
                raise Invalid(f"field {key}: choice fields need options")

    def validate_answers(self, answers: dict) -> None:
        known = {f["key"]: f for f in self.fields}
        unknown = set(answers) - set(known)
        if unknown:
            raise Invalid(f"unknown demographics fields: {', '.join(sorted(unknown))}")
        for key, f in known.items():
            value = answers.get(key)
            if value in (None, ""):
                if f.get("required", False):
                    raise Invalid(f"field {key} is required")
                continue
            t = f["type"]
            if t == "number" and (isinstance(value, bool) or not isinstance(value, (int, float))):
                raise Invalid(f"field {key} must be a number")
            if t == "choice" and value not in f.get("options", []):
                raise Invalid(f"field {key} must be one of its options")
            if t == "boolean" and not isinstance(value, bool):
                raise Invalid(f"field {key} must be true or false")
            if t == "text" and not isinstance(value, str):
                raise Invalid(f"field {key} must be text")

    def is_complete(self, answers: dict | None) -> bool:
        if answers is None:
            return not any(f.get("required", False) for f in self.fields)
        return all(answers.get(f["key"]) not in (None, "") for f in self.fields if f.get("required", False))


@dataclass
class DemographicsAnswer:
    participant_id: int
    form_version: int
    answers: dict = field(default_factory=dict)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass(frozen=True)
class Readiness:
    ready: bool
    reasons: tuple[str, ...]


def compute_readiness(
    sheet: InformationSheet | None,
    consent: Consent | None,
    form: DemographicsForm | None,
    answers: DemographicsAnswer | None,
) -> Readiness:
    reasons: list[str] = []
    if sheet is None:
        reasons.append("no_information_sheet_published")
    elif consent is None or not consent.is_active_for(sheet.version):
        reasons.append("consent_missing_or_outdated")
    if form is not None:
        if answers is None or answers.form_version != form.version or not form.is_complete(answers.answers):
            reasons.append("demographics_incomplete")
    return Readiness(ready=not reasons, reasons=tuple(reasons))
