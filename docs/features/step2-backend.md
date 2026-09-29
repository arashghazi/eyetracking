# Step 2 — backend and gaze service snapshot

Scope from the design (p. 6, step 2): camera, calibration, regional validation (eye / mouth / outside), recording with pause and resume, PC first then the secure Android path, no accuracy claims from synthetic tests, and showing the real validation result to the reviewer.

## What exists
- `backend/eyetracking/domain/measurement.py`: session status machine, per-study measurement settings, calibration fit (least squares from yaw, pitch and face position to screen pixels; median and p90 residual), point classification (eye = upper face half, mouth = lower half, face_other, outside, uncertain), validation with reasons (correct ratio, uncertain ratio, eye-region size vs residual, missing regions), coverage (missing time is a gap, never "not looking"), region shares, face- and eye-region attention with evaluability reasons.
- `backend/eyetracking/application/measurement_use_cases.py`: readiness gate on session creation, camera check, calibration and re-calibration, validation tied to the latest calibration, layouts per segment, sample batches (only while running with a valid calibration), events with rules (segment_start / pause / resume / end; camera, orientation and zoom changes invalidate calibration), coded summaries and paged samples for staff.
- `backend/eyetracking/web/routers/sessions.py`: the endpoints in docs/api/step2-measurement.md (participant `/me/*`, staff `/studies/{id}/*`).
- `backend/eyetracking/gaze/`: `GazeEstimator` port; `HaarFaceDetector` (OpenCV, no download); `SyntheticEstimator` (head position proxy, `synthetic: true`); `L2CSEstimator` (ResNet-50 with 90-bin yaw and pitch heads, loads the public checkpoint layout, `synthetic: true` until weights are loaded); HTTP surface `/info` and `/estimate` (frames decoded in memory only). Standalone service: `uvicorn eyetracking.gaze.main:app --port 8100`; secure path for phones: the same routes under `/gaze/*` on the research server with the bearer token.
- Configuration: `EYETRACKING_GAZE_MODEL=synthetic|l2cs`, `EYETRACKING_GAZE_WEIGHTS=<path>`, `EYETRACKING_GAZE_IN_API=true`.

## Verified
- `python -m pytest -q`: 28 passed (15 step 1 + 8 measurement + 5 gaze, including the L2CS pipeline with an untrained network and a checkpoint in the public key layout).
- Live smoke: standalone gaze service `/info` and `/estimate`; research server with `/gaze/*` behind authentication; 36 OpenAPI paths.
- The calibration and validation maths were checked with synthetic linear data only. **No accuracy claim follows from this.** Real numbers come from the PC test with a webcam and the published L2CS weights.

## Remaining in step 2
- Run the PC path with a real webcam and the published L2CS weights and record the real validation result for the reviewer.
- Android capture in the participant app (server path is ready).
- Per-study choice of estimator and stimulus size rules once the research team fixes the thresholds.
