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

## Not started (design steps 2–7)
Camera, calibration and regional validation; the two practice paths; sessions panel and replay; AI content pipeline; pilot; live avatar.

## Open decisions (design p. 7)
Age range and inclusion criteria; final number position and comfort rule; filmed actor vs realistic avatar; validation pass thresholds (placeholders 80 % / 20 %); research-grade tracker access.
