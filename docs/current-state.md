# Current state (keep under 5 KB)

Updated: 2026-09-30 · design authority: docs/design/EyeTracking-Product-Design-FA-v1.1.pdf

## Build steps 1–5 (built; each verified in a headless browser; notes in docs/features/stepN-*.md)
1. Accounts, roles, studies, identity-link grant, invitations with research codes, versioned information sheet and consent, demographics, profile, own-data export.
2. Sessions with readiness gate, camera check, calibration, regional validation with reasons, samples and events (missing ≠ not looking), eye-region results only with a passed validation on a non-synthetic estimator; gaze service (synthetic, L2CS adapter, Haar). Pending sign-off: real webcam with the published L2CS weights (`run-local.cmd -Model l2cs -Weights ...`), result shown to the reviewer; Android capture.
3. Protocols with immutable versions, content library and media, assignments, both practice paths, server-side stage decisions, three outcomes and the all-three improvement rule.
4. Quality grades, replay, analysis with comparability groups, coded CSV/JSON exports, data dictionary, access log, raw data, withdrawal and deletion.
5. AI text and video providers (fake, Anthropic, HeyGen), job queue, cost cap, mandatory review. No live provider call yet.

## Build step 6 — supervised pilot support (built; verified in a headless browser)
- Backend: versioned thresholds with rationale, what-if threshold review, live monitor, supervisor observations, versioned optional debrief, research-tracker CSV import and agreement metrics with caveats, pilot report JSON/CSV; all logged; deletion covers them.
- Flutter: admin Pilot tab (Live, Thresholds, Tracker comparison, Report, Questions), settings version and history, observations in session detail, AI free-text switch; participant questions card after a session.
- Tests: 54 backend; Flutter core 146, participant 312, admin 427. Browser run in docs/features/step6-e2e.md. Runbook: docs/pilot/pilot-runbook.md. The pilot itself (people, real webcam, L2CS weights, lab tracker) has not happened.

## Local run
Windows one-command run: scripts/run-local.cmd (data, accounts and logs outside the repo). Guide: docs/run-local.fa.md.

## Not started
The pilot with participants (research team); live avatar (design step 7).

## Open decisions (design p. 7)
Age range and inclusion criteria; final number position and comfort rule; filmed actor vs realistic avatar; validation pass thresholds (placeholders 80 % / 20 %); research-grade tracker access; whether supervisor observations belong in the participant's own data download.
