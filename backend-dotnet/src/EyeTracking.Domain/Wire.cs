using System.Collections.Concurrent;
using System.Text.Json;

namespace EyeTracking.Domain;

/// <summary>Enums travel and are stored as snake_case strings (<c>CameraOk</c> is <c>"camera_ok"</c>),
/// the same values the Python service used.</summary>
public static class Wire
{
    private static readonly ConcurrentDictionary<Enum, string> Names = new();

    public static string Name(string pascal) => JsonNamingPolicy.SnakeCaseLower.ConvertName(pascal);

    public static string Value(this Enum e) => Names.GetOrAdd(e, x => Name(x.ToString()));

    public static T Parse<T>(string wire) where T : struct, Enum =>
        TryParse<T>(wire, out var value) ? value : throw new Invalid($"'{wire}' is not a valid {Name(typeof(T).Name).Replace('_', ' ')}");

    public static bool TryParse<T>(string? wire, out T value) where T : struct, Enum
    {
        foreach (var candidate in Enum.GetValues<T>())
        {
            if (candidate.Value() == wire)
            {
                value = candidate;
                return true;
            }
        }
        value = default;
        return false;
    }

    public static string[] Values<T>() where T : struct, Enum => Enum.GetValues<T>().Select(e => e.Value()).ToArray();
}
