"""Measurement rules for build step 2: calibration, regional validation, classification, coverage.

Framework-free. numpy is used only for the least-squares fit. Nothing here knows about HTTP or SQL.
The rules encode the design: eye region = upper half of the face, mouth region = lower half,
missing data is never "not looking", and eye-level results need a passed validation.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from statistics import median

import numpy as np

from .errors import Conflict, Invalid

REGIONS = ("eye", "mouth", "face_other", "outside", "uncertain")
CLASSIFIABLE = ("eye", "mouth", "face_other", "outside")
SEGMENTS = ("baseline", "practice", "post", "free")
EVENT_TYPES = (
    "segment_start",
    "segment_end",
    "pause",
    "resume",
    "end",
    "camera_changed",
    "orientation_changed",
    "zoom_changed",
    "face_lost",
    "face_found",
    "comfort_answer",
    "note",
)
INVALIDATING_EVENTS = ("camera_changed", "orientation_changed", "zoom_changed")
FEATURE_NAMES = ("bias", "yaw_deg", "pitch_deg", "face_cx", "face_cy", "face_w")


class SessionStatus(str, Enum):
    created = "created"
    camera_ok = "camera_ok"
    calibrated = "calibrated"
    validated = "validated"
    running = "running"
    paused = "paused"
    ended = "ended"


@dataclass
class MeasurementSettings:
    study_id: int
    validation_min_correct: float = 0.8
    validation_max_uncertain: float = 0.2
    min_region_to_error_ratio: float = 2.0
    gaze_conf_threshold: float = 0.5
    calibration_points: int = 9
    allow_continue_without_validation: bool = True
    id: int | None = None

    def validate(self) -> None:
        for name in ("validation_min_correct", "validation_max_uncertain", "gaze_conf_threshold"):
            v = getattr(self, name)
            if not 0.0 <= float(v) <= 1.0:
                raise Invalid(f"{name} must be between 0 and 1")
        if self.min_region_to_error_ratio < 1.0:
            raise Invalid("min_region_to_error_ratio must be at least 1")
        if not 5 <= int(self.calibration_points) <= 16:
            raise Invalid("calibration_points must be between 5 and 16")


@dataclass
class Session:
    participant_id: int
    study_id: int
    device: dict = field(default_factory=dict)
    screen: dict = field(default_factory=dict)
    camera: dict = field(default_factory=dict)
    gaze_model: dict = field(default_factory=dict)
    synthetic: bool = True
    status: SessionStatus = SessionStatus.created
    calibration_valid: bool = False
    created_at: datetime = field(default_factory=datetime.utcnow)
    ended_at: datetime | None = None
    end_reason: str | None = None
    notes: list[str] = field(default_factory=list)
    id: int | None = None

    def ensure_open(self) -> None:
        if self.status is SessionStatus.ended:
            raise Conflict("this session has ended")


@dataclass
class Calibration:
    session_id: int
    params: dict
    residual_px_median: float
    residual_px_p90: float
    per_target: list[dict] = field(default_factory=list)
    points: int = 0
    accepted: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class Validation:
    session_id: int
    calibration_id: int
    layout: dict
    passed: bool
    correct_ratio: float
    uncertain_ratio: float
    size_ratio: float
    reasons: list[str] = field(default_factory=list)
    targets: list[dict] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class StimulusLayout:
    session_id: int
    segment: str
    layout: dict
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class GazeSample:
    session_id: int
    t_ms: int
    x: float | None
    y: float | None
    conf: float
    valid: bool
    region: str
    segment: str
    layout_id: int | None = None
    id: int | None = None


@dataclass
class SessionEvent:
    session_id: int
    t_ms: int
    type: str
    payload: dict = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


# ---------- geometry helpers ----------


def _box(layout: dict, key: str) -> tuple[float, float, float, float] | None:
    b = layout.get(key)
    if not b or len(b) != 4:
        return None
    return float(b[0]), float(b[1]), float(b[2]), float(b[3])


def _inside(x: float, y: float, box: tuple[float, float, float, float] | None) -> bool:
    if box is None:
        return False
    bx, by, bw, bh = box
    return bx <= x <= bx + bw and by <= y <= by + bh


def validate_layout(layout: dict) -> None:
    for key in ("face_box", "eye_region", "mouth_region"):
        if _box(layout, key) is None:
            raise Invalid(f"layout.{key} must be [x, y, w, h]")
    screen = layout.get("screen") or {}
    if not screen.get("w") or not screen.get("h"):
        raise Invalid("layout.screen needs w and h")
    ex, ey, ew, eh = _box(layout, "eye_region")
    mx, my, mw, mh = _box(layout, "mouth_region")
    if eh <= 0 or ew <= 0 or mh <= 0 or mw <= 0:
        raise Invalid("regions must have positive size")
    if ey + eh > my + 1e-6:
        raise Invalid("eye_region must lie above mouth_region")


# ---------- raw samples and calibration ----------


def feature_vector(raw: dict) -> list[float] | None:
    """Features used by the calibration mapping; None when the sample is unusable."""
    if not raw.get("face_detected") or raw.get("yaw_deg") is None or raw.get("pitch_deg") is None:
        return None
    box = raw.get("face_box")
    fw = float(raw.get("frame_w") or 0)
    fh = float(raw.get("frame_h") or 0)
    if not box or len(box) != 4 or fw <= 0 or fh <= 0:
        return None
    x, y, w, h = (float(v) for v in box)
    return [1.0, float(raw["yaw_deg"]), float(raw["pitch_deg"]), (x + w / 2) / fw, (y + h / 2) / fh, w / fw]


def sample_confidence(raw: dict) -> float:
    if not raw.get("face_detected"):
        return 0.0
    return float(min(float(raw.get("face_conf", 1.0)), float(raw.get("gaze_conf", 1.0))))


def fit_calibration(targets: list[dict], conf_threshold: float, min_targets: int = 5, min_samples: int = 5) -> Calibration:
    """Least-squares affine mapping from gaze features to screen pixels, with a small ridge term."""
    rows: list[list[float]] = []
    xs: list[float] = []
    ys: list[float] = []
    per_target: list[dict] = []
    usable_targets = 0
    for t in targets:
        tx, ty = float(t["x"]), float(t["y"])
        feats = [f for f in (feature_vector(s) for s in t.get("samples", []) if sample_confidence(s) >= conf_threshold) if f]
        per_target.append({"x": tx, "y": ty, "n_valid": len(feats), "err_px": None})
        if len(feats) >= min_samples:
            usable_targets += 1
            for f in feats:
                rows.append(f)
                xs.append(tx)
                ys.append(ty)
    if usable_targets < min_targets:
        raise Invalid(f"calibration needs at least {min_targets} targets with {min_samples} valid samples each; got {usable_targets}")
    a = np.asarray(rows, dtype=float)
    ridge = np.eye(a.shape[1]) * 1e-6
    ridge[0, 0] = 0.0
    ata = a.T @ a + ridge
    beta_x = np.linalg.solve(ata, a.T @ np.asarray(xs))
    beta_y = np.linalg.solve(ata, a.T @ np.asarray(ys))
    params = {"features": list(FEATURE_NAMES), "x": [float(v) for v in beta_x], "y": [float(v) for v in beta_y]}
    errors: list[float] = []
    idx = 0
    for pt in per_target:
        n = pt["n_valid"]
        if n < min_samples:
            continue
        seg = a[idx : idx + n]
        px = seg @ beta_x
        py = seg @ beta_y
        d = np.hypot(px - pt["x"], py - pt["y"])
        pt["err_px"] = float(np.median(d))
        errors.extend(float(v) for v in d)
        idx += n
    return Calibration(
        session_id=0,
        params=params,
        residual_px_median=float(np.median(errors)),
        residual_px_p90=float(np.percentile(errors, 90)),
        per_target=per_target,
        points=usable_targets,
        accepted=True,
    )


def map_point(params: dict, raw: dict) -> tuple[float, float] | None:
    f = feature_vector(raw)
    if f is None:
        return None
    fx = float(np.dot(params["x"], f))
    fy = float(np.dot(params["y"], f))
    return fx, fy


def classify_point(point: tuple[float, float] | None, conf: float, layout: dict, conf_threshold: float) -> str:
    if point is None or conf < conf_threshold:
        return "uncertain"
    x, y = point
    screen = layout.get("screen") or {}
    if x < 0 or y < 0 or x > float(screen.get("w", 0)) or y > float(screen.get("h", 0)):
        return "outside"
    if _inside(x, y, _box(layout, "eye_region")):
        return "eye"
    if _inside(x, y, _box(layout, "mouth_region")):
        return "mouth"
    if _inside(x, y, _box(layout, "face_box")):
        return "face_other"
    return "outside"


def classify_raw(params: dict, raw: dict, layout: dict, conf_threshold: float) -> tuple[tuple[float, float] | None, float, str]:
    point = map_point(params, raw)
    conf = sample_confidence(raw)
    return point, conf, classify_point(point, conf, layout, conf_threshold)


# ---------- validation ----------


def evaluate_validation(
    calibration: Calibration, layout: dict, targets: list[dict], settings: MeasurementSettings
) -> Validation:
    validate_layout(layout)
    if not targets:
        raise Invalid("validation needs targets")
    results: list[dict] = []
    correct = 0
    total_samples = 0
    uncertain_samples = 0
    present = set()
    for t in targets:
        region = t.get("region")
        if region not in ("eye", "mouth", "outside"):
            raise Invalid("validation target region must be eye, mouth or outside")
        present.add(region)
        counts = {r: 0 for r in REGIONS}
        samples = t.get("samples", [])
        for raw in samples:
            _, _, cls = classify_raw(calibration.params, raw, layout, settings.gaze_conf_threshold)
            counts[cls] += 1
        n = len(samples)
        total_samples += n
        uncertain_samples += counts["uncertain"]
        classified = {r: counts[r] for r in CLASSIFIABLE if counts[r] > 0}
        majority = max(classified, key=classified.get) if classified else "uncertain"
        is_correct = majority == region and n > 0
        correct += int(is_correct)
        results.append(
            {
                "region": region,
                "x": float(t.get("x", 0)),
                "y": float(t.get("y", 0)),
                "n": n,
                "majority": majority,
                "correct": is_correct,
                "uncertain_share": (counts["uncertain"] / n) if n else 1.0,
                "counts": counts,
            }
        )
    correct_ratio = correct / len(targets)
    uncertain_ratio = (uncertain_samples / total_samples) if total_samples else 1.0
    _, _, _, eye_h = _box(layout, "eye_region")
    size_ratio = eye_h / max(calibration.residual_px_median, 1.0)
    reasons: list[str] = []
    missing = [r for r in ("eye", "mouth", "outside") if r not in present]
    if missing:
        reasons.append("missing_target_regions:" + ",".join(missing))
    if correct_ratio < settings.validation_min_correct:
        reasons.append(f"correct_ratio_below_{settings.validation_min_correct}")
    if uncertain_ratio > settings.validation_max_uncertain:
        reasons.append(f"uncertain_ratio_above_{settings.validation_max_uncertain}")
    if size_ratio < settings.min_region_to_error_ratio:
        reasons.append(f"eye_region_smaller_than_{settings.min_region_to_error_ratio}x_error")
    return Validation(
        session_id=calibration.session_id,
        calibration_id=calibration.id or 0,
        layout=layout,
        passed=not reasons,
        correct_ratio=round(correct_ratio, 4),
        uncertain_ratio=round(uncertain_ratio, 4),
        size_ratio=round(size_ratio, 3),
        reasons=reasons,
        targets=results,
    )


# ---------- coverage and attention ----------


@dataclass(frozen=True)
class Coverage:
    total_ms: int
    classifiable_ms: int
    uncertain_ms: int
    missing_ms: int
    region_ms: dict


def segments_from_events(events: list[SessionEvent], last_sample_t: int | None) -> list[dict]:
    segments: list[dict] = []
    open_seg: dict | None = None
    for e in sorted(events, key=lambda e: (e.t_ms, e.id or 0)):
        if e.type == "segment_start":
            if open_seg is not None and open_seg["ended_ms"] is None:
                open_seg["ended_ms"] = e.t_ms
            open_seg = {"label": e.payload.get("segment", "free"), "started_ms": e.t_ms, "ended_ms": None}
            segments.append(open_seg)
        elif e.type in ("segment_end", "end") and open_seg is not None and open_seg["ended_ms"] is None:
            open_seg["ended_ms"] = e.t_ms
    for s in segments:
        if s["ended_ms"] is None and last_sample_t is not None and last_sample_t > s["started_ms"]:
            s["ended_ms"] = last_sample_t
    return segments


def coverage(samples: list[GazeSample], segments: list[dict]) -> Coverage:
    """Missing time is a gap in samples, never counted as looking anywhere."""
    region_ms = {r: 0 for r in CLASSIFIABLE}
    uncertain_ms = 0
    covered_ms = 0
    total_ms = 0
    ordered = sorted(samples, key=lambda s: s.t_ms)
    for seg in segments:
        start, end = seg["started_ms"], seg.get("ended_ms")
        if end is None or end <= start:
            continue
        total_ms += end - start
        inside = [s for s in ordered if start <= s.t_ms <= end]
        if not inside:
            continue
        diffs = [b.t_ms - a.t_ms for a, b in zip(inside, inside[1:]) if b.t_ms > a.t_ms]
        nominal = int(median(diffs)) if diffs else 100
        nominal = max(20, min(nominal, 1000))
        for i, s in enumerate(inside):
            nxt = inside[i + 1].t_ms if i + 1 < len(inside) else end
            dur = max(0, min(nxt - s.t_ms, 2 * nominal))
            covered_ms += dur
            if s.region in region_ms:
                region_ms[s.region] += dur
            else:
                uncertain_ms += dur
    classifiable_ms = sum(region_ms.values())
    return Coverage(
        total_ms=total_ms,
        classifiable_ms=classifiable_ms,
        uncertain_ms=uncertain_ms,
        missing_ms=max(0, total_ms - covered_ms),
        region_ms=region_ms,
    )


def region_shares(cov: Coverage) -> dict | None:
    if cov.classifiable_ms <= 0:
        return None
    return {r: round(ms / cov.classifiable_ms, 4) for r, ms in cov.region_ms.items()}


def eye_region_attention(session: Session, validation: Validation | None, shares: dict | None) -> dict:
    """Eye-level results exist only with a passed validation on a real estimator and classifiable time."""
    if session.synthetic:
        return {"evaluable": False, "share": None, "reason": "synthetic_estimator"}
    if validation is None:
        return {"evaluable": False, "share": None, "reason": "validation_missing"}
    if not validation.passed:
        return {"evaluable": False, "share": None, "reason": "validation_failed"}
    if shares is None:
        return {"evaluable": False, "share": None, "reason": "no_classifiable_time"}
    return {"evaluable": True, "share": shares["eye"], "reason": None}


def face_region_attention(shares: dict | None) -> dict:
    if shares is None:
        return {"share": None}
    return {"share": round(shares["eye"] + shares["mouth"] + shares["face_other"], 4)}
