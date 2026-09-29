"""Nobody can reach another person's or another study's data. This is the acceptance test of build step 1."""
import json

from .conftest import FORM, SHEET, auth


def _has_key(obj, key: str) -> bool:
    text = json.dumps(obj)
    return f'"{key}"' in text


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_unauthenticated_and_bad_password(client):
    assert client.get("/me").status_code == 401
    assert client.post("/auth/login", json={"email": "admin@test.local", "password": "wrong"}).status_code == 401
    assert client.get("/me", headers=auth("not-a-token")).status_code == 401


def test_participant_sees_only_own_record(world):
    c = world.c
    me = c.get("/me/participant", headers=auth(world.p1)).json()
    assert me["code"] == "P-001" and me["study_id"] == world.study_a
    other = c.get("/me/participant", headers=auth(world.p2)).json()
    assert other["code"] == "P-002"
    # participant accounts cannot use any study endpoint, even for their own study
    assert c.get(f"/studies/{world.study_a}/participants", headers=auth(world.p1)).status_code == 403
    assert c.get(f"/studies/{world.study_a}/participants/P-002", headers=auth(world.p1)).status_code == 403
    assert c.post(f"/studies/{world.study_a}/invitations", json={}, headers=auth(world.p1)).status_code == 403
    assert c.get("/studies", headers=auth(world.p1)).json() == []


def test_participant_gets_sheet_of_own_study_only(world):
    c = world.c
    c.put(f"/studies/{world.study_a}/information-sheet", json=SHEET, headers=auth(world.researcher_a))
    assert c.get("/me/information-sheet", headers=auth(world.p1)).status_code == 200
    assert c.get("/me/information-sheet", headers=auth(world.p3)).status_code == 404


def test_researcher_is_scoped_to_own_study_and_never_sees_email(world):
    c = world.c
    studies = c.get("/studies", headers=auth(world.researcher_a)).json()
    assert [s["id"] for s in studies] == [world.study_a]
    r = c.get(f"/studies/{world.study_a}/participants", headers=auth(world.researcher_a))
    assert r.status_code == 200
    assert [p["code"] for p in r.json()] == ["P-001", "P-002"]
    assert not _has_key(r.json(), "email")
    assert not _has_key(r.json(), "user_id")
    assert c.get(f"/studies/{world.study_b}/participants", headers=auth(world.researcher_a)).status_code == 403
    assert c.get(f"/studies/{world.study_b}/participants/P-001", headers=auth(world.researcher_a)).status_code == 403
    assert c.put(f"/studies/{world.study_b}/information-sheet", json=SHEET, headers=auth(world.researcher_a)).status_code == 403
    assert c.post(f"/studies/{world.study_b}/invitations", json={}, headers=auth(world.researcher_a)).status_code == 403


def test_identity_link_requires_separate_grant(world):
    c = world.c
    url_a = f"/studies/{world.study_a}/participants/P-001/identity"
    url_b = f"/studies/{world.study_b}/participants/P-001/identity"
    assert c.get(url_a, headers=auth(world.researcher_a)).status_code == 403  # member, no grant
    assert c.get(url_a, headers=auth(world.analyst_a)).status_code == 403  # analyst, no grant
    assert c.get(url_b, headers=auth(world.researcher_a)).status_code == 403  # not a member at all
    assert c.get(url_a, headers=auth(world.admin)).status_code == 403  # admin without the grant
    r = c.get(url_b, headers=auth(world.researcher_b))  # member with grant
    assert r.status_code == 200 and r.json() == {"email": "p3@test.local"}
    # an admin only sees the link after being granted it explicitly
    me = c.get("/me", headers=auth(world.admin)).json()
    r = c.post(f"/studies/{world.study_a}/members", json={"user_id": me["id"], "study_role": "researcher", "can_link_identity": True}, headers=auth(world.admin))
    assert r.status_code == 201
    assert c.get(url_a, headers=auth(world.admin)).json() == {"email": world.p1_email}


def test_analyst_reads_coded_data_but_cannot_write(world):
    c = world.c
    r = c.get(f"/studies/{world.study_a}/participants", headers=auth(world.analyst_a))
    assert r.status_code == 200 and not _has_key(r.json(), "email")
    assert c.put(f"/studies/{world.study_a}/information-sheet", json=SHEET, headers=auth(world.analyst_a)).status_code == 403
    assert c.put(f"/studies/{world.study_a}/demographics-form", json=FORM, headers=auth(world.analyst_a)).status_code == 403
    assert c.post(f"/studies/{world.study_a}/invitations", json={}, headers=auth(world.analyst_a)).status_code == 403
    assert c.post("/studies", json={"name": "X"}, headers=auth(world.analyst_a)).status_code == 403
    assert c.post("/users", json={"email": "x@test.local", "password": "password-123", "role": "analyst"}, headers=auth(world.analyst_a)).status_code == 403


def test_admin_only_operations(world):
    c = world.c
    assert c.post("/studies", json={"name": "C"}, headers=auth(world.researcher_a)).status_code == 403
    assert c.post(f"/studies/{world.study_a}/members", json={"user_id": world.ids["rb"], "study_role": "analyst"}, headers=auth(world.researcher_a)).status_code == 403
    # participants are never created by admins directly
    r = c.post("/users", json={"email": "p9@test.local", "password": "password-123", "role": "participant"}, headers=auth(world.admin))
    assert r.status_code == 422
    # a participant account cannot be made a study member
    me_p1 = c.get("/me", headers=auth(world.p1)).json()
    r = c.post(f"/studies/{world.study_a}/members", json={"user_id": me_p1["id"], "study_role": "analyst"}, headers=auth(world.admin))
    assert r.status_code == 422
