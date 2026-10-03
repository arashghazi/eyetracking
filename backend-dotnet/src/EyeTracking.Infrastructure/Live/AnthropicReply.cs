using System.Text.Json;
using System.Text.Json.Nodes;
using Anthropic;
using Anthropic.Exceptions;
using Anthropic.Models.Beta.Messages;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Infrastructure.Ai;
using Role = Anthropic.Models.Beta.Messages.Role;

namespace EyeTracking.Infrastructure.Live;

/// <summary>Avatar replies through the Anthropic Messages API with a JSON-schema output format
/// (backend/eyetracking/infrastructure/live/anthropic_reply.py), using the official Anthropic SDK as
/// step 5 does. Short conversational turns at low effort keep latency down; the stable system prompt
/// is cached. The participant's words travel inside a delimited conversation block and are treated as
/// content. Refusals and API errors never reach the participant: the conversation uses a scripted
/// line instead. The client is injectable so tests run without a key; the key comes from settings
/// only and is never logged.</summary>
public sealed class AnthropicReplyGenerator(
    string? apiKey, string model = "claude-opus-5-5", string effort = "low", IAnthropicClient? client = null, int maxTokens = 16000) : IReplyGenerator
{
    public const string Name = "anthropic";

    private readonly bool _injected = client is not null;
    private IAnthropicClient? _client = client;

    public string Model { get; } = model;
    public string Effort { get; } = effort;

    public JsonObject Info() => new()
    {
        ["name"] = Name, ["model"] = Model, ["effort"] = Effort, ["configured"] = !string.IsNullOrEmpty(apiKey) || _injected, ["synthetic"] = false,
    };

    /// <summary>USD per million input and output tokens (the same table as the text adapter).</summary>
    private (double In, double Out) Prices() =>
        AnthropicTextGenerator.PricesPerMtok.TryGetValue(Model, out var p) ? p : (4.0, 20.0);

    public double EstimateCost()
    {
        // about 1k input tokens and 600 output tokens (thinking included) per turn at low effort
        var (pin, pout) = Prices();
        return PyMath.Round((1000 * pin + 600 * pout) / 1_000_000, 4);
    }

    private IAnthropicClient GetClient()
    {
        if (_client is null)
        {
            if (string.IsNullOrEmpty(apiKey))
                throw new ReplyError("provider_not_configured: Anthropic API key is missing");
            _client = new AnthropicClient { ApiKey = apiKey };
        }
        return _client;
    }

    public async Task<(JsonObject? Data, JsonObject Meta)> Reply(string system, string conversation, string topic)
    {
        var c = GetClient();
        BetaMessage response;
        try
        {
            response = await c.Beta.Messages.Create(new MessageCreateParams
            {
                Model = Model,
                MaxTokens = maxTokens,
                System = new List<BetaTextBlockParam> { new() { Text = system, CacheControl = new BetaCacheControlEphemeral() } },
                Messages = [new() { Role = Role.User, Content = conversation }],
                OutputConfig = new BetaOutputConfig
                {
                    Effort = Effort,
                    Format = new BetaJsonOutputFormat
                    {
                        Schema = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(LiveRules.ReplySchema().ToJsonString())!,
                    },
                },
                Betas = ["server-side-fallback-2026-07-01"],
                Fallbacks = new Default(),
            });
        }
        // any API failure becomes a scripted line; the message names the Python SDK's exception
        catch (AnthropicApiException e)
        {
            throw new ReplyError($"{AnthropicTextGenerator.PythonName(e)}: {AnthropicTextGenerator.PythonMessage(e)}");
        }
        catch (AnthropicIOException)
        {
            throw new ReplyError("APIConnectionError: Connection error.");
        }
        catch (TaskCanceledException e) when (e.InnerException is TimeoutException)
        {
            throw new ReplyError("APITimeoutError: Request timed out.");
        }
        catch (Exception e)
        {
            throw new ReplyError($"{e.GetType().Name}: {e.Message}");
        }
        var stopReason = response.StopReason?.Raw();
        if (stopReason == "refusal")
        {
            var category = response.StopDetails?.Category?.Raw();
            throw new ReplyRefused($"refusal: {(string.IsNullOrEmpty(category) ? "unspecified" : category)}");
        }
        if (stopReason == "max_tokens")
            throw new ReplyError("the model hit max_tokens");
        var text = response.Content.Select(b => b.Value).OfType<BetaTextBlock>().FirstOrDefault()?.Text;
        if (string.IsNullOrEmpty(text))
            throw new ReplyError("the model returned no text block");
        JsonNode? parsed;
        try
        {
            parsed = JsonNode.Parse(text);
        }
        catch (JsonException)
        {
            throw new ReplyError("the reply was not valid JSON");
        }
        // JSON null is "no reply" (the guard rules use a scripted line); another non-object fails like Python's .get
        var data = parsed is null ? null : parsed as JsonObject ?? throw new InvalidOperationException("the reply must be a JSON object");
        var (pin, pout) = Prices();
        var usage = response.Usage;
        var cached = usage.CacheReadInputTokens ?? 0;
        var cost = PyMath.Round((usage.InputTokens * pin + cached * pin * 0.1 + usage.OutputTokens * pout) / 1_000_000, 5);
        return (data, new JsonObject { ["cost_actual_units"] = Json.Float(cost), ["model"] = response.Model.Raw() });
    }
}
