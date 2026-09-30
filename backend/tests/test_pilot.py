"""Step 6: supervised pilot. Settings versions, threshold review, observations, live monitor,
debrief, research-tracker comparison, pilot report, deletion coverage and the dev-DB column upgrade."""
import csv
import io
import random

from sqlalchemy import create_engine, inspect, text

from eyetracking.infrastructure.uow import create_schema

from .conftest import auth
from .measurement_helpers import LAYOUT, samples_for, validation_targets
from .test_measurement import CAMERA, DEVICE, REAL_MODEL, SCREEN, SYNTHETIC_MODEL, calibrate, make_ready
from .test_research import full_gradual_session


def _log_actions(world) -> list[str]:
    return [e["action"] for e in world.c.get(f"/studies/{world.study_a}/access-log", headers=auth(world.researcher_a)).json()]


def test_settings_versions_and_history(world):
    c, ra = world.c, auth(world.researcher_a)
    url = f"/studies/{world.study_a}/measurement-settings"
    assert c.get(url, headers=ra).json()["version"] == 1
    hist = c.get(url + "/history", headers=ra).json()
    assert len(hist) == 1 and hist[0]["version"] == 1 and "Defaults" in hist[0]["rationale"]
    r = c.put(url, json={"validation_min_correct": 0.7, "rationale": "Pilot day 1: 3 of 5 real sessions failed at 0.8 on laptops"}, headers=ra)
    assert r.status_code == 200 and r.json()["version"] == 2
    # the same values again make no new version
    assert c.put(url, json={"validation_min_correct": 0.7, "rationale": "again"}, headers=ra).json()["version"] == 2
    # a rejected change leaves the stored values alone
    assert c.put(url, json={"validation_min_correct": 0.6, "quality_max_missing_share": 2}, headers=ra).status_code == 422
    assert c.get(url, headers=ra).json()["validation_min_correct"] == 0.7
    hist = c.get(url + "/history", headers=auth(world.analyst_a)).json()
    assert [h["version"] for h in hist] == [2, 1]
    assert hist[0]["values"]["validation_min_correct"] == 0.7 and hist[0]["rationale"].startswith("Pilot day 1")
    assert hist[1]["values"]["validation_min_correct"] == 0.8 and hist[1]["changed_by"] is None
    assert c.get(url + "/history", headers=auth(world.researcher_b)).status_code == 403
    # a new validation records the version it was judged with
    make_ready(world, world.p1)
    p = auth(world.p1)
    sid = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": REAL_MODEL}, headers=p).json()["id"]
    calibrate(world, world.p1, sid)
    c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=p)
    assert c.get(f"/me/sessions/{sid}", headers=p).json()["validation"]["settings_version"] == 2
    rows = c.get(f"/studies/{world.study_a}/analysis", params={"quality": "ok,review,exclude"}, headers=ra).json()["rows"]
    assert any(r["session_id"] == sid and r["settings_version"] == 2 for r in rows)


def test_threshold_review_changes_nothing(world):
    c, ra = world.c, auth(world.researcher_a)
    make_ready(world, world.p1)
    real = [full_gradual_session(world, world.p1), full_gradual_session(world, world.p1)]
    full_gradual_session(world, world.p1, model=SYNTHETIC_MODEL)
    url = f"/studies/{world.study_a}/pilot/threshold-review"
    r = c.post(url, json={"changes": {"min_region_to_error_ratio": 1000}}, headers=ra)
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["sessions"] == 2 and d["skipped_synthetic"] == 1 and d["validated_sessions"] == 2
    assert d["validation_pass"] == {"current": 2, "candidate": 0} and d["changed_sessions"] == 2
    assert d["quality"]["current"]["ok"] == 2 and d["quality"]["candidate"]["review"] == 2
    row = next(x for x in d["rows"] if x["session_id"] == real[0])
    assert row["validation_candidate"]["reasons"] == ["eye_region_smaller_than_1000x_error"]
    assert d["distributions"]["correct_ratio"]["n"] == 2 and d["by_device"][0]["pass_candidate"] == 0
    # nothing was saved
    assert c.get(f"/studies/{world.study_a}/measurement-settings", headers=ra).json()["version"] == 1
    assert "threshold_review" in _log_actions(world)
    # the confidence threshold is not re-evaluated on recorded samples, and says so
    d = c.post(url, json={"changes": {"gaze_conf_threshold": 0.9}}, headers=auth(world.analyst_a)).json()
    assert any("gaze_conf_threshold" in n for n in d["notes"])
    d = c.post(url, json={"changes": {}, "include_synthetic": True}, headers=ra).json()
    assert d["sessions"] == 3 and d["includes_synthetic"] is True
    assert c.post(url, json={"changes": {"nope": 1}}, headers=ra).status_code == 422
    assert c.post(url, json={"changes": {"validation_min_correct": 3}}, headers=ra).status_code == 422
    assert c.post(url, json={}, headers=auth(world.researcher_b)).status_code == 403
    assert c.post(url, json={}, headers=auth(world.p1)).status_code == 403


def test_observations_and_live_monitor(world):
    c, ra = world.c, auth(world.researcher_a)
    make_ready(world, world.p1)
    p = auth(world.p1)
    sid = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": REAL_MODEL}, headers=p).json()["id"]
    calibrate(world, world.p1, sid)
    c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=p)
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "baseline", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 0, "type": "segment_start", "payload": {"segment": "baseline"}}, headers=p)
    c.post(f"/me/sessions/{sid}/samples", json={"samples": samples_for(540, 270, n=30, t0=100)}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 3200, "type": "pause"}, headers=p)
    active = c.get(f"/studies/{world.study_a}/pilot/active", headers=ra).json()
    assert [a["session_id"] for a in active] == [sid] and active[0]["participant_code"] == "P-001"
    base = f"/studies/{world.study_a}/sessions/{sid}"
    live = c.get(base + "/live", params={"first": True}, headers=ra).json()
    assert live["current_segment"] == "baseline" and live["paused"] is True and live["pauses"] == 1
    assert live["samples_total"] == 30 and live["recent"]["regions"]["eye"] > 0 and live["validation"]["passed"] is True
    c.get(base + "/live", headers=ra)
    assert _log_actions(world).count("live_monitor") == 1
    assert c.get(base + "/live", headers=auth(world.analyst_a)).status_code == 403
    # observations: researchers write, analysts read, nobody else
    r = c.post(base + "/observations", json={"category": "comfort", "severity": "major", "text": "Looked away when the number moved near the eyes.", "t_ms": 3100}, headers=ra)
    assert r.status_code == 201 and r.json()["author_id"] > 0
    assert c.post(base + "/observations", json={"category": "mood", "text": "x"}, headers=ra).status_code == 422
    assert c.post(base + "/observations", json={"category": "ux", "text": "   "}, headers=ra).status_code == 422
    assert c.post(base + "/observations", json={"category": "ux", "text": "x"}, headers=auth(world.analyst_a)).status_code == 403
    assert len(c.get(base + "/observations", headers=auth(world.analyst_a)).json()) == 1
    assert c.get(base + "/observations", headers=auth(world.researcher_b)).status_code == 403
    assert c.get(f"/studies/{world.study_b}/sessions/{sid}/observations", headers=auth(world.researcher_b)).status_code == 404
    assert c.get(base + "/live", headers=ra).json()["observations"] == 1
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 3300, "type": "end", "payload": {"reason": "completed"}}, headers=p)
    assert c.get(f"/studies/{world.study_a}/pilot/active", headers=ra).json() == []


def test_debrief_versions_and_rules(world):
    c, ra = world.c, auth(world.researcher_a)
    make_ready(world, world.p1)
    p = auth(world.p1)
    form_url = f"/studies/{world.study_a}/debrief-form"
    f = c.get(form_url, headers=auth(world.analyst_a)).json()
    assert f["version"] == 0 and f["enabled"] is False and f["saved"] is False and len(f["questions"]) == 6
    sid = full_gradual_session(world, world.p1)
    assert c.get(f"/me/sessions/{sid}/debrief", headers=p).json() == {"enabled": False, "session_ended": True, "form": None, "answer": None}
    assert c.post(f"/me/sessions/{sid}/debrief", json={"form_version": 0, "answers": {}}, headers=p).status_code == 409
    assert c.put(form_url, json={"enabled": True}, headers=auth(world.analyst_a)).status_code == 403
    f = c.put(form_url, json={"enabled": True}, headers=ra).json()
    assert f["version"] == 1 and f["enabled"] is True
    d = c.get(f"/me/sessions/{sid}/debrief", headers=p).json()
    assert d["enabled"] and d["form"]["version"] == 1
    answers = {"instructions_clear": 4, "comfort_overall": 3, "anything_uncomfortable": True, "uncomfortable_detail": "The number near the eyes.", "camera_setup_easy": True}
    assert c.post(f"/me/sessions/{sid}/debrief", json={"form_version": 2, "answers": answers}, headers=p).status_code == 409
    assert c.post(f"/me/sessions/{sid}/debrief", json={"form_version": 1, "answers": {"comfort_overall": 3}}, headers=p).status_code == 422
    assert c.post(f"/me/sessions/{sid}/debrief", json={"form_version": 1, "answers": dict(answers, instructions_clear=9)}, headers=p).status_code == 422
    assert c.post(f"/me/sessions/{sid}/debrief", json={"form_version": 1, "answers": dict(answers, extra=1)}, headers=p).status_code == 422
    r = c.post(f"/me/sessions/{sid}/debrief", json={"form_version": 1, "answers": answers}, headers=p)
    assert r.status_code == 201 and r.json()["answers"]["instructions_clear"] == 4
    assert c.post(f"/me/sessions/{sid}/debrief", json={"form_version": 1, "answers": answers}, headers=p).status_code == 409
    # another participant cannot see or answer it
    assert c.get(f"/me/sessions/{sid}/debrief", headers=auth(world.p2)).status_code == 404
    # an open session cannot be debriefed
    open_sid = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": REAL_MODEL}, headers=p).json()["id"]
    assert c.post(f"/me/sessions/{open_sid}/debrief", json={"form_version": 1, "skipped": True}, headers=p).status_code == 409
    # new questions make a new version; the earlier answer keeps version 1
    qs = [{"key": "clear", "type": "choice", "prompt": "Was it clear?", "options": ["Yes", "Partly", "No"], "required": True}]
    f = c.put(form_url, json={"questions": qs}, headers=ra).json()
    assert f["version"] == 2 and f["enabled"] is True and f["questions"][0]["options"] == ["Yes", "Partly", "No"]
    assert c.put(form_url, json={"questions": qs + [dict(qs[0])]}, headers=ra).status_code == 422
    assert c.put(form_url, json={"questions": [{"key": "Bad Key", "type": "text", "prompt": "x"}]}, headers=ra).status_code == 422
    sid2 = full_gradual_session(world, world.p1)
    assert c.post(f"/me/sessions/{sid2}/debrief", json={"form_version": 2, "skipped": True}, headers=p).json()["skipped"] is True
    data = c.get("/me/data", headers=p).json()
    by_id = {s["summary"]["id"]: s for s in data["sessions"]}
    assert by_id[sid]["debrief"]["form_version"] == 1 and by_id[sid2]["debrief"]["skipped"] is True


def _tracker_csv(points, offset_us=5_000_000, delimiter=";", decimal_comma=True, shift_ms=0) -> bytes:
    """A Tobii-like export: microsecond timestamps, device pixels, validity column."""
    buf = io.StringIO()
    w = csv.writer(buf, delimiter=delimiter)
    w.writerow(["Recording timestamp", "Gaze point X", "Gaze point Y", "Validity"])
    rnd = random.Random(3)
    for t_ms in range(0, 8300, 17):
        x, y = points(t_ms)
        x += rnd.gauss(0, 3)
        y += rnd.gauss(0, 3)
        fx, fy = (f"{x:.1f}", f"{y:.1f}")
        if decimal_comma:
            fx, fy = fx.replace(".", ","), fy.replace(".", ",")
        valid = "Valid" if t_ms % 1000 else "Invalid"
        w.writerow([(t_ms + shift_ms) * 1000 + offset_us, fx, fy, valid])
    return buf.getvalue().encode("utf-8")


def _import(c, url, data, headers, **extra):
    form = {"source": "Tobii Pro Spectrum (lab day)", "time_column": "Recording timestamp", "x_column": "Gaze point X", "y_column": "Gaze point Y",
            "valid_column": "Validity", "valid_values": "Valid", "time_unit": "us", "offset": "5000000", "coord_space": "device_px"}
    form.update({k: str(v) for k, v in extra.items()})
    return c.post(url, data=form, files={"file": ("tracker.tsv", data, "text/csv")}, headers=headers)


def test_reference_tracker_comparison(world):
    c, ra = world.c, auth(world.researcher_a)
    make_ready(world, world.p1)
    sid = full_gradual_session(world, world.p1)
    url = f"/studies/{world.study_a}/sessions/{sid}/reference"
    r = _import(c, url, _tracker_csv(lambda t: (540, 270)), ra)
    assert r.status_code == 201, r.text
    rec = r.json()
    assert rec["sample_count"] > 400 and rec["valid_count"] < rec["sample_count"] and rec["settings"]["alignment"] == "given_offset"
    cmp = c.get(f"{url}/{rec['id']}/compare", headers=auth(world.analyst_a)).json()
    assert cmp["paired_classified"] >= 40 and cmp["region_agreement"] == 1.0
    assert cmp["distance_px"]["median"] < 40 and cmp["eye_region"]["recall"] == 1.0
    assert cmp["session"]["validation_passed"] is True and cmp["caveats"] == []
    # a tracker that says the person looked at the mouth disagrees
    rec2 = _import(c, url, _tracker_csv(lambda t: (640, 480)), ra).json()
    cmp2 = c.get(f"{url}/{rec2['id']}/compare", headers=ra).json()
    assert cmp2["region_agreement"] == 0.0 and cmp2["confusion"]["rows_webcam_columns_reference"]["eye"]["mouth"] == cmp2["paired_classified"]
    assert len(c.get(url, headers=auth(world.analyst_a)).json()) == 2
    # errors and access
    bad = _import(c, url, _tracker_csv(lambda t: (540, 270)), ra, x_column="GazeX")
    assert bad.status_code == 422 and "Gaze point X" in bad.json()["detail"]
    assert _import(c, url, b"", ra).status_code == 422
    assert c.get(f"{url}/{rec['id']}/compare", params={"tolerance_ms": 0}, headers=ra).status_code == 422
    assert _import(c, url, _tracker_csv(lambda t: (540, 270)), auth(world.analyst_a)).status_code == 403
    assert c.get(f"/studies/{world.study_a}/sessions/{sid}/reference/9999/compare", headers=ra).status_code == 404
    actions = _log_actions(world)
    assert "reference_import" in actions and "reference_compare" in actions


CHANGES = [0, 400, 1300, 1700, 2900, 3300, 4600, 5200, 6300, 7400]
POINTS = [(540, 270), (740, 270), (640, 480), (540, 270), (740, 270), (640, 480), (540, 270), (740, 270), (640, 480), (540, 270)]


def _target(t: int) -> tuple[int, int]:
    i = max(k for k, start in enumerate(CHANGES) if t >= start)
    return POINTS[i]


def test_reference_auto_alignment(world):
    c, ra = world.c, auth(world.researcher_a)
    make_ready(world, world.p1)
    p = auth(world.p1)
    sid = c.post("/me/sessions", json={"device": DEVICE, "screen": SCREEN, "camera": CAMERA, "gaze_model": REAL_MODEL}, headers=p).json()["id"]
    calibrate(world, world.p1, sid)
    c.post(f"/me/sessions/{sid}/validation", json={"layout": LAYOUT, "targets": validation_targets()}, headers=p)
    c.post(f"/me/sessions/{sid}/layout", json={"segment": "baseline", "layout": LAYOUT}, headers=p)
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 0, "type": "segment_start", "payload": {"segment": "baseline"}}, headers=p)
    samples = [samples_for(*_target(t), n=1, t0=t, seed=t)[0] for t in range(100, 8000, 50)]
    assert c.post(f"/me/sessions/{sid}/samples", json={"samples": samples}, headers=p).status_code == 200
    c.post(f"/me/sessions/{sid}/events", json={"t_ms": 8100, "type": "end", "payload": {"reason": "completed"}}, headers=p)
    url = f"/studies/{world.study_a}/sessions/{sid}/reference"
    # the tracker's clock runs 300 ms ahead of what the given offset says
    rec = _import(c, url, _tracker_csv(_target, shift_ms=300), ra, auto_align_window_ms=1000).json()
    assert rec["settings"]["alignment"] == "estimated_from_data" and abs(rec["settings"]["estimated_shift_ms"] + 300) <= 40
    cmp = c.get(f"{url}/{rec['id']}/compare", headers=ra).json()
    assert any("optimistic" in x for x in cmp["caveats"]) and cmp["region_agreement"] > 0.9
    plain = _import(c, url, _tracker_csv(_target, shift_ms=300), ra).json()
    worse = c.get(f"{url}/{plain['id']}/compare", headers=ra).json()
    assert worse["distance_px"]["median"] > cmp["distance_px"]["median"]


def test_pilot_report_csv_and_erasure(world):
    c, ra = world.c, auth(world.researcher_a)
    make_ready(world, world.p1)
    p = auth(world.p1)
    c.put(f"/studies/{world.study_a}/debrief-form", json={"enabled": True}, headers=ra)
    sid = full_gradual_session(world, world.p1)
    early = full_gradual_session(world, world.p1, end="ended_early")
    full_gradual_session(world, world.p1, model=SYNTHETIC_MODEL)
    c.post(f"/me/sessions/{sid}/debrief", json={"form_version": 1, "answers": {"instructions_clear": 5, "comfort_overall": 4, "one_change": "Bigger buttons"}}, headers=p)
    c.post(f"/me/sessions/{early}/debrief", json={"form_version": 1, "skipped": True}, headers=p)
    c.post(f"/studies/{world.study_a}/sessions/{early}/observations", json={"category": "comfort", "severity": "stop", "text": "Asked to stop at the second stage."}, headers=ra)
    _import(c, f"/studies/{world.study_a}/sessions/{sid}/reference", _tracker_csv(lambda t: (540, 270)), ra)
    rep = c.get(f"/studies/{world.study_a}/pilot/report", headers=auth(world.analyst_a)).json()
    assert rep["sessions"] == 2 and rep["skipped_synthetic"] == 1 and rep["participants"] == 1
    assert rep["validation"] == {"validated": 2, "passed": 2} and rep["ended_early"] == 1
    assert rep["debrief"]["answered"] == 1 and rep["debrief"]["skipped"] == 1
    q = {x["key"]: x for x in rep["debrief"]["questions"]}
    assert q["instructions_clear"]["mean"] == 5 and rep["debrief"]["comments"][0]["text"] == "Bigger buttons"
    assert rep["observations"]["by_category"] == {"comfort": {"stop": 1}} and rep["comfort_stage_values"] == {"4": 2}
    row = next(r for r in rep["rows"] if r["session_id"] == sid)
    assert row["reference_recordings"] == 1 and row["debrief"] == "answered" and row["camera"] == "640x480"
    assert c.get(f"/studies/{world.study_a}/pilot/report", params={"include_synthetic": True}, headers=ra).json()["sessions"] == 3
    r = c.get(f"/studies/{world.study_a}/pilot/report.csv", headers=ra)
    assert r.status_code == 200 and "attachment" in r.headers["content-disposition"]
    rows = list(csv.DictReader(io.StringIO(r.content.decode("utf-8-sig"))))
    assert len(rows) == 2 and "debrief_one_change" in rows[0] and {x["debrief"] for x in rows} == {"answered", "skipped"}
    assert c.get(f"/studies/{world.study_a}/pilot/report", headers=auth(world.researcher_b)).status_code == 403
    actions = _log_actions(world)
    assert "pilot_report" in actions and "export_pilot_csv" in actions
    # withdrawal under delete_all removes the pilot rows too
    gone = c.post("/me/erase", json={"confirm": "DELETE MY DATA"}, headers=p).json()["deleted"]
    assert gone["observations"] == 1 and gone["debrief_answers"] == 2 and gone["reference_recordings"] == 1 and gone["reference_samples"] > 400
    rep = c.get(f"/studies/{world.study_a}/pilot/report", params={"include_synthetic": True}, headers=ra).json()
    assert rep["sessions"] == 0 and rep["observations"]["total"] == 0


def test_dev_sqlite_gets_new_columns(tmp_path):
    url = f"sqlite:///{tmp_path / 'old.db'}"
    engine = create_engine(url)
    create_schema(engine)
    with engine.begin() as conn:
        conn.execute(text('ALTER TABLE validations DROP COLUMN settings_version'))
        conn.execute(text('ALTER TABLE measurement_settings DROP COLUMN version'))
        conn.execute(text("INSERT INTO studies (id, name, created_at, retention_policy) VALUES (1, 'old', '2026-01-01', 'delete_all')"))
        conn.execute(text("INSERT INTO measurement_settings (study_id, validation_min_correct, validation_max_uncertain, min_region_to_error_ratio, gaze_conf_threshold, calibration_points, allow_continue_without_validation, quality_max_uncertain_share, quality_max_missing_share) VALUES (1, 0.8, 0.2, 2, 0.5, 9, 1, 0.2, 0.2)"))
    create_schema(engine)
    cols = {c["name"] for c in inspect(engine).get_columns("validations")}
    assert "settings_version" in cols
    with engine.connect() as conn:
        assert conn.execute(text("SELECT version FROM measurement_settings WHERE study_id = 1")).scalar() == 1
