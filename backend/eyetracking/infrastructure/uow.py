from __future__ import annotations

from sqlalchemy import create_engine
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

    def commit(self) -> None:
        self.session.commit()

    def rollback(self) -> None:
        self.session.rollback()

    def close(self) -> None:
        self.session.close()


def session_factory_for(engine: Engine) -> sessionmaker:
    return sessionmaker(bind=engine, expire_on_commit=False)
