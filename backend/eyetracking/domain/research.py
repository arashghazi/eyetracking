"""Research and data rules for build step 4: quality grades, comparability groups, replay helpers.

Framework-free. A session's quality grade tells the analysis what to pool by default; nothing here
manufactures accuracy, and missing time stays missing.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from .measurement import CLASSIFIABLE, GazeSample, SessionEvent

REGION_CODES = {"eye": 0, "mouth": 1, "face_other": 2, "outside": 3, "uncertain": 4}
EXPORT_VERSION = "1"


@dataclass(frozen=True)
class Quality:
    grade: str
    reasons: tuple[str, ...]

    def as_dict(self) -> dict:
        return {"grade": self.grade, "reasons": list(self.reasons)}


def grade_quality(summary: dict, max_uncertain_share: float, max_missing_share: float) -> Quality:
    exclude: list[str] = []
    review: list[str] = []
    if summary.get("synthetic"):
        exclude.append("synthetic_estimator")
    if summary.get("calibration") is None:
        exclude.append("no_calibration")
    cov = summary.get("coverage") or {}
    total = cov.get("total_ms") or 0
    classifiable = cov.get("classifiable_ms") or 0
    uncertain = cov.get("uncertain_ms") or 0
    missing = cov.get("missing_ms") or 0
    if classifiable <= 0:
        exclude.append("no_classifiable_time")
    val = summary.get("validation")
    if val is None or not val.get("passed"):
        review.append("validation_not_passed")
    observed = classifiable + uncertain
    if observed > 0 and uncertain / observed > max_uncertain_share:
        review.append(f"uncertain_share_above_{max_uncertain_share}")
    if total > 0 and missing / total > max_missing_share:
        review.append(f"missing_share_above_{max_missing_share}")
    if summary.get("end_reason") == "ended_early":
        review.append("ended_early")
    if any(str(n).startswith("calibration_invalidated") for n in summary.get("notes") or []):
        review.append("calibration_invalidated")
    if exclude:
        return Quality("exclude", tuple(exclude + review))
    if review:
        return Quality("review", tuple(review))
    return Quality("ok", ())


def screen_bucket(screen: dict) -> str:
    w = int(screen.get("w") or 0)
    h = int(screen.get("h") or 0)
    return f"{(w // 300) * 300}x{(h // 300) * 300}"


def stimulus_bucket(eye_region_height_px: float | None) -> str:
    if eye_region_height_px is None:
        return "unknown"
    return f"{int(eye_region_height_px // 50) * 50}px"


def group_key(device_platform: str | None, protocol_version: str | None, estimator: str | None, screen: dict, eye_region_height_px: float | None) -> str:
    return "|".join(
        [
            device_platform or "unknown",
            protocol_version or "none",
            estimator or "unknown",
            screen_bucket(screen or {}),
            stimulus_bucket(eye_region_height_px),
        ]
    )


def compact_samples(samples: list[GazeSample]) -> list[list]:
    return [[s.t_ms, None if s.x is None else round(s.x, 1), None if s.y is None else round(s.y, 1), round(s.conf, 3), REGION_CODES.get(s.region, 4)] for s in samples]


def layout_ranges(samples: list[GazeSample]) -> dict[int, tuple[int, int]]:
    ranges: dict[int, tuple[int, int]] = {}
    for s in samples:
        if s.layout_id is None:
            continue
        lo, hi = ranges.get(s.layout_id, (s.t_ms, s.t_ms))
        ranges[s.layout_id] = (min(lo, s.t_ms), max(hi, s.t_ms))
    return ranges


def quality_strip(samples: list[GazeSample], start_ms: int, end_ms: int, step_ms: int = 1000) -> list[dict]:
    if end_ms <= start_ms:
        return []
    out: list[dict] = []
    ordered = sorted(samples, key=lambda s: s.t_ms)
    idx = 0
    for t in range(start_ms, end_ms, step_ms):
        stop = min(t + step_ms, end_ms)
        while idx < len(ordered) and ordered[idx].t_ms < t:
            idx += 1
        j = idx
        valid = total = 0
        while j < len(ordered) and ordered[j].t_ms < stop:
            total += 1
            valid += int(ordered[j].region in CLASSIFIABLE)
            j += 1
        out.append({"from_ms": t, "to_ms": stop, "valid_share": round(valid / total, 3) if total else None})
    return out


def sample_gaps(samples: list[GazeSample], min_gap_factor: float = 2.0, default_nominal_ms: int = 100) -> list[dict]:
    ordered = sorted(s.t_ms for s in samples)
    if len(ordered) < 2:
        return []
    diffs = sorted(b - a for a, b in zip(ordered, ordered[1:]) if b > a)
    nominal = diffs[len(diffs) // 2] if diffs else default_nominal_ms
    nominal = max(20, min(nominal, 1000))
    return [{"from_ms": a, "to_ms": b} for a, b in zip(ordered, ordered[1:]) if b - a > min_gap_factor * nominal]


def pause_intervals(events: list[SessionEvent], end_ms: int | None) -> list[dict]:
    out: list[dict] = []
    open_at: int | None = None
    for e in sorted(events, key=lambda e: (e.t_ms, e.id or 0)):
        if e.type == "pause" and open_at is None:
            open_at = e.t_ms
        elif e.type in ("resume", "end") and open_at is not None:
            out.append({"from_ms": open_at, "to_ms": e.t_ms})
            open_at = None
    if open_at is not None and end_ms is not None and end_ms > open_at:
        out.append({"from_ms": open_at, "to_ms": end_ms})
    return out


@dataclass
class AccessLogEntry:
    study_id: int | None
    user_id: int
    role: str
    action: str
    detail: dict = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


DATA_DICTIONARY: list[dict] = [
    {"name": "session_id", "type": "integer", "unit": "", "meaning": "Session identifier."},
    {"name": "participant_code", "type": "string", "unit": "", "meaning": "Research code; never the login identity."},
    {"name": "created_at", "type": "datetime (UTC)", "unit": "", "meaning": "When the session was created."},
    {"name": "path", "type": "string", "unit": "", "meaning": "gradual_face or interest_conversation; empty for measurement-only sessions."},
    {"name": "protocol_name", "type": "string", "unit": "", "meaning": "Name of the published protocol version the session ran."},
    {"name": "protocol_version", "type": "integer", "unit": "", "meaning": "Immutable protocol version number."},
    {"name": "sheet_version", "type": "integer", "unit": "", "meaning": "Information-sheet version the participant consented to at export time."},
    {"name": "device_platform", "type": "string", "unit": "", "meaning": "web, android, ..."},
    {"name": "screen", "type": "string", "unit": "px", "meaning": "Screen width x height and pixel ratio."},
    {"name": "estimator", "type": "string", "unit": "", "meaning": "Gaze model id."},
    {"name": "gaze_model_version", "type": "string", "unit": "", "meaning": "Gaze model version; 'untrained' or a synthetic id means no measurement."},
    {"name": "synthetic", "type": "boolean", "unit": "", "meaning": "True when the estimator makes no measurement claim."},
    {"name": "quality", "type": "string", "unit": "", "meaning": "ok, review or exclude (see quality_reasons)."},
    {"name": "quality_reasons", "type": "string", "unit": "", "meaning": "Semicolon-separated reasons behind the grade."},
    {"name": "calibration_residual_px", "type": "number", "unit": "px", "meaning": "Median calibration error on the participant's screen."},
    {"name": "validation_passed", "type": "boolean", "unit": "", "meaning": "Regional validation (eye / mouth / outside) passed."},
    {"name": "settings_version", "type": "integer", "unit": "", "meaning": "Measurement-settings version the validation was judged with (empty for validations recorded before step 6)."},
    {"name": "size_ratio", "type": "number", "unit": "", "meaning": "Eye-region height divided by calibration error."},
    {"name": "total_ms", "type": "integer", "unit": "ms", "meaning": "Observed segment time (baseline + practice + post)."},
    {"name": "classifiable_share", "type": "number", "unit": "0-1", "meaning": "Share of total time with a classifiable gaze region."},
    {"name": "uncertain_share", "type": "number", "unit": "0-1", "meaning": "Share of total time with an uncertain estimate."},
    {"name": "missing_share", "type": "number", "unit": "0-1", "meaning": "Share of total time without samples; never counted as looking away."},
    {"name": "face_share", "type": "number", "unit": "0-1", "meaning": "Share of classifiable time inside the face."},
    {"name": "eye_share", "type": "number", "unit": "0-1", "meaning": "Share of classifiable time in the eye region; empty when not evaluable."},
    {"name": "baseline_eye_share", "type": "number", "unit": "0-1", "meaning": "Eye share during the prompt-free baseline."},
    {"name": "post_eye_share", "type": "number", "unit": "0-1", "meaning": "Eye share during the prompt-free post observation."},
    {"name": "eye_share_delta", "type": "number", "unit": "0-1", "meaning": "post_eye_share minus baseline_eye_share."},
    {"name": "comprehension_share", "type": "number", "unit": "0-1", "meaning": "Correct comprehension answers over answered."},
    {"name": "number_task_share", "type": "number", "unit": "0-1", "meaning": "Correct number readings over trials."},
    {"name": "stages_completed", "type": "integer", "unit": "", "meaning": "Gradual stages finished with advance or complete."},
    {"name": "comfort_min", "type": "integer", "unit": "scale", "meaning": "Lowest comfort answer."},
    {"name": "comfort_mean", "type": "number", "unit": "scale", "meaning": "Mean comfort answer."},
    {"name": "comfort_low_count", "type": "integer", "unit": "", "meaning": "Comfort answers below the study's lowest comfortable value."},
    {"name": "pauses", "type": "integer", "unit": "", "meaning": "Pause events."},
    {"name": "ended_early", "type": "boolean", "unit": "", "meaning": "Participant ended before the plan finished."},
    {"name": "improvement", "type": "string", "unit": "", "meaning": "true, false or empty; true only when eye share rose, comfort did not worsen and content responses held."},
    {"name": "group_key", "type": "string", "unit": "", "meaning": "device | protocol version | estimator | screen bucket | stimulus bucket; sessions in different groups are not pooled."},
    {"name": "demo_<key>", "type": "varies", "unit": "", "meaning": "Demographics answer for <key>, stored under the research code."},
    {"name": "export_version", "type": "string", "unit": "", "meaning": "Version of this export layout."},
    {"name": "samples.t_ms", "type": "integer", "unit": "ms", "meaning": "Client monotonic time of the frame."},
    {"name": "samples.x / samples.y", "type": "number", "unit": "px", "meaning": "Mapped gaze point on the participant's screen; empty when uncertain."},
    {"name": "samples.conf", "type": "number", "unit": "0-1", "meaning": "Estimator confidence proxy."},
    {"name": "samples.region", "type": "string", "unit": "", "meaning": "eye, mouth, face_other, outside or uncertain."},
]
