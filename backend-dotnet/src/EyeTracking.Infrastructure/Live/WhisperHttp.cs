using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Live;

/// <summary>Speech to text through a Whisper-compatible HTTP server (POST /v1/audio/transcriptions;
/// backend/eyetracking/infrastructure/live/whisper_http.py). Meant for a speech server running on the
/// same computer or inside the research network, so audio does not leave it. The audio is sent once,
/// from memory, and never written anywhere by this app. The transport is injectable so tests use a
/// stub handler; the key comes from settings only and is never logged.</summary>
public sealed class WhisperHttpSpeechToText(
    string? baseUrl, string model = "whisper-1", string? apiKey = null, HttpMessageHandler? transport = null, double timeoutS = 60.0) : ISpeechToText
{
    public const string Name = "whisper-http";

    private static readonly HttpMessageHandler SharedHandler = new SocketsHttpHandler { PooledConnectionLifetime = TimeSpan.FromMinutes(5) };

    private static readonly Dictionary<string, string> Extensions = new()
    {
        ["audio/webm"] = "webm", ["audio/ogg"] = "ogg", ["audio/wav"] = "wav", ["audio/x-wav"] = "wav", ["audio/mp4"] = "m4a", ["audio/mpeg"] = "mp3",
    };

    public string BaseUrl { get; } = (baseUrl ?? "").TrimEnd('/');
    public string Model { get; } = model;

    public JsonObject Info() => new()
    {
        ["name"] = Name, ["model"] = Model, ["configured"] = BaseUrl.Length > 0, ["synthetic"] = false, ["base_url"] = BaseUrl.Length > 0 ? BaseUrl : null,
    };

    /// <summary>A form part as httpx writes it: the name (and file name) quoted, no content type for text fields.</summary>
    private static ByteArrayContent Part(byte[] data, string disposition, string? contentType = null)
    {
        var part = new ByteArrayContent(data);
        part.Headers.TryAddWithoutValidation("Content-Disposition", disposition);
        if (contentType is not null)
            part.Headers.TryAddWithoutValidation("Content-Type", contentType);
        return part;
    }

    public async Task<string> Transcribe(byte[] audio, string contentType, string language = "en")
    {
        if (BaseUrl.Length == 0)
            throw new SpeechError("provider_not_configured: no speech server address is set");
        if (audio.Length == 0)
            throw new SpeechError("no audio was received");
        using var c = new HttpClient(transport ?? SharedHandler, disposeHandler: false) { Timeout = TimeSpan.FromSeconds(timeoutS) };
        var ext = Extensions.GetValueOrDefault(LiveRules.PyStrip(contentType.Split(';')[0]), "webm");
        // httpx's multipart body: the data fields, then the file; an unquoted random hex boundary
        var boundary = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16));
        var form = new MultipartFormDataContent(boundary)
        {
            Part(Encoding.UTF8.GetBytes(Model), "form-data; name=\"model\""),
            Part(Encoding.UTF8.GetBytes(language), "form-data; name=\"language\""),
            Part("json"u8.ToArray(), "form-data; name=\"response_format\""),
            Part(audio, $"form-data; name=\"file\"; filename=\"utterance.{ext}\"", contentType),
        };
        form.Headers.Remove("Content-Type");
        form.Headers.TryAddWithoutValidation("Content-Type", $"multipart/form-data; boundary={boundary}");
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{BaseUrl}/v1/audio/transcriptions") { Content = form };
        if (!string.IsNullOrEmpty(apiKey))
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {apiKey}");
        HttpResponseMessage r;
        try
        {
            r = await c.SendAsync(request);
        }
        // httpx's exception names
        catch (HttpRequestException)
        {
            throw new SpeechError("speech server unreachable: ConnectError");
        }
        catch (TaskCanceledException)
        {
            throw new SpeechError("speech server unreachable: ReadTimeout");
        }
        using (r)
        {
            if ((int)r.StatusCode >= 400)
                throw new SpeechError($"speech server answered {(int)r.StatusCode}");
            JsonNode? json;
            try
            {
                json = JsonNode.Parse(await r.Content.ReadAsStringAsync());
            }
            catch (JsonException)
            {
                throw new SpeechError("speech server sent no JSON");
            }
            // r.json().get("text", ""): anything but an object fails like Python's AttributeError
            var text = PracticeRules.Get(json as JsonObject ?? throw new InvalidOperationException("the speech server's JSON is not an object"), "text", "");
            return LiveRules.PyStrip(Json.Truthy(text) ? PyText.Str(text) : "");
        }
    }
}
