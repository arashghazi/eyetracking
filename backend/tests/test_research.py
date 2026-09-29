"""Step 4: quality grades, replay, analysis, exports, access log, raw data and deletion rules."""
import csv
import io
import json

from .conftest import ADMIN, auth, login
from .measurement_helpers import LAYOUT, samples_for, validation_targets
from .test_measurement import CAMERA, DEVICE, REAL_MODEL, SCREEN, SYNTHETIC_MODEL, calibrate, make_ready
from .test_practice import GRADUAL, INTEREST, approved_content, publish, start_practice_session


def full_gradual_session(world, token, model=REAL_MODEL, pause=True, end="completed") -> int:
    """Baseline (eyes), one practice stage with trials, post (eyes), comfort, end."""
    c = world.c
    p = auth(token)
    gradual = publish(world, GRADUAL, "Gradual")
    code = c.get("/me/participant", headers=p).json()["code"]
    aid = c.post(f"/studies/{world.study_a}/participants/{code}/assignments", json={"protocol_id": gradual}, headers=auth(world.researcher_a)).json()["id"]
    sid = start_practice_session(world, token, aid, model=model)
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "baseline", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 0, "type": "segment_start"}, headers=p)
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=20, t0=100)}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 2100, "type": "segment_end"}, headers=p)
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "practice", "layout": LAYOUT, "stage_index": 0}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 3000, "type": "segment_start"}, headers=p)
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=10, t0=3100)}, headers=p)
    if pause:
        c.post(f"/me/sessions/{sid}/events", json={"t_ms": 4200, "type": "pause"}, headers=p)
        c.post(f"/me/sessions/{sid}/events", json={"t_ms": 4700, "type": "resume"}, headers=p)
    c.post(f"/me/sessions/{sid}/trials", json={"trials": [{"stage_index": 0, "trial_index": 0, "t_ms": 3200, "number_shown": "7", "zone": "outside", "position": {"x": 100, "y": 100}, "face_level": 0, "response": "7"}, {"stage_index": 0, "trial_index": 1, "t_ms": 3900, "number_shown": "4", "zone": "outside", "position": {"x": 1100, "y": 600}, "face_level": 0, "response": "4"}]}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 5000, "type": "comfort_answer", "payload": {"value": 4, "stage_index": 0}}, headers=p)
    c.post(f"/me/sessions/{sid}/stage-result", json={"stage_index": 0, "comfort_value": 4}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 5100, "type": "segment_end"}, headers=p)
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "post", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 6000, "type": "segment_start"}, headers=p)
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=20, t0=6100)}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 8100, "type": "segment_end"}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 8200, "type": "end", "payload": {"reason": end}}, headers=p)
    return sid


def test_quality_grades(world):
    c = world.c
    make_ready(world, world.p1)
    p = auth(world.p1)
    # synthetic estimator -> exclude
    sid = full_gradual_session(world, world.p1, model=SYNTHETIC_MODEL)
    q = c.get(f"/me/sessions/{sid}", headers=p).json()["quality"]
    assert q["grade"] == "exclude" and "synthetic_estimator" in q["reasons"]
    # real estimator, validation passed, full coverage -> ok
    sid = full_gradual_session(world, world.p1)
    q = c.get(f"/me/sessions/{sid}", headers=p).json()["quality"]
    assert q == {"grade": "ok", "reasons": []}
    # ended early -> review; a session without calibration -> exclude
    sid = full_gradual_session(world, world.p1, end="ended_early")
    q = c.get(f"/me/sessions/{sid}", headers=p).json()["quality"]
    assert q["grade"] == "review" and q["reasons"] == ["ended_early"]
    r = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": REAL_MODEL}, headers=p)
    assert r.json()["quality"]["grade"] == "exclude" and "no_calibration" in r.json()["quality"]["reasons"]
    # thresholds are study settings
    r = c.put(f"/studies/{world.study_a}/measurement-settings", json={"quality_max_missing_share": 0.0}, headers=auth(world.researcher_a))
    assert r.status_code == 200 and r.json()["quality_max_missing_share"] == 0.0
    assert c.put(f"/studies/{world.study_a}/measurement-settings", json={"quality_max_missing_share": 2}, headers=auth(world.researcher_a)).status_code == 422
    rows = c.get(f"/studies/{world.study_a}/sessions", headers=auth(world.researcher_a)).json()
    row = next(x for x in rows if x["id"] == sid)
    assert row["quality"]["grade"] == "review" and row["protocol"]["name"] == "Gradual" and rows[0]["protocol"] is None


def test_replay_bundle_and_access(world):
    c = world.c
    make_ready(world, world.p1)
    sid = full_gradual_session(world, world.p1)
    url = f"/studies/{world.study_a}/sessions/{sid}/replay"
    assert c.get(url, headers=auth(world.p1)).status_code == 403
    assert c.get(url, headers=auth(world.researcher_b)).status_code == 403
    r = c.get(url, headers=auth(world.analyst_a))
    assert r.status_code == 200
    b = r.json()
    assert b["session"]["participant_code"] == "P-001" and b["session"]["protocol"]["path"] == "gradual_face" and b["screen"]["w"] == 1280
    assert [s["label"] for s in b["segments"]] == ["baseline", "practice", "post"]
    assert [l["segment"] for l in b["layouts"]] == ["baseline", "practice", "post"] and b["layouts"][1]["stage_index"] == 0
    assert b["layouts"][0]["from_ms"] == 100 and b["layouts"][0]["to_ms"] == 2000
    assert len(b["samples"]) == 50 and b["samples"][0][4] == 0 and len(b["samples"][0]) == 5
    assert b["pauses"] == [{"from_ms": 4200, "to_ms": 4700}]
    assert any(g["from_ms"] == 2000 for g in b["gaps"]) and len(b["trials"]) == 2
    strip = b["quality_strip"]
    assert strip[0]["from_ms"] == 0 and strip[0]["valid_share"] == 1.0 and any(x["valid_share"] is None for x in strip)
    assert b["media"] == []
    log = c.get(f"/studies/{world.study_a}/access-log", headers=auth(world.researcher_a)).json()
    assert log[0]["action"] == "replay" and log[0]["role"] == "analyst" and log[0]["detail"]["session_id"] == sid
    assert c.get(f"/studies/{world.study_a}/access-log", headers=auth(world.analyst_a)).status_code == 403


def test_replay_media_for_interest_path(world):
    c = world.c
    make_ready(world, world.p1)
    p = auth(world.p1)
    interest = publish(world, INTEREST, "Interest")
    base = f"/studies/{world.study_a}/participants/P-001/assignments"
    aid = c.post(base, json={"protocol_id": interest}, headers=auth(world.researcher_a)).json()["id"]
    c.post(f"/me/assignments/{aid}/topic", json={"topic": "Trains"}, headers=p)
    cid = approved_content(world)
    c.put(f"{base}/{aid}", json={"content_id": cid}, headers=auth(world.researcher_a))
    sid = start_practice_session(world, world.p1, aid)
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "practice", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 0, "type": "segment_start"}, headers=p)
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 10, "type": "media_start", "payload": {"segment_id": "s1", "media_key": "s1.webm"}}, headers=p).status_code == 200
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=5, t0=100)}, headers=p)
    b = c.get(f"/studies/{world.study_a}/sessions/{sid}/replay", headers=auth(world.researcher_a)).json()
    assert b["media"][0]["segment_id"] == "s1" and b["media"][0]["start_ms"] == 10 and b["media"][0]["url"].startswith("/media/")
    assert c.get(b["media"][0]["url"]).status_code == 200


def test_analysis_exports_and_dictionary(world):
    c = world.c
    make_ready(world, world.p1)
    full_gradual_session(world, world.p1, model=SYNTHETIC_MODEL)
    sid_ok = full_gradual_session(world, world.p1)
    url = f"/studies/{world.study_a}/analysis"
    assert c.get(url, headers=auth(world.p1)).status_code == 403
    a = c.get(url, headers=auth(world.analyst_a)).json()
    assert len(a["rows"]) == 1 and a["excluded"] == 1 and a["rows"][0]["session_id"] == sid_ok
    row = a["rows"][0]
    assert row["participant_code"] == "P-001" and row["quality"] == "ok" and row["eye_share"] == 1.0 and row["eye_share_delta"] == 0.0
    assert row["demographics"] == {"age": 25, "diagnosis": True} and row["protocol_version"] == 2 and row["number_task_share"] == 1.0
    assert row["group_key"].startswith("web|2|l2cs-net-resnet50|1200x600|150px")
    assert a["groups"][0]["sessions"] == 1 and a["trends"][0]["participant_code"] == "P-001" and len(a["trends"][0]["points"]) == 1
    assert "email" not in json.dumps(a)
    a2 = c.get(url + "?include_synthetic=true&quality=ok,review,exclude", headers=auth(world.researcher_a)).json()
    assert len(a2["rows"]) == 2 and a2["excluded"] == 0 and len(a2["groups"]) == 2
    assert c.get(url + "?participant=P-002", headers=auth(world.researcher_a)).json()["rows"] == []
    assert c.get(url + "?path=interest_conversation", headers=auth(world.researcher_a)).json()["rows"] == []
    assert c.get(url + "?from=2090-01-01", headers=auth(world.researcher_a)).json()["rows"] == []
    assert c.get(url + "?from=bad", headers=auth(world.researcher_a)).status_code == 422
    # CSV export with demographics columns and a BOM; JSON export
    r = c.get(f"/studies/{world.study_a}/exports/sessions.csv", headers=auth(world.analyst_a))
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv") and "attachment" in r.headers["content-disposition"]
    text = r.content.decode("utf-8-sig")
    reader = list(csv.DictReader(io.StringIO(text)))
    assert len(reader) == 1 and reader[0]["demo_age"] == "25" and reader[0]["export_version"] == "1" and reader[0]["quality"] == "ok"
    assert "email" not in text
    j = c.get(f"/studies/{world.study_a}/exports/sessions.json?include_synthetic=true&quality=ok,review,exclude", headers=auth(world.researcher_a)).json()
    assert j["export_version"] == "1" and len(j["rows"]) == 2
    r = c.get(f"/studies/{world.study_a}/exports/samples.csv?session_id={sid_ok}", headers=auth(world.analyst_a))
    lines = r.content.decode("utf-8-sig").splitlines()
    assert lines[0] == "t_ms,x,y,conf,valid,region,segment,layout_id" and len(lines) == 51
    r = c.get(f"/studies/{world.study_a}/exports/events.csv?session_id={sid_ok}", headers=auth(world.analyst_a))
    assert r.content.decode("utf-8-sig").splitlines()[0] == "t_ms,type,payload_json"
    assert c.get(f"/studies/{world.study_a}/exports/samples.csv?session_id={sid_ok}", headers=auth(world.researcher_b)).status_code == 403
    d = c.get(f"/studies/{world.study_a}/exports/data-dictionary.json", headers=auth(world.analyst_a)).json()
    names = {f["name"] for f in d["fields"]}
    assert {"participant_code", "missing_share", "group_key", "demo_<key>", "samples.region"} <= names
    # every export column is documented
    columns = set(reader[0].keys())
    documented = names | {f"demo_{k}" for k in ("age", "diagnosis")}
    assert columns <= documented, columns - documented
    actions = [e["action"] for e in c.get(f"/studies/{world.study_a}/access-log", headers=auth(world.researcher_a)).json()]
    assert {"analysis", "export_sessions_csv", "export_sessions_json", "export_samples_csv", "export_events_csv"} <= set(actions)
    c.get(f"/studies/{world.study_b}/participants/P-001/identity", headers=auth(world.researcher_b))
    assert c.get(f"/studies/{world.study_b}/access-log", headers=auth(world.researcher_b)).json()[0]["action"] == "identity_reveal"


def test_participant_raw_data_and_erasure(world):
    c = world.c
    make_ready(world, world.p1)
    sid = full_gradual_session(world, world.p1)
    data = c.get("/me/data", headers=auth(world.p1)).json()
    assert data["export_version"] == "1" and len(data["sessions"]) == 1 and len(data["sessions"][0]["samples"]) == 50
    assert data["sessions"][0]["summary"]["id"] == sid and len(data["sessions"][0]["trials"]) == 2 and data["account"]["email"] == world.p1_email
    assert c.post("/me/erase", json={"confirm": "nope"}, headers=auth(world.p1)).status_code == 422
    r = c.post("/me/erase", json={"confirm": "DELETE MY DATA"}, headers=auth(world.p1))
    assert r.status_code == 200
    body = r.json()
    assert body["policy"] == "delete_all" and body["identity_removed"] is True and body["deleted"]["sessions"] == 1 and body["deleted"]["samples"] == 50
    assert c.get("/me", headers=auth(world.p1)).status_code == 401
    assert c.post("/auth/login", json={"email": world.p1_email, "password": "participant-pw-1"}).status_code == 401
    codes = [p["code"] for p in c.get(f"/studies/{world.study_a}/participants", headers=auth(world.researcher_a)).json()]
    assert codes == ["P-002"]
    assert c.get(f"/studies/{world.study_a}/sessions", headers=auth(world.researcher_a)).json() == []
    assert c.get(f"/studies/{world.study_a}/access-log", headers=auth(world.researcher_a)).json()[0]["action"] == "erasure"
    # keep_coded policy: coded rows stay, identity goes
    assert c.put(f"/studies/{world.study_a}", json={"retention_policy": "keep_coded"}, headers=auth(world.researcher_a)).status_code == 403
    r = c.put(f"/studies/{world.study_a}", json={"retention_policy": "keep_coded"}, headers=auth(world.admin))
    assert r.status_code == 200 and r.json()["retention_policy"] == "keep_coded"
    make_ready(world, world.p2)
    sid2 = full_gradual_session(world, world.p2)
    r = c.post("/me/erase", json={"confirm": "DELETE MY DATA"}, headers=auth(world.p2))
    assert r.json()["policy"] == "keep_coded" and r.json()["deleted"] == {}
    rows = c.get(f"/studies/{world.study_a}/sessions", headers=auth(world.researcher_a)).json()
    assert [x["id"] for x in rows] == [sid2] and rows[0]["participant_code"] == "P-002"
    me = c.get("/me", headers=auth(world.admin)).json()
    c.post(f"/studies/{world.study_a}/members", json={"user_id": me["id"], "study_role": "researcher", "can_link_identity": True}, headers=auth(world.admin))
    assert c.get(f"/studies/{world.study_a}/participants/P-002/identity", headers=auth(world.admin)).json()["email"].startswith("erased-")


def test_researcher_deletes_participant_data(world):
    c = world.c
    make_ready(world, world.p1)
    full_gradual_session(world, world.p1)
    url = f"/studies/{world.study_a}/participants/P-001/data"
    assert c.request("DELETE", url, json={"confirm": "P-001"}, headers=auth(world.analyst_a)).status_code == 403
    assert c.request("DELETE", url, json={"confirm": "P-9"}, headers=auth(world.researcher_a)).status_code == 422
    r = c.request("DELETE", url, json={"confirm": "P-001"}, headers=auth(world.researcher_a))
    assert r.status_code == 200 and r.json()["deleted"]["sessions"] == 1 and r.json()["deleted"]["consents"] == 1
    assert c.get(f"/studies/{world.study_a}/sessions", headers=auth(world.researcher_a)).json() == []
    me = c.get("/me/participant", headers=auth(world.p1)).json()
    assert me["code"] == "P-001" and me["consent"] is None and me["readiness"]["ready"] is False
    assert c.get(f"/studies/{world.study_a}/access-log", headers=auth(world.researcher_a)).json()[0]["action"] == "participant_data_deleted"
