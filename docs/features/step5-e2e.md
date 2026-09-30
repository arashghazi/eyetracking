# Step 5 — browser verification record (2026-09-30)

Same setup as steps 2–4 (headless Chromium, scratch SQLite, gaze service in `e2e-fake` mode, admin web build served on :5173, API on :8765). Providers: the development fakes (`fake-text` / `fake-video`, no keys, cost 0). Seed: the step-3 seed plus P-001 confirming the interest topic "Trains" through the participant API, so the interest assignment waits for content (`content_pending`). Screenshots: `docs/features/screenshots/step5-*.png`.

## Research Admin, signed in as the researcher
1. **AI tab** (`step5-admin-ai-tab`): "Providers and budget" shows both fake providers as Configured with the "Development provider — sample content" badge, the worker off with the hint to use "Run queued jobs now", cap / spent / remaining 0.00 and the note that nothing runs on a paid provider until an administrator sets a cap. "Edit cap" is not offered to the researcher.
2. **Text job** (`step5-admin-ai-text-job-queued`): "For an assignment" → participant code P-001 → "Find assignments" lists only "#2 Interest conversation (short), content being prepared, topic: Trains". "Generate text" → banner "Text job 1 queued. It creates a draft content item that you review before anything reaches a participant." `POST /studies/1/ai/text-jobs` 201.
3. **Run** (`step5-admin-ai-jobs-succeeded`): "Run queued jobs now" → "Processed 1 job: 1 succeeded, 0 failed." The jobs table row reads Text · Succeeded · fake-text · "AI draft: Trains" · cost 0 / 30.00 estimate · Open content. `POST /studies/1/ai/run` 200.
4. **Draft** (`step5-admin-ai-content-draft`): "Open content" lands in the editor of "AI draft: Trains": status Draft, "Text reviewed: no", three segments s1–s3 with the sample mark in the text, media keys s1.webm–s3.webm all Missing, and the video section disabled until the text is reviewed.
5. **Review and videos** (`step5-admin-ai-video-jobs`): "Mark text reviewed" → banner "Text marked as reviewed. Videos can be generated now." (`POST …/text-reviewed` 200). "Generate videos" with the three segment checkboxes → "3 video jobs created", Job 2 s1, Job 3 s2, Job 4 s3, all Queued (`POST /studies/1/ai/video-jobs` 201).
6. **All done** (`step5-admin-ai-all-done`): back on the AI tab, "Run queued jobs now" processed the three video jobs; the table shows four Succeeded rows (three Video, one Text). Through the API afterwards: `GET /studies/1/content/2/media` lists s1.webm, s2.webm, s3.webm (video/webm, 17 359 bytes each, signed URLs), files stored under `media/study-1/content-2/`, the content is still a draft with `text_reviewed = true` and nothing attached to the assignment.

No browser console errors. API calls in the run: 5× status, 5× jobs, 1× text job, 3× run, 1× content detail, 1× text-reviewed, 1× video jobs.

## Caveats
- The whole run used the development providers; no Anthropic or HeyGen call was made, so the sample text and the 17 KB sample face stand in for real output. Cost stays 0 and the cap was never exercised in the browser (covered by backend and widget tests only).
- The last "Run queued jobs now" was clicked twice by the driver; the second click reports "Processed 0 jobs", which is correct.
- Approval and attachment of the generated content to the assignment were not part of this run (that is the step-3 flow).
