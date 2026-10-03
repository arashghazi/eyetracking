using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Research;

/// <summary>Step 4 endpoints (backend/eyetracking/web/routers/research.py): replay, analysis,
/// exports, data dictionary, access log, the participant's raw data, deletion and the study's
/// retention policy. Access checks and access-log entries are in the use cases.</summary>
public sealed class ResearchEndpoints : IEndpointModule
{
    /// <summary>The analysis filters from the query string (FastAPI's query parameters; <c>from</c>
    /// is a keyword in Python, hence its alias). Problems are added to <paramref name="errors"/>.</summary>
    private static AnalysisFilters Filters(HttpContext ctx, List<JsonObject> errors) => new(
        ctx.QueryStr("participant"), ctx.QueryStr("path"), ctx.QueryStr("protocol_version"), ctx.QueryStr("device"),
        ctx.QueryStr("from"), ctx.QueryStr("to"), ctx.QueryStr("quality"), ctx.QueryBool("include_synthetic", false, errors));

    /// <summary>A download as Starlette's Response sends it: text types get <c>; charset=utf-8</c>,
    /// the name goes in a quoted <c>Content-Disposition</c> filename.</summary>
    private static IResult Download(HttpContext ctx, ExportFile file)
    {
        ctx.Response.Headers.ContentDisposition = $"attachment; filename=\"{file.Name}\"";
        var type = file.MediaType.StartsWith("text/", StringComparison.Ordinal) ? file.MediaType + "; charset=utf-8" : file.MediaType;
        return Results.Bytes(file.Data, type);
    }

    public void Map(IEndpointRouteBuilder app)
    {
        app.MapGet("/studies/{studyId:int}/sessions/{sessionId:int}/replay", (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow, IMediaSigner signer) =>
            Reply.Ok(ResearchUseCases.Replay(uow, signer, ctx.Principal(), studyId, sessionId)));

        app.MapGet("/studies/{studyId:int}/analysis", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            var filters = Filters(ctx, errors);
            RequestInvalid.ThrowIfAny(errors);
            return Reply.Ok(ResearchUseCases.Analysis(uow, principal, studyId, filters));
        });

        app.MapGet("/studies/{studyId:int}/exports/sessions.{fmt}", (HttpContext ctx, int studyId, string fmt, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            Check.LiteralAt(errors, fmt, ["path", "fmt"], "csv", "json");
            var filters = Filters(ctx, errors);
            RequestInvalid.ThrowIfAny(errors);
            return Download(ctx, ResearchUseCases.ExportSessions(uow, principal, studyId, filters, fmt));
        });

        app.MapGet("/studies/{studyId:int}/exports/samples.csv", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            var sessionId = ctx.QueryInt("session_id", errors);
            RequestInvalid.ThrowIfAny(errors);
            return Download(ctx, ResearchUseCases.ExportSamples(uow, principal, studyId, SessionIdOf(sessionId)));
        });

        app.MapGet("/studies/{studyId:int}/exports/events.csv", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            var sessionId = ctx.QueryInt("session_id", errors);
            RequestInvalid.ThrowIfAny(errors);
            return Download(ctx, ResearchUseCases.ExportEvents(uow, principal, studyId, SessionIdOf(sessionId)));
        });

        app.MapGet("/studies/{studyId:int}/exports/data-dictionary.json", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            ResearchUseCases.GetStudy(uow, ctx.Principal(), studyId);
            return Reply.Ok(new JsonObject { ["export_version"] = ResearchRules.ExportVersion, ["fields"] = ResearchUseCases.DataDictionary() });
        });

        app.MapGet("/studies/{studyId:int}/access-log", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            var limit = ctx.QueryInt("limit", 200, errors, ge: 1, le: 1000);
            RequestInvalid.ThrowIfAny(errors);
            return Reply.Ok(ResearchUseCases.AccessLog(uow, principal, studyId, (int)limit));
        });

        app.MapGet("/studies/{studyId:int}", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
            Reply.Ok(ResearchUseCases.GetStudy(uow, ctx.Principal(), studyId)));

        app.MapPut("/studies/{studyId:int}", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<StudyPatch>();
            return Reply.Ok(ResearchUseCases.UpdateStudy(uow, principal, studyId, body.RetentionPolicy));
        });

        app.MapDelete("/studies/{studyId:int}/participants/{code}/data", async (HttpContext ctx, int studyId, string code, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<DeleteDataIn>();
            return Reply.Ok(ResearchUseCases.DeleteParticipantData(uow, principal, studyId, code, body.Confirm));
        });

        app.MapGet("/me/data", (HttpContext ctx, IUnitOfWork uow) =>
            Reply.Ok(ResearchUseCases.MyFullData(uow, ctx.Principal())));

        app.MapPost("/me/erase", async (HttpContext ctx, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<EraseIn>();
            return Reply.Ok(ResearchUseCases.EraseMe(uow, clock, principal, body.Confirm));
        });
    }

    /// <summary>A session id from the query: Python's int is unbounded, and an id no session has is
    /// simply not found.</summary>
    private static int SessionIdOf(long id) => id is < int.MinValue or > int.MaxValue ? 0 : (int)id;
}
