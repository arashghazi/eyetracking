using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Infrastructure.Ai;
using EyeTracking.Web.Endpoints.Practice;
using EyeTracking.Web.Http;

namespace EyeTracking.Web.Endpoints.Ai;

/// <summary>Step 5 endpoints (backend/eyetracking/web/routers/ai.py): AI status and budget, text and
/// video jobs, the review flow and running queued jobs. Provider keys stay on the server.</summary>
public sealed class AiEndpoints : IEndpointModule
{
    /// <summary>Providers from settings (<c>_build_ai_providers</c> in web/app.py); the fake ones need
    /// no key. Real adapters are only used when configured.</summary>
    public static AiProviders BuildProviders(Settings settings)
    {
        ITextGenerator text = settings.AiTextProvider == "anthropic"
            ? new AnthropicTextGenerator(settings.AnthropicApiKey, settings.AiTextModel)
            : new FakeTextGenerator();
        IVideoGenerator video = settings.AiVideoProvider == "heygen"
            ? new HeyGenVideoGenerator(settings.HeygenApiKey, settings.HeygenBaseUrl, settings.HeygenCostPerMinuteUnits)
            : new FakeVideoGenerator();
        return new AiProviders(text, video, settings.AiWorkerEnabled, settings.AiWorkerIntervalS);
    }

    public void AddServices(IServiceCollection services, Settings settings)
    {
        services.AddSingleton(BuildProviders(settings));
        if (settings.AiWorkerEnabled)
        {
            services.AddSingleton(sp => ActivatorUtilities.CreateInstance<AiWorker>(sp, settings.AiWorkerIntervalS));
            services.AddHostedService(sp => sp.GetRequiredService<AiWorker>());
        }
    }

    public void Map(IEndpointRouteBuilder app)
    {
        app.MapGet("/studies/{studyId:int}/ai/status", (HttpContext ctx, int studyId, IUnitOfWork uow, AiProviders providers) =>
            Reply.Ok(AiUseCases.Status(uow, providers, ctx.Principal(), studyId)));

        app.MapPut("/studies/{studyId:int}/ai/budget", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<BudgetIn>();
            return Reply.Ok(AiUseCases.SetBudget(uow, principal, studyId, b.CostCapUnits, b.SendFreeText));
        });

        app.MapPost("/studies/{studyId:int}/ai/text-jobs", async (HttpContext ctx, int studyId, IUnitOfWork uow, AiProviders providers, IClock clock) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<TextJobIn>();
            return Reply.Created(AiUseCases.CreateTextJob(
                uow, providers, clock, principal, studyId, b.AssignmentId, b.Topic, b.DisplayName, b.Interests, b.InteractionPoints, b.LengthSeconds,
                b.Title, b.FaceId, b.VoiceId));
        });

        app.MapPost("/studies/{studyId:int}/ai/video-jobs", async (HttpContext ctx, int studyId, IUnitOfWork uow, AiProviders providers, IClock clock) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<VideoJobsIn>();
            return Reply.Created(AiUseCases.CreateVideoJobs(uow, providers, clock, principal, studyId, b.ContentId, b.SegmentIds, b.FaceId, b.VoiceId));
        });

        app.MapGet("/studies/{studyId:int}/ai/jobs", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            long? contentId = ctx.Request.Query["content_id"].Count > 0 ? ctx.QueryInt("content_id", 0, errors) : null;
            RequestInvalid.ThrowIfAny(errors);
            return Reply.Ok(AiUseCases.ListJobs(uow, principal, studyId, ctx.QueryStr("status"), contentId));
        });

        app.MapGet("/studies/{studyId:int}/ai/jobs/{jobId:int}", (HttpContext ctx, int studyId, int jobId, IUnitOfWork uow) =>
            Reply.Ok(AiUseCases.GetJob(uow, ctx.Principal(), studyId, jobId)));

        app.MapPost("/studies/{studyId:int}/ai/jobs/{jobId:int}/cancel", (HttpContext ctx, int studyId, int jobId, IUnitOfWork uow) =>
            Reply.Ok(AiUseCases.CancelJob(uow, ctx.Principal(), studyId, jobId)));

        app.MapPost("/studies/{studyId:int}/ai/jobs/{jobId:int}/retry", (HttpContext ctx, int studyId, int jobId, IUnitOfWork uow, IClock clock) =>
            Reply.Ok(AiUseCases.RetryJob(uow, clock, ctx.Principal(), studyId, jobId)));

        app.MapPost("/studies/{studyId:int}/ai/run",
            async (HttpContext ctx, int studyId, IUnitOfWork uow, AiProviders providers, IMediaStore store, IClock clock) =>
            {
                var principal = ctx.Principal();
                var errors = new List<JsonObject>();
                var maxJobs = ctx.QueryInt("max_jobs", 5, errors, ge: 1, le: 50);
                RequestInvalid.ThrowIfAny(errors);
                return Reply.Ok(await AiUseCases.RunJobs(uow, providers, store, clock, (int)maxJobs, principal, studyId));
            });

        app.MapPost("/studies/{studyId:int}/content/{contentId:int}/text-reviewed", (HttpContext ctx, int studyId, int contentId, IUnitOfWork uow, IClock clock) =>
        {
            var c = AiUseCases.MarkTextReviewed(uow, clock, ctx.Principal(), studyId, contentId);
            return Reply.Ok(ContentOut.From(c, PracticeUseCases.MissingMedia(uow, c), true));
        });
    }
}
