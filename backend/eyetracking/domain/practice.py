"""Practice rules for build step 3: protocol definitions, content, assignments, trials and outcomes.

Framework-free. The design's constraints live here: one factor changes per stage, the number never
goes beyond the protocol's final zone, nothing advances on a wrong answer, discomfort or invalid data,
and "improvement" needs all three outcomes at once.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from statistics import mean

from .errors import Conflict, Invalid

PATHS = ("gradual_face", "interest_conversation")
ZONES = ("outside", "face_edge", "near_eyes", "eye_region")
RESPONSE_MODES = ("number", "four_choice", "symbol", "profile")
ANSWER_KINDS = ("interaction", "comprehension")
DECISIONS = ("advance", "hold", "easier", "stop", "complete")
MEDIA_TYPES = {"video/webm", "video/mp4", "image/png", "image/jpeg"}
MAX_MEDIA_BYTES = 200 * 1024 * 1024
_TOKEN = re.compile(r"\{\{\s*(display_name|topic)\s*\}\}")


class ProtocolStatus(str, Enum):
    draft = "draft"
    published = "published"


class ContentStatus(str, Enum):
    draft = "draft"
    approved = "approved"


class AssignmentStatus(str, Enum):
    pending_topic = "pending_topic"
    content_pending = "content_pending"
    ready = "ready"
    in_progress = "in_progress"
    completed = "completed"
    cancelled = "cancelled"


@dataclass
class Protocol:
    study_id: int
    name: str
    definition: dict
    status: ProtocolStatus = ProtocolStatus.draft
    version: int = 0
    created_at: datetime = field(default_factory=datetime.utcnow)
    published_at: datetime | None = None
    id: int | None = None

    @property
    def path(self) -> str:
        return str(self.definition.get("path", ""))

    def ensure_draft(self) -> None:
        if self.status is not ProtocolStatus.draft:
            raise Conflict("published protocol versions cannot be edited; create a new draft")


@dataclass
class ContentItem:
    study_id: int
    title: str
    definition: dict
    topic_tags: list[str] = field(default_factory=list)
    face_id: str = ""
    voice_id: str = ""
    status: ContentStatus = ContentStatus.draft
    text_reviewed: bool = False
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None

    def ensure_draft(self) -> None:
        if self.status is not ContentStatus.draft:
            raise Conflict("approved content cannot be edited")

    def media_keys(self) -> list[str]:
        keys: list[str] = []
        for seg in self.definition.get("segments", []):
            if seg.get("media_key"):
                keys.append(seg["media_key"])
            for k in (seg.get("question") or {}).get("reaction_media_key", {}).values() if isinstance((seg.get("question") or {}).get("reaction_media_key"), dict) else []:
                keys.append(k)
        return keys


@dataclass
class ContentMedia:
    content_id: int
    key: str
    path: str
    content_type: str
    size: int
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class Assignment:
    participant_id: int
    study_id: int
    protocol_id: int
    order_index: int = 0
    status: AssignmentStatus = AssignmentStatus.ready
    topic: str | None = None
    topic_free_text: str | None = None
    content_id: int | None = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class Trial:
    session_id: int
    stage_index: int
    trial_index: int
    t_ms: int
    number_shown: str
    zone: str
    position: dict
    face_level: int
    response: str | None
    correct: bool
    response_ms: int | None = None
    id: int | None = None


@dataclass
class StageResult:
    session_id: int
    stage_index: int
    decision: str
    reason: str
    correct_ratio: float | None
    invalid_share: float
    comfort_value: int | None
    trials: int
    next_stage_index: int | None
    last_trial_id: int = 0
    created_at: datetime = field(default_factory=datetime.utcnow)
    id: int | None = None


@dataclass
class Answer:
    session_id: int
    segment_id: str
    question_id: str
    kind: str
    option: str
    correct: bool | None
    t_ms: int
    next_segment_id: str | None = None
    id: int | None = None


# ---------- protocol validation ----------


def _num(d: dict, key: str, lo: float, hi: float, where: str) -> float:
    v = d.get(key)
    if not isinstance(v, (int, float)) or isinstance(v, bool) or not lo <= v <= hi:
        raise Invalid(f"{where}.{key} must be a number between {lo} and {hi}")
    return v


def validate_protocol(definition: dict) -> None:
    if not isinstance(definition, dict):
        raise Invalid("definition must be an object")
    path = definition.get("path")
    if path not in PATHS:
        raise Invalid(f"path must be one of {PATHS}")
    _num(definition, "baseline_seconds", 10, 600, "definition")
    _num(definition, "post_seconds", 10, 600, "definition")
    comfort = definition.get("comfort") or {}
    scale_max = int(_num(comfort, "scale_max", 3, 7, "comfort"))
    labels = comfort.get("labels")
    if not isinstance(labels, list) or len(labels) != scale_max or not all(isinstance(x, str) and x.strip() for x in labels):
        raise Invalid("comfort.labels must have one non-empty label per scale value")
    _num(comfort, "min_ok", 1, scale_max, "comfort")
    progression = definition.get("progression") or {}
    _num(progression, "hold_on_invalid_share_above", 0, 1, "progression")
    for key in ("easier_on_comfort_below_min", "stop_on_two_low_comfort"):
        if not isinstance(progression.get(key, True), bool):
            raise Invalid(f"progression.{key} must be true or false")
    if path == "gradual_face":
        g = definition.get("gradual")
        if not isinstance(g, dict):
            raise Invalid("gradual settings are required for the gradual_face path")
        limit = g.get("final_zone_limit", "near_eyes")
        if limit not in ZONES:
            raise Invalid(f"gradual.final_zone_limit must be one of {ZONES}")
        stages = g.get("stages")
        if not isinstance(stages, list) or not 1 <= len(stages) <= 20:
            raise Invalid("gradual.stages must hold 1 to 20 stages")
        simultaneous = bool(g.get("allow_simultaneous_change", False))
        prev = None
        for i, st in enumerate(stages):
            where = f"gradual.stages[{i}]"
            level = int(_num(st, "face_level", 0, 3, where))
            zone = st.get("number_zone")
            if zone not in ZONES:
                raise Invalid(f"{where}.number_zone must be one of {ZONES}")
            if ZONES.index(zone) > ZONES.index(limit):
                raise Invalid(f"{where}.number_zone goes beyond final_zone_limit {limit}")
            _num(st, "trials", 1, 50, where)
            _num(st, "min_correct", 0, 1, where)
            _num(st, "trial_seconds", 2, 60, where)
            if st.get("response_mode", "profile") not in RESPONSE_MODES:
                raise Invalid(f"{where}.response_mode must be one of {RESPONSE_MODES}")
            if prev is not None:
                if level < prev[0] or ZONES.index(zone) < ZONES.index(prev[1]):
                    raise Invalid(f"{where} must not go back in face_level or number_zone")
                changed = int(level != prev[0]) + int(zone != prev[1])
                if changed > 1 and not simultaneous:
                    raise Invalid(f"{where} changes both face_level and number_zone; allow_simultaneous_change is off")
            prev = (level, zone)
    else:
        it = definition.get("interest")
        if not isinstance(it, dict):
            raise Invalid("interest settings are required for the interest_conversation path")
        _num(it, "interaction_points", 0, 5, "interest")


# ---------- content validation and personalization ----------


def validate_content(definition: dict) -> None:
    if not isinstance(definition, dict):
        raise Invalid("definition must be an object")
    segments = definition.get("segments")
    if not isinstance(segments, list) or not segments:
        raise Invalid("content needs at least one segment")
    ids: set[str] = set()
    for i, seg in enumerate(segments):
        sid = seg.get("id")
        if not isinstance(sid, str) or not sid.strip():
            raise Invalid(f"segments[{i}].id is required")
        if sid in ids:
            raise Invalid(f"duplicate segment id {sid}")
        ids.add(sid)
        if not isinstance(seg.get("text", ""), str):
            raise Invalid(f"segment {sid}: text must be a string")
        _num(seg, "duration_s", 1, 900, f"segment {sid}")
        layout = seg.get("face_layout")
        if layout is not None:
            for key in ("face_box", "eye_region", "mouth_region"):
                box = layout.get(key)
                if not (isinstance(box, list) and len(box) == 4 and all(isinstance(v, (int, float)) and 0 <= v <= 1 for v in box)):
                    raise Invalid(f"segment {sid}: face_layout.{key} must be four numbers between 0 and 1")
    for seg in segments:
        q = seg.get("question")
        if q is None:
            continue
        if not isinstance(q.get("id"), str) or not q.get("prompt") or not isinstance(q.get("options"), list) or len(q["options"]) < 2:
            raise Invalid(f"segment {seg['id']}: question needs id, prompt and at least two options")
        branches = q.get("branches") or {}
        if not isinstance(branches, dict) or set(branches) - set(q["options"]):
            raise Invalid(f"segment {seg['id']}: branches must map options to segment ids")
        for opt, target in branches.items():
            if target not in ids:
                raise Invalid(f"segment {seg['id']}: branch {opt} points to unknown segment {target}")
    start = definition.get("start_segment")
    if start not in ids:
        raise Invalid("start_segment must name an existing segment")
    post = definition.get("post_segment")
    if post is not None and post not in ids:
        raise Invalid("post_segment must name an existing segment")
    for i, c in enumerate(definition.get("comprehension", []) or []):
        if not isinstance(c.get("id"), str) or not c.get("prompt") or not isinstance(c.get("options"), list) or len(c["options"]) < 2:
            raise Invalid(f"comprehension[{i}] needs id, prompt and at least two options")
        if c.get("correct") not in c["options"]:
            raise Invalid(f"comprehension[{i}].correct must be one of its options")


def personalize(text: str, display_name: str | None, topic: str | None) -> str:
    values = {"display_name": display_name or "there", "topic": topic or "your topic"}
    return _TOKEN.sub(lambda m: values[m.group(1)], text or "")


def next_segment(definition: dict, segment_id: str, option: str, display_name: str | None = None, topic: str | None = None) -> str | None:
    """Options are matched after personalization, exactly as the participant saw them."""
    seg = next((s for s in definition.get("segments", []) if s["id"] == segment_id), None)
    if seg is None:
        raise Invalid("unknown segment")
    q = seg.get("question")
    if q is None:
        raise Invalid("this segment has no question")
    shown = {personalize(o, display_name, topic): o for o in q["options"]}
    if option not in shown:
        raise Invalid("option is not one of the question's options")
    return (q.get("branches") or {}).get(shown[option])


def comprehension_correct(definition: dict, question_id: str, option: str, display_name: str | None = None, topic: str | None = None) -> bool:
    q = next((c for c in definition.get("comprehension", []) if c["id"] == question_id), None)
    if q is None:
        raise Invalid("unknown comprehension question")
    shown = {personalize(o, display_name, topic): o for o in q["options"]}
    if option not in shown:
        raise Invalid("option is not one of the question's options")
    return shown[option] == q["correct"]


# ---------- stage progression ----------


@dataclass(frozen=True)
class StageDecision:
    decision: str
    reason: str
    next_stage_index: int | None
    correct_ratio: float | None
    invalid_share: float
    trials: int


def evaluate_stage(
    definition: dict,
    stage_index: int,
    trials: list[Trial],
    comfort_value: int | None,
    invalid_share: float,
    low_comfort_streak: int,
) -> StageDecision:
    """Never advance on wrong answers, discomfort or invalid data; that is the design's rule."""
    stages = definition["gradual"]["stages"]
    if not 0 <= stage_index < len(stages):
        raise Invalid("stage_index is out of range for this protocol")
    stage = stages[stage_index]
    comfort = definition.get("comfort", {})
    progression = definition.get("progression", {})
    n = len(trials)
    ratio = (sum(1 for t in trials if t.correct) / n) if n else None
    is_last = stage_index == len(stages) - 1

    def result(decision: str, reason: str, nxt: int | None) -> StageDecision:
        return StageDecision(decision, reason, nxt, ratio, invalid_share, n)

    if comfort_value is not None and comfort_value < int(comfort.get("min_ok", 3)):
        if low_comfort_streak >= 1 and progression.get("stop_on_two_low_comfort", True):
            return result("stop", "low_comfort_twice", None)
        if progression.get("easier_on_comfort_below_min", True) and stage_index > 0:
            return result("easier", "low_comfort", stage_index - 1)
        return result("hold", "low_comfort", stage_index)
    if invalid_share > float(progression.get("hold_on_invalid_share_above", 0.3)):
        return result("hold", "invalid_data", stage_index)
    if n < int(stage["trials"]):
        return result("hold", "incomplete", stage_index)
    if ratio is None or ratio < float(stage["min_correct"]):
        return result("hold", "accuracy", stage_index)
    if is_last:
        return result("complete", "all_stages_done", None)
    return result("advance", "criteria_met", stage_index + 1)


# ---------- outcomes ----------


def comfort_outcome(values: list[int], min_ok: int, pauses: int, ended_early: bool) -> dict:
    return {
        "answers": len(values),
        "min": min(values) if values else None,
        "mean": round(mean(values), 2) if values else None,
        "low_count": sum(1 for v in values if v < min_ok),
        "pauses": pauses,
        "ended_early": ended_early,
    }


def improvement(
    gaze: dict, comprehension: dict, number_task: dict, comfort_values: list[int], min_ok: int, path: str | None
) -> dict:
    criteria: dict = {"eye_share_up": None, "comfort_not_worse": None, "comprehension_maintained": None}
    if not gaze.get("evaluable"):
        return {"eligible": False, "result": None, "criteria": criteria, "reason": gaze.get("reason") or "gaze_not_evaluable"}
    b, p = gaze.get("baseline_eye_share"), gaze.get("post_eye_share")
    if b is None or p is None:
        return {"eligible": False, "result": None, "criteria": criteria, "reason": "baseline_or_post_missing"}
    criteria["eye_share_up"] = p > b
    if comfort_values:
        criteria["comfort_not_worse"] = comfort_values[-1] >= comfort_values[0] and comfort_values[-1] >= min_ok
    else:
        return {"eligible": False, "result": None, "criteria": criteria, "reason": "no_comfort_answers"}
    if path == "interest_conversation":
        share = comprehension.get("share")
        criteria["comprehension_maintained"] = None if share is None else share >= 0.5
    else:
        share = number_task.get("share")
        criteria["comprehension_maintained"] = None if share is None else share >= 0.5
    if criteria["comprehension_maintained"] is None:
        return {"eligible": False, "result": None, "criteria": criteria, "reason": "no_content_responses"}
    return {"eligible": True, "result": all(criteria.values()), "criteria": criteria, "reason": None}
