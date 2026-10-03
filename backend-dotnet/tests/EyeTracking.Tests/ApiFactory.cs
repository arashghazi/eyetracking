using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using EyeTracking.Infrastructure.Db;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;

[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace EyeTracking.Tests;

/// <summary>The API in-process on its own throwaway SQL Server database (EyeTracking_Test_*,
/// dropped when the factory is disposed). Use <see cref="Override"/> to swap services, for
/// example fake AI providers, before the first request. Settings come from the environment,
/// so tests in this assembly never run in parallel.</summary>
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    public const string AdminEmail = "admin@test.local";
    public const string AdminPassword = "admin-password-1";

    private readonly List<Action<IServiceCollection>> _overrides = [];

    public string Database { get; } = "EyeTracking_Test_cs_" + Guid.NewGuid().ToString("N")[..12];
    public string MediaDir { get; } = Path.Combine(Path.GetTempPath(), "eyetracking-cs-media-" + Guid.NewGuid().ToString("N")[..8]);

    public ApiFactory(IDictionary<string, string>? settings = null)
    {
        var server = Environment.GetEnvironmentVariable("EYETRACKING_TEST_SQLSERVER") ?? "localhost";
        var env = new Dictionary<string, string>
        {
            ["EYETRACKING_DB_CONNECTION"] = $"Server={server};Database={Database};Trusted_Connection=True;TrustServerCertificate=True",
            ["EYETRACKING_TEST_MODE"] = "true",
            ["EYETRACKING_JWT_SECRET"] = "test-secret",
            ["EYETRACKING_BOOTSTRAP_ADMIN_EMAIL"] = AdminEmail,
            ["EYETRACKING_BOOTSTRAP_ADMIN_PASSWORD"] = AdminPassword,
            ["EYETRACKING_MEDIA_DIR"] = MediaDir,
            ["EYETRACKING_GAZE_IN_API"] = "false",
        };
        foreach (var (k, v) in settings ?? new Dictionary<string, string>())
            env[k] = v;
        foreach (var (k, v) in env)
            Environment.SetEnvironmentVariable(k, v);
    }

    public ApiFactory Override(Action<IServiceCollection> configure)
    {
        _overrides.Add(configure);
        return this;
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.ConfigureTestServices(services =>
        {
            foreach (var o in _overrides)
                o(services);
        });

    /// <summary>A client on an emptied database (ids from 1, only the first admin).</summary>
    public HttpClient Fresh()
    {
        var c = CreateClient();
        c.PostAsync("/__test/reset", null).GetAwaiter().GetResult().EnsureSuccessStatusCode();
        return c;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            try
            {
                using var scope = Services.CreateScope();
                scope.ServiceProvider.GetRequiredService<EyeTrackingDb>().Database.EnsureDeleted();
            }
            catch
            {
                // best effort: a leftover EyeTracking_Test_* database is harmless
            }
            if (Directory.Exists(MediaDir))
                Directory.Delete(MediaDir, recursive: true);
        }
        base.Dispose(disposing);
    }
}

/// <summary>Small helpers that read like the Python tests (login, auth, JSON).</summary>
public static class Api
{
    public static async Task<string> Login(this HttpClient c, string email, string password)
    {
        var r = await c.PostAsJsonAsync("/auth/login", new { email, password });
        r.EnsureSuccessStatusCode();
        return (string)(await r.Json())["access_token"]!;
    }

    public static async Task<JsonNode> Json(this HttpResponseMessage r) =>
        JsonNode.Parse(await r.Content.ReadAsStringAsync()) ?? throw new InvalidOperationException("empty body");

    public static HttpRequestMessage As(this HttpRequestMessage m, string token)
    {
        m.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return m;
    }

    public static Task<HttpResponseMessage> Get(this HttpClient c, string url, string token) =>
        c.SendAsync(new HttpRequestMessage(HttpMethod.Get, url).As(token));

    public static Task<HttpResponseMessage> Send(this HttpClient c, HttpMethod method, string url, object? body, string token) =>
        c.SendAsync(new HttpRequestMessage(method, url) { Content = body is null ? null : JsonContent.Create(body) }.As(token));

    public static Task<HttpResponseMessage> Post(this HttpClient c, string url, object? body, string token) => c.Send(HttpMethod.Post, url, body, token);

    public static Task<HttpResponseMessage> Put(this HttpClient c, string url, object? body, string token) => c.Send(HttpMethod.Put, url, body, token);
}
