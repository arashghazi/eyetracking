"""Step 3: protocols, content and media, assignments, the two practice paths and the three outcomes."""
import copy

from .conftest import auth
from .measurement_helpers import LAYOUT, samples_for, validation_targets
from .test_measurement import DEVICE, CAMERA, REAL_MODEL, SCREEN, SYNTHETIC_MODEL, calibrate, make_ready

GRADUAL = {
    "path": "gradual_face",
    "baseline_seconds": 30,
    "post_seconds": 30,
    "comfort": {"scale_max": 5, "labels": ["Very uncomfortable", "Uncomfortable", "Neutral", "Comfortable", "Very comfortable"], "min_ok": 3, "ask_every_stage": True},
    "progression": {"hold_on_invalid_share_above": 0.3, "easier_on_comfort_below_min": True, "stop_on_two_low_comfort": True},
    "gradual": {
        "stages": [
            {"face_level": 0, "number_zone": "outside", "trials": 2, "min_correct": 0.5, "response_mode": "profile", "trial_seconds": 8},
            {"face_level": 1, "number_zone": "outside", "trials": 2, "min_correct": 0.5, "response_mode": "profile", "trial_seconds": 8},
            {"face_level": 1, "number_zone": "near_eyes", "trials": 2, "min_correct": 1.0, "response_mode": "four_choice", "trial_seconds": 8},
        ],
        "final_zone_limit": "near_eyes",
        "allow_simultaneous_change": False,
        "real_face_media_url": None,
    },
}
INTEREST = {
    "path": "interest_conversation",
    "baseline_seconds": 30,
    "post_seconds": 30,
    "comfort": {"scale_max": 5, "labels": ["1", "2", "3", "4", "5"], "min_ok": 3, "ask_every_stage": False},
    "progression": {"hold_on_invalid_share_above": 0.3, "easier_on_comfort_below_min": True, "stop_on_two_low_comfort": True},
    "interest": {"interaction_points": 1},
}
CONTENT = {
    "start_segment": "s1",
    "post_segment": "s3",
    "segments": [
        {"id": "s1", "text": "Hi {{display_name}}, let's talk about {{topic}}.", "media_key": "s1.webm", "duration_s": 12, "face_layout": {"face_box": [0.3, 0.1, 0.4, 0.8], "eye_region": [0.3, 0.25, 0.4, 0.2], "mouth_region": [0.3, 0.55, 0.4, 0.25]},
         "question": {"id": "q1", "prompt": "Which do you prefer, {{display_name}}?", "options": ["Trains", "Planes"], "branches": {"Trains": "s2", "Planes": "s2"}}},
        {"id": "s2", "text": "Great choice.", "media_key": "s2.webm", "duration_s": 8, "question": None},
        {"id": "s3", "text": "Thanks for listening.", "media_key": "s3.webm", "duration_s": 8, "question": None},
    ],
    "comprehension": [{"id": "c1", "prompt": "What did we talk about?", "options": ["{{topic}}", "Weather"], "correct": "{{topic}}"}],
}
WEBM = b"\x1a\x45\xdf\xa3" + b"\x00" * 2000


def publish(world, definition, name="Proto") -> int:
    c = world.c
    r = c.post(f"/studies/{world.study_a}/protocols", json={"name": name, "definition": definition}, headers=auth(world.researcher_a))
    assert r.status_code == 201, r.text
    pid = r.json()["id"]
    r = c.post(f"/studies/{world.study_a}/protocols/{pid}/publish", headers=auth(world.researcher_a))
    assert r.status_code == 200, r.text
    return pid


def approved_content(world) -> int:
    c = world.c
    r = c.post(f"/studies/{world.study_a}/content", json={"title": "Trains talk", "definition": CONTENT, "topic_tags": ["Trains"], "face_id": "f1", "voice_id": "v1"}, headers=auth(world.researcher_a))
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    for key in ("s1.webm", "s2.webm", "s3.webm"):
        r = c.post(f"/studies/{world.study_a}/content/{cid}/media/{key}", files={"file": (key, WEBM, "video/webm")}, headers=auth(world.researcher_a))
        assert r.status_code == 201, r.text
    assert c.post(f"/studies/{world.study_a}/content/{cid}/approve", headers=auth(world.researcher_a)).status_code == 200
    return cid


def start_practice_session(world, token, assignment_id, model=SYNTHETIC_MODEL) -> int:
    c = world.c
    r = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": model, "assignment_id": assignment_id}, headers=auth(token))
    assert r.status_code == 201, r.text
    sid = r.json()["id"]
    calibrate(world, token, sid)
    assert c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=auth(token)).json()["passed"] is True
    return sid


def test_protocol_validation_and_lifecycle(world):
    c = world.c
    url = f"/studies/{world.study_a}/protocols"
    bad = copy.deepcopy(GRADUAL)
    bad["gradual"]["stages"][2]["number_zone"] = "eye_region"
    r = c.post(url, json={"name": "x", "definition": bad}, headers=auth(world.researcher_a))
    assert r.status_code == 422 and "final_zone_limit" in r.json()["detail"]
    bad = copy.deepcopy(GRADUAL)
    bad["gradual"]["stages"][1] = {"face_level": 1, "number_zone": "near_eyes", "trials": 2, "min_correct": 0.5, "response_mode": "profile", "trial_seconds": 8}
    r = c.post(url, json={"name": "x", "definition": bad}, headers=auth(world.researcher_a))
    assert r.status_code == 422 and "both face_level and number_zone" in r.json()["detail"]
    bad["gradual"]["allow_simultaneous_change"] = True
    assert c.post(url, json={"name": "x", "definition": bad}, headers=auth(world.researcher_a)).status_code == 201
    bad = copy.deepcopy(GRADUAL)
    bad["gradual"]["stages"][1]["face_level"] = 0
    bad["gradual"]["stages"][2]["face_level"] = 0
    bad["gradual"]["stages"].append({"face_level": 0, "number_zone": "outside", "trials": 2, "min_correct": 0.5, "trial_seconds": 8})
    assert c.post(url, json={"name": "x", "definition": bad}, headers=auth(world.researcher_a)).status_code == 422  # zone goes back
    bad = copy.deepcopy(GRADUAL)
    bad["comfort"]["labels"] = ["only", "two"]
    assert c.post(url, json={"name": "x", "definition": bad}, headers=auth(world.researcher_a)).status_code == 422
    assert c.post(url, json={"name": "x", "definition": {"path": "interest_conversation", "baseline_seconds": 30, "post_seconds": 30, "comfort": INTEREST["comfort"], "progression": INTEREST["progression"]}}, headers=auth(world.researcher_a)).status_code == 422
    # roles
    assert c.post(url, json={"name": "x", "definition": GRADUAL}, headers=auth(world.analyst_a)).status_code == 403
    assert c.post(url, json={"name": "x", "definition": GRADUAL}, headers=auth(world.researcher_b)).status_code == 403
    assert c.get(url, headers=auth(world.analyst_a)).status_code == 200
    # lifecycle
    r = c.post(url, json={"name": "Gradual v1", "definition": GRADUAL}, headers=auth(world.researcher_a))
    pid = r.json()["id"]
    assert r.json()["status"] == "draft" and r.json()["version"] == 0 and r.json()["path"] == "gradual_face"
    assert c.put(f"{url}/{pid}", json={"name": "Gradual one"}, headers=auth(world.researcher_a)).json()["name"] == "Gradual one"
    r = c.post(f"{url}/{pid}/publish", headers=auth(world.researcher_a))
    assert r.json()["status"] == "published" and r.json()["version"] == 1 and r.json()["published_at"] is not None
    assert c.put(f"{url}/{pid}", json={"name": "nope"}, headers=auth(world.researcher_a)).status_code == 409
    assert c.post(f"{url}/{pid}/publish", headers=auth(world.researcher_a)).status_code == 409
    d = c.post(f"{url}/{pid}/new-draft", headers=auth(world.researcher_a)).json()
    assert d["status"] == "draft" and d["definition"] == GRADUAL and d["id"] != pid
    assert c.post(f"{url}/{d['id']}/publish", headers=auth(world.researcher_a)).json()["version"] == 2
    assert [p["version"] for p in c.get(url, headers=auth(world.researcher_a)).json()] == [0, 1, 2]


def test_content_media_and_streaming(world):
    c = world.c
    url = f"/studies/{world.study_a}/content"
    bad = copy.deepcopy(CONTENT)
    bad["segments"][0]["question"]["branches"]["Planes"] = "missing"
    r = c.post(url, json={"title": "t", "definition": bad}, headers=auth(world.researcher_a))
    assert r.status_code == 422 and "unknown segment" in r.json()["detail"]
    r = c.post(url, json={"title": "Trains talk", "definition": CONTENT, "topic_tags": ["Trains", " "]}, headers=auth(world.researcher_a))
    assert r.status_code == 201
    body = r.json()
    cid = body["id"]
    assert body["status"] == "draft" and body["topic_tags"] == ["trains"] and body["missing_media"] == ["s1.webm", "s2.webm", "s3.webm"]
    r = c.post(f"{url}/{cid}/approve", headers=auth(world.researcher_a))
    assert r.status_code == 422 and "missing media: s1.webm" in r.json()["detail"]
    assert c.post(f"{url}/{cid}/media/s1.webm", files={"file": ("s1.txt", b"hello", "text/plain")}, headers=auth(world.researcher_a)).status_code == 422
    assert c.post(f"{url}/{cid}/media/..%2Fevil", files={"file": ("x", WEBM, "video/webm")}, headers=auth(world.researcher_a)).status_code in (404, 422)
    assert c.post(f"{url}/{cid}/media/s1.webm", files={"file": ("s1.webm", WEBM, "video/webm")}, headers=auth(world.analyst_a)).status_code == 403
    for key in ("s1.webm", "s2.webm", "s3.webm"):
        r = c.post(f"{url}/{cid}/media/{key}", files={"file": (key, WEBM, "video/webm")}, headers=auth(world.researcher_a))
        assert r.status_code == 201 and r.json()["size"] == len(WEBM)
    media = c.get(f"{url}/{cid}/media", headers=auth(world.analyst_a)).json()
    assert [m["key"] for m in media] == ["s1.webm", "s2.webm", "s3.webm"] and media[0]["url"].startswith("/media/")
    # streaming with and without Range, and bad tokens
    r = c.get(media[0]["url"])
    assert r.status_code == 200 and r.headers["content-type"] == "video/webm" and len(r.content) == len(WEBM)
    r = c.get(media[0]["url"], headers={"Range": "bytes=10-19"})
    assert r.status_code == 206 and r.headers["content-range"] == f"bytes 10-19/{len(WEBM)}" and len(r.content) == 10
    assert c.get(media[0]["url"], headers={"Range": "bytes=999999-"}).status_code == 416
    assert c.get("/media/not-a-token").status_code == 404
    token = media[0]["url"].split("/media/")[1]
    tampered = token[:-4] + ("0000" if token[-4:] != "0000" else "1111")
    assert c.get(f"/media/{tampered}").status_code == 404
    assert c.get(f"{url}/{cid}", headers=auth(world.researcher_a)).json()["missing_media"] == []
    r = c.post(f"{url}/{cid}/approve", headers=auth(world.researcher_a))
    assert r.status_code == 200 and r.json()["status"] == "approved"
    assert c.put(f"{url}/{cid}", json={"title": "x"}, headers=auth(world.researcher_a)).status_code == 409
    assert c.post(f"{url}/{cid}/media/s1.webm", files={"file": ("s1.webm", WEBM, "video/webm")}, headers=auth(world.researcher_a)).status_code == 409
    assert c.get(url, headers=auth(world.researcher_b)).status_code == 403


def test_assignments_topic_and_personalized_content(world):
    c = world.c
    make_ready(world, world.p1)
    c.put("/me/profile", json={"display_name": "Sam"}, headers=auth(world.p1))
    base = f"/studies/{world.study_a}/participants/P-001/assignments"
    draft = c.post(f"/studies/{world.study_a}/protocols", json={"name": "d", "definition": GRADUAL}, headers=auth(world.researcher_a)).json()["id"]
    assert c.post(base, json={"protocol_id": draft}, headers=auth(world.researcher_a)).status_code == 422
    gradual = publish(world, GRADUAL, "Gradual")
    interest = publish(world, INTEREST, "Interest")
    a1 = c.post(base, json={"protocol_id": gradual}, headers=auth(world.researcher_a)).json()
    a2 = c.post(base, json={"protocol_id": interest}, headers=auth(world.researcher_a)).json()
    assert a1["status"] == "ready" and a1["order_index"] == 0 and a1["protocol"]["path"] == "gradual_face"
    assert a2["status"] == "pending_topic" and a2["order_index"] == 1
    assert c.post(base, json={"protocol_id": gradual}, headers=auth(world.analyst_a)).status_code == 403
    mine = c.get("/me/assignments", headers=auth(world.p1)).json()
    assert [a["id"] for a in mine] == [a1["id"], a2["id"]]
    assert c.get("/me/assignments", headers=auth(world.p2)).json() == []
    # topic confirmation
    assert c.post(f"/me/assignments/{a2['id']}/topic", json={"topic": "Trains", "free_text": "steam engines"}, headers=auth(world.p2)).status_code == 404
    assert c.post(f"/me/assignments/{a1['id']}/topic", json={"topic": "Trains"}, headers=auth(world.p1)).status_code == 409
    r = c.post(f"/me/assignments/{a2['id']}/topic", json={"topic": "Trains", "free_text": "steam engines"}, headers=auth(world.p1))
    assert r.status_code == 200 and r.json()["status"] == "content_pending" and r.json()["topic"] == "Trains"
    assert c.get(f"/me/assignments/{a2['id']}/content", headers=auth(world.p1)).status_code == 404
    # attach content
    r = c.post(f"/studies/{world.study_a}/content", json={"title": "Draft", "definition": CONTENT}, headers=auth(world.researcher_a))
    assert c.put(f"{base}/{a2['id']}", json={"content_id": r.json()["id"]}, headers=auth(world.researcher_a)).status_code == 422  # not approved
    cid = approved_content(world)
    assert c.put(f"{base}/{a1['id']}", json={"content_id": cid}, headers=auth(world.researcher_a)).status_code == 422  # gradual path takes no content
    r = c.put(f"{base}/{a2['id']}", json={"content_id": cid}, headers=auth(world.researcher_a))
    assert r.status_code == 200 and r.json()["status"] == "ready" and r.json()["content_title"] == "Trains talk"
    content = c.get(f"/me/assignments/{a2['id']}/content", headers=auth(world.p1)).json()
    assert content["segments"][0]["text"] == "Hi Sam, let's talk about Trains."
    assert content["segments"][0]["question"]["prompt"] == "Which do you prefer, Sam?"
    assert "correct" not in content["comprehension"][0] and content["comprehension"][0]["options"] == ["Trains", "Weather"]
    assert content["segments"][0]["media_url"].startswith("/media/") and content["segments"][1]["media_url"] != content["segments"][0]["media_url"]
    assert c.get(content["segments"][0]["media_url"]).status_code == 200
    # cancel and staff listing
    listed = c.get(base, headers=auth(world.analyst_a)).json()
    assert [a["status"] for a in listed] == ["ready", "ready"]
    assert c.put(f"{base}/{a1['id']}", json={"status": "cancelled"}, headers=auth(world.researcher_a)).json()["status"] == "cancelled"
    r = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": SYNTHETIC_MODEL, "assignment_id": a1["id"]}, headers=auth(world.p1))
    assert r.status_code == 409


def test_gradual_path_progression_and_outcomes(world):
    c = world.c
    make_ready(world, world.p1)
    p = auth(world.p1)
    gradual = publish(world, GRADUAL, "Gradual")
    aid = c.post(f"/studies/{world.study_a}/participants/P-001/assignments", json={"protocol_id": gradual}, headers=auth(world.researcher_a)).json()["id"]
    sid = start_practice_session(world, world.p1, aid)
    s = c.get(f"/me/sessions/{sid}", headers=p).json()
    assert s["assignment_id"] == aid and s["protocol"]["path"] == "gradual_face" and s["protocol"]["version"] == 1
    assert c.get("/me/assignments", headers=p).json()[0]["status"] == "in_progress"
    # baseline segment
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "baseline", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 0, "type": "segment_start"}, headers=p)
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=20, t0=100)}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 2100, "type": "segment_end"}, headers=p)
    # practice stage 0
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "practice", "layout": LAYOUT, "stage_index": 0}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 3000, "type": "segment_start"}, headers=p)
    bad = {"trials": [{"stage_index": 0, "trial_index": 0, "t_ms": 3100, "number_shown": "7", "zone": "near_eyes", "position": {"x": 1, "y": 1}, "face_level": 0, "response": "7"}]}
    assert c.post(f"/me/sessions/{sid}/trials", json=bad, headers=p).status_code == 422
    ok = {"trials": [
        {"stage_index": 0, "trial_index": 0, "t_ms": 3100, "number_shown": "7", "zone": "outside", "position": {"x": 100, "y": 100}, "face_level": 0, "response": "7", "response_ms": 900},
        {"stage_index": 0, "trial_index": 1, "t_ms": 5100, "number_shown": "42", "zone": "outside", "position": {"x": 1100, "y": 600}, "face_level": 0, "response": "24", "response_ms": 1200},
    ]}
    r = c.post(f"/me/sessions/{sid}/trials", json=ok, headers=p)
    assert r.status_code == 200 and r.json() == {"stored": 2, "correct": 1}
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 7000, "type": "comfort_answer", "payload": {"value": 9, "stage_index": 0}}, headers=p).status_code == 422
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 7000, "type": "comfort_answer", "payload": {"value": 4, "stage_index": 0}}, headers=p).status_code == 200
    r = c.post(f"/me/sessions/{sid}/stage-result", json={"stage_index": 0, "comfort_value": 4}, headers=p)
    assert r.status_code == 200 and r.json()["decision"] == "advance" and r.json()["next_stage_index"] == 1 and r.json()["correct_ratio"] == 0.5
    # stage 1: low comfort -> easier (back to stage 0); a second low answer in a row -> stop
    c.post(f"/me/sessions/{sid}/trials", json={"trials": [{"stage_index": 1, "trial_index": 0, "t_ms": 8000, "number_shown": "3", "zone": "outside", "position": {}, "face_level": 1, "response": "3"}, {"stage_index": 1, "trial_index": 1, "t_ms": 9000, "number_shown": "5", "zone": "outside", "position": {}, "face_level": 1, "response": "5"}]}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 10000, "type": "comfort_answer", "payload": {"value": 2, "stage_index": 1}}, headers=p)
    r = c.post(f"/me/sessions/{sid}/stage-result", json={"stage_index": 1, "comfort_value": 2}, headers=p).json()
    assert r["decision"] == "easier" and r["next_stage_index"] == 0 and r["reason"] == "low_comfort"
    c.post(f"/me/sessions/{sid}/trials", json={"trials": [{"stage_index": 0, "trial_index": 0, "t_ms": 11000, "number_shown": "8", "zone": "outside", "position": {}, "face_level": 0, "response": "8"}, {"stage_index": 0, "trial_index": 1, "t_ms": 12000, "number_shown": "9", "zone": "outside", "position": {}, "face_level": 0, "response": "9"}]}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 13000, "type": "comfort_answer", "payload": {"value": 1, "stage_index": 0}}, headers=p)
    r = c.post(f"/me/sessions/{sid}/stage-result", json={"stage_index": 0, "comfort_value": 1}, headers=p).json()
    assert r["decision"] == "stop" and r["reason"] == "low_comfort_twice"
    # incomplete and accuracy holds never advance; the last stage completes
    r = c.post(f"/me/sessions/{sid}/stage-result", json={"stage_index": 2, "comfort_value": 5}, headers=p).json()
    assert r["decision"] == "hold" and r["reason"] == "incomplete"
    c.post(f"/me/sessions/{sid}/trials", json={"trials": [{"stage_index": 2, "trial_index": 0, "t_ms": 14000, "number_shown": "4", "zone": "near_eyes", "position": {}, "face_level": 1, "response": "4"}, {"stage_index": 2, "trial_index": 1, "t_ms": 15000, "number_shown": "6", "zone": "near_eyes", "position": {}, "face_level": 1, "response": "1"}]}, headers=p)
    r = c.post(f"/me/sessions/{sid}/stage-result", json={"stage_index": 2, "comfort_value": 5}, headers=p).json()
    assert r["decision"] == "hold" and r["reason"] == "accuracy"
    c.post(f"/me/sessions/{sid}/trials", json={"trials": [{"stage_index": 2, "trial_index": 0, "t_ms": 16000, "number_shown": "4", "zone": "near_eyes", "position": {}, "face_level": 1, "response": "4"}, {"stage_index": 2, "trial_index": 1, "t_ms": 17000, "number_shown": "6", "zone": "near_eyes", "position": {}, "face_level": 1, "response": "6"}]}, headers=p)
    r = c.post(f"/me/sessions/{sid}/stage-result", json={"stage_index": 2, "comfort_value": 5}, headers=p).json()
    assert r["decision"] == "complete" and r["next_stage_index"] is None
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 18000, "type": "segment_end"}, headers=p)
    # outcomes and closing
    assert c.post(f"/me/sessions/{sid}/answers", json={"segment_id": "s1", "question_id": "q1", "kind": "interaction", "option": "x", "t_ms": 1}, headers=p).status_code == 409
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 19000, "type": "end", "payload": {"reason": "completed"}}, headers=p)
    s = c.get(f"/me/sessions/{sid}", headers=p).json()
    out = s["outcomes"]
    assert out["number_task"] == {"trials": 10, "correct": 8, "share": 0.8, "stages_completed": 2}
    assert out["comfort"]["answers"] == 3 and out["comfort"]["min"] == 1 and out["comfort"]["low_count"] == 2 and out["comfort"]["ended_early"] is False
    assert out["gaze"]["baseline_eye_share"] == 1.0 and out["gaze"]["post_eye_share"] is None and out["gaze"]["evaluable"] is False
    assert out["improvement"]["eligible"] is False and out["improvement"]["result"] is None
    assert [x["decision"] for x in s["stages"]] == ["advance", "easier", "stop", "hold", "hold", "complete"]
    assert c.get("/me/assignments", headers=p).json()[0]["status"] == "completed"
    detail = c.get(f"/studies/{world.study_a}/sessions/{sid}", headers=auth(world.analyst_a)).json()
    assert len(detail["trials"]) == 10 and detail["comfort_answers"][0]["value"] == 4 and detail["protocol"]["name"] == "Gradual"
    assert c.get(f"/studies/{world.study_a}/sessions/{sid}", headers=auth(world.researcher_b)).status_code == 403


def test_interest_path_answers_and_improvement(world):
    c = world.c
    make_ready(world, world.p1)
    p = auth(world.p1)
    interest = publish(world, INTEREST, "Interest")
    base = f"/studies/{world.study_a}/participants/P-001/assignments"
    aid = c.post(base, json={"protocol_id": interest}, headers=auth(world.researcher_a)).json()["id"]
    c.post(f"/me/assignments/{aid}/topic", json={"topic": "Trains"}, headers=p)
    cid = approved_content(world)
    c.put(f"{base}/{aid}", json={"content_id": cid}, headers=auth(world.researcher_a))
    sid = start_practice_session(world, world.p1, aid, model=REAL_MODEL)
    # baseline: half eyes, half mouth
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "baseline", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 0, "type": "segment_start"}, headers=p)
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=10, t0=100) + samples_for(640, 480, n=10, t0=1100)}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 2100, "type": "segment_end"}, headers=p)
    # conversation
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "practice", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 3000, "type": "segment_start"}, headers=p)
    assert c.post(f"/me/sessions/{sid}/trials", json={"trials": [{"stage_index": 0, "trial_index": 0, "t_ms": 1, "number_shown": "1", "zone": "outside", "face_level": 0}]}, headers=p).status_code == 409
    assert c.post(f"/me/sessions/{sid}/answers", json={"segment_id": "s1", "question_id": "q1", "kind": "interaction", "option": "Cars", "t_ms": 4000}, headers=p).status_code == 422
    r = c.post(f"/me/sessions/{sid}/answers", json={"segment_id": "s1", "question_id": "q1", "kind": "interaction", "option": "Trains", "t_ms": 4000}, headers=p)
    assert r.status_code == 200 and r.json() == {"correct": None, "next_segment_id": "s2"}
    assert c.post(f"/me/sessions/{sid}/answers", json={"segment_id": "s2", "question_id": "x", "kind": "interaction", "option": "Trains", "t_ms": 4500}, headers=p).status_code == 422
    assert c.post(f"/me/sessions/{sid}/answers", json={"segment_id": "s2", "question_id": "c1", "kind": "comprehension", "option": "{{topic}}", "t_ms": 5000}, headers=p).status_code == 422
    r = c.post(f"/me/sessions/{sid}/answers", json={"segment_id": "s2", "question_id": "c1", "kind": "comprehension", "option": "Trains", "t_ms": 5000}, headers=p)
    assert r.json() == {"correct": True, "next_segment_id": None}
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 5500, "type": "segment_end"}, headers=p)
    # post: all eyes
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "post", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 6000, "type": "segment_start"}, headers=p)
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=20, t0=6100)}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 8100, "type": "segment_end"}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 8200, "type": "comfort_answer", "payload": {"value": 4}}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 8300, "type": "end", "payload": {"reason": "completed"}}, headers=p)
    out = c.get(f"/me/sessions/{sid}", headers=p).json()["outcomes"]
    assert out["gaze"]["evaluable"] is True and out["gaze"]["baseline_eye_share"] < out["gaze"]["post_eye_share"] == 1.0
    assert out["comprehension"] == {"answered": 1, "correct": 1, "share": 1.0}
    assert out["improvement"] == {"eligible": True, "result": True, "criteria": {"eye_share_up": True, "comfort_not_worse": True, "comprehension_maintained": True}, "reason": None}
    detail = c.get(f"/studies/{world.study_a}/sessions/{sid}", headers=auth(world.researcher_a)).json()
    assert [a["kind"] for a in detail["answers"]] == ["interaction", "comprehension"] and detail["outcomes"]["improvement"]["result"] is True


def test_improvement_needs_all_three(world):
    c = world.c
    make_ready(world, world.p1)
    p = auth(world.p1)
    gradual = publish(world, GRADUAL, "Gradual")
    aid = c.post(f"/studies/{world.study_a}/participants/P-001/assignments", json={"protocol_id": gradual}, headers=auth(world.researcher_a)).json()["id"]
    sid = start_practice_session(world, world.p1, aid, model=REAL_MODEL)
    for label, t0, pts in (("baseline", 0, [(540, 270)] * 20), ("post", 5000, [(640, 480)] * 20)):
        c.post(f"/me/sessions/{sid}/layout", json={"segment": label, "layout": LAYOUT}, headers=p)
        c.post(f"/me/sessions/{sid}/events", json={"t_ms": t0, "type": "segment_start"}, headers=p)
        c.post(f"/me/sessions/{sid}/samples", json={"samples": [s for i, (x, y) in enumerate(pts) for s in samples_for(x, y, n=1, t0=t0 + 100 + i * 100)]}, headers=p)
        c.post(f"/me/sessions/{sid}/events", json={"t_ms": t0 + 2200, "type": "segment_end"}, headers=p)
    c.post(f"/me/sessions/{sid}/trials", json={"trials": [{"stage_index": 0, "trial_index": 0, "t_ms": 3000, "number_shown": "2", "zone": "outside", "face_level": 0, "response": "2"}]}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 9000, "type": "comfort_answer", "payload": {"value": 5}}, headers=p)
    out = c.get(f"/me/sessions/{sid}", headers=p).json()["outcomes"]
    assert out["gaze"]["evaluable"] is True and out["improvement"]["eligible"] is True
    assert out["improvement"]["result"] is False and out["improvement"]["criteria"]["eye_share_up"] is False
