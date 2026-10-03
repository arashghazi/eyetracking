using System.Globalization;
using System.Numerics;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Web.Http;
using Microsoft.AspNetCore.Http.Features;

namespace EyeTracking.Web.Endpoints.Pilot;

/// <summary>Step 6 endpoints (backend/eyetracking/web/routers/pilot.py): supervised pilot
/// (observations, live monitor, debrief, threshold review, research-tracker comparison, pilot
/// report). Access checks and access-log entries are in the use cases.</summary>
public sealed partial class PilotEndpoints : IEndpointModule
{
    public const int MaxReferenceBytes = 150 * 1024 * 1024;

    public void Map(IEndpointRouteBuilder app)
    {
        // ---------- observations ----------

        app.MapGet("/studies/{studyId:int}/sessions/{sessionId:int}/observations", (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow) =>
            Reply.Ok(PilotUseCases.ListObservations(uow, ctx.Principal(), studyId, sessionId)));

        app.MapPost("/studies/{studyId:int}/sessions/{sessionId:int}/observations", async (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<ObservationIn>();
            return Reply.Created(PilotUseCases.AddObservation(uow, principal, studyId, sessionId, b.Category, b.Severity, b.Text, b.TMs));
        });

        // ---------- live monitor ----------

        app.MapGet("/studies/{studyId:int}/pilot/active", (HttpContext ctx, int studyId, IUnitOfWork uow, IClock clock) =>
            Reply.Ok(PilotUseCases.ActiveSessions(uow, clock, ctx.Principal(), studyId)));

        app.MapGet("/studies/{studyId:int}/sessions/{sessionId:int}/live", (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            var first = ctx.QueryBool("first", false, errors);
            RequestInvalid.ThrowIfAny(errors);
            return Reply.Ok(PilotUseCases.LiveStatus(uow, clock, principal, studyId, sessionId, first));
        });

        // ---------- debrief ----------

        app.MapGet("/studies/{studyId:int}/debrief-form", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
            Reply.Ok(PilotUseCases.GetDebriefForm(uow, ctx.Principal(), studyId)));

        app.MapPut("/studies/{studyId:int}/debrief-form", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<DebriefFormIn>();
            return Reply.Ok(PilotUseCases.PutDebriefForm(uow, principal, studyId, (JsonArray?)b.Questions, b.Enabled));
        });

        app.MapGet("/me/sessions/{sessionId:int}/debrief", (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
            Reply.Ok(PilotUseCases.MyDebrief(uow, ctx.Principal(), sessionId)));

        app.MapPost("/me/sessions/{sessionId:int}/debrief", async (HttpContext ctx, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<DebriefAnswerIn>();
            return Reply.Created(PilotUseCases.SubmitDebrief(uow, principal, sessionId, b.FormVersion, (JsonObject)b.Answers!, b.Skipped));
        });

        // ---------- threshold review ----------

        app.MapPost("/studies/{studyId:int}/pilot/threshold-review", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<ThresholdReviewIn>();
            return Reply.Ok(PilotUseCases.ThresholdReview(uow, principal, studyId, (JsonObject)b.Changes!, b.IncludeSynthetic));
        });

        // ---------- research eye tracker ----------

        app.MapGet("/studies/{studyId:int}/sessions/{sessionId:int}/reference", (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow) =>
            Reply.Ok(PilotUseCases.ListReferences(uow, ctx.Principal(), studyId, sessionId)));

        app.MapPost("/studies/{studyId:int}/sessions/{sessionId:int}/reference", async (HttpContext ctx, int studyId, int sessionId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var form = await ImportForm(ctx);
            // a file over the limit is read only far enough to know that it is too large
            var data = new byte[Math.Min(form.File.Length, MaxReferenceBytes + 1L)];
            await using (var input = form.File.OpenReadStream())
                await input.ReadExactlyAsync(data, ctx.RequestAborted);
            if (data.Length > MaxReferenceBytes)
                throw new Invalid("the file is larger than 150 MB");
            return Reply.Created(PilotUseCases.ImportReference(uow, principal, studyId, sessionId, form.Source, form.Options, form.AutoAlignWindowMs, data));
        });

        app.MapGet("/studies/{studyId:int}/sessions/{sessionId:int}/reference/{recordingId:int}/compare",
            (HttpContext ctx, int studyId, int sessionId, int recordingId, IUnitOfWork uow) =>
            {
                var principal = ctx.Principal();
                var errors = new List<JsonObject>();
                var tolerance = ctx.QueryInt("tolerance_ms", 40, errors);
                RequestInvalid.ThrowIfAny(errors);
                return Reply.Ok(PilotUseCases.CompareReference(uow, principal, studyId, sessionId, recordingId, tolerance));
            });

        // ---------- pilot report ----------

        app.MapGet("/studies/{studyId:int}/pilot/report", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            var includeSynthetic = ctx.QueryBool("include_synthetic", false, errors);
            RequestInvalid.ThrowIfAny(errors);
            return Reply.Ok(PilotUseCases.PilotReport(uow, principal, studyId, includeSynthetic));
        });

        app.MapGet("/studies/{studyId:int}/pilot/report.csv", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var errors = new List<JsonObject>();
            var includeSynthetic = ctx.QueryBool("include_synthetic", false, errors);
            RequestInvalid.ThrowIfAny(errors);
            var file = PilotUseCases.ExportPilotCsv(uow, principal, studyId, includeSynthetic);
            // Starlette adds a charset to text types only when the media type has none
            ctx.Response.Headers.ContentDisposition = $"attachment; filename=\"{file.Name}\"";
            var type = file.MediaType.StartsWith("text/", StringComparison.Ordinal) && !file.MediaType.Contains("charset=", StringComparison.OrdinalIgnoreCase)
                ? file.MediaType + "; charset=utf-8"
                : file.MediaType;
            return Results.Bytes(file.Data, type);
        });
    }

    private sealed record ImportFormData(IFormFile File, string Source, ReferenceImportOptions Options, long AutoAlignWindowMs);

    /// <summary>The import form as FastAPI reads its <c>File(...)</c> and <c>Form(...)</c> parameters:
    /// an empty text counts as not sent (required fields are then missing, optional ones take their
    /// default), numbers are parsed as pydantic parses text, and every problem is reported at once
    /// in the parameters' order. Like Starlette, any upload size is read; the limit is checked after.</summary>
    private static async Task<ImportFormData> ImportForm(HttpContext ctx)
    {
        if (ctx.Features.Get<IHttpMaxRequestBodySizeFeature>() is { IsReadOnly: false } limit)
            limit.MaxRequestBodySize = null;
        IFormCollection form = FormCollection.Empty;
        if (ctx.Request.HasFormContentType)
        {
            ctx.Features.Set<IFormFeature>(new FormFeature(ctx.Request, new FormOptions { MultipartBodyLengthLimit = long.MaxValue }));
            form = await ctx.Request.ReadFormAsync(ctx.RequestAborted);
        }
        var errors = new List<JsonObject>();
        static JsonObject Missing(string name) => RequestInvalid.Error("missing", "Field required", null, "body", name);
        string? Value(string name)
        {
            var values = form[name];
            return values.Count == 0 || string.IsNullOrEmpty(values[^1]) ? null : values[^1];
        }
        string Required(string name)
        {
            var v = Value(name);
            if (v is null)
                errors.Add(Missing(name));
            return v ?? "";
        }
        double Float(string name, double @default)
        {
            var v = Value(name);
            if (v is null)
                return @default;
            var f = PydanticFloat(v);
            if (f is null)
                errors.Add(RequestInvalid.Error("float_parsing", "Input should be a valid number, unable to parse string as a number", v, "body", name));
            return f ?? @default;
        }
        long Int(string name, long @default)
        {
            var v = Value(name);
            if (v is null)
                return @default;
            var m = PythonIntRegex().Match(v);
            if (!m.Success)
            {
                errors.Add(RequestInvalid.Error("int_parsing", "Input should be a valid integer, unable to parse string as an integer", v, "body", name));
                return @default;
            }
            // Python's int is unbounded; anything past the long range is out of every allowed range anyway
            var big = BigInteger.Parse(m.Groups[1].Value.Replace("_", ""), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture);
            return (long)BigInteger.Clamp(big, long.MinValue, long.MaxValue);
        }

        var files = form.Files.GetFiles("file");
        var file = files.Count > 0 ? files[^1] : null;
        if (file is null)
            errors.Add(Missing("file"));
        var source = Required("source");
        var options = new ReferenceImportOptions(
            Required("time_column"), Required("x_column"), Required("y_column"), Value("valid_column"), Value("valid_values"),
            Value("time_unit") ?? "ms", Float("offset", 0.0), Value("coord_space") ?? "css_px", Float("origin_x", 0.0), Float("origin_y", 0.0),
            Value("delimiter"));
        var autoAlign = Int("auto_align_window_ms", 0);
        RequestInvalid.ThrowIfAny(errors);
        return new ImportFormData(file!, source, options, autoAlign);
    }

    /// <summary>pydantic's float parsing of text: the trimmed text as Rust parses a float (sign, digits,
    /// optional fraction and exponent, inf/infinity/nan in any case), or else the untrimmed text
    /// without its underscores (none doubled, none at either end). Null where it fails.</summary>
    public static double? PydanticFloat(string text)
    {
        static double? Parse(string s)
        {
            var m = RustFloatRegex().Match(s);
            if (!m.Success)
                return null;
            if (m.Groups[2].Success)
            {
                var negative = m.Groups[1].Value == "-";
                return m.Groups[2].Value.Equals("nan", StringComparison.OrdinalIgnoreCase) ? double.NaN
                    : negative ? double.NegativeInfinity : double.PositiveInfinity;
            }
            return double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);
        }
        if (Parse(text.Trim()) is { } f)
            return f;
        if (text.Contains("__", StringComparison.Ordinal) || text.StartsWith('_') || text.EndsWith('_'))
            return null;
        return Parse(text.Replace("_", ""));
    }

    [GeneratedRegex(@"^([+-]?)(?:(inf|infinity|nan)|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)\z", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex RustFloatRegex();

    /// <summary>pydantic's int parsing of text: whitespace around, a sign, ASCII digits with single
    /// underscores between them, and a fraction of zeros.</summary>
    [GeneratedRegex(@"^\s*([+-]?[0-9]+(?:_[0-9]+)*)(?:\.0+)?\s*$")]
    private static partial Regex PythonIntRegex();
}
