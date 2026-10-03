using System.Diagnostics;
using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Ai;

/// <summary>Speaking-face video through HeyGen's video generation API: create, poll, download
/// (backend/eyetracking/infrastructure/ai/heygen_video.py). Written against the public v2 API shape;
/// not exercised against the live service. The transport and the sleep are injectable so tests use
/// a stub handler; the key stays on the server.</summary>
public sealed class HeyGenVideoGenerator(
    string? apiKey, string baseUrl = "https://api.heygen.com", double costPerMinuteUnits = 1.0, HttpMessageHandler? transport = null,
    double pollIntervalS = 5.0, double timeoutS = 900.0, Func<double, Task>? sleep = null) : IVideoGenerator
{
    private static readonly HttpMessageHandler SharedHandler = new SocketsHttpHandler { PooledConnectionLifetime = TimeSpan.FromMinutes(5) };

    private readonly string _base = baseUrl.TrimEnd('/');
    private readonly Func<double, Task> _sleep = sleep ?? (s => Task.Delay(TimeSpan.FromSeconds(s)));

    public JsonObject Info() => new() { ["name"] = "heygen", ["configured"] = !string.IsNullOrEmpty(apiKey), ["synthetic"] = false };

    public double EstimateCost(string text, double durationS)
    {
        var words = Math.Max(1, PyWordCount(text));
        var seconds = Math.Max(durationS, words / 2.5);
        return PyMath.Round(costPerMinuteUnits * seconds / 60.0, 4);
    }

    /// <summary>Python's <c>len(text.split())</c>: runs of whitespace (U+001C..U+001F included) separate words.</summary>
    private static int PyWordCount(string text)
    {
        var count = 0;
        var inWord = false;
        foreach (var ch in text)
        {
            var space = char.IsWhiteSpace(ch) || ch is >= '\x1c' and <= '\x1f';
            if (!space && !inWord)
                count++;
            inWord = !space;
        }
        return count;
    }

    private HttpClient Client()
    {
        if (string.IsNullOrEmpty(apiKey))
            throw new TerminalGenerationError("provider_not_configured: HeyGen API key is missing");
        var c = new HttpClient(transport ?? SharedHandler, disposeHandler: false) { Timeout = TimeSpan.FromSeconds(60) };
        c.DefaultRequestHeaders.TryAddWithoutValidation("X-Api-Key", apiKey);
        c.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/json");
        return c;
    }

    /// <summary>httpx's URL merge: a relative path goes under the base URL, an absolute URL is used as it is.</summary>
    private string Url(string url) =>
        url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            ? url
            : _base + "/" + url.TrimStart('/');

    /// <summary>A request; transport failures carry httpx's exception names.</summary>
    private static async Task<HttpResponseMessage> Send(HttpClient c, HttpRequestMessage request)
    {
        try
        {
            return await c.SendAsync(request);
        }
        catch (HttpRequestException e)
        {
            throw new GenerationError("ConnectError", e.Message);
        }
        catch (TaskCanceledException e)
        {
            throw new GenerationError("ReadTimeout", e.Message);
        }
    }

    /// <summary>httpx's <c>raise_for_status()</c> with its message.</summary>
    private static void RaiseForStatus(HttpResponseMessage r)
    {
        var code = (int)r.StatusCode;
        if (code is >= 200 and < 300)
            return;
        var kind = (code / 100) switch
        {
            1 => "Informational response",
            3 => "Redirect response",
            4 => "Client error",
            _ => "Server error",
        };
        var message = $"{kind} '{code} {r.ReasonPhrase}' for url '{r.RequestMessage?.RequestUri}'\n"
            + $"For more information check: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/{code}";
        if (code is >= 300 and < 400 && r.Headers.Location is { } location)
            message += $"\nRedirect location: '{location}'";
        throw new GenerationError("HTTPStatusError", message);
    }

    /// <summary><c>r.json().get("data") or {}</c>.</summary>
    private static JsonObject Data(string body)
    {
        var json = JsonNode.Parse(body) as JsonObject ?? throw new InvalidOperationException("the response is not a JSON object");
        return Json.Truthy(json["data"]) ? PracticeRules.AsDict(json["data"]) : [];
    }

    /// <summary>Python's <c>float(v or 0)</c> of a response value (numbers and numeric text).</summary>
    private static double FloatOr0(JsonNode? v)
    {
        if (!Json.Truthy(v))
            return 0.0;
        if (Json.Str(v) is { } s)
            return double.TryParse(s.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var d)
                ? d
                : throw new GenerationError("ValueError", $"could not convert string to float: {PyText.Repr(v)}");
        return PracticeRules.FloatOf(v);
    }

    public async Task<(byte[] Data, string ContentType, JsonObject Meta)> Generate(string text, string faceId, string voiceId)
    {
        if (string.IsNullOrEmpty(faceId) || string.IsNullOrEmpty(voiceId))
            throw new TerminalGenerationError("face_id and voice_id are required for video generation");
        using var c = Client();
        var body = new JsonObject
        {
            ["video_inputs"] = new JsonArray(new JsonObject
            {
                ["character"] = new JsonObject { ["type"] = "avatar", ["avatar_id"] = faceId, ["avatar_style"] = "normal" },
                ["voice"] = new JsonObject { ["type"] = "text", ["input_text"] = text, ["voice_id"] = voiceId },
            }),
            ["dimension"] = new JsonObject { ["width"] = 1280, ["height"] = 720 },
        };
        var content = new ByteArrayContent(Encoding.UTF8.GetBytes(body.ToJsonString()));
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        using var r = await Send(c, new HttpRequestMessage(HttpMethod.Post, Url("/v2/video/generate")) { Content = content });
        var created = await r.Content.ReadAsStringAsync();
        if ((int)r.StatusCode is 400 or 401 or 403 or 404)
            throw new TerminalGenerationError($"heygen {(int)r.StatusCode}: {AiRules.Head(created, 300)}");
        RaiseForStatus(r);
        var videoId = Data(created)["video_id"];
        if (!Json.Truthy(videoId))
            throw new GenerationError("RuntimeError", $"heygen returned no video_id: {AiRules.Head(created, 300)}");
        var deadline = Stopwatch.StartNew();
        while (true)
        {
            var statusUrl = Url("/v1/video_status.get") + "?video_id=" + Uri.EscapeDataString(PyText.Str(videoId));
            using var s = await Send(c, new HttpRequestMessage(HttpMethod.Get, statusUrl));
            RaiseForStatus(s);
            var data = Data(await s.Content.ReadAsStringAsync());
            var status = Json.Str(data["status"]);
            if (status == "completed")
            {
                var url = data["video_url"];
                if (!Json.Truthy(url))
                    throw new GenerationError("RuntimeError", "heygen completed without a video_url");
                using var d = await Send(c, new HttpRequestMessage(HttpMethod.Get, Url(PyText.Str(url))));
                RaiseForStatus(d);
                var contentType = (d.Content.Headers.NonValidated.TryGetValues("Content-Type", out var values) ? values.ToString() : "video/mp4").Split(';')[0];
                var duration = FloatOr0(data["duration"]);
                var cost = duration != 0 ? PyMath.Round(costPerMinuteUnits * duration / 60.0, 4) : EstimateCost(text, 0);
                return (await d.Content.ReadAsByteArrayAsync(), contentType, new JsonObject
                {
                    ["cost_actual_units"] = Json.Float(cost), ["duration_s"] = Json.Float(duration), ["video_id"] = videoId!.DeepClone(),
                });
            }
            if (status == "failed")
                throw new TerminalGenerationError($"heygen failed: {(Json.Truthy(data["error"]) ? PyText.Str(data["error"]) : "unknown error")}");
            if (deadline.Elapsed.TotalSeconds > timeoutS)
                throw new GenerationError("RuntimeError", "heygen video generation timed out");
            await _sleep(pollIntervalS);
        }
    }
}
