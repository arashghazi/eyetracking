# Supervised pilot — runbook for the research team

Build step 6 of the design (v1.1, p. 6): test with the target devices and people, review comfort and understanding, settle the scientific thresholds, fix the user experience, and, if a research eye tracker is available, spend one day comparing against it. The apps support this; the decisions stay with the research team.

## 1. Before the first participant
1. **Decide the open questions** on design p. 7 that the pilot depends on: age range and inclusion criteria, where the number may finally go (`final_zone_limit`), the comfort rule, and the provisional validation thresholds (placeholders: 80 % correct, 20 % uncertain, eye region at least 2x the calibration error).
2. **Run on the pilot PC** with the real estimator: `scripts\run-local.cmd -Model l2cs -Weights <L2CSNet_gaze360.pkl>` (see docs/run-local.fa.md). A session with a synthetic estimator never produces eye-region results, and the pilot report leaves it out.
3. **Review the questions after a session** (Research Admin → Pilot → Questions after a session). The six defaults ask about the instructions, overall comfort, anything uncomfortable, camera setup and one change. Edit if needed, then switch them on. Changing questions later creates a new version; earlier answers keep theirs.
4. **Dry run** with two staff members on each device you plan to use. Write observations as you would in the pilot. Delete the dry-run participants afterwards (participant detail → delete research data).
5. **Device list.** Note for each device: laptop or external webcam, camera resolution, screen size, and browser. The session records these automatically; the pilot report groups results by device.

## 2. Each pilot session
| When | Supervisor |
|---|---|
| Setup | Even light on the face, no window behind the person, eyes about an arm's length from the screen, browser full screen (F11). |
| Start | Research Admin → Pilot → Live, open the participant's session. The panel refreshes every few seconds. Opening it is recorded in the access log. |
| During | Watch the valid share and pauses. Write an observation when something happens, using "Use current session time". Categories: comfort, comprehension, technical, ux, protocol, other. Severity: info, minor, major, **stop** (the person asked to stop or you stopped the session). Never write names or identifying details. |
| Stop rules | The participant may pause or end at any time. The app never advances a stage on a wrong answer, discomfort or invalid data. If you stop the session, write a "stop" observation with the reason. |
| After | The participant sees the optional questions after the summary and may skip them. Do not help with the answers. |

## 3. Settling the thresholds
1. Collect enough **real** sessions on each target device; the team decides how many (for example at least ten per device class).
2. Research Admin → Pilot → Thresholds. Enter a candidate value and press **Review**. The page shows how many validations would pass, how quality grades would change, the distributions (median, p90) and the effect per device. **Nothing is saved.**
3. Look at the sessions that change. A threshold that passes almost everything on a device with a high calibration error is too loose. One that fails most sessions on a good setup is too strict.
4. When the team agrees, press **Save as new settings version** and write the rationale with the evidence, for example "12 real sessions on two laptops: median correct 0.86, p90 residual 48 px; 0.8 kept, max uncertain raised to 0.25 because of glasses reflections."
5. New validations record the version they were judged with. Do not change thresholds halfway through a participant's sessions; start a new version between pilot rounds.
6. Changes to the confidence threshold, calibration points and "continue without validation" apply to new sessions only; the review says so.

## 4. Comparison day with a research eye tracker (if available)
1. Calibrate the research tracker as its manual describes. Show the Participant App **full screen on the tracker's screen**, so the app's origin is 0, 0.
2. Start the tracker recording first, then the session. Note roughly how long after the recording start the session began; that is the first estimate of the offset.
3. After the session, export the tracker's gaze data as CSV or TSV with a timestamp, gaze x, gaze y and a validity column.
4. Research Admin → Pilot → Tracker comparison: choose the session, pick the file, map the columns, set the time unit (Tobii exports usually use microseconds) and coordinate space (device pixels when the tracker reports screen pixels), and enter the offset.
5. **Alignment.** A hardware or software sync marker is best. Without one, set "auto-align window" to a few seconds. The app then estimates the shift from the data and marks the result as **optimistic**, because the same data was used to align it. Report it that way.
6. Compare. The page shows region agreement, Cohen's kappa, eye-region precision and recall, pixel distances and the confusion matrix. These numbers describe **that session on that computer**. They are not a general accuracy claim for the method.

## 5. Reviewing the pilot
- Research Admin → Pilot → Report, then **Download CSV** for the team. The report shows validation per device, quality grades, comfort values per stage, early endings, answers to the questions and comments, and observations by category and severity. Synthetic sessions are left out unless you include them on purpose.
- Fix user-experience problems that the observations and comments show, then run the next pilot round with the new app and settings versions.
- Everything is under research codes. Withdrawal removes the person's sessions, observations, answers and tracker recordings under the default policy.

## Still open
- Whether supervisor observations belong in the participant's own data download.
- Degrees of visual angle need the screen's physical size and the viewing distance; these are not recorded yet.
- The Android path and a live avatar come after the pilot (design steps 2 and 7).
