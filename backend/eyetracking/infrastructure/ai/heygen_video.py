"""Speaking-face video through HeyGen's video generation API (create → poll → download).

Written against the public v2 API shape; not exercised against the live service in this repository.
The transport is injectable so tests use httpx.MockTransport. The key stays on the server.
"""
from __future__ import annotations

import time

import httpx

from .fake import TerminalGenerationError


class HeyGenVideoGenerator:
    name = "heygen"

    def __init__(self, api_key: str | None, base_url: str = "https://api.heygen.com", cost_per_minute_units: float = 1.0, transport=None, poll_interval_s: float = 5.0, timeout_s: float = 900.0, sleep=time.sleep):
        self._api_key = api_key
        self._base = base_url.rstrip("/")
        self._cost_per_minute = cost_per_minute_units
        self._transport = transport
        self._poll = poll_interval_s
        self._timeout = timeout_s
        self._sleep = sleep

    def info(self) -> dict:
        return {"name": self.name, "configured": bool(self._api_key), "synthetic": False}

    def estimate_cost(self, text: str, duration_s: float) -> float:
        words = max(1, len(text.split()))
        seconds = max(float(duration_s or 0), words / 2.5)
        return round(self._cost_per_minute * seconds / 60.0, 4)

    def _client(self) -> httpx.Client:
        if not self._api_key:
            raise TerminalGenerationError("provider_not_configured: HeyGen API key is missing")
        return httpx.Client(base_url=self._base, headers={"X-Api-Key": self._api_key, "Accept": "application/json"}, timeout=60.0, transport=self._transport)

    def generate(self, text: str, face_id: str, voice_id: str) -> tuple[bytes, str, dict]:
        if not face_id or not voice_id:
            raise TerminalGenerationError("face_id and voice_id are required for video generation")
        with self._client() as c:
            body = {
                "video_inputs": [{"character": {"type": "avatar", "avatar_id": face_id, "avatar_style": "normal"}, "voice": {"type": "text", "input_text": text, "voice_id": voice_id}}],
                "dimension": {"width": 1280, "height": 720},
            }
            r = c.post("/v2/video/generate", json=body)
            if r.status_code in (400, 401, 403, 404):
                raise TerminalGenerationError(f"heygen {r.status_code}: {r.text[:300]}")
            r.raise_for_status()
            video_id = (r.json().get("data") or {}).get("video_id")
            if not video_id:
                raise RuntimeError(f"heygen returned no video_id: {r.text[:300]}")
            deadline = time.monotonic() + self._timeout
            while True:
                s = c.get("/v1/video_status.get", params={"video_id": video_id})
                s.raise_for_status()
                data = s.json().get("data") or {}
                status = data.get("status")
                if status == "completed":
                    url = data.get("video_url")
                    if not url:
                        raise RuntimeError("heygen completed without a video_url")
                    d = c.get(url, follow_redirects=True)
                    d.raise_for_status()
                    ctype = d.headers.get("content-type", "video/mp4").split(";")[0]
                    duration = float(data.get("duration") or 0)
                    return d.content, ctype, {"cost_actual_units": round(self._cost_per_minute * duration / 60.0, 4) if duration else self.estimate_cost(text, 0), "duration_s": duration, "video_id": video_id}
                if status == "failed":
                    raise TerminalGenerationError(f"heygen failed: {data.get('error') or 'unknown error'}")
                if time.monotonic() > deadline:
                    raise RuntimeError("heygen video generation timed out")
                self._sleep(self._poll)
