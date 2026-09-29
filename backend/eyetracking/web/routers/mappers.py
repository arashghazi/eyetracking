"""Domain -> response mapping kept in one place so coded views never leak identity fields."""
from __future__ import annotations

from eyetracking.application.use_cases import ParticipantView
from eyetracking.domain.models import Consent, DemographicsAnswer, DemographicsForm, InformationSheet, Profile

from .. import schemas as s


def consent_out(c: Consent | None) -> s.ConsentOut | None:
    if c is None:
        return None
    return s.ConsentOut(
        sheet_version=c.sheet_version,
        participate=c.participate,
        audio_recording=c.audio_recording,
        video_recording=c.video_recording,
        given_at=c.given_at,
        withdrawn_at=c.withdrawn_at,
    )


def sheet_out(sheet: InformationSheet) -> s.SheetOut:
    return s.SheetOut(
        version=sheet.version,
        aims=sheet.aims,
        discomfort_sources=sheet.discomfort_sources,
        benefits=sheet.benefits,
        data_handling=sheet.data_handling,
        stop_rules=sheet.stop_rules,
        published_at=sheet.published_at,
    )


def profile_out(p: Profile | None) -> s.ProfileOut | None:
    if p is None:
        return None
    return s.ProfileOut(
        display_name=p.display_name,
        response_mode=p.response_mode.value,
        voice_preference=p.voice_preference,
        face_preference=p.face_preference,
        speed=p.speed,
        accessibility_needs=list(p.accessibility_needs or []),
        interests=list(p.interests or []),
    )


def form_out(f: DemographicsForm) -> s.DemographicsFormOut:
    return s.DemographicsFormOut(
        version=f.version, published_at=f.published_at, fields=[s.DemographicsField(**x) for x in f.fields]
    )


def answers_out(a: DemographicsAnswer | None) -> s.DemographicsAnswersOut | None:
    if a is None:
        return None
    return s.DemographicsAnswersOut(form_version=a.form_version, answers=dict(a.answers or {}), updated_at=a.updated_at)


def readiness_out(view: ParticipantView) -> s.ReadinessOut:
    return s.ReadinessOut(ready=view.readiness.ready, reasons=list(view.readiness.reasons))


def coded_out(view: ParticipantView) -> s.ParticipantCodedOut:
    return s.ParticipantCodedOut(
        code=view.participant.code,
        readiness=readiness_out(view),
        consent=consent_out(view.consent),
        profile=profile_out(view.profile),
        demographics=answers_out(view.demographics),
    )
