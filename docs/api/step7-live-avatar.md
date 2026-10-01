# Step 7 API contract — live interactive avatar

Base and auth as before. A live conversation belongs to one session of a published `live_conversation` protocol and runs during that session's practice segment; the gaze measurement continues as in the other paths.

## Protocol path `live_conversation`
Same top level as the other paths (`baseline_seconds`, `post_seconds`, `comfort`, `progression`) plus:
```
"live": {
  "max_turns": 8 (1-30),            "max_minutes": 8 (1-30),
  "max_reply_words": 40 (10-80),    "max_participant_chars": 400 (50-1000),
  "opening_line", "closing_line", "redirect_line", "distress_line": text, max 400, no links or e-mail
      ({{display_name}} and {{topic}} are filled in),
  "avatar_id", "voice_id": text (max 120; for a future streaming vendor),
  "input_modes": ["typed", "speech"] (one or both),
  "store_transcript": false,
  "face_layout": {"face_box", "eye_region", "mouth_region": [x, y, w, h] as fractions of the avatar frame} (optional)
}
```
Assignments of this path start as `pending_topic`; `POST /me/assignments/{id}/topic` makes them `ready` (no prepared content: the confirmed topic is what the avatar may talk about).

## Participant
- `GET /me/sessions/{sid}/live` → `{conversation|null, turns, limits, store_transcript_offered, input_modes}`.
- `POST /me/sessions/{sid}/live/start` `{input_mode: typed|speech, allow_transcript: bool, t_ms?}` → `{conversation, turns: [opening], avatar, face_layout|null, limits, resumed}`. Calling it again while open returns the same conversation (`resumed: true`); after it closed → 409. Speech needs a configured speech provider (409 otherwise); a paid reply provider needs budget for one turn (422 `budget_exceeded`).
  - `conversation`: `{id, status: open|closed, topic, input_mode, transcript_allowed, turns_used, turns_left, end_reason, started_at, ended_at, providers: {reply, speech, avatar}}`. `transcript_allowed` is true only when the protocol keeps transcripts **and** the participant agreed.
  - `avatar`: development value `{mode: "sample_video", video_url: "/static/live/sample-face.webm", voice: "browser_tts", captions: true, synthetic: true, note}`. The app loops the video, shows every line as a caption and speaks it with the browser's own voice.
  - `limits`: `{max_turns, max_minutes, max_reply_words, max_participant_chars, input_modes}`.
- `POST /me/sessions/{sid}/live/turn` `{expect_turn, text, t_ms?}` and `POST /me/sessions/{sid}/live/turn-audio` multipart `file` (audio/webm, ogg, wav, mp4 or mpeg; max 4 MB), `expect_turn`, `t_ms?` → `{participant: turn|null, avatar: turn, turns_used, turns_left, done, end_reason|null, distress}`.
  - `expect_turn` must equal `turns_used` (409 otherwise), so a double send is refused.
  - Typing always works, also in a speech conversation. Audio in a typed conversation, an unsupported type, an empty file or a speech failure → 422 with a message to try again or type. Audio is processed in memory and never stored.
  - Turn: `{index, role: avatar|participant, text|null, chars, t_ms, flags: [...], latency_ms}`. Participant flags: `typed`, `speech`, `sample_speech`, `participant_truncated`, `participant_on_topic`, `participant_off_topic`, `distress`. Avatar flags: `scripted_line`, `opening`, `closing`, `redirect_line`, `fallback_line`, `reply_shortened`, `participant_off_topic`, `distress`, `participant_wants_to_stop`, `refusal`, `provider_error`, `no_reply`, `contact_or_link`, `clinical_or_research_words`, `empty_reply`, `turn_limit`, `time_limit`, `budget`.
  - `end_reason`: `participant` (asked to stop), `participant_ended` (End button), `turn_limit`, `time_limit`, `budget`, `session_ended`.
  - `distress: true` → the app shows a calm "take a break" option; the supervisor's live monitor counts it.
- `POST /me/sessions/{sid}/live/end` `{t_ms?}` → `{avatar: closing turn, turns_used, done: true, end_reason: "participant_ended"}`.
- Ending the session (`end` event) closes an open conversation (`session_ended`). When a conversation closes without `transcript_allowed`, every turn's text is removed; counts and flags stay.

## Rules the server enforces on every reply
The reply provider returns `{reply, participant_on_topic, participant_distress, participant_wants_to_stop}`. Then: a wish to stop → closing line and close; distress → the scripted distress line; a second off-topic message in a row → the redirect line; an empty reply, a link, an e-mail address, a phone number, or clinical, therapeutic or research words (diagnosis, medication, therapy, autism, disorder, eye contact, gaze, eye tracking) → the redirect line; replies longer than `max_reply_words` are shortened at a sentence or word boundary; a refusal or API error → the redirect line. The last allowed turn and the time limit end with the closing line. Stored text has e-mail addresses, phone numbers and links removed.

## Staff
- `GET /studies/{id}/live/status` (researcher, analyst) → `{reply_provider: {name, model?, effort?, configured, synthetic}, speech_provider: {name, configured, synthetic, model?, base_url?}, avatar_provider: {name, configured, synthetic, streaming}, estimates: {per_turn_units, avatar_per_minute_units}, budget: {cost_cap_units, spent_units, remaining_units, send_free_text}, open_conversations, note}`. Live replies use the study's AI cost cap from step 5 (`PUT /studies/{id}/ai/budget`, admin).
- `GET /studies/{id}/sessions/{sid}/conversation` (researcher, analyst) → `{conversation, turns (text only when the transcript was kept), outcome, cost_units, note}`. Access log: `live_transcript`.
- The live monitor (`GET /studies/{id}/sessions/{sid}/live`) gains `conversation: {status, input_mode, turns_used, distress, redirects, last_turn: {role, flags, t_ms}, end_reason}|null`.
- Session summaries gain `outcomes.conversation`: `{participant_turns, avatar_turns, on_topic, on_topic_share, redirects, distress, end_reason, note}`. For this path the improvement rule's third criterion is "the conversation held": at least two participant turns and an on-topic share of at least 0.5 (judged by the reply model).
- The pilot report rows gain `conversation_turns`, `conversation_on_topic_share`, `conversation_distress`, `conversation_end_reason`. `/me/data` carries `sessions[].conversation`.
- Withdrawal and researcher deletion also remove conversations and turns.

## Server settings (`EYETRACKING_` prefix, in `backend/.env`)
`LIVE_REPLY_PROVIDER=fake|anthropic`, `LIVE_REPLY_MODEL=claude-opus-5-5`, `LIVE_REPLY_EFFORT=low`, `ANTHROPIC_API_KEY`; `STT_PROVIDER=fake|whisper_http`, `STT_BASE_URL` (a Whisper-compatible server on this computer, for example `http://127.0.0.1:8200`), `STT_MODEL`, `STT_API_KEY`; `LIVE_AVATAR_PROVIDER=fake` (the only value until a streaming vendor is chosen).
