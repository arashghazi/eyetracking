# Step 4 API contract — replay, quality, analysis, exports, raw data, deletion

Base and auth as before. Staff endpoints need study membership; analysts may read and export but never see identity. Every export, replay, analysis view, identity reveal and deletion is written to the study's access log.

## Quality control (per session, server-side)
`quality: {grade: "ok"|"review"|"exclude", reasons: [string]}` is added to every session summary and list row.
- `exclude`: `synthetic_estimator`, `no_calibration`, `no_classifiable_time`.
- `review`: `validation_not_passed`, `uncertain_share_above_<x>`, `missing_share_above_<x>`, `ended_early`, `calibration_invalidated`.
- Thresholds live in measurement settings: `quality_max_uncertain_share` (0.2) and `quality_max_missing_share` (0.2); both editable with the other settings.

## Replay
`GET /studies/{id}/sessions/{sid}/replay` →
```
{"session": {id, participant_code, status, created_at, synthetic, quality, protocol: {name, version, path}|null},
 "screen": {w, h, dpr},
 "segments": [{label, started_ms, ended_ms}],
 "layouts": [{id, segment, stage_index|null, layout, from_ms, to_ms}],           // from/to derived from the samples that used the layout
 "samples": [[t_ms, x|null, y|null, conf, region_code]],                          // region_code: 0 eye, 1 mouth, 2 face_other, 3 outside, 4 uncertain
 "events": [{t_ms, type, payload}],
 "trials": [{stage_index, trial_index, t_ms, number_shown, zone, position, face_level, response, correct, response_ms}],
 "answers": [{segment_id, question_id, kind, option, correct, t_ms}],
 "quality_strip": [{from_ms, to_ms, valid_share|null}],                          // one entry per second; null = no samples (missing)
 "gaps": [{from_ms, to_ms}],                                                      // sample gaps longer than twice the nominal interval
 "pauses": [{from_ms, to_ms}],
 "media": [{segment_id, media_key, start_ms, url}]}                              // from media_start events; url is a signed link
```
The participant's camera video never exists; replay draws the stimulus geometry and the gaze estimate only. Smoothing is a display choice and adds no accuracy.

New participant event type `media_start` with payload `{segment_id, media_key}` (the interest path posts it when a clip starts) and the layout call accepts `stage_index`.

## Analysis
`GET /studies/{id}/analysis?participant=&path=&protocol_version=&device=&from=&to=&quality=ok,review&include_synthetic=false` →
```
{"filters": {...},
 "rows": [{session_id, participant_code, created_at, path, protocol_name, protocol_version, device_platform, screen, estimator, synthetic,
           quality, quality_reasons, calibration_residual_px, validation_passed, size_ratio,
           total_ms, classifiable_share, uncertain_share, missing_share, face_share, eye_share,
           baseline_eye_share, post_eye_share, eye_share_delta, comprehension_share, number_task_share, stages_completed,
           comfort_min, comfort_mean, comfort_low_count, pauses, ended_early, improvement, group_key, demographics: {key: value}}],
 "groups": [{group_key, device_platform, protocol_version, estimator, screen_bucket, stimulus_bucket_px, sessions, participants}],
 "trends": [{participant_code, group_key, points: [{session_id, created_at, baseline_eye_share, post_eye_share, comfort_mean, comprehension_share, number_task_share, quality}]}],
 "excluded": int, "note": "Sessions from different groups are never pooled into one trend by default."}
```
`group_key` joins device platform, protocol version, estimator model and the stimulus size bucket; trends are per participant within one group. Rows are coded; demographics come from the participant's answers under the research code.

## Exports and data dictionary
- `GET /studies/{id}/exports/sessions.csv` and `.json` (same filters as analysis) — one row per session, demographics flattened as `demo_<key>`, plus `protocol_version`, `sheet_version`, `gaze_model_version`, `export_version`.
- `GET /studies/{id}/exports/samples.csv?session_id=<sid>` — `t_ms,x,y,conf,valid,region,segment,layout_id`.
- `GET /studies/{id}/exports/events.csv?session_id=<sid>` — `t_ms,type,payload_json`.
- `GET /studies/{id}/exports/data-dictionary.json` — field name, type, unit, meaning, for every export column and summary field.
- `GET /studies/{id}/access-log?limit=200` → `[{at, user_id, role, action, detail}]` (researcher or admin member).

## Participant raw data and deletion
- `GET /me/data` now includes `sessions: [{summary, samples: [[t_ms,x,y,conf,region_code]], events, trials, answers}]` and `export_version`.
- `POST /me/erase` `{confirm: "DELETE MY DATA"}` → `{policy, deleted: {sessions, samples, events, consents, answers, trials, demographics, profile, assignments}, identity_removed: true}`; the account is deactivated and its email replaced; afterwards the token is invalid. The study's `retention_policy` decides: `delete_all` (default) removes the research rows too; `keep_coded` keeps coded research rows (never the identity link).
- Admin: `PUT /studies/{id}` `{retention_policy: "delete_all"|"keep_coded"}` ; `GET /studies/{id}` → `{id, name, retention_policy}`.
- Researcher: `DELETE /studies/{id}/participants/{code}/data` with body `{confirm: "<code>"}` → deletes the participant's research rows (sessions and everything under them, consents, demographics, profile, assignments) and logs the action; the account and code stay so the person can still sign in and see an empty record.
