from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from eyetracking.domain.models import (
    Consent,
    DemographicsAnswer,
    DemographicsForm,
    InformationSheet,
    Invitation,
    Participant,
    Profile,
    Study,
    StudyMembership,
    User,
)


class _Repo:
    def __init__(self, session: Session):
        self.s = session


class SqlUserRepo(_Repo):
    def add(self, user: User) -> User:
        self.s.add(user)
        self.s.flush()
        return user

    def get(self, user_id: int) -> User | None:
        return self.s.get(User, user_id)

    def by_email(self, email: str) -> User | None:
        return self.s.scalar(select(User).where(User.email == email))

    def count(self) -> int:
        return int(self.s.scalar(select(func.count()).select_from(User)) or 0)


class SqlStudyRepo(_Repo):
    def add(self, study: Study) -> Study:
        self.s.add(study)
        self.s.flush()
        return study

    def get(self, study_id: int) -> Study | None:
        return self.s.get(Study, study_id)

    def list_ids(self, ids: list[int]) -> list[Study]:
        if not ids:
            return []
        return list(self.s.scalars(select(Study).where(Study.id.in_(ids)).order_by(Study.id)))

    def list_all(self) -> list[Study]:
        return list(self.s.scalars(select(Study).order_by(Study.id)))


class SqlMembershipRepo(_Repo):
    def add(self, m: StudyMembership) -> StudyMembership:
        self.s.add(m)
        self.s.flush()
        return m

    def for_user(self, user_id: int) -> list[StudyMembership]:
        return list(self.s.scalars(select(StudyMembership).where(StudyMembership.user_id == user_id)))

    def get(self, study_id: int, user_id: int) -> StudyMembership | None:
        return self.s.scalar(
            select(StudyMembership).where(StudyMembership.study_id == study_id, StudyMembership.user_id == user_id)
        )


class SqlParticipantRepo(_Repo):
    def add(self, p: Participant) -> Participant:
        self.s.add(p)
        self.s.flush()
        return p

    def by_user(self, user_id: int) -> Participant | None:
        return self.s.scalar(select(Participant).where(Participant.user_id == user_id))

    def by_code(self, study_id: int, code: str) -> Participant | None:
        return self.s.scalar(select(Participant).where(Participant.study_id == study_id, Participant.code == code))

    def list_for_study(self, study_id: int) -> list[Participant]:
        return list(self.s.scalars(select(Participant).where(Participant.study_id == study_id).order_by(Participant.code)))

    def count_for_study(self, study_id: int) -> int:
        return int(self.s.scalar(select(func.count()).select_from(Participant).where(Participant.study_id == study_id)) or 0)


class SqlInvitationRepo(_Repo):
    def add(self, inv: Invitation) -> Invitation:
        self.s.add(inv)
        self.s.flush()
        return inv

    def by_token(self, token: str) -> Invitation | None:
        return self.s.scalar(select(Invitation).where(Invitation.token == token))

    def count_for_study(self, study_id: int) -> int:
        return int(self.s.scalar(select(func.count()).select_from(Invitation).where(Invitation.study_id == study_id)) or 0)


class SqlSheetRepo(_Repo):
    def add(self, sheet: InformationSheet) -> InformationSheet:
        self.s.add(sheet)
        self.s.flush()
        return sheet

    def current(self, study_id: int) -> InformationSheet | None:
        return self.s.scalar(
            select(InformationSheet)
            .where(InformationSheet.study_id == study_id)
            .order_by(InformationSheet.version.desc())
            .limit(1)
        )


class SqlConsentRepo(_Repo):
    def add(self, c: Consent) -> Consent:
        self.s.add(c)
        self.s.flush()
        return c

    def latest(self, participant_id: int) -> Consent | None:
        return self.s.scalar(
            select(Consent).where(Consent.participant_id == participant_id).order_by(Consent.id.desc()).limit(1)
        )

    def history(self, participant_id: int) -> list[Consent]:
        return list(self.s.scalars(select(Consent).where(Consent.participant_id == participant_id).order_by(Consent.id)))


class SqlProfileRepo(_Repo):
    def get(self, participant_id: int) -> Profile | None:
        return self.s.scalar(select(Profile).where(Profile.participant_id == participant_id))

    def save(self, profile: Profile) -> Profile:
        self.s.add(profile)
        self.s.flush()
        return profile


class SqlDemographicsRepo(_Repo):
    def add_form(self, form: DemographicsForm) -> DemographicsForm:
        self.s.add(form)
        self.s.flush()
        return form

    def current_form(self, study_id: int) -> DemographicsForm | None:
        return self.s.scalar(
            select(DemographicsForm)
            .where(DemographicsForm.study_id == study_id)
            .order_by(DemographicsForm.version.desc())
            .limit(1)
        )

    def answers(self, participant_id: int) -> DemographicsAnswer | None:
        return self.s.scalar(select(DemographicsAnswer).where(DemographicsAnswer.participant_id == participant_id))

    def save_answers(self, a: DemographicsAnswer) -> DemographicsAnswer:
        self.s.add(a)
        self.s.flush()
        return a


# ---------- step 2 repositories ----------

from eyetracking.domain.measurement import (  # noqa: E402
    Calibration,
    GazeSample,
    MeasurementSettings,
    Session as MeasurementSession,
    SessionEvent,
    StimulusLayout,
    Validation,
)


class SqlSessionRepo(_Repo):
    def add(self, s: MeasurementSession) -> MeasurementSession:
        self.s.add(s)
        self.s.flush()
        return s

    def get(self, session_id: int) -> MeasurementSession | None:
        return self.s.get(MeasurementSession, session_id)

    def list_for_participant(self, participant_id: int) -> list[MeasurementSession]:
        return list(self.s.scalars(select(MeasurementSession).where(MeasurementSession.participant_id == participant_id).order_by(MeasurementSession.id.desc())))

    def list_for_study(self, study_id: int) -> list[MeasurementSession]:
        return list(self.s.scalars(select(MeasurementSession).where(MeasurementSession.study_id == study_id).order_by(MeasurementSession.id.desc())))


class SqlCalibrationRepo(_Repo):
    def add(self, c: Calibration) -> Calibration:
        self.s.add(c)
        self.s.flush()
        return c

    def latest(self, session_id: int) -> Calibration | None:
        return self.s.scalar(select(Calibration).where(Calibration.session_id == session_id).order_by(Calibration.id.desc()).limit(1))


class SqlValidationRepo(_Repo):
    def add(self, v: Validation) -> Validation:
        self.s.add(v)
        self.s.flush()
        return v

    def latest(self, session_id: int) -> Validation | None:
        return self.s.scalar(select(Validation).where(Validation.session_id == session_id).order_by(Validation.id.desc()).limit(1))


class SqlLayoutRepo(_Repo):
    def add(self, l: StimulusLayout) -> StimulusLayout:
        self.s.add(l)
        self.s.flush()
        return l

    def latest(self, session_id: int) -> StimulusLayout | None:
        return self.s.scalar(select(StimulusLayout).where(StimulusLayout.session_id == session_id).order_by(StimulusLayout.id.desc()).limit(1))

    def session_all(self, session_id: int) -> list[StimulusLayout]:
        return list(self.s.scalars(select(StimulusLayout).where(StimulusLayout.session_id == session_id).order_by(StimulusLayout.id)))


class SqlSampleRepo(_Repo):
    def add_many(self, samples: list[GazeSample]) -> int:
        self.s.add_all(samples)
        self.s.flush()
        return len(samples)

    def for_session(self, session_id: int) -> list[GazeSample]:
        return list(self.s.scalars(select(GazeSample).where(GazeSample.session_id == session_id).order_by(GazeSample.t_ms, GazeSample.id)))

    def page(self, session_id: int, offset: int, limit: int) -> tuple[int, list[GazeSample]]:
        total = int(self.s.scalar(select(func.count()).select_from(GazeSample).where(GazeSample.session_id == session_id)) or 0)
        items = list(
            self.s.scalars(
                select(GazeSample).where(GazeSample.session_id == session_id).order_by(GazeSample.t_ms, GazeSample.id).offset(offset).limit(limit)
            )
        )
        return total, items


class SqlEventRepo(_Repo):
    def add(self, e: SessionEvent) -> SessionEvent:
        self.s.add(e)
        self.s.flush()
        return e

    def for_session(self, session_id: int) -> list[SessionEvent]:
        return list(self.s.scalars(select(SessionEvent).where(SessionEvent.session_id == session_id).order_by(SessionEvent.t_ms, SessionEvent.id)))


class SqlMeasurementSettingsRepo(_Repo):
    def get(self, study_id: int) -> MeasurementSettings | None:
        return self.s.scalar(select(MeasurementSettings).where(MeasurementSettings.study_id == study_id))

    def save(self, m: MeasurementSettings) -> MeasurementSettings:
        self.s.add(m)
        self.s.flush()
        return m


# ---------- step 3 repositories ----------

from eyetracking.domain.practice import (  # noqa: E402
    Answer,
    Assignment,
    ContentItem,
    ContentMedia,
    Protocol as PracticeProtocol,
    StageResult,
    Trial,
)


class SqlProtocolRepo(_Repo):
    def add(self, p: PracticeProtocol) -> PracticeProtocol:
        self.s.add(p)
        self.s.flush()
        return p

    def get(self, protocol_id: int) -> PracticeProtocol | None:
        return self.s.get(PracticeProtocol, protocol_id)

    def list_for_study(self, study_id: int) -> list[PracticeProtocol]:
        return list(self.s.scalars(select(PracticeProtocol).where(PracticeProtocol.study_id == study_id).order_by(PracticeProtocol.id)))

    def max_version(self, study_id: int) -> int:
        return int(self.s.scalar(select(func.max(PracticeProtocol.version)).where(PracticeProtocol.study_id == study_id)) or 0)


class SqlContentRepo(_Repo):
    def add(self, c: ContentItem) -> ContentItem:
        self.s.add(c)
        self.s.flush()
        return c

    def get(self, content_id: int) -> ContentItem | None:
        return self.s.get(ContentItem, content_id)

    def list_for_study(self, study_id: int) -> list[ContentItem]:
        return list(self.s.scalars(select(ContentItem).where(ContentItem.study_id == study_id).order_by(ContentItem.id)))


class SqlMediaRepo(_Repo):
    def add(self, m: ContentMedia) -> ContentMedia:
        self.s.add(m)
        self.s.flush()
        return m

    def get(self, media_id: int) -> ContentMedia | None:
        return self.s.get(ContentMedia, media_id)

    def by_key(self, content_id: int, key: str) -> ContentMedia | None:
        return self.s.scalar(select(ContentMedia).where(ContentMedia.content_id == content_id, ContentMedia.key == key))

    def list_for_content(self, content_id: int) -> list[ContentMedia]:
        return list(self.s.scalars(select(ContentMedia).where(ContentMedia.content_id == content_id).order_by(ContentMedia.key)))


class SqlAssignmentRepo(_Repo):
    def add(self, a: Assignment) -> Assignment:
        self.s.add(a)
        self.s.flush()
        return a

    def get(self, assignment_id: int) -> Assignment | None:
        return self.s.get(Assignment, assignment_id)

    def list_for_participant(self, participant_id: int) -> list[Assignment]:
        return list(self.s.scalars(select(Assignment).where(Assignment.participant_id == participant_id).order_by(Assignment.order_index, Assignment.id)))


class SqlTrialRepo(_Repo):
    def add_many(self, items: list[Trial]) -> int:
        self.s.add_all(items)
        self.s.flush()
        return len(items)

    def for_session(self, session_id: int) -> list[Trial]:
        return list(self.s.scalars(select(Trial).where(Trial.session_id == session_id).order_by(Trial.id)))


class SqlStageResultRepo(_Repo):
    def add(self, r: StageResult) -> StageResult:
        self.s.add(r)
        self.s.flush()
        return r

    def for_session(self, session_id: int) -> list[StageResult]:
        return list(self.s.scalars(select(StageResult).where(StageResult.session_id == session_id).order_by(StageResult.id)))


class SqlAnswerRepo(_Repo):
    def add(self, a: Answer) -> Answer:
        self.s.add(a)
        self.s.flush()
        return a

    def for_session(self, session_id: int) -> list[Answer]:
        return list(self.s.scalars(select(Answer).where(Answer.session_id == session_id).order_by(Answer.id)))


# ---------- step 4 repositories ----------

from eyetracking.domain.research import AccessLogEntry  # noqa: E402


class SqlAccessLogRepo(_Repo):
    def add(self, e: AccessLogEntry) -> AccessLogEntry:
        self.s.add(e)
        self.s.flush()
        return e

    def list_for_study(self, study_id: int, limit: int) -> list[AccessLogEntry]:
        return list(self.s.scalars(select(AccessLogEntry).where(AccessLogEntry.study_id == study_id).order_by(AccessLogEntry.id.desc()).limit(limit)))


# ---------- step 5 repositories ----------

from datetime import datetime as _dt  # noqa: E402

from eyetracking.domain.ai import AiBudget, GenerationJob  # noqa: E402


class SqlJobRepo(_Repo):
    def add(self, j: GenerationJob) -> GenerationJob:
        self.s.add(j)
        self.s.flush()
        return j

    def get(self, job_id: int) -> GenerationJob | None:
        return self.s.get(GenerationJob, job_id)

    def list_for_study(self, study_id: int, status: str | None, content_id: int | None) -> list[GenerationJob]:
        q = select(GenerationJob).where(GenerationJob.study_id == study_id)
        if status:
            q = q.where(GenerationJob.status == status)
        if content_id:
            q = q.where(GenerationJob.content_id == content_id)
        return list(self.s.scalars(q.order_by(GenerationJob.id.desc())))

    def next_queued(self, now: _dt) -> GenerationJob | None:
        q = (
            select(GenerationJob)
            .where(GenerationJob.status == "queued")
            .where((GenerationJob.next_attempt_at.is_(None)) | (GenerationJob.next_attempt_at <= now))
            .order_by(GenerationJob.id)
            .limit(1)
        )
        return self.s.scalar(q)


class SqlAiBudgetRepo(_Repo):
    def get(self, study_id: int) -> AiBudget | None:
        return self.s.scalar(select(AiBudget).where(AiBudget.study_id == study_id))

    def save(self, b: AiBudget) -> AiBudget:
        self.s.add(b)
        self.s.flush()
        return b


# ---------- step 6 repositories ----------

from eyetracking.domain.pilot import DebriefAnswer, DebriefForm, Observation, ReferenceRecording, ReferenceSample, SettingsVersion  # noqa: E402


class SqlSettingsVersionRepo(_Repo):
    def add(self, v: SettingsVersion) -> SettingsVersion:
        self.s.add(v)
        self.s.flush()
        return v

    def list_for_study(self, study_id: int) -> list[SettingsVersion]:
        return list(self.s.scalars(select(SettingsVersion).where(SettingsVersion.study_id == study_id).order_by(SettingsVersion.version)))


class SqlObservationRepo(_Repo):
    def add(self, o: Observation) -> Observation:
        self.s.add(o)
        self.s.flush()
        return o

    def for_session(self, session_id: int) -> list[Observation]:
        return list(self.s.scalars(select(Observation).where(Observation.session_id == session_id).order_by(Observation.id)))

    def for_study(self, study_id: int) -> list[Observation]:
        return list(self.s.scalars(select(Observation).where(Observation.study_id == study_id).order_by(Observation.id)))


class SqlDebriefFormRepo(_Repo):
    def add(self, f: DebriefForm) -> DebriefForm:
        self.s.add(f)
        self.s.flush()
        return f

    def current(self, study_id: int) -> DebriefForm | None:
        return self.s.scalar(select(DebriefForm).where(DebriefForm.study_id == study_id).order_by(DebriefForm.version.desc()).limit(1))

    def get_version(self, study_id: int, version: int) -> DebriefForm | None:
        return self.s.scalar(select(DebriefForm).where(DebriefForm.study_id == study_id, DebriefForm.version == version))


class SqlDebriefAnswerRepo(_Repo):
    def add(self, a: DebriefAnswer) -> DebriefAnswer:
        self.s.add(a)
        self.s.flush()
        return a

    def for_session(self, session_id: int) -> DebriefAnswer | None:
        return self.s.scalar(select(DebriefAnswer).where(DebriefAnswer.session_id == session_id))

    def for_study(self, study_id: int) -> list[DebriefAnswer]:
        return list(self.s.scalars(select(DebriefAnswer).where(DebriefAnswer.study_id == study_id).order_by(DebriefAnswer.id)))


class SqlReferenceRepo(_Repo):
    def add(self, r: ReferenceRecording, rows: list[tuple[int, float | None, float | None, bool]]) -> ReferenceRecording:
        from .orm import reference_samples

        self.s.add(r)
        self.s.flush()
        for i in range(0, len(rows), 5000):
            chunk = rows[i : i + 5000]
            self.s.execute(reference_samples.insert(), [{"recording_id": r.id, "t_ms": t, "x": x, "y": y, "valid": v} for t, x, y, v in chunk])
        self.s.flush()
        return r

    def get(self, recording_id: int) -> ReferenceRecording | None:
        return self.s.get(ReferenceRecording, recording_id)

    def for_session(self, session_id: int) -> list[ReferenceRecording]:
        return list(self.s.scalars(select(ReferenceRecording).where(ReferenceRecording.session_id == session_id).order_by(ReferenceRecording.id)))

    def for_study(self, study_id: int) -> list[ReferenceRecording]:
        return list(self.s.scalars(select(ReferenceRecording).where(ReferenceRecording.study_id == study_id).order_by(ReferenceRecording.id)))

    def samples(self, recording_id: int) -> list[tuple[int, float | None, float | None, bool]]:
        rows = self.s.execute(
            select(ReferenceSample.t_ms, ReferenceSample.x, ReferenceSample.y, ReferenceSample.valid).where(ReferenceSample.recording_id == recording_id).order_by(ReferenceSample.t_ms)
        )
        return [(int(t), x, y, bool(v)) for t, x, y, v in rows]
