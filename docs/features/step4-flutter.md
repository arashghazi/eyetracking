# Step 4 — Flutter snapshot (research and data)

Contract: docs/api/step4-research-data.md. Layering as before (domain -> application -> data -> presentation), same theme, plain Flutter state, no new packages.

## What exists
- `packages/core`: models for quality `{grade, reasons}` (in session summary and list rows, with plain-language reason labels), the replay bundle (compact samples `[t, x, y, conf, region]` decoded lazily, binary search by time, layout/trial/gap/pause/clip lookups), analysis (rows, groups, trends), access log, data dictionary, `StudyInfo` + `RetentionPolicy`, `EraseResult`, `MyDataCounts`; `ApiClient.getBytes` and `delete` (JSON body); `saveFile` (Blob + `<a download>` in the browser, no-op elsewhere) behind the `FileSaver` port; `VideoStageController` (seek/play/pause/rate, applied again after a clip loads) and `VideoStageConfig.autoplay`; `RecordingVideoPlayer` in `testing.dart`.
- Admin: Sessions tab Quality column (icon + word, reasons as tooltip, first reason as small label) and quality badge, Replay button, Samples CSV / Events CSV in the session detail; Replay screen (`ReplayController` + `ReplayCanvasPainter` + timeline with segment bands, gap/pause shading and valid-share strip; play/pause, 0.5x/1x/2x, arrow keys step 100 ms, gaze dot with 500 ms trail, region name, trial numbers, "No participant video exists", "Display only; no smoothing", stimulus video seeking at most 4 times a second); Analysis tab (filters, table with signed eye-share change, comparable groups, one trend card per participant and group drawn with CustomPaint, hollow bars for not evaluable, Sessions CSV/JSON, data-dictionary dialog); Access log tab (researcher/admin); participant "Delete this participant's research data" with a type-the-code dialog; retention policy card in the Members tab (admin).
- Participant: "Download my data" (counts, note that gaze numbers and events are the raw data and no camera video exists, Download JSON); profile "Withdraw and delete my data" with a `DELETE MY DATA` dialog, then sign-out with a farewell on the sign-in screen; interest path posts `media_start {segment_id, media_key}` once per clip; layout calls already carried `stage_index` for the gradual path (checked, tested).

## Choices
- The analysis is loaded only by "Show analysis" (each view is written to the access log). `quality` is always sent (default `ok,review`; the last grade cannot be switched off). "Include synthetic" also adds `exclude`, because synthetic sessions are always graded exclude and would otherwise never appear.
- A trial is on screen from its `t_ms` for `response_ms`, or until the next trial (at most 8 s) when unanswered. A sample inside a gap draws nothing; a sample without x/y draws nothing.
- Comfort marker in the trend chart uses mean / 5 (scale 1-5 fixed). Analysis table shows 500 rows at most, access log 200.
- An admin who is not a study member cannot read `GET /studies/{id}` (403): the card says so and still lets the admin set the policy.

## Run (research server :8000, gaze service :8100)
- Participant: `cd apps/participant && flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=GAZE_BASE_URL=http://localhost:8100`; Admin: `cd apps/admin && flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://localhost:8000`.
- Tests: `flutter analyze` and `flutter test` in `packages/core`, `apps/participant`, `apps/admin`; `flutter build web --no-web-resources-cdn` in both apps (delete `build/`).

## Results (2026-09-29)
- `flutter analyze`: clean in all three. `flutter test`: core 107, participant 258, admin 250, all passing (replay controller time stepping, layout/trial/gap/pause lookup and seek throttling with a fake clock; painters at 360/800/1440 px; analysis filters, groups, trends and hollow-bar painting; delete/erase dialogs need the exact code/phrase; download counts). Both web builds compile.
- Live check ran (backend :8765 with a scratch SQLite DB, gaze service `e2e-fake` :8100, real repositories; temporary drivers, not kept): replay of gradual and interest sessions, analysis and filters, CSV/JSON/samples/events downloads (BOM kept), dictionary, access log (analyst 403), retention policy, participant deletion, `/me/data`, `/me/erase` (token and login refused afterwards). A headless Chromium pass over both builds confirmed the downloads (Blob), the replay video seeking/playing with the timeline, the delete and erase dialogs and the farewell; no page errors.

## Missing
- The signed clip link is `/media/<token>`, so the app cannot tell the media key and sends the segment id; the server's replay resolves clips by key, so such a clip has `url: null` and the replay says "link not available". Fix on the server: resolve by `segment_id` through the content definition, or add `media_key` to the personalized segments (the app already prefers a `media_key` field when present).
- Only the numbers of a session are described for screen readers, not the canvas; the arrow keys need focus on the page. Non-browser platforms cannot save files. The wording of the `keep_coded` farewell needs the reviewer's approval.

- Browser verification by the session lead: see step4-e2e.md.
