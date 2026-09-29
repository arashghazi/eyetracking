# Step 3 API contract — protocols, content, assignments and the two practice paths

Base and auth as in step 2. Errors `{"detail": "..."}`. Every session that runs a practice path references one **published protocol version**; published versions never change.

## Protocol definition (JSON, validated on save and publish)
```
{
  "path": "gradual_face" | "interest_conversation",
  "baseline_seconds": 30, "post_seconds": 30,
  "comfort": {"scale_max": 5, "labels": ["Very uncomfortable","Uncomfortable","Neutral","Comfortable","Very comfortable"], "min_ok": 3, "ask_every_stage": true},
  "progression": {"hold_on_invalid_share_above": 0.3, "easier_on_comfort_below_min": true, "stop_on_two_low_comfort": true},
  "gradual": {                                      // required when path == gradual_face
    "stages": [ {"face_level": 0, "number_zone": "outside", "trials": 6, "min_correct": 0.8, "response_mode": "profile", "trial_seconds": 8}, ... ],
    "final_zone_limit": "near_eyes",                // "eye_region" only when the reviewer decides so
    "allow_simultaneous_change": false,
    "real_face_media_url": null                     // approved real face image for face_level 3 (null → vector face)
  },
  "interest": {"interaction_points": 2}             // required when path == interest_conversation
}
```
- `face_level`: 0 square, 1 face-like shape, 2 low-detail face, 3 approved real face. `number_zone` order: outside < face_edge < near_eyes < eye_region. Stages must be non-decreasing in both, change at most one factor between consecutive stages unless `allow_simultaneous_change`, and never exceed `final_zone_limit`. `response_mode`: `number` (keyboard) | `four_choice` | `symbol` | `profile` (use the participant's profile response mode; keyboard/touch → number entry, four_choice, symbol).
- Comfort: `labels` length equals `scale_max`; values are 1..scale_max; `min_ok` is the lowest comfortable value.

## Content item (interest path; JSON)
```
{
  "start_segment": "s1", "post_segment": "s3",
  "segments": [
    {"id": "s1", "text": "Hi {{display_name}}, today we talk about {{topic}} ...", "media_key": "s1.webm", "duration_s": 20,
     "face_layout": {"face_box": [0.3,0.1,0.4,0.8], "eye_region": [0.3,0.25,0.4,0.2], "mouth_region": [0.3,0.55,0.4,0.25]},   // normalized to the video frame
     "question": {"id": "q1", "prompt": "Which do you prefer?", "options": ["Trains","Planes"], "branches": {"Trains": "s2", "Planes": "s2b"}}},
    {"id": "s2", "text": "...", "media_key": "s2.webm", "duration_s": 15, "face_layout": {...}, "question": null}
  ],
  "comprehension": [ {"id": "c1", "prompt": "What colour was the train?", "options": ["Red","Blue","Green"], "correct": "Red"} ]
}
```
Segment ids unique; branches point to existing segments; a segment without a question ends the conversation. Approval requires every `media_key` to be uploaded. `{{display_name}}` and `{{topic}}` are replaced for the participant.

## Research Admin
- `GET /studies/{id}/protocols` → `[{id, name, version, status: draft|published, path, created_at, published_at}]`
- `POST /studies/{id}/protocols` `{name, definition}` → protocol (draft) ; `GET /studies/{id}/protocols/{pid}` → with `definition`
- `PUT /studies/{id}/protocols/{pid}` `{name?, definition?}` (drafts only, 409 otherwise) ; `POST /studies/{id}/protocols/{pid}/publish` → the same protocol becomes `published` with a version number (a later edit needs a new draft: `POST /studies/{id}/protocols/{pid}/new-draft` → copy)
- `GET /studies/{id}/content` → `[{id, title, topic_tags, face_id, voice_id, status, media_keys:[...], missing_media:[...]}]`
- `POST /studies/{id}/content` `{title, topic_tags, face_id, voice_id, definition}` ; `GET/PUT /studies/{id}/content/{cid}` (drafts only) ; `POST .../approve` (422 with `missing_media` when uploads are missing)
- `POST /studies/{id}/content/{cid}/media/{key}` multipart `file` (video/webm, video/mp4, image/png, image/jpeg; ≤ 200 MB) → `{key, content_type, size}` ; `GET /studies/{id}/content/{cid}/media` → list
- `GET /studies/{id}/participants/{code}/assignments` → `[assignment]` ; `POST` `{protocol_id, order_index?}` → assignment ; `PUT .../assignments/{aid}` `{content_id?, status?: "cancelled"}` (content must be approved and match the study)
- Session detail gains `assignment_id`, `protocol: {id, name, version, path}`, `outcomes`, `stages`, `trials`, `answers`, `comfort_answers`.

**Assignment** `{id, order_index, status: pending_topic|content_pending|ready|in_progress|completed|cancelled, protocol: {id, name, version, path}, topic, topic_free_text, content_id, content_title, created_at}`

## Participant
- `GET /me/assignments` → `[assignment]` (ordered). `gradual_face` assignments start `ready`; `interest_conversation` ones start `pending_topic`.
- `POST /me/assignments/{aid}/topic` `{topic, free_text?}` → assignment (`content_pending`; the researcher then attaches approved content → `ready`)
- `GET /me/assignments/{aid}/content` → personalized content: `{title, face_id, voice_id, start_segment, post_segment, segments:[{id, text, media_url (signed, expires), duration_s, face_layout, question:{id, prompt, options}|null}], comprehension:[{id, prompt, options}]}` (404 until ready)
- `POST /me/sessions` gains optional `assignment_id`; the assignment must be `ready` or `in_progress`; the session summary then has `assignment_id` and `protocol: {id, name, version, path, definition}`.
- `POST /me/sessions/{id}/trials` `{trials:[{stage_index, trial_index, t_ms, number_shown, zone, position:{x,y}, face_level, response, response_ms}]}` → `{stored, correct}`; the server checks stage index and zone against the protocol and computes `correct` (`response == number_shown`).
- `POST /me/sessions/{id}/stage-result` `{stage_index, comfort_value?}` → `{decision: advance|hold|easier|stop|complete, next_stage_index:int|null, reason, correct_ratio, invalid_share, trials}`. Rules: a low comfort value (< min_ok) never advances (easier when possible, stop after two low answers in a row); too many uncertain samples in the stage → hold (`invalid_data`); fewer trials than planned → hold (`incomplete`); accuracy below `min_correct` → hold (`accuracy`); otherwise advance, or complete on the last stage.
- `POST /me/sessions/{id}/answers` `{segment_id, question_id, kind: interaction|comprehension, option, t_ms}` → `{correct: bool|null, next_segment_id: string|null}`
- `POST /me/sessions/{id}/events` type `comfort_answer` payload `{value:int, stage_index?:int, segment?:string}` (value 1..scale_max).
- Segments: use `baseline`, `practice`, `post` for the layout segment labels; the stage index can be sent in the layout call as `{"segment":"practice","layout":{...},"stage_index":1}`.
- Session summary gains:
```
"outcomes": {
  "gaze": {"baseline_eye_share": float|null, "post_eye_share": float|null, "evaluable": bool, "reason": string|null},
  "comprehension": {"answered": int, "correct": int, "share": float|null},
  "number_task": {"trials": int, "correct": int, "share": float|null, "stages_completed": int},
  "comfort": {"answers": int, "min": int|null, "mean": float|null, "low_count": int, "pauses": int, "ended_early": bool},
  "improvement": {"eligible": bool, "result": bool|null, "criteria": {"eye_share_up": bool|null, "comfort_not_worse": bool|null, "comprehension_maintained": bool|null}, "reason": string|null}
},
"stages": [{"stage_index", "decision", "reason", "correct_ratio", "invalid_share", "comfort_value", "trials"}]
```
`improvement.result` is true only when all three criteria hold; it is null whenever gaze is not evaluable.

## Media
- `GET /media/{token}` streams the file (supports `Range`); tokens are signed, expire after 6 hours and are only issued through `GET /me/assignments/{aid}/content` or to staff via `GET /studies/{id}/content/{cid}/media`.
