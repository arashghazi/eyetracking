using System.Globalization;
using System.Numerics;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Infrastructure.Ai;
using EyeTracking.Infrastructure.Live;
using EyeTracking.Web.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Net.Http.Headers;

namespace EyeTracking.Web.Endpoints.Live;

/// <summary>Step 7 endpoints (backend/eyetracking/web/routers/live.py): the live interactive avatar.
/// Staff see the providers, the budget and a conversation's counts (its text only when kept);
/// participants start, talk (typed or recorded speech) and end their session's conversation. The
/// server decides every line the avatar says. A recording is read into memory, transcribed and
/// dropped; it is never written to disk or logged.</summary>
public sealed partial class LiveEndpoints : IEndpointModule
{
    /// <summary>Starlette's limits for a multipart form (MultiPartParser).</summary>
    private const int MaxFieldBytes = 1024 * 1024;
    private const int MaxParts = 1000;

    /// <summary>Live avatar providers from settings (<c>_build_live_providers</c> in web/app.py). The
    /// development ones need no key and cost nothing; real adapters are only used when configured.</summary>
    public static LiveProviders BuildProviders(Settings settings)
    {
        IReplyGenerator reply = settings.LiveReplyProvider == "anthropic"
            ? new AnthropicReplyGenerator(settings.AnthropicApiKey, settings.LiveReplyModel, settings.LiveReplyEffort)
            : new FakeReplyGenerator();
        ISpeechToText stt = settings.SttProvider == "whisper_http"
            ? new WhisperHttpSpeechToText(settings.SttBaseUrl, settings.SttModel, settings.SttApiKey)
            : new FakeSpeechToText();
        if (settings.LiveAvatarProvider != "fake")
            throw new InvalidOperationException(
                $"live_avatar_provider '{settings.LiveAvatarProvider}' is not available; only 'fake' exists until a streaming vendor is chosen");
        return new LiveProviders(reply, stt, new FakeAvatarProvider());
    }

    public void AddServices(IServiceCollection services, Settings settings) => services.AddSingleton(BuildProviders(settings));

    public void Map(IEndpointRouteBuilder app)
    {
        // the development avatar: a generated sample face, no personal data
        app.MapGet("/static/live/sample-face.webm", async (HttpContext ctx) =>
        {
            var data = await File.ReadAllBytesAsync(FakeVideoGenerator.DefaultClip);
            ctx.Response.Headers.CacheControl = "public, max-age=3600";
            return Results.Bytes(data, "video/webm");
        });

        app.MapGet("/studies/{studyId:int}/live/status", (HttpContext ctx, int studyId, IUnitOfWork uow, LiveProviders providers) =>
            Reply.Ok(LiveUseCases.Status(uow, providers, ctx.Principal(), studyId)));

        app.MapGet("/studies/{studyId:int}/sessions/{sessionId:int}/conversation", (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow) =>
            Reply.Ok(LiveUseCases.StaffConversation(uow, ctx.Principal(), studyId, sessionId)));

        app.MapGet("/me/sessions/{sessionId:int}/live", (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
            Reply.Ok(LiveUseCases.MyConversation(uow, ctx.Principal(), sessionId)));

        app.MapPost("/me/sessions/{sessionId:int}/live/start", async (HttpContext ctx, int sessionId, IUnitOfWork uow, IClock clock, LiveProviders providers) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<StartIn>();
            return Reply.Ok(LiveUseCases.Start(uow, providers, clock, principal, sessionId, b.InputMode, b.AllowTranscript, b.TMs));
        });

        app.MapPost("/me/sessions/{sessionId:int}/live/turn", async (HttpContext ctx, int sessionId, IUnitOfWork uow, IClock clock, LiveProviders providers) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<TurnIn>();
            return Reply.Ok(await LiveUseCases.TakeTurn(uow, providers, clock, principal, sessionId, b.ExpectTurn, b.TMs, text: b.Text));
        });

        app.MapPost("/me/sessions/{sessionId:int}/live/turn-audio", async (HttpContext ctx, int sessionId, IUnitOfWork uow, IClock clock, LiveProviders providers) =>
        {
            // FastAPI parses the form before it resolves the user (400 comes before 401), and checks
            // the fields after (422 in the parameters' order)
            var form = await ReadAudioForm(ctx);
            var file = form.GetValueOrDefault("file");
            try
            {
                var principal = ctx.Principal();
                var errors = new List<JsonObject>();
                if (file is null || file is { Data: null, Text: "" })
                    errors.Add(RequestInvalid.Error("missing", "Field required", null, "body", "file"));
                else if (file.Data is null)
                {
                    var e = RequestInvalid.Error("value_error", "Value error, Expected UploadFile, received: <class 'str'>", file.Text, "body", "file");
                    e["ctx"] = new JsonObject { ["error"] = new JsonObject() };
                    errors.Add(e);
                }
                // expect_turn is only compared (any number but the next turn is a 409); t_ms is stored
                var expectTurn = FormInt(form, "expect_turn", errors, required: true, storedAsInt: false);
                var tMs = FormInt(form, "t_ms", errors, required: false, storedAsInt: true);
                RequestInvalid.ThrowIfAny(errors);
                var audio = file!.Data!;
                if (audio.Length > LiveRules.MaxAudioBytes)
                    throw new Invalid("the recording is too long; please say it in a shorter way");
                return Reply.Ok(await LiveUseCases.TakeTurn(
                    uow, providers, clock, principal, sessionId, expectTurn!.Value, tMs is null ? null : (int)tMs, audio: audio, contentType: file.ContentType ?? ""));
            }
            finally
            {
                // whatever the outcome, nothing keeps the recording (or any other uploaded part)
                Wipe(form.Values);
            }
        });

        app.MapPost("/me/sessions/{sessionId:int}/live/end", async (HttpContext ctx, int sessionId, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<EndIn>();
            return Reply.Ok(LiveUseCases.End(uow, clock, principal, sessionId, b.TMs));
        });
    }

    // ---------- the speech turn's form ----------

    /// <summary>One form value as FastAPI receives it: a file (the first MaxAudioBytes + 1 bytes and the
    /// part's content type) or text.</summary>
    private sealed record FormItem(string? Text, byte[]? Data = null, string? ContentType = null);

    /// <summary>The form as Starlette parses it, the last value of a name winning. Multipart parts are
    /// read straight from the request into memory: a file part keeps only what the length check needs,
    /// so nothing of a recording ever reaches a temporary file. Parse errors are 400 with Starlette's
    /// messages; other content types give an empty form.</summary>
    private static async Task<Dictionary<string, FormItem>> ReadAudioForm(HttpContext ctx)
    {
        if (ctx.Features.Get<IHttpMaxRequestBodySizeFeature>() is { IsReadOnly: false } limit)
            limit.MaxRequestBodySize = null;
        var form = new Dictionary<string, FormItem>();
        if (!MediaTypeHeaderValue.TryParse(ctx.Request.ContentType, out var type))
            return form;
        if (type.MediaType.Equals("application/x-www-form-urlencoded", StringComparison.OrdinalIgnoreCase))
        {
            IFormCollection fields;
            try
            {
                fields = await ctx.Request.ReadFormAsync(ctx.RequestAborted);
            }
            catch (InvalidDataException)
            {
                throw new HttpError(400, "There was an error parsing the body");
            }
            foreach (var (name, values) in fields)
                form[name] = new FormItem(values[^1] ?? "");
            return form;
        }
        if (!type.MediaType.Equals("multipart/form-data", StringComparison.OrdinalIgnoreCase))
            return form;
        var boundary = HeaderUtilities.RemoveQuotes(type.Boundary).Value;
        if (string.IsNullOrEmpty(boundary))
            throw new HttpError(400, "Missing boundary in multipart.");
        var charset = type.Charset.HasValue ? type.Charset.Value! : "utf-8";
        var reader = new MultipartReader(boundary, ctx.Request.Body) { BodyLengthLimit = null };
        int files = 0, fieldCount = 0;
        try
        {
            while (await reader.ReadNextSectionAsync(ctx.RequestAborted) is { } section)
            {
                ContentDispositionHeaderValue.TryParse(section.ContentDisposition, out var cd);
                var name = cd is null ? null : HeaderUtilities.RemoveQuotes(cd.Name).Value;
                if (name is null)
                    throw new HttpError(400, "The Content-Disposition header field \"name\" must be provided.");
                if (cd!.FileName.HasValue || cd.FileNameStar.HasValue)
                {
                    if (++files > MaxParts)
                        throw new HttpError(400, $"Too many files. Maximum number of files is {MaxParts}.");
                    var data = await ReadAtMost(section.Body, LiveRules.MaxAudioBytes + 1, failAbove: false, ctx.RequestAborted);
                    if (form.GetValueOrDefault(name) is { } earlier)
                        Wipe([earlier]);
                    form[name] = new FormItem(null, data, section.ContentType);
                }
                else
                {
                    if (++fieldCount > MaxParts)
                        throw new HttpError(400, $"Too many fields. Maximum number of fields is {MaxParts}.");
                    var data = await ReadAtMost(section.Body, MaxFieldBytes, failAbove: true, ctx.RequestAborted);
                    form[name] = new FormItem(Decode(data, charset));
                }
            }
        }
        catch (Exception e)
        {
            Wipe(form.Values);
            if (e is IOException or InvalidDataException)
                throw new HttpError(400, "Invalid multipart data.");
            throw;
        }
        return form;
    }

    /// <summary>Zeroes the bytes of uploaded parts.</summary>
    private static void Wipe(IEnumerable<FormItem> items)
    {
        foreach (var item in items)
        {
            if (item.Data is { } data)
                Array.Clear(data);
        }
    }

    /// <summary>A part's body, kept up to <paramref name="max"/> bytes; the rest is read and dropped
    /// (or, with <paramref name="failAbove"/>, refused as Starlette refuses a large text field).
    /// The working buffers are cleared, so only the returned bytes hold the data.</summary>
    private static async Task<byte[]> ReadAtMost(Stream body, int max, bool failAbove, CancellationToken cancel)
    {
        using var kept = new MemoryStream();
        var chunk = new byte[64 * 1024];
        try
        {
            int n;
            while ((n = await body.ReadAsync(chunk, cancel)) > 0)
            {
                if (failAbove && kept.Length + n > max)
                    throw new HttpError(400, $"Part exceeded maximum size of {max / 1024}KB.");
                var keep = (int)Math.Min(n, max - kept.Length);
                if (keep > 0)
                    kept.Write(chunk, 0, keep);
            }
            return kept.ToArray();
        }
        finally
        {
            Array.Clear(chunk);
            Array.Clear(kept.GetBuffer());
        }
    }

    /// <summary>Starlette's <c>_user_safe_decode</c>: the form's charset, Latin-1 when that fails.</summary>
    private static string Decode(byte[] data, string charset)
    {
        try
        {
            var encoding = (Encoding)Encoding.GetEncoding(charset).Clone();
            encoding.DecoderFallback = DecoderFallback.ExceptionFallback;
            return encoding.GetString(data);
        }
        catch (Exception e) when (e is ArgumentException or DecoderFallbackException)
        {
            return Encoding.Latin1.GetString(data);
        }
    }

    /// <summary>An int form field as FastAPI reads it: an empty text counts as not sent (a required
    /// field is then missing) and text is parsed as pydantic parses it. Python's int is unbounded: a
    /// stored value outside the int columns is refused as in a JSON body; others are clamped to long.</summary>
    private static long? FormInt(Dictionary<string, FormItem> form, string name, List<JsonObject> errors, bool required, bool storedAsInt)
    {
        var item = form.GetValueOrDefault(name);
        if (item is null || item.Text == "")
        {
            if (required)
                errors.Add(RequestInvalid.Error("missing", "Field required", null, "body", name));
            return null;
        }
        if (item.Text is null)
        {
            // an uploaded file where a number is expected
            errors.Add(RequestInvalid.Error("int_type", "Input should be a valid integer", null, "body", name));
            return null;
        }
        var m = PythonIntRegex().Match(item.Text);
        if (!m.Success)
        {
            errors.Add(RequestInvalid.Error("int_parsing", "Input should be a valid integer, unable to parse string as an integer", item.Text, "body", name));
            return null;
        }
        var value = BigInteger.Parse(m.Groups[1].Value.Replace("_", ""), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture);
        if (storedAsInt && (value < int.MinValue || value > int.MaxValue))
        {
            errors.Add(RequestInvalid.Error("type_error", "Input should be a valid value", item.Text, "body", name));
            return null;
        }
        return (long)BigInteger.Clamp(value, long.MinValue, long.MaxValue);
    }

    /// <summary>pydantic's int parsing of text: whitespace around, a sign, ASCII digits with single
    /// underscores between them, and a fraction of zeros.</summary>
    [GeneratedRegex(@"^\s*([+-]?[0-9]+(?:_[0-9]+)*)(?:\.0+)?\s*$")]
    private static partial Regex PythonIntRegex();
}
