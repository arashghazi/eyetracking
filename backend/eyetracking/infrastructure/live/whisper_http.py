"""Speech to text through a Whisper-compatible HTTP server (POST /v1/audio/transcriptions).

Meant for a speech server running on the same computer or inside the research network, so audio
does not leave it. The audio is sent once, in memory, and never written anywhere by this app.
"""
from __future__ import annotations

import httpx

from eyetracking.domain.live import SpeechError

_EXT = {"audio/webm": "webm", "audio/ogg": "ogg", "audio/wav": "wav", "audio/x-wav": "wav", "audio/mp4": "m4a", "audio/mpeg": "mp3"}


class WhisperHttpSpeechToText:
    name = "whisper-http"

    def __init__(self, base_url: str | None, model: str = "whisper-1", api_key: str | None = None, client: httpx.Client | None = None, timeout_s: float = 60.0):
        self.base_url = (base_url or "").rstrip("/")
        self.model = model
        self._api_key = api_key
        self._client = client
        self._timeout = timeout_s

    def info(self) -> dict:
        return {"name": self.name, "model": self.model, "configured": bool(self.base_url), "synthetic": False, "base_url": self.base_url or None}

    def transcribe(self, audio: bytes, content_type: str, language: str = "en") -> str:
        if not self.base_url:
            raise SpeechError("provider_not_configured: no speech server address is set")
        if not audio:
            raise SpeechError("no audio was received")
        client = self._client or httpx.Client(timeout=self._timeout)
        headers = {"Authorization": f"Bearer {self._api_key}"} if self._api_key else {}
        ext = _EXT.get(content_type.split(";")[0].strip(), "webm")
        try:
            r = client.post(
                f"{self.base_url}/v1/audio/transcriptions",
                files={"file": (f"utterance.{ext}", audio, content_type)},
                data={"model": self.model, "language": language, "response_format": "json"},
                headers=headers,
            )
        except httpx.HTTPError as exc:
            raise SpeechError(f"speech server unreachable: {type(exc).__name__}") from exc
        finally:
            if self._client is None:
                client.close()
        if r.status_code >= 400:
            raise SpeechError(f"speech server answered {r.status_code}")
        try:
            text = r.json().get("text", "")
        except ValueError as exc:
            raise SpeechError("speech server sent no JSON") from exc
        return str(text or "").strip()
