# Step 4 — browser verification record (2026-09-29)

Same setup as steps 2 and 3 (headless Chromium, scratch SQLite, gaze service in `e2e-fake` mode). Seed: the step-3 seed plus a second participant and three completed gradual sessions created through the API with synthetic linear samples; those seeded sessions claim a non-synthetic estimator **only so the analysis tab shows rows in this scratch database**. Nothing here is a measurement. Screenshots: `docs/features/screenshots/step4-*.png`.

## Research Admin
- Sessions tab shows the Quality column ("No quality problem found. OK", "Real", 6 px, Passed, 89 %, eye share).
- **Replay** of a P-001 session: header with quality, estimator and protocol version; "No participant video exists" and "Display only; no smoothing" notes; the participant's screen with face box, eye region and mouth region; the gaze dot with a short trail; current segment and region ("Segment: baseline · Gaze: Mouth" at 00:02.649); timeline with Baseline / Practice / Post bands, gap and pause shading, the valid-share strip, Play and speed. Access log records `replay`.
- **Analysis** tab: filters (quality ok/review, synthetic off), "Show analysis" (each view is logged), the results table (participant, date, path, protocol version, device, estimator, quality, residual, validation, shares, delta…), "Comparable groups" with the pooling note, and per-participant trend cards with baseline-vs-post bars. Sessions CSV downloaded (HTTP 200, logged as `export_sessions_csv`). Data dictionary dialog lists every field with type and meaning.
- **Access log** tab: `export_sessions_csv`, `analysis`, `replay`, `erasure`, `self_export` rows with role and detail.
- Participant detail: "Delete this participant's research data" opens a dialog that names what is deleted and requires the research code; not executed in the run.

## Participant App
- "Download my data": counts (1 session, 240 gaze samples, 10 events) with the note that gaze numbers and events are the raw data and no camera video exists; "Download JSON" fetched `/me/data` (200).
- Profile → "Withdraw and delete my data": explanation of what is deleted, dialog "Delete your data and close your account?" with the typed phrase, `POST /me/erase` 200, farewell "Your data has been deleted and your account is closed. Thank you for taking part.", and the login afterwards is refused (401). The study policy was `delete_all`; the sessions of that participant disappeared from the admin lists.

## Caveats
- The scripted driver could not navigate back from the replay screen through the app bar in the Flutter web semantics tree; a person can. The rest of the admin run started from a fresh page load.
- The keep_coded farewell wording and the comfort marker's 1–5 assumption in the trend chart await the research team's review.
