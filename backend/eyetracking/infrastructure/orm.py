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
    Column("retention_policy", String(20), nullable=False, default="delete_all"),
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
    start_measurement_mappers()
    start_practice_mappers()
    start_research_mappers()
    start_ai_mappers()
    _mapped = True


# ---------- step 2 tables ----------

from sqlalchemy import Float, Index  # noqa: E402

from eyetracking.domain.measurement import (  # noqa: E402
    Calibration,
    GazeSample,
    MeasurementSettings,
    Session,
    SessionEvent,
    SessionStatus,
    StimulusLayout,
    Validation,
)

measurement_settings = Table(
    "measurement_settings",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False, unique=True),
    Column("validation_min_correct", Float, nullable=False, default=0.8),
    Column("validation_max_uncertain", Float, nullable=False, default=0.2),
    Column("min_region_to_error_ratio", Float, nullable=False, default=2.0),
    Column("gaze_conf_threshold", Float, nullable=False, default=0.5),
    Column("calibration_points", Integer, nullable=False, default=9),
    Column("allow_continue_without_validation", Boolean, nullable=False, default=True),
    Column("quality_max_uncertain_share", Float, nullable=False, default=0.2),
    Column("quality_max_missing_share", Float, nullable=False, default=0.2),
)

sessions = Table(
    "sessions",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("participant_id", Integer, ForeignKey("participants.id"), nullable=False),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("device", JSON, nullable=False, default=dict),
    Column("screen", JSON, nullable=False, default=dict),
    Column("camera", JSON, nullable=False, default=dict),
    Column("gaze_model", JSON, nullable=False, default=dict),
    Column("synthetic", Boolean, nullable=False, default=True),
    Column("status", Enum(SessionStatus, native_enum=False, length=20), nullable=False),
    Column("calibration_valid", Boolean, nullable=False, default=False),
    Column("created_at", DateTime, nullable=False),
    Column("ended_at", DateTime, nullable=True),
    Column("end_reason", String(20), nullable=True),
    Column("notes", JSON, nullable=False, default=list),
    Column("assignment_id", Integer, nullable=True),
    Column("protocol_id", Integer, nullable=True),
)

calibrations = Table(
    "calibrations",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("session_id", Integer, ForeignKey("sessions.id"), nullable=False),
    Column("params", JSON, nullable=False),
    Column("residual_px_median", Float, nullable=False),
    Column("residual_px_p90", Float, nullable=False),
    Column("per_target", JSON, nullable=False, default=list),
    Column("points", Integer, nullable=False, default=0),
    Column("accepted", Boolean, nullable=False, default=True),
    Column("created_at", DateTime, nullable=False),
)

validations = Table(
    "validations",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("session_id", Integer, ForeignKey("sessions.id"), nullable=False),
    Column("calibration_id", Integer, ForeignKey("calibrations.id"), nullable=False),
    Column("layout", JSON, nullable=False),
    Column("passed", Boolean, nullable=False),
    Column("correct_ratio", Float, nullable=False),
    Column("uncertain_ratio", Float, nullable=False),
    Column("size_ratio", Float, nullable=False),
    Column("reasons", JSON, nullable=False, default=list),
    Column("targets", JSON, nullable=False, default=list),
    Column("created_at", DateTime, nullable=False),
)

stimulus_layouts = Table(
    "stimulus_layouts",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("session_id", Integer, ForeignKey("sessions.id"), nullable=False),
    Column("segment", String(12), nullable=False),
    Column("layout", JSON, nullable=False),
    Column("stage_index", Integer, nullable=True),
    Column("created_at", DateTime, nullable=False),
)

gaze_samples = Table(
    "gaze_samples",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("session_id", Integer, ForeignKey("sessions.id"), nullable=False),
    Column("t_ms", Integer, nullable=False),
    Column("x", Float, nullable=True),
    Column("y", Float, nullable=True),
    Column("conf", Float, nullable=False),
    Column("valid", Boolean, nullable=False),
    Column("region", String(12), nullable=False),
    Column("segment", String(12), nullable=False),
    Column("layout_id", Integer, ForeignKey("stimulus_layouts.id"), nullable=True),
    Index("ix_gaze_samples_session_t", "session_id", "t_ms"),
)

session_events = Table(
    "session_events",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("session_id", Integer, ForeignKey("sessions.id"), nullable=False),
    Column("t_ms", Integer, nullable=False),
    Column("type", String(24), nullable=False),
    Column("payload", JSON, nullable=False, default=dict),
    Column("created_at", DateTime, nullable=False),
)


def start_measurement_mappers() -> None:
    mapper_registry.map_imperatively(MeasurementSettings, measurement_settings)
    mapper_registry.map_imperatively(Session, sessions)
    mapper_registry.map_imperatively(Calibration, calibrations)
    mapper_registry.map_imperatively(Validation, validations)
    mapper_registry.map_imperatively(StimulusLayout, stimulus_layouts)
    mapper_registry.map_imperatively(GazeSample, gaze_samples)
    mapper_registry.map_imperatively(SessionEvent, session_events)


# ---------- step 3 tables ----------

from eyetracking.domain.practice import (  # noqa: E402
    Answer,
    Assignment,
    AssignmentStatus,
    ContentItem,
    ContentMedia,
    ContentStatus,
    Protocol,
    ProtocolStatus,
    StageResult,
    Trial,
)

protocols = Table(
    "protocols",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("name", String(200), nullable=False),
    Column("definition", JSON, nullable=False),
    Column("status", Enum(ProtocolStatus, native_enum=False, length=20), nullable=False),
    Column("version", Integer, nullable=False, default=0),
    Column("created_at", DateTime, nullable=False),
    Column("published_at", DateTime, nullable=True),
)

content_items = Table(
    "content_items",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("title", String(200), nullable=False),
    Column("definition", JSON, nullable=False),
    Column("topic_tags", JSON, nullable=False, default=list),
    Column("face_id", String(100), nullable=False, default=""),
    Column("voice_id", String(100), nullable=False, default=""),
    Column("status", Enum(ContentStatus, native_enum=False, length=20), nullable=False),
    Column("text_reviewed", Boolean, nullable=False, default=False),
    Column("created_at", DateTime, nullable=False),
    Column("updated_at", DateTime, nullable=False),
)

content_media = Table(
    "content_media",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("content_id", Integer, ForeignKey("content_items.id"), nullable=False),
    Column("key", String(120), nullable=False),
    Column("path", String(500), nullable=False),
    Column("content_type", String(60), nullable=False),
    Column("size", Integer, nullable=False),
    Column("created_at", DateTime, nullable=False),
    UniqueConstraint("content_id", "key", name="uq_media_key"),
)

assignments = Table(
    "assignments",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("participant_id", Integer, ForeignKey("participants.id"), nullable=False),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("protocol_id", Integer, ForeignKey("protocols.id"), nullable=False),
    Column("order_index", Integer, nullable=False, default=0),
    Column("status", Enum(AssignmentStatus, native_enum=False, length=20), nullable=False),
    Column("topic", String(200), nullable=True),
    Column("topic_free_text", Text, nullable=True),
    Column("content_id", Integer, ForeignKey("content_items.id"), nullable=True),
    Column("created_at", DateTime, nullable=False),
)

trials = Table(
    "trials",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("session_id", Integer, ForeignKey("sessions.id"), nullable=False),
    Column("stage_index", Integer, nullable=False),
    Column("trial_index", Integer, nullable=False),
    Column("t_ms", Integer, nullable=False),
    Column("number_shown", String(20), nullable=False),
    Column("zone", String(20), nullable=False),
    Column("position", JSON, nullable=False, default=dict),
    Column("face_level", Integer, nullable=False),
    Column("response", String(20), nullable=True),
    Column("correct", Boolean, nullable=False),
    Column("response_ms", Integer, nullable=True),
)

stage_results = Table(
    "stage_results",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("session_id", Integer, ForeignKey("sessions.id"), nullable=False),
    Column("stage_index", Integer, nullable=False),
    Column("decision", String(12), nullable=False),
    Column("reason", String(40), nullable=False),
    Column("correct_ratio", Float, nullable=True),
    Column("invalid_share", Float, nullable=False),
    Column("comfort_value", Integer, nullable=True),
    Column("trials", Integer, nullable=False),
    Column("next_stage_index", Integer, nullable=True),
    Column("last_trial_id", Integer, nullable=False, default=0),
    Column("created_at", DateTime, nullable=False),
)

answers = Table(
    "answers",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("session_id", Integer, ForeignKey("sessions.id"), nullable=False),
    Column("segment_id", String(60), nullable=False),
    Column("question_id", String(60), nullable=False),
    Column("kind", String(16), nullable=False),
    Column("option", String(200), nullable=False),
    Column("correct", Boolean, nullable=True),
    Column("t_ms", Integer, nullable=False),
    Column("next_segment_id", String(60), nullable=True),
)


def start_practice_mappers() -> None:
    mapper_registry.map_imperatively(Protocol, protocols)
    mapper_registry.map_imperatively(ContentItem, content_items)
    mapper_registry.map_imperatively(ContentMedia, content_media)
    mapper_registry.map_imperatively(Assignment, assignments)
    mapper_registry.map_imperatively(Trial, trials)
    mapper_registry.map_imperatively(StageResult, stage_results)
    mapper_registry.map_imperatively(Answer, answers)


# ---------- step 4 tables ----------

from eyetracking.domain.research import AccessLogEntry  # noqa: E402

access_log = Table(
    "access_log",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, nullable=True),
    Column("user_id", Integer, nullable=False),
    Column("role", String(20), nullable=False),
    Column("action", String(40), nullable=False),
    Column("detail", JSON, nullable=False, default=dict),
    Column("created_at", DateTime, nullable=False),
    Index("ix_access_log_study", "study_id", "created_at"),
)


def start_research_mappers() -> None:
    mapper_registry.map_imperatively(AccessLogEntry, access_log)


# ---------- step 5 tables ----------

from eyetracking.domain.ai import AiBudget, GenerationJob  # noqa: E402

ai_budgets = Table(
    "ai_budgets",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False, unique=True),
    Column("cost_cap_units", Float, nullable=False, default=0.0),
    Column("spent_units", Float, nullable=False, default=0.0),
    Column("send_free_text", Boolean, nullable=False, default=False),
)

generation_jobs = Table(
    "generation_jobs",
    metadata,
    Column("id", Integer, primary_key=True),
    Column("study_id", Integer, ForeignKey("studies.id"), nullable=False),
    Column("kind", String(10), nullable=False),
    Column("provider", String(40), nullable=False),
    Column("content_id", Integer, ForeignKey("content_items.id"), nullable=False),
    Column("status", String(12), nullable=False),
    Column("assignment_id", Integer, nullable=True),
    Column("segment_id", String(60), nullable=True),
    Column("attempts", Integer, nullable=False, default=0),
    Column("max_attempts", Integer, nullable=False, default=3),
    Column("cost_estimate_units", Float, nullable=False, default=0.0),
    Column("cost_actual_units", Float, nullable=False, default=0.0),
    Column("error", Text, nullable=True),
    Column("request", JSON, nullable=False, default=dict),
    Column("result", JSON, nullable=False, default=dict),
    Column("created_at", DateTime, nullable=False),
    Column("started_at", DateTime, nullable=True),
    Column("finished_at", DateTime, nullable=True),
    Column("next_attempt_at", DateTime, nullable=True),
    Index("ix_generation_jobs_study_status", "study_id", "status"),
)


def start_ai_mappers() -> None:
    mapper_registry.map_imperatively(AiBudget, ai_budgets)
    mapper_registry.map_imperatively(GenerationJob, generation_jobs)
