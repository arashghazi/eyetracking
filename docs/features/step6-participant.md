# Step 6 — Participant App snapshot (debrief after a session)

Contract: "Debrief after a session" in docs/api/step6-pilot.md. Layering as before (domain -> application -> data -> presentation), plain Flutter state, no new packages. Backend and `packages/core` untouched.

## Participant debrief

### What exists
- `apps/participant/lib/features/debrief/`: models (`ParticipantDebriefForm`, `ParticipantDebriefQuestion` with type scale / yes_no / choice / text, `DebriefAnswer` {form_version, answers, skipped}, `SessionDebrief` = the GET response) kept in the feature; `DebriefRepository` port and `ApiDebriefRepository` (GET and POST `/me/sessions/{sid}/debrief`); `DebriefController` (ChangeNotifier: load, answers, required rule, send, skip, reload after 409); `DebriefCard` and question rows.
- The `Participant` prefix avoids a name clash with the admin-side `DebriefForm` / `DebriefQuestion` in `packages/core` (`models/pilot.dart`).
- Session summary (`SummaryStep`): after the numbers and before "Back to home", a card "A few questions about this session", only when the response says `enabled`, `session_ended`, the form has questions and there is no answer yet. Otherwise nothing is shown (also when the debrief fails to load: it is optional). `AppDependencies.debrief` is the new port; `AppScope.maybeRead` lets the summary work without a scope (tests).
- Inputs: scale = numbered chips in one row with the first and last label under the ends and "Chosen: <label>" (a 10-point scale wraps to two rows on a phone instead of shrinking the chips); yes/no = two chips; choice = chips; text = multi-line field, max 1000 with counter, Enter adds a line. Tapping the chosen chip again clears it. "Required" is written next to required prompts.
- "Send answers" is enabled when every required question is answered (text needs more than spaces); optional unanswered questions are left out and text is trimmed. "Skip these questions" sends `skipped: true` with no answers and is always available. Neither blocks "Back to home".
- Server 409 / 422 text is shown as written; 409 adds "Reload the questions" (fetches the form again, keeps answers that still fit the new version, hides the card if it was answered meanwhile). After success: "Thank you. Your answers help us improve the sessions." (after a skip: "Skipped. Thank you."); an answered or skipped session is never asked again (the server returns the answer).
- Keyboard: Tab follows the questions top to bottom (reading order) and ends at Skip; chips act on Enter / Space.
- The summary page builds all its children (`PageFrame(buildAll: true)`), otherwise Flutter drops the card and what was typed when it scrolls far out of view.

### Results (2026-09-30)
- `flutter analyze` clean. `flutter test`: 312 in the participant app (258 before + 54 in `test/debrief_test.dart`, fake in `test/debrief_kit.dart`, wired into `TestBed`). `flutter build web --release --no-web-resources-cdn` compiles (build dir deleted).
- The 54 cover: hidden when off / answered / skipped / not ended / no form / load failure; required rules; each input; payloads of send and skip; 409 with Reload (answers kept, new version sent), 422, network error; thank-you and never-again; 360 / 800 / 1440 px without overflow (also on the summary page); Tab order; Enter in the text field; the API wire with a canned HTTP client; the card does not block "Back to home"; typed text survives scrolling away.

### Missing
- Seen in a headless browser after a full gradual session against the backend (docs/features/step6-e2e.md): card shown, answers sent (201), thank-you shown.
- Questions of an unknown type are dropped from the form (the server would answer 422 if one were required); no separate "Answered, thank you" line for a session answered earlier.
- Tests find widgets below the fold with `skipOffstage: false`; Flutter's default finders skip built-but-scrolled-out list items.
