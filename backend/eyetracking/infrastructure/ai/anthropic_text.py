"""Text generation through the Anthropic Messages API with a JSON-schema output format.

The `anthropic` package is optional (`pip install -e ".[ai]"`). The client is injectable so tests run
without a key. Refusals are terminal; rate limits and server errors are retried by the job worker.
"""
from __future__ import annotations

import json

from eyetracking.domain.ai import CONTENT_SCHEMA, TextRequest, script_prompt

from .fake import TerminalGenerationError

PRICES_PER_MTOK = {"claude-opus-5-5": (4.0, 20.0), "claude-sonnet-5-5": (2.0, 10.0), "claude-haiku-4-5": (1.0, 5.0)}


class AnthropicTextGenerator:
    name = "anthropic"

    def __init__(self, api_key: str | None, model: str = "claude-opus-5-5", client=None, max_tokens: int = 16000):
        self._api_key = api_key
        self.model = model
        self._client = client
        self._max_tokens = max_tokens

    def info(self) -> dict:
        return {"name": self.name, "model": self.model, "configured": bool(self._api_key or self._client), "synthetic": False}

    def _prices(self) -> tuple[float, float]:
        return PRICES_PER_MTOK.get(self.model, (4.0, 20.0))

    def estimate_cost(self, req: TextRequest) -> float:
        # roughly 1.5k input tokens and 3k output tokens for a short script with thinking
        pin, pout = self._prices()
        return round((1500 * pin + 3000 * pout) / 1_000_000, 4)

    def _get_client(self):
        if self._client is None:
            if not self._api_key:
                raise TerminalGenerationError("provider_not_configured: Anthropic API key is missing")
            import anthropic

            self._client = anthropic.Anthropic(api_key=self._api_key)
        return self._client

    def generate(self, req: TextRequest) -> tuple[dict, dict]:
        client = self._get_client()
        system, user = script_prompt(req)
        try:
            import anthropic as _anthropic
        except ImportError:  # the injected client path in tests
            _anthropic = None
        try:
            response = client.beta.messages.create(
                model=self.model,
                max_tokens=self._max_tokens,
                system=system,
                messages=[{"role": "user", "content": user}],
                output_config={"format": {"type": "json_schema", "schema": CONTENT_SCHEMA}},
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
            )
        except Exception as exc:  # noqa: BLE001 - classified below
            if _anthropic is not None:
                if isinstance(exc, (_anthropic.BadRequestError, _anthropic.AuthenticationError, _anthropic.PermissionDeniedError, _anthropic.NotFoundError)):
                    raise TerminalGenerationError(f"{type(exc).__name__}: {getattr(exc, 'message', exc)}") from exc
            raise
        if response.stop_reason == "refusal":
            details = getattr(response, "stop_details", None)
            category = getattr(details, "category", None) if details else None
            raise TerminalGenerationError(f"refusal: {category or 'unspecified'}")
        if response.stop_reason == "max_tokens":
            raise RuntimeError("the model hit max_tokens before finishing the script")
        text = next((b.text for b in response.content if getattr(b, "type", "") == "text"), None)
        if not text:
            raise RuntimeError("the model returned no text block")
        data = json.loads(text)
        usage = getattr(response, "usage", None)
        pin, pout = self._prices()
        cost = 0.0
        if usage is not None:
            cost = round((getattr(usage, "input_tokens", 0) * pin + getattr(usage, "output_tokens", 0) * pout) / 1_000_000, 4)
        return data, {"cost_actual_units": cost, "model": getattr(response, "model", self.model), "input_tokens": getattr(usage, "input_tokens", None), "output_tokens": getattr(usage, "output_tokens", None)}
