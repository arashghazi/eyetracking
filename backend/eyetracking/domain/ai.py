"""AI content generation rules for build step 5: jobs, budget, prompts and sample content.

Framework-free. The provider is swappable; nothing generated reaches a participant without review,
approval and explicit attachment. Only the topic, display name, interests and constraints are sent
to a provider; never the camera image, the login email or gaze data.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from .errors import Conflict, Invalid

JOB_KINDS = ("text", "video")
JOB_STATUSES = ("queued", "running", "succeeded", "failed", "cancelled")
MAX_ATTEMPTS = 3
SAMPLE_MARK = "[Sample content from the development provider]"


@dataclass
class AiBudget:
    study_id: int
    cost_cap_units: float = 0.0
    spent_units: float = 0.0
    send_free_text: bool = False
    id: int | None = None

    def remaining(self) -> float:
        return max(0.0, self.cost_cap_units - self.spent_units)

    def assert_affordable(self, estimate: float) -> None:
        if estimate <= 0:
            return
        if self.spent_units + estimate > self.cost_cap_units + 1e-9:
            raise Invalid(f"budget_exceeded: estimate {estimate:.3f} + spent {self.spent_units:.3f} exceeds cap {self.cost_cap_units:.3f}")


@dataclass
class GenerationJob:
    study_id: int
    kind: str
    provider: str
    content_id: int
    status: str = "queued"
    assignment_id: int | None = None
    segment_id: str | None = None
    attempts: int = 0
    max_attempts: int = MAX_ATTEMPTS
    cost_estimate_units: float = 0.0
    cost_actual_units: float = 0.0
    error: str | None = None
    request: dict = field(default_factory=dict)
    result: dict = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.utcnow)
    started_at: datetime | None = None
    finished_at: datetime | None = None
    next_attempt_at: datetime | None = None
    id: int | None = None

    def cancel(self) -> None:
        if self.status != "queued":
            raise Conflict("only queued jobs can be cancelled")
        self.status = "cancelled"

    def retry(self, now: datetime) -> None:
        if self.status != "failed":
            raise Conflict("only failed jobs can be retried")
        self.status = "queued"
        self.error = None
        self.next_attempt_at = now

    def mark_failure(self, message: str, now: datetime, terminal: bool = False) -> None:
        self.attempts += 1
        self.error = message[:1000]
        if terminal or self.attempts >= self.max_attempts:
            self.status = "failed"
            self.finished_at = now
        else:
            self.status = "queued"
            self.next_attempt_at = now + timedelta(seconds=backoff_seconds(self.attempts))


def backoff_seconds(attempts: int) -> int:
    return 30 * (2 ** max(0, attempts - 1))


@dataclass(frozen=True)
class TextRequest:
    topic: str
    display_name: str | None
    interests: tuple[str, ...]
    interaction_points: int
    length_seconds: int
    free_text: str | None = None

    def validate(self) -> None:
        if not (self.topic or "").strip() or len(self.topic) > 200:
            raise Invalid("topic is required (up to 200 characters)")
        if not 0 <= self.interaction_points <= 5:
            raise Invalid("interaction_points must be between 0 and 5")
        if not 30 <= self.length_seconds <= 600:
            raise Invalid("length_seconds must be between 30 and 600")

    def minimized(self) -> dict:
        return {
            "topic": self.topic,
            "display_name": self.display_name,
            "interests": list(self.interests),
            "interaction_points": self.interaction_points,
            "length_seconds": self.length_seconds,
            "free_text_included": self.free_text is not None,
        }


CONTENT_SCHEMA: dict = {
    "type": "object",
    "additionalProperties": False,
    "required": ["title", "start_segment", "post_segment", "segments", "comprehension"],
    "properties": {
        "title": {"type": "string"},
        "start_segment": {"type": "string"},
        "post_segment": {"type": "string"},
        "segments": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["id", "text", "duration_s", "question"],
                "properties": {
                    "id": {"type": "string"},
                    "text": {"type": "string"},
                    "duration_s": {"type": "number"},
                    "question": {
                        "anyOf": [
                            {"type": "null"},
                            {
                                "type": "object",
                                "additionalProperties": False,
                                "required": ["id", "prompt", "options", "branches"],
                                "properties": {
                                    "id": {"type": "string"},
                                    "prompt": {"type": "string"},
                                    "options": {"type": "array", "items": {"type": "string"}},
                                    "branches": {"type": "array", "items": {"type": "object", "additionalProperties": False, "required": ["option", "segment"], "properties": {"option": {"type": "string"}, "segment": {"type": "string"}}}},
                                },
                            },
                        ]
                    },
                },
            },
        },
        "comprehension": {
            "type": "array",
            "items": {"type": "object", "additionalProperties": False, "required": ["id", "prompt", "options", "correct"], "properties": {"id": {"type": "string"}, "prompt": {"type": "string"}, "options": {"type": "array", "items": {"type": "string"}}, "correct": {"type": "string"}}},
        },
    },
}


def script_prompt(req: TextRequest) -> tuple[str, str]:
    """System and user prompts for a short, calm, age-respectful conversation script."""
    system = (
        "You write short spoken scripts for a research app that helps autistic young adults practise comfortable "
        "attention to a speaker's face. The speaker is a friendly adult who talks about a topic the participant chose. "
        "Rules: plain English, calm and respectful, no pressure to look, no medical claims, no personal questions, "
        "no jokes at anyone's expense, no eye-contact instructions. Each segment is spoken by the speaker as one take. "
        "Questions at segment ends are simple choices about the topic; every option must branch to an existing segment. "
        "Comprehension questions are about facts the speaker said, with exactly one correct option. Return only the JSON."
    )
    parts = [
        f"Topic: {req.topic}.",
        f"Address the participant as {req.display_name}." if req.display_name else "Do not use a name.",
        f"Their interests: {', '.join(req.interests)}." if req.interests else "",
        f"Total spoken length about {req.length_seconds} seconds across the segments (each 10 to 60 seconds).",
        f"Include {req.interaction_points} question point(s) between segments, then a final segment with no question that also serves as post_segment.",
        "Segment ids: s1, s2, ...; question ids q1, q2, ...; comprehension ids c1, c2 (two questions).",
    ]
    if req.free_text:
        parts.append(f"The participant added: {req.free_text}")
    return system, "\n".join(p for p in parts if p)


def branches_to_dict(definition: dict) -> dict:
    """The model returns branches as a list of {option, segment}; the content format wants a mapping."""
    out = json.loads(json.dumps(definition))
    for seg in out.get("segments", []):
        q = seg.get("question")
        if q and isinstance(q.get("branches"), list):
            q["branches"] = {b["option"]: b["segment"] for b in q["branches"]}
    out.pop("title", None)
    return out


def assign_media_keys(definition: dict) -> dict:
    for seg in definition.get("segments", []):
        seg["media_key"] = f"{seg['id']}.webm"
    return definition


def sample_script(req: TextRequest) -> dict:
    """Deterministic sample content for the development provider; visibly marked as a sample."""
    name = req.display_name or "there"
    topic = req.topic
    segments = [
        {"id": "s1", "text": f"{SAMPLE_MARK} Hi {name}. Today I would like to talk with you about {topic}. I find it interesting because there is always something new to notice.", "duration_s": 20,
         "question": {"id": "q1", "prompt": f"What would you like to hear about {topic} first?", "options": ["How it started", "What people enjoy about it"], "branches": {"How it started": "s2", "What people enjoy about it": "s2"}}},
        {"id": "s2", "text": f"{SAMPLE_MARK} Thank you for choosing. Many people say the best part of {topic} is sharing it with someone else. It can be quiet or lively, and both are fine.", "duration_s": 20, "question": None},
        {"id": "s3", "text": f"{SAMPLE_MARK} That is all for today, {name}. Thank you for listening. You can stop here or come back another time.", "duration_s": 12, "question": None},
    ]
    if req.interaction_points >= 2:
        segments[1]["question"] = {"id": "q2", "prompt": "Would you like one more short part?", "options": ["Yes", "No"], "branches": {"Yes": "s3", "No": "s3"}}
    definition = {
        "start_segment": "s1",
        "post_segment": "s3",
        "segments": segments,
        "comprehension": [
            {"id": "c1", "prompt": "What was the conversation about?", "options": [topic, "The weather"], "correct": topic},
            {"id": "c2", "prompt": "What did the speaker say is the best part?", "options": ["Sharing it with someone", "Doing it alone"], "correct": "Sharing it with someone"},
        ],
    }
    return assign_media_keys(definition)
