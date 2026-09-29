# Step 2 API contract — sessions and measurement

Base: research server `http://localhost:8000` (bearer token). Gaze service `http://localhost:8100` (local PC path, no auth) or the same endpoints under `/gaze/*` on the research server with the bearer token (secure path for phones). Errors: `{"detail": "..."}`.

## Concepts
- **Raw sample** (from the gaze service, never stored as an image):
  `{t_ms:int, face_detected:bool, face_box:[x,y,w,h]|null, face_conf:0..1, yaw_deg:float|null, pitch_deg:float|null, gaze_conf:0..1, frame_w:int, frame_h:int}` — `t_ms` is the client's monotonic clock in ms.
- **Layout** (stimulus geometry in CSS px of the participant's screen): `{screen:{w,h,dpr}, face_box:[x,y,w,h], eye_region:[x,y,w,h], mouth_region:[x,y,w,h]}`. Eye region = upper half of the face (brow line to below the eyes); mouth region = lower half.
- **Region classes**: `eye | mouth | face_other | outside | uncertain`. Uncertain = no face, `gaze_conf` below the study threshold, or off-screen mapping.
- **Sessions** are created only for a participant whose readiness is `ready` (consent + demographics). A study's **measurement settings** carry the thresholds.

## Gaze service
- `GET /info` → `{model_id, model_version, synthetic:bool, face_detector, max_fps}`. `synthetic:true` means the estimator is a development stub; sessions using it are flagged and never yield eye-region claims.
- `POST /estimate` `{image_b64:string (JPEG), t_ms:int, frame_w:int, frame_h:int}` → raw sample plus `model_id`. Frames are processed in memory and discarded.

## Participant (bearer token)
- `GET /me/measurement-settings` → `{validation_min_correct:0.8, validation_max_uncertain:0.2, min_region_to_error_ratio:2.0, gaze_conf_threshold:0.5, calibration_points:9, allow_continue_without_validation:true}`
- `GET /me/sessions` → `[session summary]`
- `POST /me/sessions` `{device:{platform, user_agent?, model?}, screen:{w,h,dpr}, camera:{label?, w, h}, gaze_model:{model_id, model_version, synthetic}}` → session summary (status `created`). 403 with detail when the participant is not ready.
- `POST /me/sessions/{id}/camera-check` `{face_detected:bool, face_conf:0..1, lighting_ok:bool, frame_w:int, frame_h:int}` → summary (status `camera_ok` when face_detected, else stays `created` with `detail` in `notes`).
- `POST /me/sessions/{id}/calibration` `{targets:[{x:px, y:px, samples:[raw...]}]}` → `{calibration_id, residual_px_median, residual_px_p90, per_target:[{x,y,n_valid,err_px}], accepted:bool, reasons:[string]}`; needs ≥5 targets with ≥5 valid samples each, else 422. Sets status `calibrated`, `calibration_valid=true`, and clears any previous validation.
- `POST /me/sessions/{id}/validation` `{layout, targets:[{region:"eye"|"mouth"|"outside", x, y, samples:[raw...]}]}` → `{validation_id, passed:bool, correct_ratio, uncertain_ratio, size_ratio, reasons:[string], targets:[{region, x, y, n, majority, correct:bool, uncertain_share}]}`; requires a valid calibration (409 otherwise). Status becomes `validated`.
- `POST /me/sessions/{id}/layout` `{segment:"baseline"|"practice"|"post"|"free", layout}` → `{layout_id}`; the current layout is used to classify following samples.
- `POST /me/sessions/{id}/samples` `{samples:[raw...]}` → `{stored:int, invalid:int}`; only while status is `running` and calibration is valid (409 otherwise, detail says why).
- `POST /me/sessions/{id}/events` `{t_ms, type, payload?}` with type in `segment_start | segment_end | pause | resume | end | camera_changed | orientation_changed | zoom_changed | face_lost | face_found | comfort_answer | note` → summary. Rules: `segment_start` needs a layout and puts the session in `running`; `pause`→`paused`, `resume`→`running`; `camera_changed | orientation_changed | zoom_changed` set `calibration_valid=false` (recalibrate before more samples); `end` with `payload.reason` in `completed | ended_early` closes the session (`ended`).
- `GET /me/sessions/{id}` → summary.

**Session summary** `{id, status, created_at, ended_at|null, synthetic:bool, calibration_valid:bool, calibration:{residual_px_median, residual_px_p90, points}|null, validation:{passed, correct_ratio, uncertain_ratio, size_ratio, reasons}|null, coverage:{total_ms, classifiable_ms, uncertain_ms, missing_ms}, region_shares:{eye, mouth, face_other, outside}|null, face_region_attention:{share:float|null}, eye_region_attention:{evaluable:bool, share:float|null, reason:string|null}, segments:[{label, started_ms, ended_ms|null}], events_count:int, notes:[string]}`

## Research Admin (bearer token; study membership required)
- `GET /studies/{id}/measurement-settings`, `PUT /studies/{id}/measurement-settings` (researcher) — same shape as above.
- `GET /studies/{id}/sessions` → `[{id, participant_code, status, created_at, ended_at, synthetic, device_platform, calibration_residual_px, validation_passed:bool|null, coverage, eye_region_attention}]`
- `GET /studies/{id}/sessions/{sid}` → session summary plus `participant_code`, `device`, `screen`, `camera`, `gaze_model`, `validation.targets`, `events:[{t_ms,type,payload}]`
- `GET /studies/{id}/sessions/{sid}/samples?offset=0&limit=5000` → `{total, items:[{t_ms, x, y, conf, valid, region, segment}]}` (for replay in step 4).

Analysts have read access to the same GET endpoints; participants only to `/me/*`.
