using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Live;

// Development providers for the live avatar (backend/eyetracking/infrastructure/live/fake.py): no
// key, no cost, clearly synthetic. The reply stand-in follows a few fixed rules so the whole loop can
// be tried and tested; it does not understand anything. Speech "recognition" returns a fixed
// sentence. The avatar is the packaged sample face video, and the app speaks the lines with the
// browser's own voice. ReplyError, ReplyRefused and SpeechError live with the rules (Domain/Live.cs).

public sealed partial class FakeReplyGenerator : IReplyGenerator
{
    public const string Name = "fake-reply";

    private static readonly string[] FollowUps =
    [
        "That sounds great! What do you like most about {topic}?",
        "Interesting! When did you first get into {topic}?",
        "Nice. Is there something about {topic} you would like to learn next?",
        "I like that. What would you tell a friend about {topic}?",
    ];

    private const string B = LiveRules.PyWordBoundary;

    [GeneratedRegex($"{B}(stop|bye|goodbye|end the|finish|quit){B}", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex StopRegex();

    [GeneratedRegex($"{B}(scared|afraid|upset|sad|anxious|nervous|uncomfortable|don'?t like this|need a break){B}", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex DistressRegex();

    [GeneratedRegex($"{B}(something else|another thing|different topic|homework|weather){B}", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ElsewhereRegex();

    /// <summary>Python's <c>str.splitlines()</c> line ends (U+2028 and U+2029 are the Zl and Zp categories).</summary>
    [GeneratedRegex(@"\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\p{Zl}\p{Zp}]")]
    private static partial Regex LineEndRegex();

    public JsonObject Info() => new() { ["name"] = Name, ["model"] = "sample-rules", ["configured"] = true, ["synthetic"] = true };

    public double EstimateCost() => 0.0;

    public Task<(JsonObject? Data, JsonObject Meta)> Reply(string system, string conversation, string topic)
    {
        const string prefix = "Participant: ";
        var lines = LineEndRegex().Split(conversation).Where(l => l.StartsWith(prefix, StringComparison.Ordinal)).ToList();
        var last = lines.Count > 0 ? lines[^1][prefix.Length..] : "";
        // Python's (len(lines) - 1) % 4 is never negative
        var follow = FollowUps[((lines.Count - 1) % FollowUps.Length + FollowUps.Length) % FollowUps.Length].Replace("{topic}", topic);
        return Task.FromResult<(JsonObject?, JsonObject)>((
            new JsonObject
            {
                ["reply"] = follow,
                ["participant_on_topic"] = !ElsewhereRegex().IsMatch(last),
                ["participant_distress"] = DistressRegex().IsMatch(last),
                ["participant_wants_to_stop"] = StopRegex().IsMatch(last),
            },
            new JsonObject { ["cost_actual_units"] = Json.Float(0.0), ["model"] = "sample-rules" }));
    }
}

public sealed class FakeSpeechToText : ISpeechToText
{
    public const string SampleSpeech = "This is sample speech from the development provider.";

    public JsonObject Info() => new() { ["name"] = "fake-speech", ["configured"] = true, ["synthetic"] = true };

    public Task<string> Transcribe(byte[] audio, string contentType, string language = "en")
    {
        if (audio.Length == 0)
            throw new SpeechError("no audio was received");
        return Task.FromResult(SampleSpeech);
    }
}

public sealed class FakeAvatarProvider : ILiveAvatarProvider
{
    public JsonObject Info() => new() { ["name"] = "sample-video", ["configured"] = true, ["synthetic"] = true, ["streaming"] = false };

    public double EstimateCostPerMinute() => 0.0;

    public JsonObject ClientConfig(string avatarId, string voiceId) => new()
    {
        ["mode"] = "sample_video",
        ["video_url"] = "/static/live/sample-face.webm",
        ["voice"] = "browser_tts",
        ["captions"] = true,
        ["synthetic"] = true,
        ["note"] = "Development avatar: a looping sample face and the browser's own voice. Not a streaming avatar.",
    };
}
