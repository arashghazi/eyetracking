using EyeTracking.Infrastructure.Db;
using EyeTracking.Web.Http;
using Microsoft.EntityFrameworkCore;

namespace EyeTracking.Web.Endpoints;

/// <summary>Secure gaze path for phones: the same estimator surface as the Python gaze service,
/// bearer token required, frames forwarded and never stored.</summary>
public sealed class GazeProxyEndpoints : IEndpointModule
{
    public void Map(IEndpointRouteBuilder app)
    {
        var settings = app.ServiceProvider.GetRequiredService<Settings>();
        if (!settings.GazeInApi)
            return;
        app.Map("/gaze/{**path}", async (HttpContext ctx, string? path, IHttpClientFactory http) =>
        {
            ctx.Principal();
            var target = settings.GazeServiceUrl.TrimEnd('/') + "/" + (path ?? "") + ctx.Request.QueryString;
            using var request = new HttpRequestMessage(new HttpMethod(ctx.Request.Method), target);
            if (ctx.Request.ContentLength > 0 || ctx.Request.Headers.TransferEncoding.Count > 0)
            {
                request.Content = new StreamContent(ctx.Request.Body);
                if (ctx.Request.ContentType is { } type)
                    request.Content.Headers.TryAddWithoutValidation("Content-Type", type);
            }
            HttpResponseMessage response;
            try
            {
                response = await http.CreateClient("gaze").SendAsync(request, ctx.RequestAborted);
            }
            catch (HttpRequestException)
            {
                throw new HttpError(503, "the gaze service is not reachable");
            }
            using (response)
            {
                ctx.Response.StatusCode = (int)response.StatusCode;
                ctx.Response.ContentType = response.Content.Headers.ContentType?.ToString() ?? "application/json";
                await response.Content.CopyToAsync(ctx.Response.Body);
            }
            return Results.Empty;
        });
    }
}

/// <summary>Test mode only (EYETRACKING_TEST_MODE=true and a database named EyeTracking_Test*):
/// POST /__test/reset empties every table, restarts the ids at 1 and creates the first admin
/// again, so each contract test starts like the Python tests' fresh in-memory database.</summary>
public sealed class TestResetEndpoints : IEndpointModule
{
    public void Map(IEndpointRouteBuilder app)
    {
        var settings = app.ServiceProvider.GetRequiredService<Settings>();
        if (!settings.TestMode)
            return;
        if (!Startup.DatabaseName(settings).StartsWith("EyeTracking_Test", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("EYETRACKING_TEST_MODE needs a database whose name starts with EyeTracking_Test");

        app.MapPost("/__test/reset", (HttpContext ctx, EyeTrackingDb db) =>
        {
            var tables = db.Model.GetEntityTypes().Select(t => t.GetTableName()!).Distinct().ToList();
            // RESEED 0 on a table that never had a row would make the next id 0, not 1
            var sql = string.Join("\n", tables.Select(t => $"ALTER TABLE [{t}] NOCHECK CONSTRAINT ALL;"))
                + "\n" + string.Join("\n", tables.Select(t =>
                    $"DELETE FROM [{t}]; IF EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('[{t}]') AND last_value IS NOT NULL) "
                    + $"DBCC CHECKIDENT ('[{t}]', RESEED, 0) WITH NO_INFOMSGS;"))
                + "\n" + string.Join("\n", tables.Select(t => $"ALTER TABLE [{t}] WITH CHECK CHECK CONSTRAINT ALL;"));
            db.Database.ExecuteSqlRaw(sql);
            db.ChangeTracker.Clear();
            if (Directory.Exists(settings.MediaDir))
            {
                foreach (var entry in Directory.EnumerateFileSystemEntries(settings.MediaDir))
                {
                    if (Directory.Exists(entry)) Directory.Delete(entry, recursive: true);
                    else File.Delete(entry);
                }
            }
            Startup.BootstrapAdmin(ctx.RequestServices, settings);
            return Reply.Ok(new { reset = true });
        });
    }
}
