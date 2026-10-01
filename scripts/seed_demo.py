"""Create a demo study on a LOCAL development server, through the public API only.

Used by scripts/run-local.ps1 on the first run. Never point it at a server with real participants.
It creates: a researcher, a study with an information sheet and a demographics form, one ready demo
participant with the gradual, interest and live conversation paths assigned, approved sample content (the development sample face,
not a real speaker), and a second, unused invitation link for trying the sign-up flow yourself.
Prints one JSON object. Exits without changes when the demo study already exists.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import httpx

STUDY_NAME = "Demo study (local)"
REPO = Path(__file__).resolve().parents[1]
SAMPLE_FACE = REPO / "backend" / "eyetracking" / "infrastructure" / "ai" / "assets" / "sample-face.webm"

COMFORT_LABELS = ["Very uncomfortable", "Uncomfortable", "Neutral", "Comfortable", "Very comfortable"]
PROGRESSION = {"hold_on_invalid_share_above": 0.3, "easier_on_comfort_below_min": True, "stop_on_two_low_comfort": True}
GRADUAL = {
    "path": "gradual_face",
    "baseline_seconds": 20,
    "post_seconds": 20,
    "comfort": {"scale_max": 5, "labels": COMFORT_LABELS, "min_ok": 3, "ask_every_stage": True},
    "progression": PROGRESSION,
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
    "baseline_seconds": 20,
    "post_seconds": 20,
    "comfort": {"scale_max": 5, "labels": COMFORT_LABELS, "min_ok": 3, "ask_every_stage": False},
    "progression": PROGRESSION,
    "interest": {"interaction_points": 1},
}
LIVE = {
    "path": "live_conversation",
    "baseline_seconds": 20,
    "post_seconds": 20,
    "comfort": {"scale_max": 5, "labels": COMFORT_LABELS, "min_ok": 3, "ask_every_stage": False},
    "progression": PROGRESSION,
    "live": {"max_turns": 6, "max_minutes": 6, "max_reply_words": 40, "max_participant_chars": 400, "input_modes": ["typed", "speech"], "store_transcript": False,
             "face_layout": {"face_box": [0.3, 0.1, 0.4, 0.8], "eye_region": [0.3, 0.25, 0.4, 0.2], "mouth_region": [0.3, 0.55, 0.4, 0.25]}},
}
FACE = {"face_box": [0.3, 0.1, 0.4, 0.8], "eye_region": [0.3, 0.25, 0.4, 0.2], "mouth_region": [0.3, 0.55, 0.4, 0.25]}
CONTENT = {
    "start_segment": "s1",
    "post_segment": "s3",
    "segments": [
        {"id": "s1", "text": "Hi {{display_name}}, let's talk about {{topic}}.", "media_key": "s1.webm", "duration_s": 12, "face_layout": FACE,
         "question": {"id": "q1", "prompt": "Which do you prefer, {{display_name}}?", "options": ["Trains", "Planes"], "branches": {"Trains": "s2", "Planes": "s2"}}},
        {"id": "s2", "text": "Great choice.", "media_key": "s2.webm", "duration_s": 8, "face_layout": FACE, "question": None},
        {"id": "s3", "text": "Thanks for listening.", "media_key": "s3.webm", "duration_s": 8, "face_layout": FACE, "question": None},
    ],
    "comprehension": [{"id": "c1", "prompt": "What did we talk about?", "options": ["{{topic}}", "Weather"], "correct": "{{topic}}"}],
}
SHEET = {
    "aims": "Try the practice apps on this computer. Demo data only.",
    "discomfort_sources": "Looking at faces and eyes; a number near the eyes; camera use.",
    "benefits": "None; this is a local demo.",
    "data_handling": "Gaze estimates stay in the local development database on this computer.",
    "stop_rules": "You can pause or end at any time.",
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api", default="http://127.0.0.1:8000")
    ap.add_argument("--participant-url", default="http://localhost:8080")
    ap.add_argument("--admin-email", required=True)
    ap.add_argument("--admin-password", required=True)
    ap.add_argument("--researcher-email", required=True)
    ap.add_argument("--researcher-password", required=True)
    ap.add_argument("--participant-email", required=True)
    ap.add_argument("--participant-password", required=True)
    a = ap.parse_args()
    if not a.api.startswith(("http://127.0.0.1", "http://localhost")):
        print("seed_demo only runs against a local server", file=sys.stderr)
        return 2

    c = httpx.Client(base_url=a.api, timeout=30)

    def login(email: str, password: str) -> dict:
        r = c.post("/auth/login", json={"email": email, "password": password})
        r.raise_for_status()
        return {"Authorization": f"Bearer {r.json()['access_token']}"}

    def ok(r: httpx.Response, what: str) -> dict | list:
        if r.status_code >= 300:
            raise SystemExit(f"{what} failed: HTTP {r.status_code} {r.text[:300]}")
        return r.json() if r.content else {}

    admin = login(a.admin_email, a.admin_password)
    if any(s["name"] == STUDY_NAME for s in ok(c.get("/studies", headers=admin), "list studies")):
        print(json.dumps({"skipped": True, "reason": f"'{STUDY_NAME}' already exists"}))
        return 0

    study = ok(c.post("/studies", json={"name": STUDY_NAME}, headers=admin), "create study")["id"]
    researcher = ok(c.post("/users", json={"email": a.researcher_email, "password": a.researcher_password, "role": "researcher"}, headers=admin), "create researcher")
    ok(c.post(f"/studies/{study}/members", json={"user_id": researcher["id"], "study_role": "researcher", "can_link_identity": False}, headers=admin), "add researcher")
    res = login(a.researcher_email, a.researcher_password)
    ok(c.put(f"/studies/{study}/information-sheet", json=SHEET, headers=res), "information sheet")
    ok(c.put(f"/studies/{study}/demographics-form", json={"fields": [{"key": "age", "label": "Age", "type": "number", "required": True}]}, headers=res), "demographics form")
    ok(c.put(f"/studies/{study}/debrief-form", json={"enabled": True}, headers=res), "debrief questions")

    inv = ok(c.post(f"/studies/{study}/invitations", json={}, headers=res), "invitation")
    joined = ok(c.post(f"/invitations/{inv['token']}/accept", json={"email": a.participant_email, "password": a.participant_password}), "accept invitation")
    pt = {"Authorization": f"Bearer {joined['access_token']}"}
    ok(c.post("/me/consent", json={"sheet_version": 1, "participate": True}, headers=pt), "consent")
    ok(c.put("/me/demographics", json={"answers": {"age": 30}}, headers=pt), "demographics")
    ok(c.put("/me/profile", json={"display_name": "Sam", "response_mode": "four_choice", "interests": ["Trains", "Gardening"]}, headers=pt), "profile")

    def publish(definition: dict, name: str) -> int:
        pid = ok(c.post(f"/studies/{study}/protocols", json={"name": name, "definition": definition}, headers=res), f"protocol {name}")["id"]
        ok(c.post(f"/studies/{study}/protocols/{pid}/publish", headers=res), f"publish {name}")
        return pid

    gradual = publish(GRADUAL, "Gradual face (demo)")
    interest = publish(INTEREST, "Interest conversation (demo)")
    live = publish(LIVE, "Live conversation (demo)")
    content = ok(c.post(f"/studies/{study}/content", json={"title": "Trains talk (sample face)", "definition": CONTENT, "topic_tags": ["Trains"], "face_id": "sample", "voice_id": "sample"}, headers=res), "content")["id"]
    video = SAMPLE_FACE.read_bytes()
    for key in ("s1.webm", "s2.webm", "s3.webm"):
        ok(c.post(f"/studies/{study}/content/{content}/media/{key}", files={"file": (key, video, "video/webm")}, headers=res), f"upload {key}")
    ok(c.post(f"/studies/{study}/content/{content}/approve", headers=res), "approve content")
    base = f"/studies/{study}/participants/{joined['participant_code']}/assignments"
    ok(c.post(base, json={"protocol_id": gradual}, headers=res), "assign gradual")
    ok(c.post(base, json={"protocol_id": interest}, headers=res), "assign interest")
    ok(c.post(base, json={"protocol_id": live}, headers=res), "assign live conversation")

    spare = ok(c.post(f"/studies/{study}/invitations", json={}, headers=res), "spare invitation")
    print(json.dumps({
        "skipped": False,
        "study": STUDY_NAME,
        "participant_code": joined["participant_code"],
        "invitation_link": f"{a.participant_url.rstrip('/')}/?invitation={spare['token']}",
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
