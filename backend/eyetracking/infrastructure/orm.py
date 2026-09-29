"""SQLAlchemy tables mapped imperatively onto the framework-free domain dataclasses."""
from __future__ import annotations

from sqlalchemy import JSON, Boolean, Column, DateTime, Enum, ForeignKey, Integer, String, Table, Text, UniqueConstraint
from sqlalchemy.orm import registry

from eyetracking.domain.models import (
    Consent,
    DemographicsAnswer,
    DemographicsForm,
    InformationSheet,
    Invitation,
    Participant,
    Profile,
    ResponseMode,
    Role,
    Study,
    StudyMembership,
    StudyRole,
    User,
)

mapper_registry = registry()
metadata = mapper_registry.metadata

users = Table(
    "users",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("email", String(255), nullable=False, unique=True),
    Column("password_hash", String(255), nullable=False),
    Column("role", Enum(Role, native_enum=False, length=20), nullable=False),
    Column("is_active", Boolean, nullable=False, default=True),
    Column("created_at", DateTime, nullable=False),
)

studies = Table(
    "studies",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("name", String(200), nullable=False),
    Column("created_at", DateTime, nullable=False),
)

study_memberships = Table(
    "study_memberships",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("user_id", Integer, ForeignKey("users.id"), nullable=False),
    Column("study_role", Enum(StudyRole, native_enum=False, length=20), nullable=False),
    Column("can_link_identity", Boolean, nullable=False, default=False),
    UniqueConstraint("study_id", "user_id", name="uq_membership"),
)

participants = Table(
    "participants",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("code", String(20), nullable=False),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("user_id", Integer, ForeignKey("users.id"), nullable=False, unique=True),
    Column("created_at", DateTime, nullable=False),
    UniqueConstraint("study_id", "code", name="uq_participant_code"),
)

invitations = Table(
    "invitations",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("token", String(64), nullable=False, unique=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("code", String(20), nullable=False),
    Column("created_by", Integer, ForeignKey("users.id"), nullable=False),
    Column("expires_at", DateTime, nullable=False),
    Column("invitee_email", String(255), nullable=True),
    Column("used_at", DateTime, nullable=True),
    UniqueConstraint("study_id", "code", name="uq_invitation_code"),
)

information_sheets = Table(
    "information_sheets",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("version", Integer, nullable=False),
    Column("aims", Text, nullable=False),
    Column("discomfort_sources", Text, nullable=False),
    Column("benefits", Text, nullable=False),
    Column("data_handling", Text, nullable=False),
    Column("stop_rules", Text, nullable=False),
    Column("published_at", DateTime, nullable=False),
    UniqueConstraint("study_id", "version", name="uq_sheet_version"),
)

consents = Table(
    "consents",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("participant_id", Integer, ForeignKey("participants.id"), nullable=False),
    Column("sheet_version", Integer, nullable=False),
    Column("participate", Boolean, nullable=False),
    Column("audio_recording", Boolean, nullable=False, default=False),
    Column("video_recording", Boolean, nullable=False, default=False),
    Column("given_at", DateTime, nullable=False),
    Column("withdrawn_at", DateTime, nullable=True),
)

profiles = Table(
    "profiles",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("participant_id", Integer, ForeignKey("participants.id"), nullable=False, unique=True),
    Column("display_name", String(100), nullable=True),
    Column("response_mode", Enum(ResponseMode, native_enum=False, length=20), nullable=False),
    Column("voice_preference", String(100), nullable=True),
    Column("face_preference", String(100), nullable=True),
    Column("speed", String(20), nullable=False, default="normal"),
    Column("accessibility_needs", JSON, nullable=False, default=list),
    Column("interests", JSON, nullable=False, default=list),
)

demographics_forms = Table(
    "demographics_forms",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("version", Integer, nullable=False),
    Column("fields", JSON, nullable=False, default=list),
    Column("published_at", DateTime, nullable=False),
    UniqueConstraint("study_id", "version", name="uq_form_version"),
)

demographics_answers = Table(
    "demographics_answers",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("participant_id", Integer, ForeignKey("participants.id"), nullable=False, unique=True),
    Column("form_version", Integer, nullable=False),
    Column("answers", JSON, nullable=False, default=dict),
    Column("updated_at", DateTime, nullable=False),
)

_mapped = False


def start_mappers() -> None:
    global _mapped
    if _mapped:
        return
    mapper_registry.map_imperatively(User, users)
    mapper_registry.map_imperatively(Study, studies)
    mapper_registry.map_imperatively(StudyMembership, study_memberships)
    mapper_registry.map_imperatively(Participant, participants)
    mapper_registry.map_imperatively(Invitation, invitations)
    mapper_registry.map_imperatively(InformationSheet, information_sheets)
    mapper_registry.map_imperatively(Consent, consents)
    mapper_registry.map_imperatively(Profile, profiles)
    mapper_registry.map_imperatively(DemographicsForm, demographics_forms)
    mapper_registry.map_imperatively(DemographicsAnswer, demographics_answers)
    _mapped = True
