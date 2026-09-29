"""Development providers: no key, no cost, sample content that says it is a sample."""
from __future__ import annotations

import os

from eyetracking.domain.ai import TextRequest, sample_script

ASSET_DIR = os.path.join(os.path.dirname(__file__), "assets")


class FakeTextGenerator:
    name = "fake-text"

    def info(self) -> dict:
        return {"name": self.name, "model": "sample-script", "configured": True, "synthetic": True}

    def estimate_cost(self, req: TextRequest) -> float:
        return 0.0

    def generate(self, req: TextRequest) -> tuple[dict, dict]:
        return sample_script(req), {"cost_actual_units": 0.0, "model": "sample-script"}


class FakeVideoGenerator:
    name = "fake-video"

    def __init__(self, clip_path: str | None = None):
        self._clip = clip_path or os.path.join(ASSET_DIR, "sample-face.webm")

    def info(self) -> dict:
        return {"name": self.name, "configured": os.path.exists(self._clip), "synthetic": True}

    def estimate_cost(self, text: str, duration_s: float) -> float:
        return 0.0

    def generate(self, text: str, face_id: str, voice_id: str) -> tuple[bytes, str, dict]:
        with open(self._clip, "rb") as fh:
            data = fh.read()
        return data, "video/webm", {"cost_actual_units": 0.0, "duration_s": 4.0, "note": "sample clip; the text is not spoken"}


class FailingTextGenerator:
    """Test double: fails a configurable number of times, optionally as a terminal refusal."""

    name = "failing-text"

    def __init__(self, failures: int = 99, cost: float = 1.0, terminal: bool = False):
        self.failures = failures
        self.cost = cost
        self.terminal = terminal
        self.calls = 0

    def info(self) -> dict:
        return {"name": self.name, "model": "none", "configured": True, "synthetic": True}

    def estimate_cost(self, req: TextRequest) -> float:
        return self.cost

    def generate(self, req: TextRequest) -> tuple[dict, dict]:
        self.calls += 1
        if self.calls <= self.failures:
            raise (TerminalGenerationError("refusal: general_harms") if self.terminal else RuntimeError("provider unavailable"))
        return sample_script(req), {"cost_actual_units": self.cost, "model": "none"}


class TerminalGenerationError(Exception):
    """Raised by adapters when a retry cannot help (refusal, invalid request)."""
