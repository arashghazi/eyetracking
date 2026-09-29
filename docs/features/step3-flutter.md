# Step 3 — Flutter snapshot (the two practice paths)

Contract: docs/api/step3-practice.md. Layering as before (domain -> application -> data -> presentation), same theme.

## What exists
- `packages/core`: wire models (protocol summary/definition, content item + personalized content, assignment, trial, stage decision, answer, `outcomes`, `stages`, researcher trial/answer/comfort rows), `ApiException.body/missingMedia` (also parsed from "missing media: a, b"), `ApiClient.uploadFile` (multipart, progress) and `resolveUrl`, `VideoStage` (web `<video>` through `HtmlElementView`, object-fit contain, reports `onEnded`/`onError`/`onPlaying` and the drawn rectangle; stub elsewhere), `FakeVideoStage` in `testing.dart`, `containedVideoRect`, `NormalizedFaceLayout.toStimulusLayout`.
- Participant: home "Your next session" (assignment states) above the free "Camera and calibration check only" card; "Confirm my topic" interview; the flow Baseline -> Practice -> Post observation -> Comfort & summary (`SessionFlowController` with a `SegmentRecorder` port; `GradualPracticeController`, `InterestPracticeController`); face levels 0-3 (+ real image), number zones, number/four-choice/symbol answers (keyboard Enter, digit pad on touch), comfort scale buttons, decisions advance/hold/easier/stop/complete, captions from the profile, "The video is not ready" + retry; summary with the three outcomes side by side and the improvement line.
- Admin: Protocols tab (list, draft editor with stage table, Save draft, Publish with confirmation, New draft from published), Content tab (list with missing media, editor, per-key upload with progress via a `MediaPicker` port, Approve with the missing media), Assignments in the participant detail, practice cards/tables in the session detail.

## Choices
- The media URL is used as signed; only a root-relative `/media/<token>` gets the API address in front (the app runs on another origin). Same for a relative `real_face_media_url`.
- `stop` goes straight to the summary (session ends `ended_early`), no post observation. Trial numbers keep counting when a stage is repeated (server accepted this; it decided on the latest batch).
- Baseline uses the level-2 face, post the face of the last stage; one face card layout for baseline, practice and post (bottom space reserved for the answer controls).
- The `pause` event is sent only while a segment is open; between segments a pause is local.

## Run (research server :8000, gaze service :8100)
- Participant: `cd apps/participant && flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=GAZE_BASE_URL=http://localhost:8100`
- Admin: `cd apps/admin && flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://localhost:8000`
- Tests: `flutter analyze` and `flutter test` in `packages/core`, `apps/participant`, `apps/admin`; `flutter build web --no-web-resources-cdn` in both apps (delete `build/`).

## Results (2026-09-29)
- `flutter analyze`: clean in all three. `flutter test`: core 80, participant 219, admin 119, all passing (placement zones, controllers, flow with fakes, wire checks with a canned HTTP client, 360/800/1440 px). Both web builds compile.
- Live check ran once (backend :8765 with a scratch SQLite DB, gaze service `e2e-fake` :8100, real repositories, fake camera with a real JPEG, driver not kept): gradual path (3 stages, advance/complete), stop path (hold, then stop `low_comfort_twice`), interest path (topic -> researcher attaches content -> signed media with Range 206 -> interaction, comprehension, post, comfort), outcomes "Cannot be judged yet" (synthetic estimator); admin repositories: 422 text verbatim, publish 409 on edit, upload with progress, approve refused with "missing media: b1.webm", assign/cancel, session detail with trials/answers/comfort.

## Missing
- Browser run done in headless Chromium with a fake camera and generated clips: see step3-e2e.md (real webcam, real speaker video and Android still pending).
- Face levels and symbols are drawn placeholders; the approved real face image is only a URL field. No media preview or delete in the admin, no segment reordering.
- Gaze outcomes stay "Not evaluable" until a real estimator passes validation; nothing here was tried with a real webcam or a phone.
