"""Invitation, information sheet, consent, demographics and readiness rules."""
from .conftest import FORM, SHEET, auth


def test_invitation_is_single_use_bound_to_email_and_gives_next_code(world):
    c = world.c
    r = c.post(f"/studies/{world.study_a}/invitations", json={"invitee_email": "p4@test.local"}, headers=auth(world.researcher_a))
    assert r.status_code == 201
    inv = r.json()
    assert inv["code"] == "P-003"
    # wrong email for a bound invitation
    r = c.post(f"/invitations/{inv['token']}/accept", json={"email": "other@test.local", "password": "participant-pw-1"})
    assert r.status_code == 422
    # short password
    r = c.post(f"/invitations/{inv['token']}/accept", json={"email": "p4@test.local", "password": "short"})
    assert r.status_code == 422
    r = c.post(f"/invitations/{inv['token']}/accept", json={"email": "p4@test.local", "password": "participant-pw-1"})
    assert r.status_code == 200 and r.json()["participant_code"] == "P-003"
    # second use fails
    r = c.post(f"/invitations/{inv['token']}/accept", json={"email": "p5@test.local", "password": "participant-pw-1"})
    assert r.status_code == 404
    assert c.post("/invitations/does-not-exist/accept", json={"email": "p5@test.local", "password": "participant-pw-1"}).status_code == 404
    # an open invitation (no email) works for anyone once
    inv2 = c.post(f"/studies/{world.study_a}/invitations", json={}, headers=auth(world.researcher_a)).json()
    assert inv2["code"] == "P-004"
    assert c.post(f"/invitations/{inv2['token']}/accept", json={"email": "p6@test.local", "password": "participant-pw-1"}).status_code == 200
    assert c.post("/auth/login", json={"email": "p6@test.local", "password": "participant-pw-1"}).json()["participant_code"] == "P-004"


def test_information_sheet_needs_all_sections_and_versions(world):
    c = world.c
    url = f"/studies/{world.study_a}/information-sheet"
    assert c.get(url, headers=auth(world.researcher_a)).status_code == 404
    incomplete = dict(SHEET, discomfort_sources="   ")
    r = c.put(url, json=incomplete, headers=auth(world.researcher_a))
    assert r.status_code == 422 and "discomfort_sources" in r.json()["detail"]
    assert c.put(url, json=SHEET, headers=auth(world.researcher_a)).json()["version"] == 1
    assert c.put(url, json=dict(SHEET, aims="Updated aims"), headers=auth(world.researcher_a)).json()["version"] == 2
    current = c.get(url, headers=auth(world.analyst_a)).json()
    assert current["version"] == 2 and current["aims"] == "Updated aims"


def test_consent_and_readiness_flow(world):
    c = world.c
    p = auth(world.p1)
    me = c.get("/me/participant", headers=p).json()
    assert me["readiness"] == {"ready": False, "reasons": ["no_information_sheet_published"]}
    assert c.post("/me/consent", json={"sheet_version": 1, "participate": True}, headers=p).status_code == 422

    c.put(f"/studies/{world.study_a}/information-sheet", json=SHEET, headers=auth(world.researcher_a))
    c.put(f"/studies/{world.study_a}/demographics-form", json=FORM, headers=auth(world.researcher_a))
    me = c.get("/me/participant", headers=p).json()
    assert me["readiness"]["reasons"] == ["consent_missing_or_outdated", "demographics_incomplete"]

    # consent must match the current sheet version and must say yes to taking part
    assert c.post("/me/consent", json={"sheet_version": 7, "participate": True}, headers=p).status_code == 409
    assert c.post("/me/consent", json={"sheet_version": 1, "participate": False}, headers=p).status_code == 422
    r = c.post("/me/consent", json={"sheet_version": 1, "participate": True, "audio_recording": True}, headers=p)
    assert r.status_code == 200 and r.json()["audio_recording"] is True and r.json()["video_recording"] is False
    assert c.get("/me/participant", headers=p).json()["readiness"]["reasons"] == ["demographics_incomplete"]

    # demographics validation
    assert c.get("/me/demographics", headers=p).status_code == 404
    assert c.put("/me/demographics", json={"answers": {"age": 24}}, headers=p).status_code == 422  # diagnosis required
    assert c.put("/me/demographics", json={"answers": {"age": "24", "diagnosis": True}}, headers=p).status_code == 422
    assert c.put("/me/demographics", json={"answers": {"age": 24, "diagnosis": True, "gender": "cat"}}, headers=p).status_code == 422
    assert c.put("/me/demographics", json={"answers": {"age": 24, "diagnosis": True, "extra": 1}}, headers=p).status_code == 422
    r = c.put("/me/demographics", json={"answers": {"age": 24, "diagnosis": True, "gender": "woman"}}, headers=p)
    assert r.status_code == 200 and r.json()["form_version"] == 1
    assert c.get("/me/participant", headers=p).json()["readiness"] == {"ready": True, "reasons": []}

    # the researcher sees the answers under the code, not the identity
    coded = c.get(f"/studies/{world.study_a}/participants/P-001", headers=auth(world.researcher_a)).json()
    assert coded["demographics"]["answers"]["age"] == 24 and coded["readiness"]["ready"] is True
    assert "email" not in coded and coded["consent"]["sheet_version"] == 1

    # a new sheet version makes the consent outdated until re-consented
    c.put(f"/studies/{world.study_a}/information-sheet", json=dict(SHEET, aims="v2"), headers=auth(world.researcher_a))
    assert c.get("/me/participant", headers=p).json()["readiness"]["reasons"] == ["consent_missing_or_outdated"]
    assert c.post("/me/consent", json={"sheet_version": 2, "participate": True}, headers=p).status_code == 200
    assert c.get("/me/participant", headers=p).json()["readiness"]["ready"] is True

    # withdrawing is always possible and removes readiness; withdrawing twice is a conflict
    r = c.post("/me/consent/withdraw", headers=p)
    assert r.status_code == 200 and r.json()["withdrawn_at"] is not None
    assert c.get("/me/participant", headers=p).json()["readiness"]["reasons"] == ["consent_missing_or_outdated"]
    assert c.post("/me/consent/withdraw", headers=p).status_code == 409
    # the other participant in the same study is untouched
    assert c.get("/me/participant", headers=auth(world.p2)).json()["consent"] is None


def test_demographics_form_validation(world):
    c = world.c
    url = f"/studies/{world.study_a}/demographics-form"
    bad = {"fields": [{"key": "a", "label": "A", "type": "choice", "required": True}]}
    assert c.put(url, json=bad, headers=auth(world.researcher_a)).status_code == 422
    dup = {"fields": [{"key": "a", "label": "A", "type": "text"}, {"key": "a", "label": "B", "type": "text"}]}
    assert c.put(url, json=dup, headers=auth(world.researcher_a)).status_code == 422
    assert c.put(url, json=FORM, headers=auth(world.researcher_a)).json()["version"] == 1
    assert c.get("/me/demographics-form", headers=auth(world.p1)).json()["fields"][0]["key"] == "age"
    assert c.get("/me/demographics-form", headers=auth(world.p3)).status_code == 404


def test_profile_update(world):
    c = world.c
    p = auth(world.p1)
    assert c.get("/me/profile", headers=p).json()["response_mode"] == "touch"
    assert c.put("/me/profile", json={"response_mode": "gaze"}, headers=p).status_code == 422
    body = {"display_name": "  Sam ", "response_mode": "four_choice", "speed": "slow", "accessibility_needs": ["larger text", " "], "interests": ["trains"]}
    r = c.put("/me/profile", json=body, headers=p)
    assert r.status_code == 200
    got = c.get("/me/profile", headers=p).json()
    assert got["display_name"] == "Sam" and got["response_mode"] == "four_choice"
    assert got["accessibility_needs"] == ["larger text"] and got["interests"] == ["trains"]
    # partial update keeps the rest
    c.put("/me/profile", json={"voice_preference": "calm"}, headers=p)
    got = c.get("/me/profile", headers=p).json()
    assert got["voice_preference"] == "calm" and got["display_name"] == "Sam"
    coded = c.get(f"/studies/{world.study_a}/participants/P-001", headers=auth(world.researcher_a)).json()
    assert coded["profile"]["display_name"] == "Sam"


def test_my_data_export_is_only_for_the_person(world):
    c = world.c
    c.put(f"/studies/{world.study_a}/information-sheet", json=SHEET, headers=auth(world.researcher_a))
    c.post("/me/consent", json={"sheet_version": 1, "participate": True}, headers=auth(world.p1))
    data = c.get("/me/data", headers=auth(world.p1)).json()
    assert data["participant"]["code"] == "P-001" and data["account"]["email"] == world.p1_email
    assert len(data["consents"]) == 1 and data["sessions"] == []
    # staff accounts have no "me/data" and researchers get 403 (not a participant)
    assert c.get("/me/data", headers=auth(world.researcher_a)).status_code == 403
