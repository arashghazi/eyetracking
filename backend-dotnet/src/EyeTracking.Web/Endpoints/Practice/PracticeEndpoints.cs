using System.Numerics;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Infrastructure;
using EyeTracking.Web.Http;
using Microsoft.AspNetCore.Http.Features;

namespace EyeTracking.Web.Endpoints.Practice;

/// <summary>Step 3 endpoints (backend/eyetracking/web/routers/practice.py): protocols, content and
/// media, assignments, trials, stage results, answers. Media files are private and only reachable
/// through signed, expiring links (<c>/media/{token}</c>, no bearer token).</summary>
public sealed partial class PracticeEndpoints : IEndpointModule
{
    public void AddServices(IServiceCollection services, Settings settings)
    {
        services.AddSingleton<IMediaStore>(new LocalMediaStore(settings.MediaDir));
        services.AddSingleton<IMediaSigner>(new HmacMediaSigner(settings.JwtSecret, settings.MediaUrlTtlSeconds));
    }

    public void Map(IEndpointRouteBuilder app)
    {
        // ---------- protocols ----------

        app.MapGet("/studies/{studyId:int}/protocols", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
            Reply.Ok(PracticeUseCases.ListProtocols(uow, ctx.Principal(), studyId).Select(p => ProtocolOut.From(p, false))));

        app.MapPost("/studies/{studyId:int}/protocols", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<ProtocolIn>();
            return Reply.Created(ProtocolOut.From(PracticeUseCases.CreateProtocol(uow, principal, studyId, body.Name, body.Definition), true));
        });

        app.MapGet("/studies/{studyId:int}/protocols/{protocolId:int}", (HttpContext ctx, int studyId, int protocolId, IUnitOfWork uow) =>
            Reply.Ok(ProtocolOut.From(PracticeUseCases.GetProtocol(uow, ctx.Principal(), studyId, protocolId), true)));

        app.MapPut("/studies/{studyId:int}/protocols/{protocolId:int}", async (HttpContext ctx, int studyId, int protocolId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<ProtocolPatch>();
            return Reply.Ok(ProtocolOut.From(PracticeUseCases.UpdateProtocol(uow, principal, studyId, protocolId, body.Name, body.Definition), true));
        });

        app.MapPost("/studies/{studyId:int}/protocols/{protocolId:int}/publish", (HttpContext ctx, int studyId, int protocolId, IUnitOfWork uow, IClock clock) =>
            Reply.Ok(ProtocolOut.From(PracticeUseCases.PublishProtocol(uow, clock, ctx.Principal(), studyId, protocolId), true)));

        app.MapPost("/studies/{studyId:int}/protocols/{protocolId:int}/new-draft", (HttpContext ctx, int studyId, int protocolId, IUnitOfWork uow) =>
            Reply.Created(ProtocolOut.From(PracticeUseCases.NewDraftFrom(uow, ctx.Principal(), studyId, protocolId), true)));

        // ---------- content and media ----------

        app.MapGet("/studies/{studyId:int}/content", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
            Reply.Ok(PracticeUseCases.ListContent(uow, ctx.Principal(), studyId).Select(x => ContentOut.From(x.Item, x.Missing, false))));

        app.MapPost("/studies/{studyId:int}/content", async (HttpContext ctx, int studyId, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<ContentIn>();
            var c = PracticeUseCases.CreateContent(uow, clock, principal, studyId, b.Title, b.Definition, b.TopicTags, b.FaceId, b.VoiceId);
            return Reply.Created(ContentOut.From(c, PracticeUseCases.MissingMedia(uow, c), true));
        });

        app.MapGet("/studies/{studyId:int}/content/{contentId:int}", (HttpContext ctx, int studyId, int contentId, IUnitOfWork uow) =>
        {
            var (c, missing) = PracticeUseCases.GetContent(uow, ctx.Principal(), studyId, contentId);
            return Reply.Ok(ContentOut.From(c, missing, true));
        });

        app.MapPut("/studies/{studyId:int}/content/{contentId:int}", async (HttpContext ctx, int studyId, int contentId, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<ContentPatch>();
            var c = PracticeUseCases.UpdateContent(uow, clock, principal, studyId, contentId, new ContentChanges(b.Title, b.Definition, b.TopicTags, b.FaceId, b.VoiceId));
            return Reply.Ok(ContentOut.From(c, PracticeUseCases.MissingMedia(uow, c), true));
        });

        app.MapPost("/studies/{studyId:int}/content/{contentId:int}/approve", (HttpContext ctx, int studyId, int contentId, IUnitOfWork uow, IClock clock) =>
            Reply.Ok(ContentOut.From(PracticeUseCases.ApproveContent(uow, clock, ctx.Principal(), studyId, contentId), [], true)));

        app.MapPost("/studies/{studyId:int}/content/{contentId:int}/media/{key}",
            async (HttpContext ctx, int studyId, int contentId, string key, IUnitOfWork uow, IMediaStore store) =>
            {
                var principal = ctx.Principal();
                var file = await UploadedFile(ctx, "file");
                // a file over the limit is read only far enough to know that it is too large
                var data = new byte[Math.Min(file.Length, PracticeRules.MaxMediaBytes + 1L)];
                await using (var input = file.OpenReadStream())
                    await input.ReadExactlyAsync(data, ctx.RequestAborted);
                var m = PracticeUseCases.UploadMedia(uow, store, principal, studyId, contentId, key, file.ContentType ?? "", data);
                return Reply.Created(new JsonObject { ["key"] = m.Key, ["content_type"] = m.ContentType, ["size"] = m.Size });
            });

        app.MapGet("/studies/{studyId:int}/content/{contentId:int}/media", (HttpContext ctx, int studyId, int contentId, IUnitOfWork uow, IMediaSigner signer) =>
            Reply.Ok(PracticeUseCases.ListMedia(uow, signer, ctx.Principal(), studyId, contentId)));

        app.MapGet("/media/{token}", StreamMedia);

        // ---------- assignments ----------

        app.MapGet("/studies/{studyId:int}/participants/{code}/assignments", (HttpContext ctx, int studyId, string code, IUnitOfWork uow) =>
            Reply.Ok(PracticeUseCases.ListAssignments(uow, ctx.Principal(), studyId, code)));

        app.MapPost("/studies/{studyId:int}/participants/{code}/assignments", async (HttpContext ctx, int studyId, string code, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<AssignmentIn>();
            return Reply.Created(PracticeUseCases.CreateAssignment(uow, principal, studyId, code, b.ProtocolId, b.OrderIndex));
        });

        app.MapPut("/studies/{studyId:int}/participants/{code}/assignments/{assignmentId:int}",
            async (HttpContext ctx, int studyId, string code, int assignmentId, IUnitOfWork uow) =>
            {
                var principal = ctx.Principal();
                var b = await ctx.Body<AssignmentPatch>();
                return Reply.Ok(PracticeUseCases.UpdateAssignment(uow, principal, studyId, code, assignmentId, b.ContentId, b.Status));
            });

        app.MapGet("/me/assignments", (HttpContext ctx, IUnitOfWork uow) =>
            Reply.Ok(PracticeUseCases.MyAssignments(uow, ctx.Principal())));

        app.MapPost("/me/assignments/{assignmentId:int}/topic", async (HttpContext ctx, int assignmentId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<TopicIn>();
            return Reply.Ok(PracticeUseCases.ConfirmTopic(uow, principal, assignmentId, b.Topic, b.FreeText));
        });

        app.MapGet("/me/assignments/{assignmentId:int}/content", (HttpContext ctx, int assignmentId, IUnitOfWork uow, IMediaSigner signer) =>
            Reply.Ok(PracticeUseCases.MyAssignmentContent(uow, signer, ctx.Principal(), assignmentId)));

        // ---------- practice recording ----------

        app.MapPost("/me/sessions/{sessionId:int}/trials", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<TrialsIn>();
            var (stored, correct) = PracticeUseCases.AddTrials(uow, principal, sessionId, b.Trials);
            return Reply.Ok(new JsonObject { ["stored"] = stored, ["correct"] = correct });
        });

        app.MapPost("/me/sessions/{sessionId:int}/stage-result", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<StageResultIn>();
            var r = PracticeUseCases.SubmitStageResult(uow, principal, sessionId, b.StageIndex, b.ComfortValue);
            return Reply.Ok(new StageResultOut(r.Decision, r.NextStageIndex, r.Reason, r.CorrectRatio, r.InvalidShare, r.Trials));
        });

        app.MapPost("/me/sessions/{sessionId:int}/answers", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<AnswerIn>();
            var a = PracticeUseCases.SubmitAnswer(uow, principal, sessionId, b.SegmentId, b.QuestionId, b.Kind, b.Option, b.TMs);
            return Reply.Ok(new AnswerOut(a.Correct, a.NextSegmentId));
        });
    }

    /// <summary>FastAPI's <c>UploadFile = File(...)</c>: the multipart part, 422 when it is missing.
    /// Like Starlette, any upload size is read; the use case refuses media over 200 MB.</summary>
    private static async Task<IFormFile> UploadedFile(HttpContext ctx, string field)
    {
        if (ctx.Features.Get<IHttpMaxRequestBodySizeFeature>() is { IsReadOnly: false } limit)
            limit.MaxRequestBodySize = null;
        IFormFile? file = null;
        if (ctx.Request.HasFormContentType)
        {
            ctx.Features.Set<IFormFeature>(new FormFeature(ctx.Request, new FormOptions { MultipartBodyLengthLimit = long.MaxValue }));
            file = (await ctx.Request.ReadFormAsync(ctx.RequestAborted)).Files.GetFile(field);
        }
        return file ?? throw RequestInvalid.Single("missing", "Field required", null, "body", field);
    }

    /// <summary>Streams a media file from its signed link, with single byte ranges (206/416) as the
    /// Python router parses them.</summary>
    private static async Task<IResult> StreamMedia(HttpContext ctx, string token, IUnitOfWork uow, IMediaSigner signer, IMediaStore store)
    {
        var m = PracticeUseCases.ResolveMedia(uow, signer, token);
        var path = store.Absolute(m.Path);
        if (!File.Exists(path))
            throw new Invalid("media file is missing on disk");
        var size = new FileInfo(path).Length;
        long start = 0, end = size - 1;
        var status = 200;
        var range = ctx.Request.Headers.Range.FirstOrDefault();
        if (!string.IsNullOrEmpty(range) && range.StartsWith("bytes=", StringComparison.Ordinal))
        {
            var spec = range[6..].Split(',')[0].Trim();
            var dash = spec.IndexOf('-');
            var (a, b) = dash < 0 ? (spec, "") : (spec[..dash], spec[(dash + 1)..]);
            // int() failing anywhere falls back to the whole file
            long? first = PyInt(a), last = PyInt(b);
            if (a.Length > 0 && first is not null && (b.Length == 0 || last is not null))
                (start, end) = (first.Value, b.Length > 0 ? last!.Value : size - 1);
            else if (a.Length == 0 && last is not null)
                start = Math.Max(0, size - last.Value);
            end = Math.Min(end, size - 1);
            if (start > end || start >= size)
            {
                ctx.Response.StatusCode = 416;
                ctx.Response.Headers.ContentRange = $"bytes */{size}";
                ctx.Response.ContentLength = 0;
                return Results.Empty;
            }
            status = 206;
        }
        var length = end - start + 1;
        ctx.Response.StatusCode = status;
        ctx.Response.ContentType = m.ContentType;
        ctx.Response.ContentLength = length;
        ctx.Response.Headers.AcceptRanges = "bytes";
        ctx.Response.Headers.CacheControl = "private, max-age=3600";
        if (status == 206)
            ctx.Response.Headers.ContentRange = $"bytes {start}-{end}/{size}";
        await using var fh = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, useAsync: true);
        fh.Seek(start, SeekOrigin.Begin);
        var buffer = new byte[256 * 1024];
        var remaining = length;
        while (remaining > 0)
        {
            var n = await fh.ReadAsync(buffer.AsMemory(0, (int)Math.Min(buffer.Length, remaining)), ctx.RequestAborted);
            if (n == 0)
                break;
            remaining -= n;
            await ctx.Response.Body.WriteAsync(buffer.AsMemory(0, n), ctx.RequestAborted);
        }
        return Results.Empty;
    }

    /// <summary>Python's <c>int(text)</c> (whitespace, sign, digit groups with underscores), kept
    /// within ±2^62 so the range arithmetic cannot overflow; null where int() raises.</summary>
    private static long? PyInt(string text)
    {
        var m = PyIntRegex().Match(text);
        if (!m.Success)
            return null;
        var value = BigInteger.Zero;
        foreach (var c in m.Groups[2].Value)
        {
            if (c != '_')
                value = value * 10 + (int)char.GetNumericValue(c);
        }
        if (m.Groups[1].Value == "-")
            value = -value;
        return (long)BigInteger.Clamp(value, -(1L << 62), 1L << 62);
    }

    [GeneratedRegex(@"^\s*([+-]?)(\d+(?:_\d+)*)\s*$")]
    private static partial Regex PyIntRegex();
}
