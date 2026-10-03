using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure.Ai;

// Development providers (backend/eyetracking/infrastructure/ai/fake.py): no key, no cost, sample
// content that says it is a sample. TerminalGenerationError lives with the ports (Ports.Ai.cs).

public sealed class FakeTextGenerator : ITextGenerator
{
    public JsonObject Info() => new() { ["name"] = "fake-text", ["model"] = "sample-script", ["configured"] = true, ["synthetic"] = true };

    public double EstimateCost(TextRequest req) => 0.0;

    public Task<(JsonObject Data, JsonObject Meta)> Generate(TextRequest req) =>
        Task.FromResult((AiRules.SampleScript(req), new JsonObject { ["cost_actual_units"] = Json.Float(0.0), ["model"] = "sample-script" }));
}

/// <summary>Returns the bundled sample clip (Ai/Assets/sample-face.webm, copied next to the binaries)
/// for every segment.</summary>
public sealed class FakeVideoGenerator(string? clipPath = null) : IVideoGenerator
{
    public static readonly string DefaultClip = Path.Combine(AppContext.BaseDirectory, "Ai", "Assets", "sample-face.webm");

    private readonly string _clip = clipPath ?? DefaultClip;

    public JsonObject Info() => new() { ["name"] = "fake-video", ["configured"] = File.Exists(_clip), ["synthetic"] = true };

    public double EstimateCost(string text, double durationS) => 0.0;

    public async Task<(byte[] Data, string ContentType, JsonObject Meta)> Generate(string text, string faceId, string voiceId)
    {
        var data = await File.ReadAllBytesAsync(_clip);
        return (data, "video/webm", new JsonObject { ["cost_actual_units"] = Json.Float(0.0), ["duration_s"] = Json.Float(4.0), ["note"] = "sample clip; the text is not spoken" });
    }
}

/// <summary>Test double: fails a configurable number of times, optionally as a terminal refusal.</summary>
public sealed class FailingTextGenerator(int failures = 99, double cost = 1.0, bool terminal = false) : ITextGenerator
{
    public int Failures { get; } = failures;
    public double Cost { get; } = cost;
    public bool Terminal { get; } = terminal;
    public int Calls { get; private set; }

    public JsonObject Info() => new() { ["name"] = "failing-text", ["model"] = "none", ["configured"] = true, ["synthetic"] = true };

    public double EstimateCost(TextRequest req) => Cost;

    public Task<(JsonObject Data, JsonObject Meta)> Generate(TextRequest req)
    {
        Calls += 1;
        if (Calls <= Failures)
            throw Terminal ? new TerminalGenerationError("refusal: general_harms") : new GenerationError("RuntimeError", "provider unavailable");
        return Task.FromResult((AiRules.SampleScript(req), new JsonObject { ["cost_actual_units"] = Json.Float(Cost), ["model"] = "none" }));
    }
}
