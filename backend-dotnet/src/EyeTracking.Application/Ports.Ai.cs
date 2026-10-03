using System.Text.Json.Nodes;
using EyeTracking.Domain;

namespace EyeTracking.Application;

// Step 5 ports: AI content generation (AiUnitOfWork, TextGenerator and VideoGenerator in ports.py).
// Providers describe themselves with info() dicts and return free-form meta dicts, kept as JSON.

public interface IJobRepo
{
    GenerationJob Add(GenerationJob j);
    GenerationJob? Get(int jobId);
    /// <summary>Newest first; an empty status or a content id of 0 does not filter.</summary>
    List<GenerationJob> ListForStudy(int studyId, string? status, long? contentId);
    /// <summary>The oldest queued job whose backoff has passed.</summary>
    GenerationJob? NextQueued(DateTime now);
}

public interface IAiBudgetRepo
{
    AiBudget? Get(int studyId);
    AiBudget Save(AiBudget b);
}

public partial interface IUnitOfWork
{
    IJobRepo Jobs { get; }
    IAiBudgetRepo AiBudgets { get; }
}

/// <summary>Writes a script as a dict matching <see cref="AiRules.ContentSchema"/>.</summary>
public interface ITextGenerator
{
    /// <summary><c>name</c>, <c>model</c>, <c>configured</c>, <c>synthetic</c>.</summary>
    JsonObject Info();
    double EstimateCost(TextRequest req);
    /// <summary>The script and a meta dict (<c>cost_actual_units</c>, <c>model</c>, token counts).</summary>
    Task<(JsonObject Data, JsonObject Meta)> Generate(TextRequest req);
}

/// <summary>Turns one segment's text into a speaking-face clip.</summary>
public interface IVideoGenerator
{
    /// <summary><c>name</c>, <c>configured</c>, <c>synthetic</c>.</summary>
    JsonObject Info();
    double EstimateCost(string text, double durationS);
    /// <summary>The clip, its content type and a meta dict (<c>cost_actual_units</c>, <c>duration_s</c>, ...).</summary>
    Task<(byte[] Data, string ContentType, JsonObject Meta)> Generate(string text, string faceId, string voiceId);
}

/// <summary>Raised by adapters when a retry cannot help (refusal, invalid request). Python keeps it in
/// infrastructure/ai/fake.py; the job runner needs it, so it lives next to the ports here.</summary>
public sealed class TerminalGenerationError(string message) : Exception(message);

/// <summary>A failure a later attempt may not repeat. <see cref="Kind"/> is the Python exception type
/// (<c>RuntimeError</c>, <c>RateLimitError</c>, <c>HTTPStatusError</c>, ...) the job's error names.</summary>
public sealed class GenerationError(string kind, string message) : Exception(message)
{
    public string Kind { get; } = kind;
}
