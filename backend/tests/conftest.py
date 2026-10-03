"""Test world: one admin, two studies, staff with different grants, participants in each study.

Every test gets a fresh in-memory SQLite database; nothing touches a real database.

Contract mode: with EYETRACKING_PARITY=dotnet the same HTTP tests run against the C# API in
backend-dotnet instead. The session builds and starts it on a throwaway SQL Server database
(EyeTracking_Test_*, dropped at the end) next to a synthetic Python gaze service, and every test
starts from an emptied database. Tests marked `python_only` exercise Python internals and are
skipped there; the C# test project covers them.
"""
from __future__ import annotations

import os
import shutil
import socket
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

import tempfile

import httpx
import pytest
from fastapi.testclient import TestClient

from eyetracking.web.app import create_app
from eyetracking.web.settings import Settings

PARITY_DOTNET = os.environ.get("EYETRACKING_PARITY") == "dotnet"
DOTNET_ROOT = Path(__file__).resolve().parents[2] / "backend-dotnet"

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


def pytest_configure(config):
    config.addinivalue_line("markers", "python_only: tests Python internals; skipped in the C# contract run")


def pytest_collection_modifyitems(config, items):
    if not PARITY_DOTNET:
        return
    skip = pytest.mark.skip(reason="Python internals; covered by backend-dotnet/tests")
    for item in items:
        if "python_only" in item.keywords:
            item.add_marker(skip)


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _wait(url: str, proc: subprocess.Popen, seconds: float, log: Path) -> None:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        try:
            if httpx.get(url, timeout=2).status_code == 200:
                return
        except httpx.HTTPError:
            pass
        time.sleep(0.3)
    raise RuntimeError(f"{url} did not start; log: {log}\n{log.read_text(errors='replace')[-3000:]}")


def _sql(query: str) -> None:
    subprocess.run(["sqlcmd", "-S", os.environ.get("EYETRACKING_TEST_SQLSERVER", "localhost"), "-E", "-C", "-b", "-Q", query], check=False, capture_output=True)


@pytest.fixture(scope="session")
def dotnet_api():
    """Builds and starts the C# API on a throwaway database; yields its base URL."""
    work = Path(tempfile.mkdtemp(prefix="eyetracking-dotnet-"))
    if os.environ.get("EYETRACKING_PARITY_NO_BUILD") != "1":
        build = subprocess.run(["dotnet", "build", str(DOTNET_ROOT / "src" / "EyeTracking.Web"), "-c", "Debug", "--nologo", "-v", "q"], capture_output=True, text=True)
        if build.returncode != 0:
            raise RuntimeError("dotnet build failed:\n" + build.stdout[-4000:] + build.stderr[-2000:])
    dll = DOTNET_ROOT / "src" / "EyeTracking.Web" / "bin" / "Debug" / "net10.0" / "EyeTracking.Web.dll"
    gaze_port, api_port = _free_port(), _free_port()
    database = f"EyeTracking_Test_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    server = os.environ.get("EYETRACKING_TEST_SQLSERVER", "localhost")

    gaze_log = work / "gaze.log"
    gaze_env = dict(os.environ, EYETRACKING_GAZE_MODEL="synthetic")
    gaze = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "eyetracking.gaze.main:app", "--host", "127.0.0.1", "--port", str(gaze_port)],
        cwd=Path(__file__).resolve().parents[1], env=gaze_env, stdout=gaze_log.open("w"), stderr=subprocess.STDOUT,
    )
    api_log = work / "api.log"
    api_env = {k: v for k, v in os.environ.items() if not k.startswith("EYETRACKING_")}
    api_env.update(
        ASPNETCORE_URLS=f"http://127.0.0.1:{api_port}",
        EYETRACKING_DB_CONNECTION=f"Server={server};Database={database};Trusted_Connection=True;TrustServerCertificate=True",
        EYETRACKING_TEST_MODE="true",
        EYETRACKING_JWT_SECRET="test-secret",
        EYETRACKING_BOOTSTRAP_ADMIN_EMAIL=ADMIN[0],
        EYETRACKING_BOOTSTRAP_ADMIN_PASSWORD=ADMIN[1],
        EYETRACKING_MEDIA_DIR=str(work / "media"),
        EYETRACKING_GAZE_SERVICE_URL=f"http://127.0.0.1:{gaze_port}",
    )
    api = subprocess.Popen(["dotnet", str(dll)], cwd=work, env=api_env, stdout=api_log.open("w"), stderr=subprocess.STDOUT)
    try:
        _wait(f"http://127.0.0.1:{gaze_port}/info", gaze, 60, gaze_log)
        _wait(f"http://127.0.0.1:{api_port}/health", api, 120, api_log)
        yield f"http://127.0.0.1:{api_port}"
    finally:
        for proc in (api, gaze):
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
        _sql(f"IF DB_ID('{database}') IS NOT NULL BEGIN ALTER DATABASE [{database}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{database}]; END")
        if os.environ.get("EYETRACKING_PARITY_KEEP_LOGS") != "1":
            shutil.rmtree(work, ignore_errors=True)
        else:
            print(f"\nC# API logs kept in {work}")


@pytest.fixture
def client(request):
    if PARITY_DOTNET:
        base = request.getfixturevalue("dotnet_api")
        with httpx.Client(base_url=base, timeout=120) as c:
            r = c.post("/__test/reset")
            assert r.status_code == 200, r.text
            yield c
        return
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
