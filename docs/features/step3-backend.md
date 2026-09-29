# Step 3 — backend snapshot (practice paths)

Scope from the design (p. 6, steps 3a and 3b): Interest Conversation with approved sample content, personalization and approved branches; Gradual Face Practice as the main target with shape/number stages, a comfort question per stage, the number's final zone from the protocol, and recorded stage changes and answers; shared baseline and post observation.

## What exists
- `domain/practice.py`: protocol definition rules (non-decreasing face level and number zone, one factor per stage unless allowed, never beyond `final_zone_limit`, comfort scale with labels), content rules (unique segments, branches to existing segments, comprehension answers among options), personalization of `{{display_name}}` and `{{topic}}`, stage progression (`evaluate_stage`: low comfort → easier or stop after two low answers, invalid data → hold, incomplete → hold, accuracy → hold, else advance/complete), comfort outcome and the all-three improvement rule.
- `application/practice_use_cases.py`: protocols (draft → publish with an immutable version → new draft), content library with media upload and approval that demands every media key, assignments (interest path waits for the participant's topic and attached approved content; gradual path is ready at once), personalized content with signed media URLs, trials validated against the protocol stage, stage results, interaction and comprehension answers, outcomes (gaze baseline vs post, comprehension, number task, comfort, improvement) merged into every session summary.
- `web/routers/practice.py`: the endpoints in docs/api/step3-practice.md, including `/media/{token}` streaming with HTTP Range for video seeking. Media files live under `EYETRACKING_MEDIA_DIR` (default `backend/media`, git-ignored) and are reachable only through signed, expiring links.
- Sessions now carry `assignment_id` and `protocol_id`; `comfort_answer` events are validated against the protocol's scale; ending a session with `completed` completes its assignment.

## Verified
- `python -m pytest -q`: 35 passed (29 earlier + 6 practice: protocol validation and lifecycle, content/media/streaming, assignments and personalized content, gradual progression and outcomes, interest answers and improvement, improvement needs all three criteria).
- 54 OpenAPI paths.

## Remaining
- Real video content: the library holds researcher-uploaded WebM/MP4; AI generation and review queue are step 5.
- Per-trial gaze validity is estimated from the practice samples in the stage window; per-trial "looked at the number" analysis arrives with replay in step 4.
- A real-face image for `face_level` 3 must be an approved image URL; none ships with the repository.
