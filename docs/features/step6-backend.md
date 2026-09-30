# Step 6 — backend snapshot (supervised pilot)

Scope from the design (p. 6, step 6): pilot with the target devices and people, review of comfort and understanding, settling the scientific thresholds, UX fixes, and one comparison day with a research eye tracker when available. The pilot itself needs people and the research team; this step builds what they use. Contract: docs/api/step6-pilot.md.

## What exists
- `domain/pilot.py` (framework-free): observation rules, settings-version record, debrief question and answer validation with six default questions, threshold re-judging from stored validation ratios, distributions, tracker CSV parsing (time units, offset, device px / CSS px / normalised, origin, delimiter and decimal comma), nearest-in-time pairing, confusion matrix, Cohen's kappa, eye-region precision and recall, per-segment eye shares, offset search with an "optimistic" flag.
- Measurement settings carry a `version`; every change stores values, rationale and author; validations store `settings_version`; analysis rows and the sessions export show it.
- `application/pilot_use_cases.py`: observations, active sessions and live status (logged once per monitoring start), debrief form versions and participant answers (once per ended session), threshold review (saves nothing), tracker import and comparison, pilot report JSON and CSV. All reads are logged.
- Deletion rules cover the new tables. `/me/data` includes the participant's debrief answers.
- Local SQLite dev databases get the new nullable columns automatically (`create_schema`); other databases need a migration.

## Verified
- `python -m pytest -q`: 54 passed (46 earlier + 8 pilot: settings versions and history, threshold review, observations and live monitor, debrief versions and rules, tracker comparison, auto-alignment, pilot report and CSV with erasure, dev-DB column upgrade).

## Remaining
- Nothing here has met a real participant or a real research tracker. The CSV importer was tested with a synthetic Tobii-like export only; column names of the lab's tracker must be checked on the day.
- Degrees of visual angle need the screen's physical size and viewing distance, which are not recorded yet.
- Whether supervisor observations belong in the participant's own data download is an open decision.
