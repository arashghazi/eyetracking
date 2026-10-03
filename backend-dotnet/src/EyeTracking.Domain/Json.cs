using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace EyeTracking.Domain;

/// <summary>Helpers for the free-form JSON the Python service kept as dicts and lists
/// (layouts, payloads, answers). Reads follow Python's semantics: a missing key and JSON
/// null are both "None", and truthiness is Python's.</summary>
public static class Json
{
    public static string? Str(JsonNode? n) =>
        n is JsonValue v && v.GetValueKind() == JsonValueKind.String ? v.GetValue<string>() : null;

    public static double? Num(JsonNode? n)
    {
        if (n is not JsonValue v || v.GetValueKind() != JsonValueKind.Number)
            return null;
        // parsed numbers read as double; numbers built in code (int, long, ...) via their JSON text
        return v.TryGetValue<double>(out var d) ? d : double.Parse(v.ToJsonString(), NumberStyles.Float, CultureInfo.InvariantCulture);
    }

    public static int? Int(JsonNode? n)
    {
        var d = Num(n);
        return d is null ? null : (int)d.Value;
    }

    public static bool IsNumber(JsonNode? n) => n is JsonValue v && v.GetValueKind() == JsonValueKind.Number;

    public static bool IsBool(JsonNode? n) => n is JsonValue v && v.GetValueKind() is JsonValueKind.True or JsonValueKind.False;

    /// <summary>Python truthiness: None, False, 0, "", [] and {} are false.</summary>
    public static bool Truthy(JsonNode? n) => n switch
    {
        null => false,
        JsonArray a => a.Count > 0,
        JsonObject o => o.Count > 0,
        JsonValue v => v.GetValueKind() switch
        {
            JsonValueKind.True => true,
            JsonValueKind.String => v.GetValue<string>().Length > 0,
            JsonValueKind.Number => Num(v) != 0,
            _ => false,
        },
        _ => false,
    };

    public static bool Bool(JsonNode? n) => Truthy(n);

    /// <summary>Python's <c>value in (None, "")</c>.</summary>
    public static bool IsBlank(JsonNode? n) =>
        n is null || n.GetValueKind() == JsonValueKind.Null || (n.GetValueKind() == JsonValueKind.String && n.GetValue<string>().Length == 0);

    public static JsonNode? Clone(JsonNode? n) => n?.DeepClone();

    public static JsonObject CloneObj(JsonObject? o) => o is null ? [] : (JsonObject)o.DeepClone();

    public static JsonArray CloneArr(JsonArray? a) => a is null ? [] : (JsonArray)a.DeepClone();

    public static JsonArray Array<T>(IEnumerable<T> items) => new(items.Select(i => i is JsonNode n ? n : JsonValue.Create(i)).ToArray<JsonNode?>());

    /// <summary>A float formatted the way Python's json module writes it (<c>1.0</c>, not <c>1</c>).</summary>
    public static JsonNode Float(double value) => JsonNode.Parse(PythonFloat(value))!;

    public static string PythonFloat(double value)
    {
        if (double.IsNaN(value)) return "NaN";
        if (double.IsPositiveInfinity(value)) return "Infinity";
        if (double.IsNegativeInfinity(value)) return "-Infinity";
        // the shortest round-trip digits, as Python's repr; a custom format like "0.0" would keep
        // only 15 significant digits (9999999999999998.0 would print as 10000000000000000.0)
        var r = value.ToString("R", CultureInfo.InvariantCulture);
        if (!r.Contains('E'))
        {
            if (Math.Abs(value) >= 1e16)
            {
                // Python switches to an exponent from 1e16 on, .NET only from 1e17 (these are all integers)
                var digits = r.TrimStart('-');
                var mantissa = digits.TrimEnd('0');
                r = (value < 0 ? "-" : "") + mantissa[0] + (mantissa.Length > 1 ? "." + mantissa[1..] : "")
                    + "E+" + (digits.Length - 1).ToString(CultureInfo.InvariantCulture);
            }
            else if (!r.Contains('.'))
            {
                r += ".0";
            }
        }
        // Python writes 1e-05 and 1e+16 where .NET writes 1E-05 and 1E+16.
        return r.Replace("E", "e");
    }
}
