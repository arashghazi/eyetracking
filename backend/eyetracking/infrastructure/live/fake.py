"""Development providers for the live avatar: no key, no cost, clearly synthetic.

The reply stand-in follows a few fixed rules so the whole loop can be tried and tested; it does not
understand anything. Speech "recognition" returns a fixed sentence. The avatar is the packaged
sample face video, and the app speaks the lines with the browser's own voice.
"""
from __future__ import annotations

import re

from eyetracking.domain.live import ReplyError, ReplyRefused, SpeechError  # noqa: F401 - re-exported for adapters

SAMPLE_SPEECH = "This is sample speech from the development provider."
_STOP = re.compile(r"\b(stop|bye|goodbye|end the|finish|quit)\b", re.I)
_DISTRESS = re.compile(r"\b(scared|afraid|upset|sad|anxious|nervous|uncomfortable|don'?t like this|need a break)\b", re.I)
_ELSEWHERE = re.compile(r"\b(something else|another thing|different topic|homework|weather)\b", re.I)
_FOLLOW_UPS = (
    "That sounds great! What do you like most about {topic}?",
    "Interesting! When did you first get into {topic}?",
    "Nice. Is there something about {topic} you would like to learn next?",
    "I like that. What would you tell a friend about {topic}?",
)


class FakeReplyGenerator:
    name = "fake-reply"

    def info(self) -> dict:
        return {"name": self.name, "model": "sample-rules", "configured": True, "synthetic": True}

    def estimate_cost(self) -> float:
        return 0.0

    def reply(self, system: str, conversation: str, topic: str) -> tuple[dict, dict]:
        lines = [l for l in conversation.splitlines() if l.startswith("Participant: ")]
        last = lines[-1][len("Participant: "):] if lines else ""
        follow = _FOLLOW_UPS[(len(lines) - 1) % len(_FOLLOW_UPS)].format(topic=topic)
        return (
            {
                "reply": follow,
                "participant_on_topic": not bool(_ELSEWHERE.search(last)),
                "participant_distress": bool(_DISTRESS.search(last)),
                "participant_wants_to_stop": bool(_STOP.search(last)),
            },
            {"cost_actual_units": 0.0, "model": "sample-rules"},
        )


class FakeSpeechToText:
    name = "fake-speech"

    def info(self) -> dict:
        return {"name": self.name, "configured": True, "synthetic": True}

    def transcribe(self, audio: bytes, content_type: str, language: str = "en") -> str:
        if not audio:
            raise SpeechError("no audio was received")
        return SAMPLE_SPEECH


class FakeAvatarProvider:
    name = "sample-video"

    def info(self) -> dict:
        return {"name": self.name, "configured": True, "synthetic": True, "streaming": False}

    def estimate_cost_per_minute(self) -> float:
        return 0.0

    def client_config(self, avatar_id: str, voice_id: str) -> dict:
        return {
            "mode": "sample_video",
            "video_url": "/static/live/sample-face.webm",
            "voice": "browser_tts",
            "captions": True,
            "synthetic": True,
            "note": "Development avatar: a looping sample face and the browser's own voice. Not a streaming avatar.",
        }
