"""Gaze service: synthetic estimator, decoding, the authenticated /gaze mount and the L2CS adapter."""
import base64

import numpy as np
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from eyetracking.gaze.detector import FixedBoxDetector, HaarFaceDetector
from eyetracking.gaze.service import build_router
from eyetracking.gaze.synthetic import SyntheticEstimator

from .conftest import ADMIN, auth, login


def jpeg_b64(w: int = 640, h: int = 480, value: int = 120) -> str:
    import cv2

    img = np.full((h, w, 3), value, dtype=np.uint8)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return base64.b64encode(buf.tobytes()).decode()


@pytest.fixture
def gaze_client():
    app = FastAPI()
    app.include_router(build_router(SyntheticEstimator(FixedBoxDetector([200, 100, 240, 240]))))
    return TestClient(app)


def test_info_and_estimate(gaze_client):
    info = gaze_client.get("/info").json()
    assert info["synthetic"] is True and info["model_id"] == "synthetic-head-proxy"
    r = gaze_client.post("/estimate", json={"image_b64": jpeg_b64(), "t_ms": 123, "frame_w": 640, "frame_h": 480})
    assert r.status_code == 200
    body = r.json()
    assert body["face_detected"] is True and body["face_box"] == [200, 100, 240, 240] and body["t_ms"] == 123
    assert body["frame_w"] == 640 and body["frame_h"] == 480 and isinstance(body["yaw_deg"], float)


def test_no_face_and_bad_input():
    app = FastAPI()
    app.include_router(build_router(SyntheticEstimator(FixedBoxDetector(None))))
    c = TestClient(app)
    r = c.post("/estimate", json={"image_b64": jpeg_b64(), "t_ms": 1, "frame_w": 640, "frame_h": 480})
    assert r.json()["face_detected"] is False and r.json()["yaw_deg"] is None
    assert c.post("/estimate", json={"image_b64": "not base64 at all!!", "t_ms": 1, "frame_w": 1, "frame_h": 1}).status_code == 422
    garbage = base64.b64encode(b"x" * 64).decode()
    assert c.post("/estimate", json={"image_b64": garbage, "t_ms": 1, "frame_w": 1, "frame_h": 1}).status_code == 422


def test_haar_detector_reports_no_face_on_flat_image():
    det = HaarFaceDetector()
    assert det.detect(np.full((480, 640, 3), 90, dtype=np.uint8)) is None


def test_gaze_mount_requires_auth(client):
    assert client.get("/gaze/info").status_code == 401
    token = login(client, *ADMIN)
    info = client.get("/gaze/info", headers=auth(token)).json()
    assert info["synthetic"] is True and info["face_detector"] == "HaarFaceDetector"
    r = client.post("/gaze/estimate", json={"image_b64": jpeg_b64(), "t_ms": 5, "frame_w": 640, "frame_h": 480}, headers=auth(token))
    assert r.status_code == 200 and r.json()["face_detected"] is False


torch = pytest.importorskip("torch")


def test_l2cs_pipeline_without_weights_is_synthetic(tmp_path):
    from eyetracking.gaze.l2cs import L2CSEstimator

    est = L2CSEstimator(FixedBoxDetector([200, 100, 240, 240]), weights_path=None, input_size=224)
    assert est.info()["synthetic"] is True and est.info()["model_version"] == "untrained"
    rng = np.random.default_rng(0)
    img = rng.integers(0, 255, size=(480, 640, 3), dtype=np.uint8)
    out = est.estimate(img)
    assert out.face_detected and -180 <= out.yaw_deg <= 180 and -180 <= out.pitch_deg <= 180 and 0 <= out.gaze_conf <= 1
    # a checkpoint in the L2CS layout (backbone keys + fc_yaw_gaze/fc_pitch_gaze + fc_finetune) loads and clears the flag
    state = dict(est._backbone.state_dict())
    state.update({f"fc_yaw_gaze.{k}": v for k, v in est._fc_yaw.state_dict().items()})
    state.update({f"fc_pitch_gaze.{k}": v for k, v in est._fc_pitch.state_dict().items()})
    state["fc_finetune.weight"] = torch.zeros(3, 2051)
    state["fc_finetune.bias"] = torch.zeros(3)
    path = tmp_path / "fake_l2cs.pkl"
    torch.save(state, path)
    loaded = L2CSEstimator(FixedBoxDetector([200, 100, 240, 240]), weights_path=str(path), input_size=224)
    assert loaded.weights_loaded is True and loaded.info()["synthetic"] is False and loaded.info()["model_version"] == "fake_l2cs.pkl"
    # the same keys in a .safetensors file load the same way
    from safetensors.torch import save_file

    st_path = tmp_path / "fake_l2cs.safetensors"
    save_file({k: v.contiguous() for k, v in state.items()}, str(st_path))
    from_st = L2CSEstimator(FixedBoxDetector([200, 100, 240, 240]), weights_path=str(st_path), input_size=224)
    assert from_st.weights_loaded is True and from_st.info()["model_version"] == "fake_l2cs.safetensors"
    assert from_st.estimate(img).yaw_deg == pytest.approx(loaded.estimate(img).yaw_deg, abs=1e-4)
    bad = {"conv1.weight": torch.zeros(1)}
    torch.save(bad, tmp_path / "bad.pkl")
    with pytest.raises((ValueError, RuntimeError)):
        L2CSEstimator(FixedBoxDetector([0, 0, 10, 10]), weights_path=str(tmp_path / "bad.pkl"), input_size=224)


def test_estimator_from_env_modes(monkeypatch):
    from eyetracking.gaze.service import estimator_from_env

    monkeypatch.setenv("EYETRACKING_GAZE_MODEL", "e2e-fake")
    est = estimator_from_env()
    assert est.info()["synthetic"] is True and est.info()["face_detector"] == "FixedBoxDetector"
    monkeypatch.setenv("EYETRACKING_GAZE_MODEL", "synthetic")
    assert estimator_from_env().info()["face_detector"] == "HaarFaceDetector"
