namespace EyeTracking.Web.Endpoints.Live;

// HTTP shapes of build step 7 (the pydantic models in backend/eyetracking/web/routers/live.py).
// The responses are free-form JSON built by the use cases; a speech turn is a multipart form
// (see LiveEndpoints.ReadAudioForm).

public sealed record StartIn(string InputMode = "typed", bool AllowTranscript = false, int? TMs = null);

public sealed record TurnIn(int ExpectTurn, string Text, int? TMs = null);

public sealed record EndIn(int? TMs = null);
