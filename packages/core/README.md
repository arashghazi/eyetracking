# eyetracking_core

Shared package for the Participant App and the Research Admin: theme, `ApiClient`
(http + bearer token), in-memory `TokenStore`, `ApiException`, wire models and a
few small shared widgets. Step 2 adds the session wire models, `GazeServiceClient`
(`GAZE_BASE_URL`, `GAZE_MODE=local|server`) and the `FrameSource` camera port with
`WebFrameSource` (conditional import; the non-web stub throws `UnsupportedError`).
`package:eyetracking_core/testing.dart` has `FakeFrameSource` and `FakeGazeEstimator`.
Third-party dependencies: `http`, and `web` for browser camera access.
