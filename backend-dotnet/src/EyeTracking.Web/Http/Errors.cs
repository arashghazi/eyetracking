using System.Text.Json.Nodes;
using EyeTracking.Domain;
using Microsoft.EntityFrameworkCore;

namespace EyeTracking.Web.Http;

/// <summary>An HTTP error with a ready <c>detail</c> (FastAPI's HTTPException).</summary>
public sealed class HttpError(int status, string detail) : Exception(detail)
{
    public int Status { get; } = status;
}

/// <summary>A request body that does not match the schema: 422 with FastAPI's list of errors
/// (<c>{"detail": [{"type", "loc", "msg", "input"}]}</c>).</summary>
public sealed class RequestInvalid(JsonArray errors) : Exception("request validation failed")
{
    public JsonArray Errors { get; } = errors;

    public static RequestInvalid Single(string type, string msg, JsonNode? input, params string[] loc) =>
        new([Error(type, msg, input, loc)]);

    public static void ThrowIfAny(List<JsonObject> errors)
    {
        if (errors.Count > 0)
            throw new RequestInvalid([.. errors]);
    }

    public static JsonObject Error(string type, string msg, JsonNode? input, params string[] loc) => new()
    {
        ["type"] = type,
        ["loc"] = new JsonArray(loc.Select(l => (JsonNode?)JsonValue.Create(l)).ToArray()),
        ["msg"] = msg,
        ["input"] = input?.DeepClone(),
    };
}

/// <summary>Maps exceptions to the responses the Python service gave:
/// domain errors by kind (404/403/409/422/401) with the message as <c>detail</c>.</summary>
public sealed class ErrorMiddleware(RequestDelegate next, ILogger<ErrorMiddleware> log)
{
    private static int StatusOf(DomainError e) => e switch
    {
        NotFound => 404,
        Forbidden => 403,
        Conflict => 409,
        Invalid => 422,
        AuthenticationFailed => 401,
        _ => 400,
    };

    public async Task Invoke(HttpContext ctx)
    {
        try
        {
            await next(ctx);
        }
        catch (Exception e) when (!ctx.Response.HasStarted)
        {
            var (status, detail) = e switch
            {
                DomainError d => (StatusOf(d), (JsonNode?)d.Message),
                HttpError h => (h.Status, h.Message),
                RequestInvalid r => (422, r.Errors),
                BadHttpRequestException b => (b.StatusCode, b.Message),
                _ => (500, null),
            };
            if (status == 500)
            {
                log.LogError(e, "unhandled error on {Method} {Path}", ctx.Request.Method, ctx.Request.Path);
                ctx.Response.Clear();
                ctx.Response.StatusCode = 500;
                ctx.Response.ContentType = "text/plain; charset=utf-8";
                await ctx.Response.WriteAsync("Internal Server Error");
                return;
            }
            ctx.Response.Clear();
            await Reply.Json(new JsonObject { ["detail"] = detail }, status).ExecuteAsync(ctx);
        }
    }
}

internal static class DbErrors
{
    public static bool IsUniqueViolation(DbUpdateException e) =>
        e.InnerException is Microsoft.Data.SqlClient.SqlException { Number: 2601 or 2627 };
}
