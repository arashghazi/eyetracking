# Step 6 API contract — supervised pilot

Base and auth as before. Study data needs study membership: researcher for writes and for the live monitor, researcher or analyst for reads. Admins read only as explicit members. Every read below that shows study data is written to the access log.

## Measurement settings are versioned
- `GET /studies/{id}/measurement-settings` now also returns `version` (int, 1 = defaults).
- `PUT /studies/{id}/measurement-settings` accepts `rationale` (string, max 1000) next to the fields. A real change creates version N+1 with who and why; the same values again create nothing; a rejected change (422) stores nothing.
- `GET /studies/{id}/measurement-settings/history` → `[{version, values: {validation_min_correct, validation_max_uncertain, min_region_to_error_ratio, gaze_conf_threshold, calibration_points, allow_continue_without_validation, quality_max_uncertain_share, quality_max_missing_share}, rationale, changed_by|null, created_at|null}]`, newest first. Before any change it holds one synthesized entry (`created_at: null`).
- Every new validation records `settings_version`. It appears in session summaries (`validation.settings_version`), analysis rows and the sessions export (data dictionary updated).

## Threshold review (what-if, saves nothing)
`POST /studies/{id}/pilot/threshold-review` `{changes: {<settings field>: value, ...}, include_synthetic?: false}` → 
`{current: {version, values}, candidate: {values, changes}, sessions, skipped_synthetic, includes_synthetic, validated_sessions, validation_pass: {current, candidate}, quality: {current: {ok, review, exclude}, candidate: {...}}, changed_sessions, distributions: {correct_ratio|uncertain_ratio|size_ratio|residual_px_median|uncertain_share|missing_share: {n, min, p25, median, p75, p90, max}}, by_device: [{device_platform, sessions, validated, pass_current, pass_candidate}], rows: [{session_id, participant_code, created_at, device_platform, synthetic, settings_version, validation_current: {passed, reasons}|null, validation_candidate: {passed, reasons}|null, quality_current: {grade, reasons}, quality_candidate: {grade, reasons}, changed, metrics: {correct_ratio, uncertain_ratio, size_ratio, residual_px_median}}], notes: [string]}`
- Validation is re-judged from the stored ratios. `gaze_conf_threshold`, `calibration_points` and `allow_continue_without_validation` apply to new sessions only; `notes` says so.
- Unknown field or out-of-range value → 422. Access log: `threshold_review`.

## Supervisor observations
- `POST /studies/{id}/sessions/{sid}/observations` (researcher) `{category: comfort|comprehension|technical|ux|protocol|other, severity: info|minor|major|stop (default info), text (1-2000), t_ms?: int}` → 201 `{id, session_id, author_id, category, severity, text, t_ms, created_at}`.
- `GET /studies/{id}/sessions/{sid}/observations` (researcher, analyst) → list, oldest first.
- Observations cannot be edited or deleted; a correction is a new observation. They are research notes under the code: never write names or identifying details. They are not part of the participant's own data download (open decision for the research team).

## Live monitor
- `GET /studies/{id}/pilot/active` (researcher) → sessions not ended and started within the last 12 hours: `[{session_id, participant_code, status, created_at, device_platform, protocol_id, last_event: {type, t_ms, created_at}|null}]`, newest first.
- `GET /studies/{id}/sessions/{sid}/live?first=true|false` (researcher) → `{session_id, participant_code, status, synthetic, estimator, calibration_valid, validation: {passed, reasons}|null, current_segment|null, paused, pauses, stage_index|null, last_stage_result: {stage_index, decision, reason, comfort_value, correct_ratio}|null, samples_total, last_sample_t_ms|null, recent_window_ms: 10000, recent: {samples, valid_share|null, regions: {eye, mouth, face_other, outside, uncertain}}, recent_events: [{t_ms, type, payload}] (last 8), seconds_since_last_event|null, observations, end_reason|null, note}`.
- Poll every 2-3 s. Send `first=true` once when monitoring starts: that call is logged (`live_monitor`); the polls are not.

## Debrief after a session
Question: `{key: a-z0-9_ (starts with a letter, max 40), type: scale|yes_no|choice|text, prompt (max 300), required: bool, scale_max?: 2-10 (scale), labels?: [string] one per point (scale), options?: [2-10 strings] (choice)}`.
- `GET /studies/{id}/debrief-form` (researcher, analyst) → `{version, enabled, questions, saved}`. Before anything is saved: version 0, `enabled: false`, six default questions (instructions clear 1-5, comfort 1-5, anything uncomfortable yes/no, what (text), camera setup easy yes/no, one change (text)).
- `PUT /studies/{id}/debrief-form` (researcher) `{questions?: [...], enabled?: bool}` → form. Changed questions make a new version; `enabled` alone switches the current version on or off. Invalid questions → 422.
- `GET /me/sessions/{sid}/debrief` (participant, own session) → `{enabled, session_ended, form: {version, enabled, questions, saved}|null, answer: {form_version, answers, skipped, created_at}|null}`.
- `POST /me/sessions/{sid}/debrief` `{form_version, answers: {key: value}, skipped?: false}` → 201 answer. Values: scale → int 1..scale_max, yes_no → bool, choice → one option, text → string (max 1000). 409 when the session is not ended, the form is off, the version changed, or the session is already answered; 422 for a missing required or invalid value. `skipped: true` stores an empty answer.
- The participant's own data download (`/me/data`) carries `sessions[].debrief`.

## Research eye tracker (comparison day)
Run the Participant App full screen (F11) on the tracker's screen so `origin_x = origin_y = 0`.
- `POST /studies/{id}/sessions/{sid}/reference` (researcher), multipart: `file` (CSV/TSV, max 150 MB), `source` (tracker name and model), `time_column`, `x_column`, `y_column`, `valid_column?`, `valid_values?` (comma list, default `1,true,valid,yes`, case-insensitive), `time_unit: ms|us|s`, `offset` (tracker time at session t_ms = 0, in `time_unit`), `coord_space: css_px|device_px|norm`, `origin_x`, `origin_y` (CSS px), `delimiter?` (`,` `;` `tab`; guessed when empty; decimal commas are read in `;`/tab files), `auto_align_window_ms?` (0 = off, max 10000) → 201 `{id, session_id, source, settings: {..., alignment: given_offset|estimated_from_data, estimated_shift_ms?}, sample_count, valid_count, uploaded_by, created_at}`. A missing column → 422 naming the file's columns. Access log: `reference_import`.
- `GET /studies/{id}/sessions/{sid}/reference` (researcher, analyst) → recordings.
- `GET /studies/{id}/sessions/{sid}/reference/{rid}/compare?tolerance_ms=40` (1-500) → `{tolerance_ms, webcam_samples, paired_classified, webcam_uncertain_while_reference_valid, reference_invalid, no_reference_in_time, distance_px: {n, min, p25, median, p75, p90, max}, bias_px: {x, y}, region_agreement|null, cohen_kappa|null, confusion: {rows_webcam_columns_reference: {eye|mouth|face_other|outside: {eye, mouth, face_other, outside}}}, eye_region: {precision, recall}, segments: [{segment, pairs, webcam_eye_share, reference_eye_share}], note, recording, session: {id, participant_code, estimator, gaze_model_version, synthetic, validation_passed, screen}, caveats: [string]}`. Access log: `reference_compare`.
- Reference points are classified with the stimulus layout of the webcam sample they are paired with. Distances are CSS pixels. `caveats` names a synthetic estimator, an alignment estimated from the same data (optimistic) and a failed validation.

## Pilot report
- `GET /studies/{id}/pilot/report?include_synthetic=false` (researcher, analyst) → `{study_id, settings: {version, values}, sessions, participants, skipped_synthetic, includes_synthetic, validation: {validated, passed}, quality: {ok, review, exclude}, ended_early, comfort_stage_values: {"1".."5": count}, by_device: [{device_platform, sessions, validated, validation_passed, quality_ok}], debrief: {answered, skipped, questions: [{key, type, prompt, answered, counts: {value: n}, mean?}], comments: [{session_id, participant_code, key, text}]}, observations: {total, by_category: {category: {severity: n}}, items: [observation + participant_code]}, rows: [session row], note}`.
- Session row: `session_id, participant_code, created_at, status, end_reason, path, protocol_version, device_platform, device_model, user_agent, screen, camera, camera_label, estimator, synthetic, calibration_residual_px, validation_passed, validation_correct_ratio, validation_reasons, settings_version, quality, quality_reasons, stages_completed, stage_decisions ("0:advance;1:hold"), comfort_min, comfort_mean, comfort_low_count, pauses, ended_early, comprehension_share, number_task_share, debrief (answered|skipped|none), debrief_answers {}, observations, observations_major_or_stop, reference_recordings`.
- `GET /studies/{id}/pilot/report.csv?include_synthetic=false` → the rows as UTF-8 CSV with BOM, one `debrief_<key>` column per answered question. Access log: `pilot_report`, `export_pilot_csv`.

## Deletion
Withdrawal under `delete_all` and researcher deletion also remove observations, debrief answers and reference recordings with their samples (counts in `deleted`).
