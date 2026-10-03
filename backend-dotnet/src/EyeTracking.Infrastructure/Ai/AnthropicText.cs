using System.Text.Json;
using System.Text.Json.Nodes;
using Anthropic;
using Anthropic.Exceptions;
using Anthropic.Models.Beta.Messages;
using EyeTracking.Application;
using EyeTracking.Domain;
using Role = Anthropic.Models.Beta.Messages.Role;

namespace EyeTracking.Infrastructure.Ai;

/// <summary>Text generation through the Anthropic Messages API with a JSON-schema output format
/// (backend/eyetracking/infrastructure/ai/anthropic_text.py), using the official Anthropic SDK.
/// The client is injectable so tests run without a key; the key comes from settings only and is
/// never logged. Refusals and invalid requests are terminal; rate limits, server and connection
/// errors (after the SDK's own retries) are retried by the job runner.</summary>
public sealed class AnthropicTextGenerator(string? apiKey, string model = "claude-opus-5-5", IAnthropicClient? client = null, int maxTokens = 16000)
    : ITextGenerator
{
    public const string Name = "anthropic";

    /// <summary>USD per million input and output tokens.</summary>
    public static readonly IReadOnlyDictionary<string, (double In, double Out)> PricesPerMtok = new Dictionary<string, (double, double)>
    {
        ["claude-opus-5-5"] = (4.0, 20.0), ["claude-sonnet-5-5"] = (2.0, 10.0), ["claude-haiku-4-5"] = (1.0, 5.0),
    };

    private readonly bool _injected = client is not null;
    private IAnthropicClient? _client = client;

    public string Model { get; } = model;

    public JsonObject Info() =>
        new() { ["name"] = Name, ["model"] = Model, ["configured"] = !string.IsNullOrEmpty(apiKey) || _injected, ["synthetic"] = false };

    private (double In, double Out) Prices() => PricesPerMtok.TryGetValue(Model, out var p) ? p : (4.0, 20.0);

    public double EstimateCost(TextRequest req)
    {
        // roughly 1.5k input tokens and 3k output tokens for a short script with thinking
        var (pin, pout) = Prices();
        return PyMath.Round((1500 * pin + 3000 * pout) / 1_000_000, 4);
    }

    private IAnthropicClient GetClient()
    {
        if (_client is null)
        {
            if (string.IsNullOrEmpty(apiKey))
                throw new TerminalGenerationError("provider_not_configured: Anthropic API key is missing");
            _client = new AnthropicClient { ApiKey = apiKey };
        }
        return _client;
    }

    /// <summary>The anthropic Python package's class for an error status (the job's error names it;
    /// the live reply adapter uses it too).</summary>
    internal static string PythonName(AnthropicApiException e) => (int)e.StatusCode switch
    {
        400 => "BadRequestError",
        401 => "AuthenticationError",
        403 => "PermissionDeniedError",
        404 => "NotFoundError",
        409 => "ConflictError",
        413 => "RequestTooLargeError",
        422 => "UnprocessableEntityError",
        429 => "RateLimitError",
        529 => "OverloadedError",
        >= 500 => "InternalServerError",
        _ => "APIStatusError",
    };

    /// <summary>The Python SDK's error message: <c>Error code: 429 - {'type': 'error', ...}</c> (the body as a
    /// Python dict), the raw text when the body is not JSON.</summary>
    internal static string PythonMessage(AnthropicApiException e)
    {
        var status = (int)e.StatusCode;
        var text = (e.ResponseBody ?? "").Trim();
        try
        {
            return $"Error code: {status} - {PyText.Str(JsonNode.Parse(text))}";
        }
        catch (JsonException)
        {
            return text.Length > 0 ? text : $"Error code: {status}";
        }
    }

    public async Task<(JsonObject Data, JsonObject Meta)> Generate(TextRequest req)
    {
        var c = GetClient();
        var (system, user) = AiRules.ScriptPrompt(req);
        BetaMessage response;
        try
        {
            response = await c.Beta.Messages.Create(new MessageCreateParams
            {
                Model = Model,
                MaxTokens = maxTokens,
                System = system,
                Messages = [new() { Role = Role.User, Content = user }],
                OutputConfig = new BetaOutputConfig
                {
                    Format = new BetaJsonOutputFormat
                    {
                        Schema = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(AiRules.ContentSchema().ToJsonString())!,
                    },
                },
                Betas = ["server-side-fallback-2026-07-01"],
                Fallbacks = new Default(),
            });
        }
        catch (AnthropicApiException e) when (e is AnthropicBadRequestException or AnthropicUnauthorizedException or AnthropicForbiddenException or AnthropicNotFoundException)
        {
            throw new TerminalGenerationError($"{PythonName(e)}: {PythonMessage(e)}");
        }
        catch (AnthropicApiException e)
        {
            throw new GenerationError(PythonName(e), PythonMessage(e));
        }
        catch (AnthropicIOException)
        {
            throw new GenerationError("APIConnectionError", "Connection error.");
        }
        catch (TaskCanceledException e) when (e.InnerException is TimeoutException)
        {
            throw new GenerationError("APITimeoutError", "Request timed out.");
        }
        var stopReason = response.StopReason?.Raw();
        if (stopReason == "refusal")
        {
            var category = response.StopDetails?.Category?.Raw();
            throw new TerminalGenerationError($"refusal: {(string.IsNullOrEmpty(category) ? "unspecified" : category)}");
        }
        if (stopReason == "max_tokens")
            throw new GenerationError("RuntimeError", "the model hit max_tokens before finishing the script");
        var text = response.Content.Select(b => b.Value).OfType<BetaTextBlock>().FirstOrDefault()?.Text;
        if (string.IsNullOrEmpty(text))
            throw new GenerationError("RuntimeError", "the model returned no text block");
        var data = JsonNode.Parse(text) as JsonObject ?? throw new InvalidOperationException("the script must be a JSON object");
        var (pin, pout) = Prices();
        var usage = response.Usage;
        var cost = PyMath.Round((usage.InputTokens * pin + usage.OutputTokens * pout) / 1_000_000, 4);
        return (data, new JsonObject
        {
            ["cost_actual_units"] = Json.Float(cost),
            ["model"] = response.Model.Raw(),
            ["input_tokens"] = usage.InputTokens,
            ["output_tokens"] = usage.OutputTokens,
        });
    }
}
