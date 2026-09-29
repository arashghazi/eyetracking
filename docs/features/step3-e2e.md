# Step 3 — browser verification record (2026-09-29)

Same setup as step 2 (headless Chromium, Chrome's fake camera, gaze service in `e2e-fake` mode, scratch SQLite, both apps built with `--no-web-resources-cdn`). Seed: one ready participant (profile "Sam", four-choice response mode, interests Trains and Gardening), a short gradual protocol (3 stages × 2 trials, 10 s baseline and post), a short interest protocol, approved content "Trains talk" with three generated VP9 clips (drawn talking face), and two assignments. **None of the numbers are measurements.** Screenshots: `docs/features/screenshots/step3-*.png`.

## Gradual Face Practice
- Home lists the assignments in order; "Prepare for session" starts the flow with the assignment.
- Camera check → calibration → validation (not passed with the fake face) → "Continue without eye-level scoring" → 10 s baseline → practice.
- The driver answered the four-choice trials at random, so most stages came back as **hold** ("Let's do this one again") until accuracy was reached: 45 stage results, 90 trials, decisions hold/advance/complete, comfort question after every stage, then post observation (10 s), the final comfort question and the summary.
- Summary: Number task 90 shown / 20 matched / 3 stages completed; Comfort lowest 4, average 4.0; Gaze "Not evaluable" (synthetic); "Did it help? Cannot be judged yet"; coverage 3:16 min total, 96 % usable, missing counted as missing.
- Network: 2110 gaze estimates, 200 sample batches, 141 events, 47 layouts, 45 trial batches, 45 stage results; no HTTP or page errors. The assignment ended **Completed** on the home screen.

## Interest Conversation
- "Confirm my topic": interests as checkboxes, free text; after confirming, the home shows "Content being prepared by your researcher".
- The researcher attached the approved content (API) → the assignment became ready → "Prepare for session".
- Practice: the first clip streamed from `/media/{token}` (HTTP 206 range requests), the question "Which do you prefer, Sam?" appeared at the clip end, "Trains" led to the second clip, then the comprehension question "What did we talk about?" (answered Trains), then the post clip, the 1–5 comfort scale and the summary.
- Summary: Comprehension 1 answered / 1 correct; Comfort 4; Gaze not evaluable; improvement "Cannot be judged yet"; coverage 16 s, 98 % usable.
- Network: 360 gaze estimates, 16 sample batches, 3 media streams (206), 2 answers; no errors.

## Research Admin
- Protocols tab with versions and Published/Draft; protocol view with comfort scale, progression switches and the stage table (face level, number zone, trials…); Content tab ("Trains talk · Approved · All uploaded"); participant detail with the two assignments (Completed / Ready); session detail with the Improvement block ("Cannot be judged yet" plus the three criteria), practice protocol block, trials, answers and comfort answers.

## Caveats
- The shown number of a trial is not exposed to the accessibility tree, so the scripted driver could not read it; a person reads it on screen. Screen-reader support for the number task is a later accessibility decision.
- Clips were drawn faces, not a real speaker; real content arrives with the AI pipeline in step 5.
- A page reload signs the participant out (memory-only token), as noted in step 1.
