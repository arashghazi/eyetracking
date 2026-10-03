using System.Text.Json;
using System.Text.Json.Nodes;
using EyeTracking.Domain;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace EyeTracking.Infrastructure.Db;

public sealed class SnakeEnumConverter<T>() : ValueConverter<T, string>(v => v.Value(), v => Wire.Parse<T>(v))
    where T : struct, Enum;

public sealed class JsonObjectConverter() : ValueConverter<JsonObject, string>(
    v => v.ToJsonString((JsonSerializerOptions?)null),
    v => JsonNode.Parse(v, null, default)!.AsObject());

public sealed class JsonArrayConverter() : ValueConverter<JsonArray, string>(
    v => v.ToJsonString((JsonSerializerOptions?)null),
    v => JsonNode.Parse(v, null, default)!.AsArray());

public sealed class StringListConverter() : ValueConverter<List<string>, string>(
    v => JsonSerializer.Serialize(v, (JsonSerializerOptions?)null),
    v => JsonSerializer.Deserialize<List<string>>(v, (JsonSerializerOptions?)null) ?? new List<string>());

/// <summary>JSON columns change when their serialized text changes, so in-place edits
/// (<c>session.Camera["label"] = ...</c>) are saved like reassignments.</summary>
public sealed class JsonNodeComparer<T>() : ValueComparer<T>(
    (a, b) => JsonNode.DeepEquals(a, b),
    v => v == null ? 0 : v.ToJsonString((JsonSerializerOptions?)null).GetHashCode(),
    v => (T)v.DeepClone()) where T : JsonNode;

public sealed class StringListComparer() : ValueComparer<List<string>>(
    (a, b) => a == null ? b == null : b != null && a.SequenceEqual(b),
    v => v.Aggregate(0, (h, s) => HashCode.Combine(h, s.GetHashCode())),
    v => v.ToList());
