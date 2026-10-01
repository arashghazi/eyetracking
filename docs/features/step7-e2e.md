# Step 7 — browser verification record (2026-10-01)

Same setup as steps 2–6: headless Chromium with a fake camera, scratch SQLite, the gaze service in `e2e-fake` mode, admin web on :5173, participant web on :8080, API on :8765, development live providers (sample rules, sample speech, sample face video with the browser's voice). Seed: the step-3 seed, then a published `live_conversation` protocol (4 turns, transcripts allowed) assigned to P-001 with the topic "Trains" confirmed (assignment `ready`). Screenshots: `docs/features/screenshots/step7-*.png`.

## Participant App
1. Prepare for session → camera check → calibration → validation → baseline (10 s) → practice.
2. **Choice** (`step7-participant-live-choice`, `-filled`): "How would you like to talk? You will chat about Trains." with Type and Speak, "Your voice is turned into text and the recording is not kept.", and the optional "Keep a written record…" checkbox, ticked here. "Start the conversation" gave `POST /me/sessions/{id}/live/start` 200 and the sample face video `GET /static/live/sample-face.webm` 200.
3. **Conversation** (`step7-participant-live-reply`): avatar video on the left, the "Development avatar - sample face and your browser's voice" badge, turns left, Voice on/off, End conversation, the caption, and the message box with Send and a 400-character counter. Four typed turns (`POST …/live/turn` ×4, all 200).
4. **Distress** (`step7-participant-live-distress`): "I feel a bit nervous now" brought the scripted line "Thank you for telling me. We can take a break whenever you like…" and the banner "It's okay to take a break." with Pause and Keep talking. After Keep talking the message box takes the keyboard back (`step7-participant-live-after-keep-talking`).
5. **Closing** (`step7-participant-live-closing`): "ok bye, I want to stop" ended the conversation with "Thank you for talking with me about Trains, Sam. I enjoyed it.", "The conversation has ended. You asked to stop", and Continue. Then the post observation, the comfort question and the summary.
6. **Summary** (`step7-participant-live-summary`): Conversation card with 4 messages, 100 % on topic, "You asked to stop" and the note that on-topic is judged by the reply model. Gaze shows face-region time from the live segment; eye-level results stay "Not evaluable" with the development estimator.

No browser console errors.

## Research Admin
- **AI tab → Live avatar** (`step7-admin-live-avatar-card`): reply, speech and avatar providers, all development and configured, "No streaming avatar connected", estimates, the shared budget and open conversations.
- **Protocols** (`step7-admin-protocol-live-editor`, `-face-layout`): the published "Live conversation (short)" opens read-only with limits, the four lines, avatar and voice ids, Typed and Speech, the transcript switch, and the face layout with its preview and the eye-above-mouth rule.
- **Session detail → Conversation** (`step7-admin-session-conversation`, `-turns`): topic, input mode, transcript kept, status, end reason, turns, cost, the outcome with distress highlighted, and each turn with its time, flags and text (kept, because the participant agreed). The page states that opening it is written to the access log.

## Found and fixed during the run
- When a conversation closed without a kept transcript, the server removed the text before answering, so the closing line came back empty. The response now carries the line the participant hears before the stored text is removed (backend test added).
- After "Keep talking", the message box had lost the keyboard: it is switched off while a reply is on its way, and the banner's button took the focus with it. The box now takes the focus back (widget test added).

## Caveats
- Only typed input was run. Speech needs a microphone, which a headless browser does not have; the upload path was tested through the API and widget tests, and the browser voice is not audible here.
- In this accessibility-mode test browser, typing right after a mouse click into an already-focused box was unreliable after the distress banner; returning with Tab worked. Check by hand on the pilot PC, with and without a screen reader.
- Interrupted driver runs left 13 sessions with open conversations. A conversation stays open until its session ends; abandoned sessions need a cleanup rule.
- Nothing here used Claude, a speech server or a streaming avatar.
