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
