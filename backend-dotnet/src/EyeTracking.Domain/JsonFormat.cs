using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace EyeTracking.Domain;

/// <summary>The wire format of the Python service: snake_case names, snake_case enum values,
/// naive UTC timestamps (<c>2026-10-03T10:15:00.123456</c>) and floats written as Python writes
/// them (<c>1.0</c>). Used for HTTP responses and for entity snapshots in exports.</summary>
public static class JsonFormat
{
    public static readonly JsonSerializerOptions Options = Create();

    private static JsonSerializerOptions Create()
    {
        var o = new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            DictionaryKeyPolicy = null,
            DefaultIgnoreCondition = JsonIgnoreCondition.Never,
            NumberHandling = JsonNumberHandling.Strict,
            WriteIndented = false,
        };
        o.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower, allowIntegerValues: false));
        o.Converters.Add(new NaiveDateTimeConverter());
        o.Converters.Add(new PythonDoubleConverter());
        o.MakeReadOnly(populateMissingResolver: true);
        return o;
    }

    /// <summary>All public properties of an entity as a snake_case JSON object (Python's <c>obj.__dict__</c>).</summary>
    public static JsonObject Entity(object entity) => JsonSerializer.SerializeToNode(entity, entity.GetType(), Options)!.AsObject();

    public static string Timestamp(DateTime t)
    {
        var s = t.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture);
        var micro = (int)(t.Ticks % TimeSpan.TicksPerSecond / 10);
        return micro == 0 ? s : s + "." + micro.ToString("D6", CultureInfo.InvariantCulture);
    }

    private sealed class NaiveDateTimeConverter : JsonConverter<DateTime>
    {
        public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var text = reader.GetString() ?? throw new JsonException("timestamp expected");
            var parsed = DateTime.Parse(text, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal);
            return DateTime.SpecifyKind(parsed, DateTimeKind.Unspecified);
        }

        public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options) =>
            writer.WriteStringValue(Timestamp(value));
    }

    private sealed class PythonDoubleConverter : JsonConverter<double>
    {
        public override double Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            reader.TokenType == JsonTokenType.Number ? reader.GetDouble() : throw new JsonException("number expected");

        public override void Write(Utf8JsonWriter writer, double value, JsonSerializerOptions options) =>
            writer.WriteRawValue(Json.PythonFloat(value), skipInputValidation: true);
    }
}
