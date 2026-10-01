# Step 7 — backend snapshot (live interactive avatar)

Scope from the design (p. 6, step 7): a streaming avatar with speech recognition and replies limited to the approved topic. The design places it after the pilot with a separate estimate; it was started on request before the pilot, so its rules and limits should be reviewed with the pilot findings. Contract: docs/api/step7-live-avatar.md.

## What exists
- Third practice path `live_conversation` with versioned settings: turn and time limits, reply length, scripted opening, closing, redirect and distress lines, input modes, transcript policy, the avatar's face layout for gaze regions.
- `domain/live.py`: validation, the reply schema, guard rules that replace any reply breaking a rule with a scripted line, storage scrubbing of e-mail, phone and links, the stable system prompt, the delimited conversation block, the conversation outcome. The improvement rule's third criterion for this path is "the conversation held".
- Providers behind ports: replies from the development rules or Claude (`claude-opus-5-5`, effort low, JSON-schema output, cached system prompt, server-side refusal fallback); speech from the development stand-in or a Whisper-compatible HTTP server (local, so audio stays on the computer); the avatar as the development sample video with the browser's voice. No streaming avatar vendor is connected.
- Use cases and endpoints for start, typed and spoken turns (double sends refused), end, participant view, staff view (logged), provider status. Live replies count against the study's AI cost cap. The live monitor, pilot report, participant data download, session outcomes and deletion rules include conversations.
- Text is kept after a conversation only when the protocol and the participant both allow it; audio is never kept.

## Verified
- `python -m pytest -q`: 63 passed (54 earlier + 9 live: protocol rules, guard rules, typed flow and privacy, transcript consent, turn limit and distress, speech turns, Claude request shape, budget and failures, Whisper adapter, deletion).

## Remaining
- No real speech, no real participant, no live Claude call (the request shape was tested with a fake client), no streaming avatar. A vendor for the streaming face and voice is an open decision (cost, data terms, latency, how the face layout is known while the face moves).
- On-topic and distress judgements come from the reply model; the research team should review them before using them as outcomes.
