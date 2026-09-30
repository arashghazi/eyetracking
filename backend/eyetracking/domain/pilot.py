"""Supervised pilot rules for build step 6 (design p. 6): observations, debrief, threshold review
and comparison with a research eye tracker.

Framework-free. Nothing here changes a threshold on its own: the review only shows what a candidate
would change, and a researcher decides. Agreement with a reference tracker describes one session on
one computer; it is not a general accuracy claim.
"""
from __future__ import annotations

import csv
import io
import math
import re
from dataclasses import dataclass, field
from datetime import datetime

from .errors import Invalid
from .measurement import CLASSIFIABLE, MeasurementSettings, classify_point

# ---------- supervisor observations ----------

OBS_CATEGORIES = ("comfort", "comprehension", "technical", "ux", "protocol", "other")
OBS_SEVERITIES = ("info", "minor", "major", "stop")
MAX_OBSERVATION_CHARS = 2000


@dataclass
class Observation:
    study_id: int
    session_id: int
    author_id: int
    category: str
    severity: str
    text: str
    t_ms: int | None = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None

    def validate(self) -> None:
        if self.category not in OBS_CATEGORIES:
            raise Invalid("category must be one of " + ", ".join(OBS_CATEGORIES))
        if self.severity not in OBS_SEVERITIES:
            raise Invalid("severity must be one of " + ", ".join(OBS_SEVERITIES))
        self.text = (self.text or "").strip()
        if not self.text:
            raise Invalid("observation text is required")
        if len(self.text) > MAX_OBSERVATION_CHARS:
            raise Invalid(f"observation text is limited to {MAX_OBSERVATION_CHARS} characters")
        if self.t_ms is not None and self.t_ms < 0:
            raise Invalid("t_ms must not be negative")


# ---------- settings versions ----------

SETTINGS_FIELDS = (
    "validation_min_correct",
    "validation_max_uncertain",
    "min_region_to_error_ratio",
    "gaze_conf_threshold",
    "calibration_points",
    "allow_continue_without_validation",
    "quality_max_uncertain_share",
    "quality_max_missing_share",
)
MAX_RATIONALE_CHARS = 1000


@dataclass
class SettingsVersion:
    study_id: int
    version: int
    values: dict
    rationale: str = ""
    changed_by: int | None = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


def settings_values(s: MeasurementSettings) -> dict:
    return {k: getattr(s, k) for k in SETTINGS_FIELDS}


# ---------- debrief ----------

QUESTION_TYPES = ("scale", "yes_no", "choice", "text")
MAX_QUESTIONS = 20
MAX_TEXT_ANSWER = 1000
_KEY = re.compile(r"^[a-z][a-z0-9_]{0,39}$")

DEFAULT_DEBRIEF_QUESTIONS: list[dict] = [
    {"key": "instructions_clear", "type": "scale", "prompt": "How easy were the instructions to understand?", "scale_max": 5,
     "labels": ["Very hard", "Hard", "OK", "Easy", "Very easy"], "required": True},
    {"key": "comfort_overall", "type": "scale", "prompt": "How comfortable did you feel during the session?", "scale_max": 5,
     "labels": ["Very uncomfortable", "Uncomfortable", "Neutral", "Comfortable", "Very comfortable"], "required": True},
    {"key": "anything_uncomfortable", "type": "yes_no", "prompt": "Was anything uncomfortable or upsetting?", "required": False},
    {"key": "uncomfortable_detail", "type": "text", "prompt": "If something was uncomfortable, what was it? (optional)", "required": False},
    {"key": "camera_setup_easy", "type": "yes_no", "prompt": "Was setting up the camera easy?", "required": False},
    {"key": "one_change", "type": "text", "prompt": "If you could change one thing, what would it be? (optional)", "required": False},
]


@dataclass
class DebriefForm:
    study_id: int
    version: int
    questions: list[dict]
    enabled: bool = False
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class DebriefAnswer:
    study_id: int
    session_id: int
    participant_id: int
    form_version: int
    answers: dict
    skipped: bool = False
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


def validate_debrief_questions(questions: list[dict]) -> list[dict]:
    if not isinstance(questions, list) or not 1 <= len(questions) <= MAX_QUESTIONS:
        raise Invalid(f"a debrief form needs 1 to {MAX_QUESTIONS} questions")
    seen: set[str] = set()
    out: list[dict] = []
    for i, q in enumerate(questions):
        where = f"questions[{i}]"
        if not isinstance(q, dict):
            raise Invalid(f"{where} must be an object")
        key = str(q.get("key") or "")
        if not _KEY.match(key):
            raise Invalid(f"{where}.key must start with a letter and use a-z, 0-9 or _ (max 40)")
        if key in seen:
            raise Invalid(f"{where}.key '{key}' is used twice")
        seen.add(key)
        qtype = q.get("type")
        if qtype not in QUESTION_TYPES:
            raise Invalid(f"{where}.type must be one of " + ", ".join(QUESTION_TYPES))
        prompt = str(q.get("prompt") or "").strip()
        if not prompt or len(prompt) > 300:
            raise Invalid(f"{where}.prompt is required (max 300 characters)")
        clean = {"key": key, "type": qtype, "prompt": prompt, "required": bool(q.get("required", False))}
        if qtype == "scale":
            smax = q.get("scale_max", 5)
            if not isinstance(smax, int) or isinstance(smax, bool) or not 2 <= smax <= 10:
                raise Invalid(f"{where}.scale_max must be a whole number from 2 to 10")
            labels = q.get("labels") or []
            if labels and (len(labels) != smax or not all(isinstance(x, str) and x.strip() for x in labels)):
                raise Invalid(f"{where}.labels must have one text per scale point")
            clean["scale_max"] = smax
            clean["labels"] = [x.strip() for x in labels]
        elif qtype == "choice":
            options = q.get("options") or []
            if not 2 <= len(options) <= 10 or not all(isinstance(x, str) and x.strip() for x in options):
                raise Invalid(f"{where}.options needs 2 to 10 texts")
            if len({x.strip() for x in options}) != len(options):
                raise Invalid(f"{where}.options must be different")
            clean["options"] = [x.strip() for x in options]
        out.append(clean)
    return out


def validate_debrief_answers(questions: list[dict], answers: dict) -> dict:
    if not isinstance(answers, dict):
        raise Invalid("answers must be an object")
    known = {q["key"]: q for q in questions}
    unknown = sorted(set(answers) - set(known))
    if unknown:
        raise Invalid("unknown questions: " + ", ".join(unknown))
    clean: dict = {}
    for key, q in known.items():
        v = answers.get(key)
        if v is None or (isinstance(v, str) and not v.strip()):
            if q.get("required"):
                raise Invalid(f"'{key}' needs an answer")
            continue
        if q["type"] == "scale":
            if not isinstance(v, int) or isinstance(v, bool) or not 1 <= v <= q["scale_max"]:
                raise Invalid(f"'{key}' must be a whole number from 1 to {q['scale_max']}")
        elif q["type"] == "yes_no":
            if not isinstance(v, bool):
                raise Invalid(f"'{key}' must be true or false")
        elif q["type"] == "choice":
            if v not in q["options"]:
                raise Invalid(f"'{key}' must be one of the options")
        else:
            if not isinstance(v, str):
                raise Invalid(f"'{key}' must be text")
            v = v.strip()
            if len(v) > MAX_TEXT_ANSWER:
                raise Invalid(f"'{key}' is limited to {MAX_TEXT_ANSWER} characters")
        clean[key] = v
    return clean


# ---------- threshold review ----------


def revalidate(stored: dict, candidate: MeasurementSettings) -> dict:
    """Re-evaluate a stored validation under candidate thresholds.

    Uses only what the validation stored (ratios and missing target regions). The confidence
    threshold changes how each sample is classified, so it cannot be re-evaluated here.
    """
    reasons = [r for r in stored.get("reasons") or [] if str(r).startswith("missing_target_regions")]
    if stored["correct_ratio"] < candidate.validation_min_correct:
        reasons.append(f"correct_ratio_below_{candidate.validation_min_correct}")
    if stored["uncertain_ratio"] > candidate.validation_max_uncertain:
        reasons.append(f"uncertain_ratio_above_{candidate.validation_max_uncertain}")
    if stored["size_ratio"] < candidate.min_region_to_error_ratio:
        reasons.append(f"eye_region_smaller_than_{candidate.min_region_to_error_ratio}x_error")
    return {"passed": not reasons, "reasons": reasons}


def distribution(values: list[float]) -> dict:
    vals = sorted(float(v) for v in values if v is not None and not (isinstance(v, float) and math.isnan(v)))
    if not vals:
        return {"n": 0}

    def q(p: float) -> float:
        if len(vals) == 1:
            return vals[0]
        pos = p * (len(vals) - 1)
        lo = int(math.floor(pos))
        hi = min(lo + 1, len(vals) - 1)
        return vals[lo] + (vals[hi] - vals[lo]) * (pos - lo)

    return {"n": len(vals), "min": round(vals[0], 4), "p25": round(q(0.25), 4), "median": round(q(0.5), 4),
            "p75": round(q(0.75), 4), "p90": round(q(0.9), 4), "max": round(vals[-1], 4)}


# ---------- research eye tracker comparison ----------

TIME_UNITS = {"ms": 1.0, "us": 0.001, "s": 1000.0}
COORD_SPACES = ("css_px", "device_px", "norm")
MAX_REFERENCE_ROWS = 2_000_000


@dataclass
class ReferenceRecording:
    study_id: int
    session_id: int
    source: str
    uploaded_by: int
    settings: dict
    sample_count: int = 0
    valid_count: int = 0
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class ReferenceSample:
    recording_id: int
    t_ms: int
    x: float | None
    y: float | None
    valid: bool
    id: int | None = None


def parse_reference_csv(data: bytes, opts: dict, screen: dict) -> list[tuple[int, float | None, float | None, bool]]:
    """Parse a tracker export into (session t_ms, x, y, valid) in the app's CSS pixels.

    opts: time_column, x_column, y_column, valid_column (optional), valid_values (comma list),
    time_unit (ms|us|s), offset (tracker time at session t_ms = 0, in time_unit), coord_space
    (css_px|device_px|norm), origin_x / origin_y (CSS px of the app's top-left on the tracker's
    screen; 0 when the app runs full screen), delimiter (',' ';' or 'tab'; guessed when empty).
    """
    unit = opts.get("time_unit", "ms")
    if unit not in TIME_UNITS:
        raise Invalid("time_unit must be ms, us or s")
    space = opts.get("coord_space", "css_px")
    if space not in COORD_SPACES:
        raise Invalid("coord_space must be css_px, device_px or norm")
    try:
        offset = float(opts.get("offset") or 0)
        origin_x = float(opts.get("origin_x") or 0)
        origin_y = float(opts.get("origin_y") or 0)
    except (TypeError, ValueError) as e:
        raise Invalid("offset, origin_x and origin_y must be numbers") from e
    dpr = float(screen.get("dpr") or 1) or 1.0
    sw, sh = float(screen.get("w") or 0), float(screen.get("h") or 0)
    if space == "norm" and (sw <= 0 or sh <= 0):
        raise Invalid("norm coordinates need the session's screen size")
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = data.decode("latin-1")
    delim = {"tab": "\t", ",": ",", ";": ";"}.get(opts.get("delimiter") or "")
    if delim is None:
        head = text[:4096]
        delim = max(("\t", ";", ","), key=head.count)
    reader = csv.DictReader(io.StringIO(text), delimiter=delim)
    cols = reader.fieldnames or []
    tcol, xcol, ycol, vcol = opts.get("time_column"), opts.get("x_column"), opts.get("y_column"), opts.get("valid_column") or None
    for name, col in (("time_column", tcol), ("x_column", xcol), ("y_column", ycol)):
        if not col:
            raise Invalid(f"{name} is required")
    for name, col in (("time_column", tcol), ("x_column", xcol), ("y_column", ycol), ("valid_column", vcol)):
        if col is not None and col not in cols:
            raise Invalid(f"{name} '{col}' is not in the file; columns: " + ", ".join(cols[:30]))
    valid_values = {v.strip().lower() for v in str(opts.get("valid_values") or "1,true,valid,yes").split(",") if v.strip()}

    def num(v: str | None) -> float | None:
        if v is None:
            return None
        v = v.strip().replace(",", ".") if delim != "," else v.strip()
        if not v:
            return None
        try:
            f = float(v)
        except ValueError:
            return None
        return None if math.isnan(f) else f

    out: list[tuple[int, float | None, float | None, bool]] = []
    for i, row in enumerate(reader):
        if i >= MAX_REFERENCE_ROWS:
            raise Invalid(f"the file has more than {MAX_REFERENCE_ROWS} rows")
        t = num(row.get(tcol))
        if t is None:
            continue
        t_ms = int(round((t - offset) * TIME_UNITS[unit]))
        x, y = num(row.get(xcol)), num(row.get(ycol))
        ok = x is not None and y is not None
        if vcol is not None:
            ok = ok and str(row.get(vcol) or "").strip().lower() in valid_values
        if ok:
            if space == "device_px":
                x, y = x / dpr, y / dpr
            elif space == "norm":
                x, y = x * sw, y * sh
            x, y = x - origin_x, y - origin_y
        else:
            x = y = None
        out.append((t_ms, x, y, ok))
    if not out:
        raise Invalid("no rows with a time value were found")
    out.sort(key=lambda r: r[0])
    return out


def _nearest(ref_t: list[int], t: int, tolerance_ms: int) -> int | None:
    import bisect

    i = bisect.bisect_left(ref_t, t)
    best, best_d = None, tolerance_ms + 1
    for j in (i - 1, i):
        if 0 <= j < len(ref_t):
            d = abs(ref_t[j] - t)
            if d < best_d:
                best, best_d = j, d
    return best if best_d <= tolerance_ms else None


def cohen_kappa(matrix: dict[str, dict[str, int]], labels: tuple[str, ...]) -> float | None:
    n = sum(matrix[a][b] for a in labels for b in labels)
    if n == 0:
        return None
    po = sum(matrix[a][a] for a in labels) / n
    pe = sum((sum(matrix[a][b] for b in labels) / n) * (sum(matrix[b][a] for b in labels) / n) for a in labels)
    if pe >= 1.0:
        return None
    return round((po - pe) / (1 - pe), 4)


def compare_with_reference(
    webcam: list[dict],
    reference: list[tuple[int, float | None, float | None, bool]],
    layouts: dict[int, dict],
    tolerance_ms: int,
) -> dict:
    """Pair each webcam sample with the nearest reference sample in time and compare.

    webcam items: {t_ms, x, y, valid, region, segment, layout_id}. Reference points are classified
    with the same stimulus layout as the webcam sample they are paired with.
    """
    if not 1 <= tolerance_ms <= 500:
        raise Invalid("tolerance_ms must be between 1 and 500")
    ref_t = [r[0] for r in reference]
    labels = CLASSIFIABLE
    matrix = {a: {b: 0 for b in labels} for a in labels}
    dists: list[float] = []
    dxs: list[float] = []
    dys: list[float] = []
    paired = 0
    webcam_uncertain_ref_valid = 0
    ref_invalid = 0
    unpaired = 0
    per_segment: dict[str, dict] = {}
    for w in webcam:
        j = _nearest(ref_t, int(w["t_ms"]), tolerance_ms)
        if j is None:
            unpaired += 1
            continue
        _, rx, ry, rvalid = reference[j]
        if not rvalid:
            ref_invalid += 1
            continue
        layout = layouts.get(w.get("layout_id") or -1)
        if layout is None:
            continue
        ref_region = classify_point((rx, ry), 1.0, layout, 0.0)
        seg = per_segment.setdefault(w.get("segment") or "free", {"pairs": 0, "webcam_eye": 0, "reference_eye": 0, "webcam_classified": 0})
        if not w.get("valid") or w.get("region") not in labels or w.get("x") is None:
            webcam_uncertain_ref_valid += 1
            seg["pairs"] += 1
            seg["reference_eye"] += int(ref_region == "eye")
            continue
        paired += 1
        seg["pairs"] += 1
        seg["webcam_classified"] += 1
        seg["webcam_eye"] += int(w["region"] == "eye")
        seg["reference_eye"] += int(ref_region == "eye")
        matrix[w["region"]][ref_region] += 1
        dx, dy = float(w["x"]) - rx, float(w["y"]) - ry
        dxs.append(dx)
        dys.append(dy)
        dists.append(math.hypot(dx, dy))
    agree = sum(matrix[a][a] for a in labels)
    segments = []
    for label, s in per_segment.items():
        segments.append({
            "segment": label,
            "pairs": s["pairs"],
            "webcam_eye_share": round(s["webcam_eye"] / s["webcam_classified"], 4) if s["webcam_classified"] else None,
            "reference_eye_share": round(s["reference_eye"] / s["pairs"], 4) if s["pairs"] else None,
        })
    eye_row = sum(matrix["eye"].values())
    eye_col = sum(matrix[a]["eye"] for a in labels)
    return {
        "tolerance_ms": tolerance_ms,
        "webcam_samples": len(webcam),
        "paired_classified": paired,
        "webcam_uncertain_while_reference_valid": webcam_uncertain_ref_valid,
        "reference_invalid": ref_invalid,
        "no_reference_in_time": unpaired,
        "distance_px": distribution(dists),
        "bias_px": {"x": round(sum(dxs) / len(dxs), 2) if dxs else None, "y": round(sum(dys) / len(dys), 2) if dys else None},
        "region_agreement": round(agree / paired, 4) if paired else None,
        "cohen_kappa": cohen_kappa(matrix, labels),
        "confusion": {"rows_webcam_columns_reference": matrix},
        "eye_region": {
            "precision": round(matrix["eye"]["eye"] / eye_row, 4) if eye_row else None,
            "recall": round(matrix["eye"]["eye"] / eye_col, 4) if eye_col else None,
        },
        "segments": sorted(segments, key=lambda s: s["segment"]),
        "note": "Agreement for this session on this computer only. Distances are in the app's CSS pixels; not a general accuracy claim.",
    }


def estimate_offset(webcam: list[dict], reference: list[tuple[int, float | None, float | None, bool]], window_ms: int, step_ms: int = 20) -> int:
    """Search the time shift (added to reference times) that minimises the median distance.

    Estimating the alignment from the same data makes the agreement optimistic; callers must say so.
    """
    if not 0 < window_ms <= 10_000:
        raise Invalid("auto-align window must be between 1 and 10000 ms")
    pts = [w for w in webcam if w.get("valid") and w.get("x") is not None][:: max(1, len(webcam) // 2000)]
    valid_ref = [r for r in reference if r[3]]
    if not pts or not valid_ref:
        return 0
    best_shift, best = 0, float("inf")
    for shift in range(-window_ms, window_ms + 1, step_ms):
        ref_t = [r[0] + shift for r in valid_ref]
        ds = []
        for w in pts:
            j = _nearest(ref_t, int(w["t_ms"]), step_ms)
            if j is not None:
                ds.append(math.hypot(float(w["x"]) - valid_ref[j][1], float(w["y"]) - valid_ref[j][2]))
        if len(ds) >= max(10, len(pts) // 4):
            ds.sort()
            med = ds[len(ds) // 2]
            if med < best:
                best, best_shift = med, shift
    return best_shift
