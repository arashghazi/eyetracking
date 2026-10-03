using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Measurement;

/// <summary>Step 2 endpoints (backend/eyetracking/web/routers/sessions.py): measurement settings,
/// sessions, calibration, validation, samples, events.</summary>
public sealed class SessionEndpoints : IEndpointModule
{
    private static List<CalibrationTarget> Targets(CalibrationIn body) =>
        body.Targets.Select(t => new CalibrationTarget(t.X, t.Y, t.Samples)).ToList();

    private static List<ValidationTarget> Targets(ValidationIn body) =>
        body.Targets.Select(t => new ValidationTarget(t.Region, t.X, t.Y, t.Samples)).ToList();

    public void Map(IEndpointRouteBuilder app)
    {
        // ---------- participant ----------

        app.MapGet("/me/measurement-settings", (HttpContext ctx, IUnitOfWork uow) =>
            Reply.Ok(SettingsOut.From(MeasurementUseCases.MySettings(uow, ctx.Principal()))));

        app.MapGet("/me/sessions", (HttpContext ctx, IUnitOfWork uow) =>
            Reply.Ok(MeasurementUseCases.MySessions(uow, ctx.Principal())));

        app.MapPost("/me/sessions", async (HttpContext ctx, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<SessionCreateIn>();
            var s = MeasurementUseCases.CreateSession(uow, principal, body.Device, body.Screen, body.Camera, body.GazeModel, body.AssignmentId);
            return Reply.Created(MeasurementUseCases.Summarize(uow, s));
        });

        app.MapGet("/me/sessions/{sessionId:int}", (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
            Reply.Ok(MeasurementUseCases.MySession(uow, ctx.Principal(), sessionId)));

        app.MapPost("/me/sessions/{sessionId:int}/camera-check", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<CameraCheckIn>();
            var s = MeasurementUseCases.CameraCheck(uow, principal, sessionId, b.FaceDetected, b.FaceConf, b.LightingOk, b.FrameW, b.FrameH, b.CameraLabel);
            return Reply.Ok(MeasurementUseCases.Summarize(uow, s));
        });

        app.MapPost("/me/sessions/{sessionId:int}/calibration", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<CalibrationIn>();
            var c = MeasurementUseCases.SubmitCalibration(uow, principal, sessionId, Targets(body));
            return Reply.Ok(new CalibrationOut(
                c.Id, PyMath.Round(c.ResidualPxMedian, 2), PyMath.Round(c.ResidualPxP90, 2), Json.CloneArr(c.PerTarget), c.Accepted, []));
        });

        app.MapPost("/me/sessions/{sessionId:int}/validation", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<ValidationIn>();
            var v = MeasurementUseCases.SubmitValidation(uow, principal, sessionId, body.Layout, Targets(body));
            return Reply.Ok(new ValidationOut(v.Id, v.Passed, v.CorrectRatio, v.UncertainRatio, v.SizeRatio, [.. v.Reasons], Json.CloneArr(v.Targets)));
        });

        app.MapPost("/me/sessions/{sessionId:int}/layout", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<LayoutIn>();
            var l = MeasurementUseCases.SetLayout(uow, principal, sessionId, body.Segment, body.Layout, body.StageIndex);
            return Reply.Ok(new JsonObject { ["layout_id"] = l.Id });
        });

        app.MapPost("/me/sessions/{sessionId:int}/samples", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<SamplesIn>();
            var (stored, invalid) = MeasurementUseCases.AddSamples(uow, principal, sessionId, body.Samples);
            return Reply.Ok(new JsonObject { ["stored"] = stored, ["invalid"] = invalid });
        });

        app.MapPost("/me/sessions/{sessionId:int}/events", async (HttpContext ctx, int sessionId, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<EventIn>();
            var s = MeasurementUseCases.AddEvent(uow, clock, principal, sessionId, body.TMs, body.Type, body.Payload);
            return Reply.Ok(MeasurementUseCases.Summarize(uow, s));
        });

        // ---------- research admin ----------

        app.MapGet("/studies/{studyId:int}/measurement-settings", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
            Reply.Ok(SettingsOut.From(MeasurementUseCases.GetStudySettings(uow, ctx.Principal(), studyId))));

        app.MapPut("/studies/{studyId:int}/measurement-settings", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<SettingsIn>();
            var changes = new SettingsChanges(
                b.ValidationMinCorrect, b.ValidationMaxUncertain, b.MinRegionToErrorRatio, b.GazeConfThreshold, b.CalibrationPoints,
                b.AllowContinueWithoutValidation, b.QualityMaxUncertainShare, b.QualityMaxMissingShare);
            return Reply.Ok(SettingsOut.From(MeasurementUseCases.UpdateStudySettings(uow, principal, studyId, b.Rationale, changes)));
        });

        app.MapGet("/studies/{studyId:int}/measurement-settings/history", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
            Reply.Ok(MeasurementUseCases.SettingsHistory(uow, ctx.Principal(), studyId)));

        app.MapGet("/studies/{studyId:int}/sessions", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
            Reply.Ok(MeasurementUseCases.ListStudySessions(uow, ctx.Principal(), studyId)));

        app.MapGet("/studies/{studyId:int}/sessions/{sessionId:int}", (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow) =>
            Reply.Ok(MeasurementUseCases.GetStudySession(uow, ctx.Principal(), studyId, sessionId)));

        app.MapGet("/studies/{studyId:int}/sessions/{sessionId:int}/samples", (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            var offset = ctx.QueryInt("offset", 0, errors, ge: 0);
            var limit = ctx.QueryInt("limit", 2000, errors, ge: 1, le: 5000);
            RequestInvalid.ThrowIfAny(errors);
            var (total, items) = MeasurementUseCases.StudySessionSamples(
                uow, principal, studyId, sessionId, (int)Math.Min(offset, int.MaxValue), (int)limit);
            return Reply.Ok(new SamplesPage(total, items));
        });
    }
}
