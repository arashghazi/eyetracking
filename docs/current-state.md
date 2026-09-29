# Current state (keep under 5 KB)

Updated: 2026-09-29 · design authority: docs/design/EyeTracking-Product-Design-FA-v1.1.pdf

## Build step 1 — base of the two apps (built, not yet run end-to-end)

**Backend (Python 3.11 / FastAPI, SQLAlchemy, SQLite dev / PostgreSQL-ready)** — done, 14 tests green.
- Accounts with roles participant / researcher / analyst / admin; admin bootstrap from environment.
- Studies, memberships with a separate `can_link_identity` grant; invitations that pre-assign research codes (P-001…), single use, optional email binding, expiry.
- Information sheet with the five sections (aims, discomfort sources, benefits, data handling, stop rules); publishing fails if any is empty; versioned.
- Consent bound to the sheet version, withdrawable; participant readiness = active consent for the current sheet + complete demographics.
- Configurable demographics form per study; answers validated and stored under the research code.
- Profile: display name, response mode (keyboard / touch / four choices / symbol), voice, face, speed, accessibility needs, interests.
- "My data" export for the participant; coded views for researchers/analysts never contain email or user ids.
- Run: `cd backend && uvicorn eyetracking.web.main:app --reload` · tests: `python -m pytest -q`.

**Flutter apps (3.47, only dependency `http`)** — done for step 1: `packages/core` (theme, API client, models), `apps/participant` (sign-in, invitation, readiness home, sheet + consent, profile, demographics, my data), `apps/admin` (studies, participants, invitations, sheet, demographics form, members). `flutter analyze` clean; tests core 24 / participant 34 / admin 25. Not yet: browser click-through, Android build, persisted token. See docs/features/step1-flutter.md.

## Build step 2 — session and measurement (built; verified in a headless browser with a fake camera)
- Backend: sessions with readiness gate, camera check, calibration fit and re-calibration, regional validation with reasons, layouts and sample recording (only while running and calibrated), events (pause/resume/end; camera/orientation/zoom changes invalidate calibration), coverage where missing ≠ not looking, eye-region attention only with a passed validation on a non-synthetic estimator. Per-study measurement settings.
- Gaze service: swappable estimator; synthetic head-proxy for development, L2CS-Net adapter (weights not in repo), Haar face detector; standalone on :8100 or authenticated under `/gaze/*`.
- Flutter: participant session flow (intro, camera preview via getUserMedia, camera check, 9-dot calibration, regional validation on a placeholder face with a per-dot table, 30 s baseline with pause/resume/end, summary that says "Not evaluable" and flags the development estimator); admin Sessions tab, session detail and Measurement settings. Browser capture lives in `packages/core` (`WebFrameSource`, `package:web`), Android capture is a stub.
- Tests: 29 backend (pytest); Flutter core 45, participant 91, admin 49; end-to-end run in headless Chromium recorded in docs/features/step2-e2e.md with screenshots. No accuracy claims: every number so far comes from synthetic data or a fake face.
- Pending for step 2 sign-off: run on a PC with a real webcam and the published L2CS weights (`EYETRACKING_GAZE_MODEL=l2cs`, `EYETRACKING_GAZE_WEIGHTS=...`) and show the real validation result to the reviewer; Android capture.

## Build step 3 — the two practice paths (backend done; Flutter in progress)
- Protocols with immutable published versions (path, baseline/post seconds, comfort scale, progression rules, gradual stages with face level and number zone, `final_zone_limit` default near_eyes); content library with segments, branches, comprehension questions, media upload and approval; assignments with topic confirmation and content attachment; trials, server-side stage decisions that never advance on wrong answers, discomfort or invalid data; interaction and comprehension answers; three outcomes and the all-three improvement rule in every session summary.
- Tests: 35 backend. See docs/features/step3-backend.md and docs/api/step3-practice.md.

## Not started (design steps 4–7)
Sessions replay and analysis; AI content pipeline; pilot; live avatar.

## Open decisions (design p. 7)
Age range and inclusion criteria; final number position and comfort rule; filmed actor vs realistic avatar; validation pass thresholds (placeholders 80 % / 20 %); research-grade tracker access.
