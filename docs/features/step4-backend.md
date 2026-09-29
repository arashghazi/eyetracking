# Step 4 — backend snapshot (research and data)

Scope from the design (p. 6, step 4): sessions panel, replay of the gaze estimate on the stimulus, two gaze levels, comparison with quality control, coded CSV/JSON exports with versions and demographics, raw data for the participant, deletion rules. Access logging from the Exports section (p. 4).

## What exists
- `domain/research.py`: quality grade (`ok` / `review` / `exclude` with reasons; thresholds `quality_max_uncertain_share` and `quality_max_missing_share` in measurement settings), comparability group key (device | protocol version | estimator | screen bucket | stimulus-size bucket), compact samples with region codes, layout time ranges, per-second quality strip, sample gaps, pause intervals, the data dictionary.
- `application/research_use_cases.py`: replay bundle (stimulus geometry, gaze estimate, trials, answers, gaps, pauses, quality strip, signed media entries from `media_start` events; never any participant video), analysis rows with filters (participant, path, protocol version, device, dates, quality, synthetic off by default), groups and per-participant trends within one group, CSV/JSON session exports with `demo_<key>` columns and versions, samples and events CSV, access log, participant raw data (`/me/data` with sessions, samples, events, trials, answers), erasure (`/me/erase` with the study's retention policy: `delete_all` default, `keep_coded`), researcher deletion of a participant's research rows, study retention policy (admin).
- Every replay, analysis view, export, identity reveal, erasure and deletion is written to `access_log`; researchers and admin members read it.
- `web/routers/research.py`: the endpoints in docs/api/step4-research-data.md; downloads carry `Content-Disposition`; CSV is UTF-8 with BOM for spreadsheets.
- Session summaries and list rows now carry `quality` and the protocol reference; layouts carry `stage_index`; new event `media_start`.

## Verified
- `python -m pytest -q`: 41 passed (35 earlier + 6 research: quality grades and thresholds, replay bundle and access, replay media entries, analysis/exports/dictionary/access log, raw data and erasure under both policies, researcher deletion).
- Every column of the sessions export is documented in the data dictionary (asserted by a test).

## Remaining
- Analysis runs in Python over all sessions of a study; fine for a pilot, needs materialised summaries for large studies.
- Per-frame eye regions for moving faces are still per segment (`face_layout`); replay draws the segment layout.
- Retention timers (automatic deletion after N months) are not implemented; the policy only governs withdrawal.
