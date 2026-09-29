# Step 5 — backend snapshot (AI content generation)

Scope from the design (p. 6, step 5): text and video generation with branch reactions, review, a work queue, a cost cap and error handling; the provider choice and key are the product owner's decisions, so everything works with a fake provider first.

## What exists
- `domain/ai.py`: budget with a hard cap (`assert_affordable`), generation jobs with attempts, backoff and terminal failures, the minimized text request (topic, display name, interests, interaction points, length; free text only when the study allows it), the JSON schema the text model must return, the prompt for a calm, respectful script, and a deterministic sample script for the fake provider (visibly marked as a sample).
- Ports `TextGenerator` and `VideoGenerator`; adapters in `infrastructure/ai/`: `FakeTextGenerator` / `FakeVideoGenerator` (bundled 17 KB sample clip; no key, no cost), `AnthropicTextGenerator` (official SDK, `claude-opus-5-5`, JSON-schema output, server-side refusal fallback enabled, refusals are terminal, cost from token usage), `HeyGenVideoGenerator` (create → poll → download over HTTP; written against the public API shape and exercised only with a mock transport here).
- `application/ai_use_cases.py`: status, budget (admin), text jobs that create a draft content item, video jobs per segment that require `text_reviewed`, list/get/cancel/retry, `run_jobs` (used by the API and by the background worker) with retries up to 3, backoff 30 s · 2^n, budget accounting from actual cost, access-log rows `ai_job_created`, `ai_job_run`, `ai_budget_changed`.
- `infrastructure/ai/worker.py`: one daemon thread with its own unit of work per pass; enabled by `EYETRACKING_AI_WORKER_ENABLED`.
- `web/routers/ai.py`: the endpoints in docs/api/step5-ai-content.md. Content items carry `text_reviewed`; editing the definition resets it.
- Review flow: generated text is always a draft → researcher reviews/edits → marks text reviewed → videos → approve (needs every clip) → attach to the assignment. Nothing generated reaches a participant without those steps.

## Verified
- `python -m pytest -q`: 46 passed (41 earlier + 5 AI: fake end-to-end flow through participant content, budget cap and retries and terminal failures, worker, Anthropic adapter with a stub client, HeyGen adapter with a mock transport).
- The live Anthropic and HeyGen services were **not** called; that needs your keys and cap.

## Configuration (server only)
`EYETRACKING_AI_TEXT_PROVIDER=anthropic` + `EYETRACKING_ANTHROPIC_API_KEY`, `EYETRACKING_AI_VIDEO_PROVIDER=heygen` + `EYETRACKING_HEYGEN_API_KEY`, `EYETRACKING_HEYGEN_COST_PER_MINUTE_UNITS`, `EYETRACKING_AI_WORKER_ENABLED`; install the SDK with `pip install -e ".[ai]"`. The study's cap is set by an admin through the API or the AI tab; with cap 0 no paid job is accepted.

## Remaining
- First live run against Anthropic and HeyGen with real keys; HeyGen avatar and voice ids must come from the provider's catalogue.
- Branch reactions are generated as ordinary segments; a per-option reaction clip field exists in the content format but the generator does not fill it yet.
- Cost units are USD estimates from list prices; reconcile with the providers' invoices.
