"""Authorization policy. Every use case that touches study data goes through here."""
from __future__ import annotations

from dataclasses import dataclass, field

from eyetracking.domain.errors import Forbidden
from eyetracking.domain.models import Participant, Role, StudyMembership, StudyRole


@dataclass(frozen=True)
class Principal:
    user_id: int
    role: Role
    memberships: tuple[StudyMembership, ...] = field(default_factory=tuple)
    participant: Participant | None = None

    def membership(self, study_id: int) -> StudyMembership | None:
        return next((m for m in self.memberships if m.study_id == study_id), None)


def require_role(principal: Principal, *roles: Role) -> None:
    if principal.role not in roles:
        raise Forbidden("this action is not available for your role")


def require_participant(principal: Principal) -> Participant:
    if principal.role is not Role.participant or principal.participant is None:
        raise Forbidden("participant account required")
    return principal.participant


def require_study_access(principal: Principal, study_id: int, *study_roles: StudyRole) -> None:
    """Admins manage studies; researchers/analysts need a membership with an allowed study role."""
    if principal.role is Role.admin:
        return
    m = principal.membership(study_id)
    if m is None or (study_roles and m.study_role not in study_roles):
        raise Forbidden("no access to this study")


def require_identity_link(principal: Principal, study_id: int) -> None:
    """The identity <-> research code link needs its own grant, even for admins."""
    m = principal.membership(study_id)
    if m is None or not m.can_link_identity:
        raise Forbidden("identity link permission required")
