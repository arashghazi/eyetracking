# Current state (keep under 5 KB)

Updated: 2026-09-30 · design authority: docs/design/EyeTracking-Product-Design-FA-v1.1.pdf

## Build step 1 — base of the two apps (done)
Accounts and roles, studies and memberships with a separate identity-link grant, single-use invitations with research codes, versioned information sheet, consent bound to the sheet version, demographics under the code, profile, own-data export; Flutter sign-in, invitation, readiness home, consent, profile, demographics; admin participants, invitations, sheet, form, members.

## Build step 2 — session and measurement (built; verified in a headless browser with a fake camera)
- Backend: sessions with readiness gate, camera check, calibration fit and re-calibration, regional validation with reasons, layouts and sample recording (only while running and calibrated), events (pause/resume/end; camera/orientation/zoom changes invalidate calibration), coverage where missing ≠ not looking, eye-region attention only with a passed validation on a non-synthetic estimator. Per-study measurement settings.
- Gaze service: swappable estimator (synthetic proxy, L2CS-Net adapter, Haar detector); standalone on :8100 or under `/gaze/*`.
- Flutter: participant session flow (camera preview, camera check, 9-dot calibration, regional validation, baseline with pause/resume/end, honest summary); admin Sessions tab, session detail, Measurement settings. Browser capture in `packages/core`; Android capture is a stub.
- Browser run in docs/features/step2-e2e.md. No accuracy claims: every number so far comes from synthetic data or a fake face.
- Pending for step 2 sign-off: a real webcam with the published L2CS weights (`run-local.cmd -Model l2cs -Weights ...`) and the real validation result shown to the reviewer; Android capture.

## Build step 3 — the two practice paths (built; both paths verified in a headless browser)
- Protocols with immutable published versions (path, baseline/post seconds, comfort scale, progression rules, gradual stages with face level and number zone, `final_zone_limit` default near_eyes); content library with segments, branches, comprehension questions, media upload and approval; assignments with topic confirmation and content attachment; trials, server-side stage decisions that never advance on wrong answers, discomfort or invalid data; interaction and comprehension answers; three outcomes and the all-three improvement rule in every session summary.
- Flutter: assignments and topic confirmation, gradual practice (face levels, number zones, three response modes, comfort per stage, server decisions), interest conversation (signed video segments, branches, comprehension, post clip), three-outcome summary; admin Protocols, Content, Assignments, session outcomes.
- Browser runs of both paths in docs/features/step3-e2e.md. Notes: docs/features/step3-*.md, docs/api/step3-practice.md.

## Build step 4 — research and data (built; verified in a headless browser)
- Quality grades with study thresholds; replay bundle (stimulus geometry + gaze estimate, gaps, pauses, quality strip, signed media); analysis with filters and comparability groups that are never pooled; coded CSV/JSON exports with demographics and versions; data dictionary; access log; participant raw data; withdrawal under the retention policy; researcher deletion.
- Flutter: admin Replay (geometry + gaze dot, timeline, gaps, pauses, quality strip), Analysis (filters, table, groups, trend charts, exports, dictionary), Access log, participant data deletion, retention policy; participant data download and withdraw-and-erase.
- Browser run in docs/features/step4-e2e.md. Notes: docs/features/step4-*.md, docs/api/step4-research-data.md.

## Build step 5 — AI content generation (built; verified in a headless browser with fake providers)
- Backend: swappable text and video providers (fake without key; Anthropic text with JSON-schema output; HeyGen video), job queue with retries and backoff, per-study cost cap, review flow (draft → text reviewed → videos → approve → attach), worker thread, access log. No live provider call yet.
- Flutter: admin AI tab (providers, budget, cap for admins, text job for an assignment or free form, jobs table with cancel/retry/run), content list and editor with "Mark text reviewed" and per-segment "Generate videos".
- Tests: 46 backend; Flutter core 120, participant 258, admin 320. Browser run in docs/features/step5-e2e.md. Notes: docs/features/step5-*.md, docs/api/step5-ai-content.md.

## Local run
Windows one-command run: scripts/run-local.cmd (data, accounts and logs outside the repo). Guide: docs/run-local.fa.md.

## Not started (design steps 6–7)
Supervised pilot; live avatar.

## Open decisions (design p. 7)
Age range and inclusion criteria; final number position and comfort rule; filmed actor vs realistic avatar; validation pass thresholds (placeholders 80 % / 20 %); research-grade tracker access.
