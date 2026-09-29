from __future__ import annotations

from sqlalchemy import create_engine, delete, select
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from . import repositories as r
from .orm import metadata, start_mappers


def make_engine(database_url: str) -> Engine:
    if database_url.startswith("sqlite"):
        in_memory = database_url.endswith(":memory:")
        return create_engine(
            database_url,
            connect_args={"check_same_thread": False},
            poolclass=StaticPool if in_memory else None,
        )
    return create_engine(database_url)


def create_schema(engine: Engine) -> None:
    start_mappers()
    metadata.create_all(engine)


class SqlUnitOfWork:
    def __init__(self, session_factory: sessionmaker):
        start_mappers()
        self.session: Session = session_factory()
        self.users = r.SqlUserRepo(self.session)
        self.studies = r.SqlStudyRepo(self.session)
        self.memberships = r.SqlMembershipRepo(self.session)
        self.participants = r.SqlParticipantRepo(self.session)
        self.invitations = r.SqlInvitationRepo(self.session)
        self.sheets = r.SqlSheetRepo(self.session)
        self.consents = r.SqlConsentRepo(self.session)
        self.profiles = r.SqlProfileRepo(self.session)
        self.demographics = r.SqlDemographicsRepo(self.session)
        self.sessions = r.SqlSessionRepo(self.session)
        self.calibrations = r.SqlCalibrationRepo(self.session)
        self.validations = r.SqlValidationRepo(self.session)
        self.layouts = r.SqlLayoutRepo(self.session)
        self.samples = r.SqlSampleRepo(self.session)
        self.events = r.SqlEventRepo(self.session)
        self.measurement_settings = r.SqlMeasurementSettingsRepo(self.session)
        self.protocols = r.SqlProtocolRepo(self.session)
        self.content = r.SqlContentRepo(self.session)
        self.media = r.SqlMediaRepo(self.session)
        self.assignments = r.SqlAssignmentRepo(self.session)
        self.trials = r.SqlTrialRepo(self.session)
        self.stage_results = r.SqlStageResultRepo(self.session)
        self.answers = r.SqlAnswerRepo(self.session)
        self.access_log = r.SqlAccessLogRepo(self.session)
        self.jobs = r.SqlJobRepo(self.session)
        self.ai_budgets = r.SqlAiBudgetRepo(self.session)

    def commit(self) -> None:
        self.session.commit()

    def rollback(self) -> None:
        self.session.rollback()

    def close(self) -> None:
        self.session.close()

    # ---- deletion rules (step 4) ----

    def purge_participant_research_data(self, participant_id: int) -> dict:
        """Delete everything recorded under a research code. Returns row counts per table."""
        from eyetracking.domain.measurement import Calibration, GazeSample, Session, SessionEvent, StimulusLayout, Validation
        from eyetracking.domain.models import Consent, DemographicsAnswer, Profile
        from eyetracking.domain.practice import Answer, Assignment, StageResult, Trial

        session_ids = list(self.session.scalars(select(Session.id).where(Session.participant_id == participant_id)))
        counts: dict[str, int] = {"sessions": len(session_ids)}
        if session_ids:
            for name, model in (("samples", GazeSample), ("events", SessionEvent), ("trials", Trial), ("stage_results", StageResult), ("answers", Answer), ("validations", Validation), ("calibrations", Calibration), ("layouts", StimulusLayout)):
                counts[name] = int(self.session.execute(delete(model).where(model.session_id.in_(session_ids))).rowcount or 0)
            self.session.execute(delete(Session).where(Session.id.in_(session_ids)))
        else:
            counts.update({k: 0 for k in ("samples", "events", "trials", "stage_results", "answers", "validations", "calibrations", "layouts")})
        counts["consents"] = int(self.session.execute(delete(Consent).where(Consent.participant_id == participant_id)).rowcount or 0)
        counts["demographics"] = int(self.session.execute(delete(DemographicsAnswer).where(DemographicsAnswer.participant_id == participant_id)).rowcount or 0)
        counts["profile"] = int(self.session.execute(delete(Profile).where(Profile.participant_id == participant_id)).rowcount or 0)
        counts["assignments"] = int(self.session.execute(delete(Assignment).where(Assignment.participant_id == participant_id)).rowcount or 0)
        self.session.flush()
        return counts

    def delete_participant(self, participant_id: int) -> None:
        from eyetracking.domain.models import Participant

        self.session.execute(delete(Participant).where(Participant.id == participant_id))
        self.session.flush()


def session_factory_for(engine: Engine) -> sessionmaker:
    return sessionmaker(bind=engine, expire_on_commit=False)
