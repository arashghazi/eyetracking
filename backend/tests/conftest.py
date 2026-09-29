"""Test world: one admin, two studies, staff with different grants, participants in each study.

Every test gets a fresh in-memory SQLite database; nothing touches a real database.
"""
from __future__ import annotations

from dataclasses import dataclass

import tempfile

import pytest
from fastapi.testclient import TestClient

from eyetracking.web.app import create_app
from eyetracking.web.settings import Settings

ADMIN = ("admin@test.local", "admin-password-1")

SHEET = {
    "aims": "Explore whether short, interest-led conversations support comfortable attention to a speaker's face.",
    "discomfort_sources": "Looking at faces and eyes, a number moving near the eye region, session length, camera use.",
    "benefits": "Possible practice effect; no clinical benefit is promised.",
    "data_handling": "Gaze estimates and session events are stored under a research code, separate from your email.",
    "stop_rules": "You can pause or end a session at any time and start again whenever you like.",
}

FORM = {
    "fields": [
        {"key": "age", "label": "Age", "type": "number", "required": True},
        {"key": "gender", "label": "Gender", "type": "choice", "options": ["woman", "man", "other", "prefer not to say"], "required": False},
        {"key": "diagnosis", "label": "Formal autism diagnosis", "type": "boolean", "required": True},
    ]
}


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def login(c: TestClient, email: str, password: str) -> str:
    r = c.post("/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


@dataclass
class World:
    c: TestClient
    admin: str
    study_a: int
    study_b: int
    researcher_a: str  # member of A, no identity link
    researcher_b: str  # member of B, with identity link
    analyst_a: str  # analyst in A
    p1: str  # participant A / P-001
    p1_email: str
    p2: str  # participant A / P-002
    p3: str  # participant B / P-001
    ids: dict


@pytest.fixture
def client() -> TestClient:
    settings = Settings(
        database_url="sqlite:///:memory:",
        jwt_secret="test-secret",
        bootstrap_admin_email=ADMIN[0],
        bootstrap_admin_password=ADMIN[1],
        media_dir=tempfile.mkdtemp(prefix="eyetracking-media-"),
    )
    app = create_app(settings)
    with TestClient(app) as c:
        yield c


def _staff(c: TestClient, admin: str, email: str, role: str) -> tuple[int, str]:
    r = c.post("/users", json={"email": email, "password": "staff-password-1", "role": role}, headers=auth(admin))
    assert r.status_code == 201, r.text
    return r.json()["id"], login(c, email, "staff-password-1")


def _join(c: TestClient, inviter: str, study_id: int, email: str) -> str:
    r = c.post(f"/studies/{study_id}/invitations", json={"invitee_email": email}, headers=auth(inviter))
    assert r.status_code == 201, r.text
    token = r.json()["token"]
    r = c.post(f"/invitations/{token}/accept", json={"email": email, "password": "participant-pw-1"})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


@pytest.fixture
def world(client: TestClient) -> World:
    c = client
    admin = login(c, *ADMIN)
    study_a = c.post("/studies", json={"name": "Study A"}, headers=auth(admin)).json()["id"]
    study_b = c.post("/studies", json={"name": "Study B"}, headers=auth(admin)).json()["id"]
    ra_id, researcher_a = _staff(c, admin, "ra@test.local", "researcher")
    rb_id, researcher_b = _staff(c, admin, "rb@test.local", "researcher")
    an_id, analyst_a = _staff(c, admin, "an@test.local", "analyst")
    for study, uid, role, link in ((study_a, ra_id, "researcher", False), (study_b, rb_id, "researcher", True), (study_a, an_id, "analyst", False)):
        r = c.post(f"/studies/{study}/members", json={"user_id": uid, "study_role": role, "can_link_identity": link}, headers=auth(admin))
        assert r.status_code == 201, r.text
    p1 = _join(c, researcher_a, study_a, "p1@test.local")
    p2 = _join(c, researcher_a, study_a, "p2@test.local")
    p3 = _join(c, researcher_b, study_b, "p3@test.local")
    return World(c, admin, study_a, study_b, researcher_a, researcher_b, analyst_a, p1, "p1@test.local", p2, p3, {"ra": ra_id, "rb": rb_id, "an": an_id})
