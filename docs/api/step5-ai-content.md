# Step 5 API contract — AI content generation (text and video), review queue, cost cap

Base and auth as before; all endpoints need study membership (researcher for writes, admin for the budget). API keys never leave the server; the app only ever sees `configured: true/false`.

## Providers and budget
- `GET /studies/{id}/ai/status` → `{text_provider: {name, model, configured, synthetic}, video_provider: {name, configured, synthetic}, budget: {cost_cap_units, spent_units, remaining_units, unit: "usd_estimate"}, worker: {enabled, interval_s}, send_free_text: bool}`
  - `synthetic: true` means the fake provider (no key, no cost, sample content clearly marked as such).
- `PUT /studies/{id}/ai/budget` `{cost_cap_units: number}` (admin) → budget. Jobs whose estimate would exceed the cap are refused with 422 `budget_exceeded`. Default cap 0: nothing runs on a paid provider until an admin sets a cap.

## Jobs
Job: `{id, kind: text|video, status: queued|running|succeeded|failed|cancelled, provider, content_id, assignment_id|null, segment_id|null, attempts, max_attempts, cost_estimate_units, cost_actual_units, error|null, created_at, started_at|null, finished_at|null, request: {...}, result: {...}}`
- `POST /studies/{id}/ai/text-jobs` `{assignment_id?: int, topic?: string, display_name?: string, interests?: [string], interaction_points?: int (0-5, default 2), length_seconds?: int (30-600, default 90), title?: string, face_id?: string, voice_id?: string}` → job (201). With `assignment_id` the topic, display name and interests come from the assignment and profile; the participant's free text is sent only when the study setting `ai_send_free_text` is on. Creates a **draft content item** titled "AI draft: <topic>" that receives the generated segments (each segment gets `media_key = "<segment id>.webm"`).
- `POST /studies/{id}/ai/video-jobs` `{content_id, segment_ids?: [string], face_id?: string, voice_id?: string}` → `[job]` (201), one per segment that has no uploaded media. Requires `text_reviewed = true` on the content (409 otherwise).
- `GET /studies/{id}/ai/jobs?status=&content_id=` → `[job]` newest first; `GET /studies/{id}/ai/jobs/{jid}` → job.
- `POST /studies/{id}/ai/jobs/{jid}/cancel` (queued only) ; `POST /studies/{id}/ai/jobs/{jid}/retry` (failed only → queued).
- `POST /studies/{id}/ai/run?max_jobs=5` → `{processed, succeeded, failed}`: runs queued jobs now (the background worker does the same every `interval_s` when enabled).

## Review flow
- Content items gain `text_reviewed: bool`. `POST /studies/{id}/content/{cid}/text-reviewed` marks the generated (or edited) text as reviewed; editing the definition resets it to false. Video jobs need it; approval still needs every media key uploaded (generated videos land in the content's media like uploads).
- Generated text is always a draft; nothing reaches a participant without the researcher's review, approval and explicit attachment to the assignment.

## Errors
`{"detail": "budget_exceeded: ..."}`, `{"detail": "provider_not_configured: ..."}`, provider errors are stored on the job (`error`) and the job is retried up to `max_attempts` (3) with backoff by the worker; a refusal by the text model is a terminal failure with the category in `error`.

## Access log
`ai_job_created`, `ai_job_run` (with provider and cost), `ai_budget_changed`.
