# Step 2 — Flutter snapshot (session and measurement)

Contract: docs/api/step2-measurement.md. Same layering as step 1 (domain -> application -> data -> presentation), same theme.

## What exists
- `packages/core`: wire models (settings, raw sample, layout, session summary, calibration, validation, list item, detail, samples page), `GazeServiceClient` (`info`, `estimate`; local `GAZE_BASE_URL`, default :8100, or `/gaze/*` on the research server with `GAZE_MODE=server`), `FrameSource` port with `WebFrameSource` (package:web, conditional import; the stub throws `UnsupportedError`), camera/orientation/zoom events. Test doubles: `package:eyetracking_core/testing.dart`. New dependency: `web`.
- Participant `features/session`: `SessionFlowController` (intro, camera check, calibration, validation, baseline, summary), face-card geometry (`stimulus_geometry.dart`), step list, Pause/End from calibration, home "Start a session" card (ready only) and "My sessions".
- Admin: Sessions tab (table), Session detail (four cards, device, calibration, validation table, segments, events, samples pager), Measurement settings tab (validated form; analysts read-only).
- Camera choice (2026-10-03): with more than one camera the Camera check step shows a picker (`FrameSource.cameras` / `selectCamera`); switching reopens the camera and the face check must pass again; the device id is kept in localStorage (`eyetracking.camera_device_id`) so the next session opens the same camera, falling back to the browser default only when it is no longer connected. The camera check sends `camera_label`, and the server keeps the checked camera in the session record (a different camera after calibration invalidates it).
- Choices: the 3-2-1 countdown runs once before the first dot of calibration and of validation; pausing before the baseline is local (no server event); the camera closes on pause and at the end; `lighting_ok` equals `face_detected`; the detail screen accepts `validation_targets` next to `validation`.

## Run (research server :8000, gaze service :8100)
- Gaze: `cd backend && uvicorn eyetracking.gaze.main:app --port 8100`
- Participant: `cd apps/participant && flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=GAZE_BASE_URL=http://localhost:8100`
- Admin: `cd apps/admin && flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://localhost:8000`
- Tests: `flutter analyze` and `flutter test` in `packages/core`, `apps/participant`, `apps/admin`.

## Results (2026-09-29)
- `flutter analyze`: clean in all three.
- `flutter test`: core 45, participant 91, admin 49, all passing (flow controller with fakes, screens, 360/800/1440 px, admin tables and settings validation).
- `flutter build web` compiles for both apps (build output deleted).
- Live check ran once against a scratch backend (:8765, SQLite) and the synthetic gaze service (:8100), with the real repositories and a fake camera: 403 readiness reasons, camera check, calibration, validation, baseline with pause/resume/face_lost/face_found, summary, researcher list/detail/samples, analyst 403 on settings PUT, gaze client local and `/gaze/*`. Driver not kept.

## Missing
- No real browser run: `WebFrameSource` (getUserMedia, canvas JPEG, device/resize events, preview) compiles but was never run against a camera; no screenshots of the running apps.
- The gaze estimate in the live check followed the on-screen dot (scripted), not a face; the synthetic model is a head-position stub, so eye-region claims stay "Not evaluable".
- No Android capture; no replay of samples (first 200 rows only); no comprehension and comfort data (cards show a dash).
- Token is still memory only; a reload during a session leaves it open until "My sessions" shows it as unfinished.

- Browser verification: see step2-e2e.md.
