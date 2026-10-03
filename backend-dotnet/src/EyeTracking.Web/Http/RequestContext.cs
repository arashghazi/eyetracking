using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Web.Http;

/// <summary>A request body that checks its own constraints (pydantic Literal, min_length, ge/le).
/// Add one error per problem with <see cref="Check"/>.</summary>
public interface IValidatedBody
{
    void Validate(List<JsonObject> errors);
}

public static partial class RequestContext
{
    private static readonly JsonSerializerOptions BodyOptions = CreateBodyOptions();

    private static JsonSerializerOptions CreateBodyOptions()
    {
        var o = new JsonSerializerOptions(JsonFormat.Options)
        {
            PropertyNameCaseInsensitive = false,
            RespectNullableAnnotations = true,
            RespectRequiredConstructorParameters = true,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
        };
        o.MakeReadOnly(populateMissingResolver: true);
        return o;
    }

    /// <summary>The signed-in user. 401 with the Python service's details when the bearer token
    /// is missing, invalid or expired. Resolve it before reading the body: authentication
    /// errors come before validation errors, as in FastAPI.</summary>
    public static Principal Principal(this HttpContext ctx)
    {
        if (ctx.Items.TryGetValue(typeof(Principal), out var cached) && cached is Principal p)
            return p;
        var header = ctx.Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) || header.Length <= 7)
            throw new HttpError(401, "authentication required");
        var tokens = ctx.RequestServices.GetRequiredService<ITokenIssuer>();
        var uow = ctx.RequestServices.GetRequiredService<IUnitOfWork>();
        var userId = tokens.Parse(header[7..].Trim());
        var principal = userId is null ? null : UseCases.LoadPrincipal(uow, userId.Value);
        if (principal is null)
            throw new HttpError(401, "invalid or expired token");
        ctx.Items[typeof(Principal)] = principal;
        return principal;
    }

    /// <summary>The JSON body as <typeparamref name="T"/>; 422 in FastAPI's shape when it is
    /// missing, malformed, lacks a required field or breaks a constraint.</summary>
    public static async Task<T> Body<T>(this HttpContext ctx) where T : class
    {
        var node = await ctx.JsonBody();
        if (node is null)
            throw RequestInvalid.Single("missing", "Field required", null, "body");
        if (typeof(T) != typeof(JsonNode) && typeof(T) != typeof(JsonArray) && node is not JsonObject)
            throw RequestInvalid.Single("model_attributes_type", "Input should be a valid dictionary or object to extract fields from", node, "body");
        T? value;
        try
        {
            value = node.Deserialize<T>(BodyOptions);
        }
        catch (JsonException e)
        {
            throw new RequestInvalid([.. Describe(e, node)]);
        }
        if (value is null)
            throw RequestInvalid.Single("missing", "Field required", null, "body");
        if (value is IValidatedBody v)
        {
            var errors = new List<JsonObject>();
            v.Validate(errors);
            if (errors.Count > 0)
                throw new RequestInvalid([.. errors.Select(e => WithRawInput(e, node))]);
        }
        return value;
    }

    /// <summary>pydantic reports the value as sent and list positions as numbers: take both from
    /// the raw body along the error's <c>loc</c>.</summary>
    private static JsonObject WithRawInput(JsonObject error, JsonNode body)
    {
        if (error["loc"] is not JsonArray loc || loc.Count == 0 || Json.Str(loc[0]) != "body")
            return error;
        JsonNode? current = body;
        for (var i = 1; i < loc.Count; i++)
        {
            var key = Json.Str(loc[i]);
            switch (current)
            {
                case JsonObject o when key is not null && o.TryGetPropertyValue(key, out var child):
                    current = child;
                    break;
                case JsonArray a when int.TryParse(key, out var index) && index >= 0 && index < a.Count:
                    loc[i] = index;
                    current = a[index];
                    break;
                default:
                    return error;
            }
        }
        error["input"] = current?.DeepClone();
        return error;
    }

    /// <summary>The raw JSON body (null when empty). 422 json_invalid when it is not JSON.</summary>
    public static async Task<JsonNode?> JsonBody(this HttpContext ctx)
    {
        if (ctx.Items.TryGetValue("json-body", out var cached))
            return (JsonNode?)cached;
        using var reader = new StreamReader(ctx.Request.Body);
        var text = await reader.ReadToEndAsync();
        JsonNode? node = null;
        if (!string.IsNullOrWhiteSpace(text))
        {
            try
            {
                node = JsonNode.Parse(text);
            }
            catch (JsonException)
            {
                throw RequestInvalid.Single("json_invalid", "JSON decode error", null, "body", "0");
            }
        }
        ctx.Items["json-body"] = node;
        return node;
    }

    private static IEnumerable<JsonObject> Describe(JsonException e, JsonNode body)
    {
        // e.Path is where the reader stopped: the object that lacks a field, or the bad value
        var (loc, input) = Locate(e.Path, body);
        var missing = MissingRegex().Match(e.Message);
        if (missing.Success)
        {
            foreach (Match m in QuotedRegex().Matches(missing.Groups[1].Value))
                yield return LocatedError("missing", "Field required", input, [.. loc, m.Groups[1].Value]);
            yield break;
        }
        var msg = input is null || input.GetValueKind() == JsonValueKind.Null ? "Input should not be None" : "Input should be a valid value";
        yield return LocatedError(input is null ? "missing" : "type_error", msg, input, loc);
    }

    private static JsonObject LocatedError(string type, string msg, JsonNode? input, List<JsonNode> loc) => new()
    {
        ["type"] = type,
        ["loc"] = new JsonArray(loc.Select(l => (JsonNode?)l.DeepClone()).ToArray()),
        ["msg"] = msg,
        ["input"] = input?.DeepClone(),
    };

    /// <summary>A reader path (<c>$.trials[0].zone</c>) as pydantic's loc, list positions as numbers,
    /// and the value found there in the body.</summary>
    private static (List<JsonNode> Loc, JsonNode? Node) Locate(string? path, JsonNode body)
    {
        var loc = new List<JsonNode> { "body" };
        JsonNode? node = body;
        foreach (Match m in PathRegex().Matches(path ?? "$"))
        {
            if (m.Groups[2].Success)
            {
                var index = int.Parse(m.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture);
                loc.Add(index);
                node = node is JsonArray a && index < a.Count ? a[index] : null;
            }
            else
            {
                var key = m.Groups[1].Success ? m.Groups[1].Value : m.Groups[3].Value;
                loc.Add(key);
                node = node is JsonObject o ? o[key] : null;
            }
        }
        return (loc, node);
    }

    /// <summary>An integer query parameter (FastAPI's <c>Query(default, ge=, le=)</c>); the last value
    /// wins. Problems are added to <paramref name="errors"/> in FastAPI's shape, so all parameters
    /// are reported together (see <see cref="RequestInvalid.ThrowIfAny"/>).</summary>
    public static long QueryInt(this HttpContext ctx, string name, long @default, List<JsonObject> errors, long? ge = null, long? le = null)
    {
        var values = ctx.Request.Query[name];
        if (values.Count == 0)
            return @default;
        var raw = values[^1] ?? "";
        var m = PythonIntRegex().Match(raw);
        if (!m.Success || !long.TryParse(m.Groups[1].Value.Replace("_", ""), out var value))
        {
            errors.Add(RequestInvalid.Error("int_parsing", "Input should be a valid integer, unable to parse string as an integer", raw, "query", name));
            return @default;
        }
        if (ge is not null && value < ge)
        {
            var e = RequestInvalid.Error("greater_than_equal", $"Input should be greater than or equal to {ge}", raw, "query", name);
            e["ctx"] = new JsonObject { ["ge"] = ge };
            errors.Add(e);
        }
        if (le is not null && value > le)
        {
            var e = RequestInvalid.Error("less_than_equal", $"Input should be less than or equal to {le}", raw, "query", name);
            e["ctx"] = new JsonObject { ["le"] = le };
            errors.Add(e);
        }
        return value;
    }

    /// <summary>A required integer query parameter (FastAPI's <c>name: int</c> without a default):
    /// a <c>missing</c> error when it is absent, otherwise as <see cref="QueryInt(HttpContext, string, long, List{JsonObject}, long?, long?)"/>.</summary>
    public static long QueryInt(this HttpContext ctx, string name, List<JsonObject> errors)
    {
        if (ctx.Request.Query[name].Count == 0)
        {
            errors.Add(RequestInvalid.Error("missing", "Field required", null, "query", name));
            return 0;
        }
        return ctx.QueryInt(name, 0, errors);
    }

    /// <summary>A string query parameter (the last value wins); null when it is absent.</summary>
    public static string? QueryStr(this HttpContext ctx, string name)
    {
        var values = ctx.Request.Query[name];
        return values.Count == 0 ? null : values[^1] ?? "";
    }

    /// <summary>A boolean query parameter as pydantic reads it (true/false, 1/0, yes/no, on/off,
    /// t/f, y/n in any case, nothing else; the last value wins).</summary>
    public static bool QueryBool(this HttpContext ctx, string name, bool @default, List<JsonObject> errors)
    {
        var raw = ctx.QueryStr(name);
        switch (raw?.ToLowerInvariant())
        {
            case null:
                return @default;
            case "1" or "on" or "t" or "true" or "y" or "yes":
                return true;
            case "0" or "off" or "f" or "false" or "n" or "no":
                return false;
            default:
                errors.Add(RequestInvalid.Error("bool_parsing", "Input should be a valid boolean, unable to interpret input", raw, "query", name));
                return @default;
        }
    }

    [GeneratedRegex(@"^\s*([+-]?\d+(?:_\d+)*)(?:\.0+)?\s*$")]
    private static partial Regex PythonIntRegex();

    [GeneratedRegex(@"missing required properties including: (.*)\.?$")]
    private static partial Regex MissingRegex();

    [GeneratedRegex("'([^']+)'")]
    private static partial Regex QuotedRegex();

    [GeneratedRegex(@"\.([^.\[]+)|\[(\d+)\]|\['((?:[^']|'')*)'\]")]
    private static partial Regex PathRegex();
}

/// <summary>pydantic-style constraint checks for <see cref="IValidatedBody"/>.</summary>
public static class Check
{
    public static void Literal(List<JsonObject> errors, string? value, string field, params string[] allowed) =>
        LiteralAt(errors, value, ["body", field], allowed);

    /// <summary><see cref="Literal"/> for a nested field, e.g. <c>["body", "targets", "0", "region"]</c>.</summary>
    public static void LiteralAt(List<JsonObject> errors, string? value, string[] loc, params string[] allowed)
    {
        if (value is null || allowed.Contains(value))
            return;
        var expected = allowed.Length == 1
            ? $"'{allowed[0]}'"
            : string.Join(", ", allowed[..^1].Select(a => $"'{a}'")) + $" or '{allowed[^1]}'";
        var error = RequestInvalid.Error("literal_error", $"Input should be {expected}", value, loc);
        error["ctx"] = new JsonObject { ["expected"] = expected };
        errors.Add(error);
    }

    /// <summary>pydantic's <c>Field(min_length=, max_length=)</c> on a list (the input is taken from the raw body).</summary>
    public static void Items<T>(List<JsonObject> errors, IReadOnlyCollection<T>? items, string field, int? min = null, int? max = null)
    {
        if (items is null)
            return;
        var n = items.Count;
        static string Plural(int k) => k == 1 ? "item" : "items";
        if (min is { } lo && n < lo)
        {
            var e = RequestInvalid.Error("too_short", $"List should have at least {lo} {Plural(lo)} after validation, not {n}", null, "body", field);
            e["ctx"] = new JsonObject { ["field_type"] = "List", ["min_length"] = lo, ["actual_length"] = n };
            errors.Add(e);
        }
        if (max is { } hi && n > hi)
        {
            var e = RequestInvalid.Error("too_long", $"List should have at most {hi} {Plural(hi)} after validation, not {n}", null, "body", field);
            e["ctx"] = new JsonObject { ["field_type"] = "List", ["max_length"] = hi, ["actual_length"] = n };
            errors.Add(e);
        }
    }

    public static void MinLength(List<JsonObject> errors, string? value, string field, int min)
    {
        if (value is null || value.Length >= min)
            return;
        var e = RequestInvalid.Error("string_too_short", $"String should have at least {min} character{(min == 1 ? "" : "s")}", value, "body", field);
        e["ctx"] = new JsonObject { ["min_length"] = min };
        errors.Add(e);
    }

    public static void MaxLength(List<JsonObject> errors, string? value, string field, int max)
    {
        if (value is null || value.Length <= max)
            return;
        var e = RequestInvalid.Error("string_too_long", $"String should have at most {max} character{(max == 1 ? "" : "s")}", value, "body", field);
        e["ctx"] = new JsonObject { ["max_length"] = max };
        errors.Add(e);
    }

    public static void Range(List<JsonObject> errors, double? value, string field, double? ge = null, double? le = null, double? gt = null, double? lt = null)
    {
        if (value is null)
            return;
        var v = value.Value;
        if (ge is not null && v < ge)
            errors.Add(RequestInvalid.Error("greater_than_equal", $"Input should be greater than or equal to {Num(ge.Value)}", Json.Float(v), "body", field));
        if (le is not null && v > le)
            errors.Add(RequestInvalid.Error("less_than_equal", $"Input should be less than or equal to {Num(le.Value)}", Json.Float(v), "body", field));
        if (gt is not null && v <= gt)
            errors.Add(RequestInvalid.Error("greater_than", $"Input should be greater than {Num(gt.Value)}", Json.Float(v), "body", field));
        if (lt is not null && v >= lt)
            errors.Add(RequestInvalid.Error("less_than", $"Input should be less than {Num(lt.Value)}", Json.Float(v), "body", field));
    }

    private static string Num(double d) => d == Math.Floor(d) ? ((long)d).ToString() : Json.PythonFloat(d);
}
