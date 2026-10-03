using System.Text.Json.Nodes;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Research;

// HTTP shapes of build step 4 (the pydantic models in backend/eyetracking/web/routers/research.py).
// The research responses themselves are free-form JSON built by the use cases.

public sealed record EraseIn(string Confirm);

public sealed record DeleteDataIn(string Confirm);

public sealed record StudyPatch(string? RetentionPolicy = null) : IValidatedBody
{
    public void Validate(List<JsonObject> errors) => Check.Literal(errors, RetentionPolicy, "retention_policy", "delete_all", "keep_coded");
}
