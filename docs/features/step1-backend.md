# Step 1 — backend snapshot

Scope from the design (p. 6, step 1): English UI, sign-in, profile, three-part information sheet and consent, demographics form, roles and invitations, plus the test that no user can reach another person's or another study's data.

## What exists
- `backend/eyetracking/domain`: entities and rules (sheet validation, consent activity, demographics validation, readiness).
- `backend/eyetracking/application`: ports, authorization policy (`authz.py`), use cases.
- `backend/eyetracking/infrastructure`: SQLAlchemy imperative mapping, repositories, unit of work, argon2 hashing, JWT tokens.
- `backend/eyetracking/web`: settings, schemas, dependencies, routers `auth`, `participant` (`/me/*`), `studies`, composition in `app.py`.
- 21 HTTP paths; OpenAPI at `/docs`.

## Verified
- `python -m pytest -q`: 14 passed (access control, invitations, sheet sections, consent/readiness, demographics validation, profile, own-data export).
- Live server smoke test: health, admin bootstrap login, study creation.

## Remaining in step 1
- Flutter screens (see step1-flutter.md) and an end-to-end run of both apps against this backend.
- Email delivery of invitation links (today the researcher copies the token).
- Password reset and researcher two-factor sign-in (listed in the review, not in the design yet).
- PostgreSQL migration tooling (Alembic) before any shared deployment.
