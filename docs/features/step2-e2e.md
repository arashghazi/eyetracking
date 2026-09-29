# Step 2 — browser verification record (2026-09-29)

**What ran:** the built Participant App and Research Admin (Flutter web, `--no-web-resources-cdn`) in headless Chromium 154 via Playwright, against the real backend (scratch SQLite) and the gaze service in `EYETRACKING_GAZE_MODEL=e2e-fake` mode. Chromium's fake camera device supplied the video; the fake estimator reports one face at a fixed box, so **none of the numbers below are measurements**. Screenshots are in `docs/features/screenshots/step2-*.png`.

## Participant App (port 8080)
1. Sign in as the seeded participant; home shows "You are ready to start" and the research code.
2. Start a session → intro → camera preview through `getUserMedia` (device `fake_device_0`) → "Check camera": face found in 5 of 5 frames → session `camera_ok`.
3. Calibration: 9 dots, 432 frames sent to `/estimate` in total during the session; calibration accepted with a 517 px median error (expected: the fake face never moves).
4. Validation on the placeholder face: **not passed**, 43 % on target, 0 % uncertain, size ratio 0.5; reasons `correct_ratio_below_0.8`, `eye_region_smaller_than_2.0x_error`; per-dot table shown; "Continue without eye-level scoring" chosen (study default allows it).
5. Baseline: 30 s prompt-free face, pause and resume once, 31 sample batches, `segment_end`, `end` with reason `completed`.
6. Summary: total 32.0 s, usable 30.2 s (94 %), missing 1.8 s counted as missing rather than looking away; face region 100 %; eye region **Not evaluable** (`synthetic_estimator`); banner "Development estimator — no measurement claims".
7. Home afterwards lists the session as Completed with the Development badge.

API calls seen from the browser: login, participant, sessions, measurement-settings, gaze info, session create, camera-check, calibration, validation, layout, 5 events, 31 sample batches, session summary. No HTTP errors, no page errors.

## Research Admin (port 5173)
- Sign in as the study researcher → study → **Sessions** tab: row `P-001 · Ended · Synthetic · 517 px · Failed · 94 % · Not evaluable` (plus the earlier camera-checked attempt).
- Session detail: face-region attention 100 %, eye-region not evaluable with reason, device/screen/camera/gaze-model block, calibration numbers, regional validation with the per-target table, events. The "load samples" control was not exercised by the script.
- Measurement settings tab renders for the researcher.

## Caveats found while running
- Headless Chromium without `navigator.languages` made Flutter throw "Incorrect locale information provided"; real browsers always provide a locale. Playwright runs need `locale: 'en-US'`.
- CanvasKit is fetched from Google's CDN by default; on a network that blocks it the app stays blank. Build with `--no-web-resources-cdn` for such sites.
- The fake camera has no face, so the Haar path and the L2CS weights are still untested with a real person. That is the PC test on a real webcam, next.
