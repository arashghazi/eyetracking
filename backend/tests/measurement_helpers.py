"""Synthetic raw samples with a known linear relation between gaze angles and screen position.

These helpers exist only to exercise the pipeline; they say nothing about real accuracy.
"""
from __future__ import annotations

import random

W, H = 1280, 720
FW, FH = 640, 480


def raw(yaw: float, pitch: float, t_ms: int = 0, conf: float = 0.9, face: bool = True) -> dict:
    if not face:
        return {"t_ms": t_ms, "face_detected": False, "face_box": None, "face_conf": 0.0, "yaw_deg": None, "pitch_deg": None, "gaze_conf": 0.0, "frame_w": FW, "frame_h": FH}
    return {
        "t_ms": t_ms,
        "face_detected": True,
        "face_box": [200, 120, 240, 240],
        "face_conf": conf,
        "yaw_deg": yaw,
        "pitch_deg": pitch,
        "gaze_conf": conf,
        "frame_w": FW,
        "frame_h": FH,
    }


def angles_for(x: float, y: float) -> tuple[float, float]:
    return (x - W / 2) / 20.0, (y - H / 2) / 15.0


def samples_for(x: float, y: float, n: int = 8, t0: int = 0, dt: int = 100, noise: float = 0.3, seed: int = 1, conf: float = 0.9) -> list[dict]:
    rnd = random.Random(seed + int(x) * 7 + int(y) * 13)
    yaw, pitch = angles_for(x, y)
    return [raw(yaw + rnd.gauss(0, noise), pitch + rnd.gauss(0, noise), t_ms=t0 + i * dt, conf=conf) for i in range(n)]


def calibration_targets(n_per_axis: int = 3) -> list[dict]:
    xs = [W * (0.1 + 0.8 * i / (n_per_axis - 1)) for i in range(n_per_axis)]
    ys = [H * (0.1 + 0.8 * i / (n_per_axis - 1)) for i in range(n_per_axis)]
    return [{"x": x, "y": y, "samples": samples_for(x, y)} for x in xs for y in ys]


LAYOUT = {
    "screen": {"w": W, "h": H, "dpr": 1},
    "face_box": [440, 120, 400, 480],
    "eye_region": [440, 190, 400, 170],
    "mouth_region": [440, 390, 400, 190],
}
EYE_POINT = (540, 270)
MOUTH_POINT = (640, 480)
OUTSIDE_POINT = (60, 60)


def validation_targets(eye_ok: bool = True) -> list[dict]:
    eye_src = EYE_POINT if eye_ok else MOUTH_POINT  # when not ok, the "eye" target's samples look at the mouth
    return [
        {"region": "eye", "x": EYE_POINT[0], "y": EYE_POINT[1], "samples": samples_for(*eye_src)},
        {"region": "eye", "x": 740, "y": 270, "samples": samples_for(740, 270) if eye_ok else samples_for(*MOUTH_POINT)},
        {"region": "mouth", "x": MOUTH_POINT[0], "y": MOUTH_POINT[1], "samples": samples_for(*MOUTH_POINT)},
        {"region": "outside", "x": OUTSIDE_POINT[0], "y": OUTSIDE_POINT[1], "samples": samples_for(*OUTSIDE_POINT)},
    ]
