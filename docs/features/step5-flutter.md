# Step 5 — Flutter snapshot (AI content generation)

Contract: docs/api/step5-ai-content.md. Layering as before (domain -> application -> data -> presentation), same theme, plain Flutter state, no new packages. Participant app unchanged.

## What exists
- `packages/core`: `models/ai.dart` (`AiStatus` with provider, budget and worker, `AiJob`, `AiJobStatus`, `TextJobRequest`, `VideoJobRequest`, `AiRunResult`; ids are sent as numbers), `ContentSummary.textReviewed`, `formatUnits` (2 to 4 decimals).
- Admin `features/ai/`: `AiRepository` port and `ApiAiRepository`; `AiController` (status, jobs, cap, cancel, retry, run; one-shot 5 s refresh timer while a job is queued or running, injected so tests fire it by hand), `TextJobFormController`, `VideoJobsController`; presentation `AiTab`, `AiStatusCard`, `TextJobCard`, `JobsTable`, shared `StateChip` / `JobStatusChip` / `SyntheticBadge`.
- AI tab on the study screen right after Content: status card (provider name and model, Configured or Not configured, "Development provider — sample content" badge, worker, cap / spent / remaining, keys-live-on-the-server note, "Edit cap" for admins only, server 422 shown as written); "Generate conversation text" (For an assignment: participant code lists only `content_pending` and `pending_topic`; Free form: topic, display name, interest chips; points 0-5, length 30-600 s, title, face and voice ids); jobs table with status chips, Cancel (queued), Retry (failed), Open content, error tooltip and expander; Refresh and Run queued jobs now.
- Content: "Text reviewed" column in the list; the editor shows "Text reviewed: yes/no", "Mark text reviewed" (saves pending edits first; disabled when approved) and a "Generate videos" section (face and voice ids, segment checkboxes for segments without media, created jobs, link to the AI tab, disabled with the reason until the text is reviewed and saved).

## Choices
- An administrator who is not a study member cannot read the status (403); the card says so and still offers "Edit cap" (PUT budget only needs the admin role).
- The free-text setting is only explained (assignment mode note); the app never sends a participant's free text itself.
- The jobs table scrolls sideways when the window is narrower than its columns (Created, Error and Actions are compact); analysts see it read-only.

## Run (backend :8000)
- `cd apps/admin && flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://localhost:8000`; fake providers need no keys.
- Tests: `flutter analyze` and `flutter test` in `packages/core`, `apps/participant`, `apps/admin`; `flutter build web --no-web-resources-cdn` in apps/admin (delete `build/`).

## Results (2026-09-30)
- `flutter analyze` clean in all three. `flutter test`: core 120, participant 258, admin 320, all passing (`ai_test`, `content_review_test`, `api_step5_test`: status card, form, jobs table, fake-ticker auto-refresh, review and video jobs, 360 / 800 / 1440 px). Admin web build compiles.
- Live check ran (backend :8765, scratch SQLite, fake providers, real repositories and controllers through a temporary driver, not kept): status, assignment and free-form text jobs, 422 texts as written (empty topic, cap out of range), researcher 403 on the cap, admin cap, run queued (processed 2), 409 before review, mark reviewed, video jobs per segment, media filled, cancel, retry refused for a cancelled job.

## Missing
- Seen in a headless browser with the fake providers (docs/features/step5-e2e.md): text job, run, draft, review, video jobs, media filled. A failed job (Retry success) and a paid provider (budget_exceeded, provider_not_configured from a real server) were tested with fakes only.
- The budget PUT also takes `send_free_text`; the app has no switch for it yet.
