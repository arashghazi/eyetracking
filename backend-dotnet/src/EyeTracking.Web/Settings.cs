using System.Globalization;
using System.Reflection;
using System.Text.Json;
using EyeTracking.Domain;

namespace EyeTracking.Web;

/// <summary>Runtime configuration, read from EYETRACKING_* environment variables or a local
/// <c>.env</c> file in the working directory (environment wins), like the Python service's
/// pydantic settings. Property <c>JwtSecret</c> is variable <c>EYETRACKING_JWT_SECRET</c>.</summary>
public sealed class Settings
{
    /// <summary>SQL Server connection string.</summary>
    public string DbConnection { get; set; } =
        "Server=localhost;Database=EyeTracking_Dev;Trusted_Connection=True;TrustServerCertificate=True";

    public string JwtSecret { get; set; } = "change-me-in-production";
    public int JwtExpireMinutes { get; set; } = 120;
    public string? BootstrapAdminEmail { get; set; }
    public string? BootstrapAdminPassword { get; set; }
    public List<string> CorsOrigins { get; set; } = ["http://localhost:8080", "http://localhost:5173", "http://localhost:3000"];

    /// <summary>Serve /gaze/* for phones, behind the bearer token. The estimator itself runs in the
    /// Python gaze service at <see cref="GazeServiceUrl"/>; this API forwards to it.</summary>
    public bool GazeInApi { get; set; } = true;
    public string GazeServiceUrl { get; set; } = "http://127.0.0.1:8100";

    public string MediaDir { get; set; } = "./media";
    public int MediaUrlTtlSeconds { get; set; } = 6 * 3600;

    // AI content generation (step 5); keys never leave the server
    public string AiTextProvider { get; set; } = "fake";
    public string AiTextModel { get; set; } = "claude-opus-5-5";
    public string? AnthropicApiKey { get; set; }
    public string AiVideoProvider { get; set; } = "fake";
    public string? HeygenApiKey { get; set; }
    public string HeygenBaseUrl { get; set; } = "https://api.heygen.com";
    public double HeygenCostPerMinuteUnits { get; set; } = 1.0;
    public bool AiWorkerEnabled { get; set; }
    public int AiWorkerIntervalS { get; set; } = 5;

    // live avatar (step 7): replies, speech to text and the avatar itself are swappable
    public string LiveReplyProvider { get; set; } = "fake";
    public string LiveReplyModel { get; set; } = "claude-opus-5-5";
    public string LiveReplyEffort { get; set; } = "low";
    public string SttProvider { get; set; } = "fake";
    public string? SttBaseUrl { get; set; }
    public string SttModel { get; set; } = "whisper-1";
    public string? SttApiKey { get; set; }
    public string LiveAvatarProvider { get; set; } = "fake";

    /// <summary>Enables POST /__test/reset, which empties the database. Refused unless the
    /// database name starts with EyeTracking_Test.</summary>
    public bool TestMode { get; set; }

    public static Settings Load(string? envFile = ".env")
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (envFile is not null && File.Exists(envFile))
        {
            foreach (var raw in File.ReadAllLines(envFile))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith('#') || !line.Contains('='))
                    continue;
                var at = line.IndexOf('=');
                values[line[..at].Trim()] = line[(at + 1)..].Trim().Trim('"', '\'');
            }
        }
        foreach (System.Collections.DictionaryEntry e in Environment.GetEnvironmentVariables())
            values[(string)e.Key] = (string?)e.Value ?? "";

        var settings = new Settings();
        foreach (var p in typeof(Settings).GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (!values.TryGetValue("EYETRACKING_" + Wire.Name(p.Name).ToUpperInvariant(), out var text))
                continue;
            p.SetValue(settings, Convert(text, p.PropertyType, p.Name));
        }
        return settings;
    }

    private static object? Convert(string text, Type type, string name)
    {
        var target = Nullable.GetUnderlyingType(type) ?? type;
        if (target == typeof(string))
            return text.Length == 0 && type != typeof(string) ? null : text;
        if (target == typeof(bool))
            return text.ToLowerInvariant() switch
            {
                "1" or "true" or "yes" or "on" or "y" or "t" => true,
                "0" or "false" or "no" or "off" or "n" or "f" => false,
                _ => throw new InvalidOperationException($"EYETRACKING setting {name}: '{text}' is not a boolean"),
            };
        if (target == typeof(int))
            return int.Parse(text, CultureInfo.InvariantCulture);
        if (target == typeof(double))
            return double.Parse(text, CultureInfo.InvariantCulture);
        if (target == typeof(List<string>))
            return text.TrimStart().StartsWith('[')
                ? JsonSerializer.Deserialize<List<string>>(text)!
                : text.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
        throw new InvalidOperationException($"unsupported setting type for {name}");
    }
}
