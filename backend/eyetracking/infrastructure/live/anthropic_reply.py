"""Avatar replies through the Anthropic Messages API with a JSON-schema output format.

Short conversational turns at low effort keep latency down; the stable system prompt is cached.
The participant's words travel inside a delimited conversation block and are treated as content.
Refusals and API errors never reach the participant: the conversation uses a scripted line instead.
"""
from __future__ import annotations

import json

from eyetracking.domain.live import REPLY_SCHEMA

from eyetracking.domain.live import ReplyError, ReplyRefused

PRICES_PER_MTOK = {"claude-opus-5-5": (4.0, 20.0), "claude-sonnet-5-5": (2.0, 10.0), "claude-haiku-4-5": (1.0, 5.0)}


class AnthropicReplyGenerator:
    name = "anthropic"

    def __init__(self, api_key: str | None, model: str = "claude-opus-5-5", effort: str = "low", client=None, max_tokens: int = 16000):
        self._api_key = api_key
        self.model = model
        self.effort = effort
        self._client = client
        self._max_tokens = max_tokens

    def info(self) -> dict:
        return {"name": self.name, "model": self.model, "effort": self.effort, "configured": bool(self._api_key or self._client), "synthetic": False}

    def _prices(self) -> tuple[float, float]:
        return PRICES_PER_MTOK.get(self.model, (4.0, 20.0))

    def estimate_cost(self) -> float:
        # about 1k input tokens and 600 output tokens (thinking included) per turn at low effort
        pin, pout = self._prices()
        return round((1000 * pin + 600 * pout) / 1_000_000, 4)

    def _get_client(self):
        if self._client is None:
            if not self._api_key:
                raise ReplyError("provider_not_configured: Anthropic API key is missing")
            import anthropic

            self._client = anthropic.Anthropic(api_key=self._api_key)
        return self._client

    def reply(self, system: str, conversation: str, topic: str) -> tuple[dict, dict]:
        client = self._get_client()
        try:
            response = client.beta.messages.create(
                model=self.model,
                max_tokens=self._max_tokens,
                system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
                messages=[{"role": "user", "content": conversation}],
                output_config={"effort": self.effort, "format": {"type": "json_schema", "schema": REPLY_SCHEMA}},
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
            )
        except Exception as exc:  # noqa: BLE001 - any API failure becomes a scripted line
            raise ReplyError(f"{type(exc).__name__}: {getattr(exc, 'message', exc)}") from exc
        if response.stop_reason == "refusal":
            details = getattr(response, "stop_details", None)
            raise ReplyRefused(f"refusal: {getattr(details, 'category', None) or 'unspecified'}")
        if response.stop_reason == "max_tokens":
            raise ReplyError("the model hit max_tokens")
        text = next((b.text for b in response.content if getattr(b, "type", "") == "text"), None)
        if not text:
            raise ReplyError("the model returned no text block")
        try:
            data = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ReplyError("the reply was not valid JSON") from exc
        usage = getattr(response, "usage", None)
        pin, pout = self._prices()
        cost = 0.0
        if usage is not None:
            cached = getattr(usage, "cache_read_input_tokens", 0) or 0
            cost = round(((getattr(usage, "input_tokens", 0) or 0) * pin + cached * pin * 0.1 + (getattr(usage, "output_tokens", 0) or 0) * pout) / 1_000_000, 5)
        return data, {"cost_actual_units": cost, "model": getattr(response, "model", self.model)}
