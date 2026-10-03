"""Step 2: sessions, calibration, validation, recording and coded staff views."""
import pytest

from eyetracking.domain.measurement import GazeSample, SessionEvent, coverage, segments_from_events

from .conftest import FORM, SHEET, auth
from .measurement_helpers import LAYOUT, calibration_targets, raw, samples_for, validation_targets

DEVICE = {"platform": "web", "user_agent": "test"}
SCREEN = {"w": 1280, "h": 720, "dpr": 1}
CAMERA = {"label": "test-cam", "w": 640, "h": 480}
SYNTHETIC_MODEL = {"model_id": "synthetic-head-proxy", "model_version": "0", "synthetic": True}
REAL_MODEL = {"model_id": "l2cs-net-resnet50", "model_version": "gaze360.pkl", "synthetic": False}


def make_ready(world, participant_token: str):
    c = world.c
    c.put(f"/studies/{world.study_a}/information-sheet", json=SHEET, headers=auth(world.researcher_a))
    c.put(f"/studies/{world.study_a}/demographics-form", json=FORM, headers=auth(world.researcher_a))
    version = c.get("/me/information-sheet", headers=auth(participant_token)).json()["version"]
    c.post("/me/consent", json={"sheet_version": version, "participate": True}, headers=auth(participant_token))
    r = c.put("/me/demographics", json={"answers": {"age": 25, "diagnosis": True}}, headers=auth(participant_token))
    assert r.status_code == 200


def new_session(world, token: str, model=SYNTHETIC_MODEL) -> int:
    r = world.c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": model}, headers=auth(token))
    assert r.status_code == 201, r.text
    return r.json()["id"]


def calibrate(world, token: str, sid: int):
    c = world.c
    assert c.post(f"/me/sessions/{sid}/camera-check", json={"face_detected": True, "face_conf": 0.9, "lighting_ok": True, "frame_w": 640, "frame_h": 480}, headers=auth(token)).status_code == 200
    r = c.post(f"/me/sessions/{sid}/calibration", json={"targets": calibration_targets()}, headers=auth(token))
    assert r.status_code == 200, r.text
    return r.json()


def test_session_needs_readiness_and_flags_synthetic(world):
    c = world.c
    r = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": SYNTHETIC_MODEL}, headers=auth(world.p1))
    assert r.status_code == 403 and "not ready" in r.json()["detail"] and "no_information_sheet_published" in r.json()["detail"]
    make_ready(world, world.p1)
    r = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": SYNTHETIC_MODEL}, headers=auth(world.p1))
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "created" and body["synthetic"] is True and "synthetic_estimator" in body["notes"]
    assert body["eye_region_attention"] == {"evaluable": False, "share": None, "reason": "synthetic_estimator"}
    assert c.post("/me/sessions", json={"device": DEVICE, "screen": {}, "camera": CAMERA, "gaze_model": SYNTHETIC_MODEL}, headers=auth(world.p1)).status_code == 422
    assert [s["id"] for s in c.get("/me/sessions", headers=auth(world.p1)).json()] == [body["id"]]


def test_session_isolation(world):
    c = world.c
    make_ready(world, world.p1)
    sid = new_session(world, world.p1)
    for method, url in (("get", f"/me/sessions/{sid}"), ("post", f"/me/sessions/{sid}/events")):
        r = getattr(c, method)(url, headers=auth(world.p2), **({"json": {"t_ms": 0, "type": "note"}} if method == "post" else {}))
        assert r.status_code == 404, url
    assert c.get(f"/studies/{world.study_a}/sessions/{sid}", headers=auth(world.researcher_a)).status_code == 200
    assert c.get(f"/studies/{world.study_a}/sessions/{sid}", headers=auth(world.researcher_b)).status_code == 403
    assert c.get(f"/studies/{world.study_b}/sessions/{sid}", headers=auth(world.researcher_b)).status_code == 404
    assert c.get(f"/studies/{world.study_a}/sessions", headers=auth(world.p1)).status_code == 403
    assert c.get("/me/sessions", headers=auth(world.researcher_a)).status_code == 403


def test_camera_check_and_calibration_rules(world):
    c = world.c
    make_ready(world, world.p1)
    sid = new_session(world, world.p1)
    p = auth(world.p1)
    assert c.post(f"/me/sessions/{sid}/calibration", json={"targets": calibration_targets()}, headers=p).status_code == 409
    r = c.post(f"/me/sessions/{sid}/camera-check", json={"face_detected": False, "face_conf": 0.0, "lighting_ok": True}, headers=p)
    assert r.json()["status"] == "created" and "camera_check_failed" in r.json()["notes"]
    r = c.post(f"/me/sessions/{sid}/camera-check", json={"face_detected": True, "face_conf": 0.9, "lighting_ok": True, "frame_w": 640, "frame_h": 480}, headers=p)
    assert r.json()["status"] == "camera_ok"
    # too few usable targets
    few = calibration_targets()[:3]
    r = c.post(f"/me/sessions/{sid}/calibration", json={"targets": few}, headers=p)
    assert r.status_code == 422 and "at least 5" in r.json()["detail"]
    # low-confidence samples do not count
    weak = [dict(t, samples=samples_for(t["x"], t["y"], conf=0.2)) for t in calibration_targets()]
    assert c.post(f"/me/sessions/{sid}/calibration", json={"targets": weak}, headers=p).status_code == 422
    r = c.post(f"/me/sessions/{sid}/calibration", json={"targets": calibration_targets()}, headers=p)
    assert r.status_code == 200
    cal = r.json()
    assert cal["accepted"] is True and cal["residual_px_median"] < 30 and len(cal["per_target"]) == 9
    s = c.get(f"/me/sessions/{sid}", headers=p).json()
    assert s["status"] == "calibrated" and s["calibration_valid"] is True and s["calibration"]["points"] == 9


def test_camera_check_records_the_chosen_camera(world):
    c = world.c
    make_ready(world, world.p1)
    sid = new_session(world, world.p1)
    p = auth(world.p1)
    staff = f"/studies/{world.study_a}/sessions/{sid}"
    # The participant picked another camera before checking: the session keeps the checked one.
    check = {"face_detected": True, "face_conf": 0.9, "lighting_ok": True, "frame_w": 1280, "frame_h": 720, "camera_label": "HD Pro Webcam C920"}
    assert c.post(f"/me/sessions/{sid}/camera-check", json=check, headers=p).status_code == 200
    detail = c.get(staff, headers=auth(world.researcher_a)).json()
    assert detail["camera"] == {"label": "HD Pro Webcam C920", "w": 1280, "h": 720}
    noted = [e["payload"]["camera_check"] for e in detail["events"] if "camera_check" in e["payload"]]
    assert noted[-1]["camera_label"] == "HD Pro Webcam C920"
    # Without a label the creation record stays as it was.
    sid2 = new_session(world, world.p1)
    assert c.post(f"/me/sessions/{sid2}/camera-check", json=dict(check, camera_label=None), headers=p).status_code == 200
    assert c.get(f"/studies/{world.study_a}/sessions/{sid2}", headers=auth(world.researcher_a)).json()["camera"] == CAMERA
    # A different camera after calibration makes the calibration invalid.
    calibrate(world, world.p1, sid)
    assert c.get(f"/me/sessions/{sid}", headers=p).json()["calibration_valid"] is True
    r = c.post(f"/me/sessions/{sid}/camera-check", json=dict(check, camera_label="Integrated Camera"), headers=p)
    assert r.json()["calibration_valid"] is False and "calibration_invalidated:camera_changed" in r.json()["notes"]


def test_validation_recording_and_summary(world):
    c = world.c
    make_ready(world, world.p1)
    sid = new_session(world, world.p1, model=REAL_MODEL)
    p = auth(world.p1)
    # validation before calibration
    assert c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=p).status_code == 409
    calibrate(world, world.p1, sid)
    r = c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=p)
    assert r.status_code == 200, r.text
    v = r.json()
    assert v["passed"] is True and v["reasons"] == [] and [t["majority"] for t in v["targets"]] == ["eye", "eye", "mouth", "outside"]
    assert c.get(f"/me/sessions/{sid}", headers=p).json()["status"] == "validated"

    # recording needs a layout and a running segment
    batch = {"samples": samples_for(540, 270, n=10, t0=1000)}
    assert c.post(f"/me/sessions/{sid}/samples", json=batch, headers=p).status_code == 409
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 900, "type": "segment_start"}, headers=p).status_code == 409  # no layout
    assert c.post(f"/me/sessions/{sid}/layout", json={"segment": "baseline", "layout": LAYOUT}, headers=p).status_code == 200
    r = c.post(f"/me/sessions/{sid}/events", json={"t_ms": 900, "type": "segment_start"}, headers=p)
    assert r.status_code == 200 and r.json()["status"] == "running"
    mixed = {"samples": samples_for(540, 270, n=8, t0=1000) + [raw(0, 0, t_ms=1800, conf=0.1), raw(0, 0, t_ms=1900, face=False)]}
    r = c.post(f"/me/sessions/{sid}/samples", json=mixed, headers=p)
    assert r.status_code == 200 and r.json() == {"stored": 10, "invalid": 2}

    # pause / resume
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 2000, "type": "resume"}, headers=p).status_code == 409
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 2000, "type": "pause"}, headers=p).json()["status"] == "paused"
    assert c.post(f"/me/sessions/{sid}/samples", json=batch, headers=p).status_code == 409
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 2500, "type": "resume"}, headers=p).json()["status"] == "running"

    # a camera change invalidates calibration until a new calibration is posted
    r = c.post(f"/me/sessions/{sid}/events", json={"t_ms": 2600, "type": "camera_changed"}, headers=p)
    assert r.json()["calibration_valid"] is False
    r = c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=5, t0=2700)}, headers=p)
    assert r.status_code == 409 and "calibration" in r.json()["detail"]
    assert c.post(f"/me/sessions/{sid}/calibration", json={"targets": calibration_targets()}, headers=p).status_code == 200
    summary = c.get(f"/me/sessions/{sid}", headers=p).json()
    assert summary["status"] == "running" and summary["calibration_valid"] is True
    assert summary["validation"] is None and "validation_predates_latest_calibration" in summary["notes"]
    assert summary["eye_region_attention"]["reason"] == "validation_missing"
    # re-validate, record more, end
    assert c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=p).json()["passed"] is True
    assert c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=10, t0=3000)}, headers=p).status_code == 200
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 4000, "type": "segment_end"}, headers=p).status_code == 200
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 4100, "type": "end", "payload": {"reason": "nope"}}, headers=p).status_code == 422
    r = c.post(f"/me/sessions/{sid}/events", json={"t_ms": 4100, "type": "end", "payload": {"reason": "completed"}}, headers=p)
    assert r.json()["status"] == "ended" and r.json()["ended_at"] is not None
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 4200, "type": "note"}, headers=p).status_code == 409

    summary = c.get(f"/me/sessions/{sid}", headers=p).json()
    cov = summary["coverage"]
    assert cov["total_ms"] == 3100 and cov["classifiable_ms"] > 0 and cov["missing_ms"] > 0
    assert cov["total_ms"] == cov["classifiable_ms"] + cov["uncertain_ms"] + cov["missing_ms"]
    assert summary["region_shares"]["eye"] > 0.9 and summary["face_region_attention"]["share"] > 0.9
    assert summary["eye_region_attention"]["evaluable"] is True and summary["eye_region_attention"]["share"] == summary["region_shares"]["eye"]
    assert summary["segments"] == [{"label": "baseline", "started_ms": 900, "ended_ms": 4000}]


def test_validation_failure_reasons_and_continue_rule(world):
    c = world.c
    make_ready(world, world.p1)
    sid = new_session(world, world.p1, model=REAL_MODEL)
    p = auth(world.p1)
    calibrate(world, world.p1, sid)
    r = c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets(eye_ok=False)}, headers=p)
    v = r.json()
    assert v["passed"] is False and any(x.startswith("correct_ratio_below") for x in v["reasons"]) and v["correct_ratio"] == 0.5
    # uncertain samples and a too-small eye region each add a reason
    small = dict(LAYOUT, eye_region=[440, 190, 400, 4], mouth_region=[440, 390, 400, 190])
    targets = validation_targets()
    targets[0]["samples"] = samples_for(540, 270, conf=0.1)
    v = c.post(f"/me/sessions/{sid}/validation", json={"layout": small, "targets": targets}, headers=p).json()
    assert any(x.startswith("uncertain_ratio_above") for x in v["reasons"]) and any("eye_region_smaller" in x for x in v["reasons"])
    # missing region and bad layout
    v = c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()[:2]}, headers=p).json()
    assert "missing_target_regions:mouth,outside" in v["reasons"]
    bad = dict(LAYOUT, eye_region=[440, 500, 400, 100])
    assert c.post(f"/me/sessions/{sid}/validation", json={"layout": bad, "targets": validation_targets()}, headers=p).status_code == 422
    # the study can forbid continuing without a passed validation
    assert c.put(f"/studies/{world.study_a}/measurement-settings", json={"allow_continue_without_validation": False}, headers=auth(world.researcher_a)).status_code == 200
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "baseline", "layout": LAYOUT}, headers=p)
    r = c.post(f"/me/sessions/{sid}/events", json={"t_ms": 10, "type": "segment_start"}, headers=p)
    assert r.status_code == 409 and "validation" in r.json()["detail"]
    assert c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=p).json()["passed"] is True
    assert c.post(f"/me/sessions/{sid}/events", json={"t_ms": 10, "type": "segment_start"}, headers=p).json()["status"] == "running"
    summary = c.get(f"/me/sessions/{sid}", headers=p).json()
    assert summary["eye_region_attention"]["reason"] == "no_classifiable_time"


def test_measurement_settings_access(world):
    c = world.c
    defaults = c.get("/me/measurement-settings", headers=auth(world.p1)).json()
    assert defaults["validation_min_correct"] == 0.8 and defaults["calibration_points"] == 9
    url = f"/studies/{world.study_a}/measurement-settings"
    assert c.get(url, headers=auth(world.analyst_a)).status_code == 200
    assert c.put(url, json={"calibration_points": 12}, headers=auth(world.analyst_a)).status_code == 403
    assert c.put(url, json={"calibration_points": 3}, headers=auth(world.researcher_a)).status_code == 422
    assert c.put(url, json={"validation_min_correct": 1.5}, headers=auth(world.researcher_a)).status_code == 422
    r = c.put(url, json={"calibration_points": 12, "min_region_to_error_ratio": 3.0}, headers=auth(world.researcher_a))
    assert r.status_code == 200 and r.json()["calibration_points"] == 12
    assert c.get("/me/measurement-settings", headers=auth(world.p1)).json()["min_region_to_error_ratio"] == 3.0
    assert c.get(f"/studies/{world.study_b}/measurement-settings", headers=auth(world.researcher_a)).status_code == 403


def test_staff_views_are_coded_and_paged(world):
    c = world.c
    make_ready(world, world.p1)
    sid = new_session(world, world.p1)
    p = auth(world.p1)
    calibrate(world, world.p1, sid)
    c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=p)
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "baseline", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 0, "type": "segment_start"}, headers=p)
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=30, t0=100)}, headers=p)
    rows = c.get(f"/studies/{world.study_a}/sessions", headers=auth(world.researcher_a)).json()
    assert len(rows) == 1 and rows[0]["participant_code"] == "P-001" and rows[0]["synthetic"] is True
    assert rows[0]["validation_passed"] is True and rows[0]["eye_region_attention"]["reason"] == "synthetic_estimator"
    assert "email" not in str(rows)
    detail = c.get(f"/studies/{world.study_a}/sessions/{sid}", headers=auth(world.analyst_a)).json()
    assert detail["participant_code"] == "P-001" and len(detail["validation_targets"]) == 4 and detail["camera"]["label"] == "test-cam"
    assert [e["type"] for e in detail["events"]] == ["note", "segment_start"]
    page = c.get(f"/studies/{world.study_a}/sessions/{sid}/samples?offset=0&limit=10", headers=auth(world.researcher_a)).json()
    assert page["total"] == 30 and len(page["items"]) == 10 and page["items"][0]["region"] == "eye" and page["items"][0]["segment"] == "baseline"
    assert c.get(f"/studies/{world.study_a}/sessions/{sid}/samples", headers=auth(world.researcher_b)).status_code == 403


def test_coverage_counts_gaps_as_missing():
    events = [SessionEvent(session_id=1, t_ms=0, type="segment_start", payload={"segment": "baseline"}), SessionEvent(session_id=1, t_ms=10000, type="segment_end")]
    samples = [GazeSample(session_id=1, t_ms=t, x=1.0, y=1.0, conf=0.9, valid=True, region="eye", segment="baseline") for t in range(0, 2001, 100)]
    samples.append(GazeSample(session_id=1, t_ms=2100, x=None, y=None, conf=0.0, valid=False, region="uncertain", segment="baseline"))
    segs = segments_from_events(events, 2100)
    cov = coverage(samples, segs)
    assert cov.total_ms == 10000 and cov.classifiable_ms == 2100 and cov.uncertain_ms == 200 and cov.missing_ms == 7700
    # an unfinished segment ends at the last sample
    segs = segments_from_events(events[:1], 2100)
    assert segs == [{"label": "baseline", "started_ms": 0, "ended_ms": 2100}]
