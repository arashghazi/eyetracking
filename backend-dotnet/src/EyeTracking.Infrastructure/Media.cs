using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;

namespace EyeTracking.Infrastructure;

/// <summary>Private file storage for approved content media (backend/eyetracking/infrastructure/media.py).
/// Files live outside the web root and are only reachable through signed URLs.</summary>
public sealed class LocalMediaStore(string root) : IMediaStore
{
    public string Root { get; } = Path.GetFullPath(root);

    public string Save(string relativePath, byte[] data)
    {
        var full = Absolute(relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllBytes(full, data);
        return relativePath;
    }

    public string Absolute(string relativePath)
    {
        var full = Path.GetFullPath(Path.Combine(Root, relativePath));
        if (!full.StartsWith(Root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            throw new ArgumentException("invalid media path");
        return full;
    }
}

/// <summary>Short-lived, signed media tokens: base64url(json{m, e}) + '.' + hex HMAC-SHA256
/// (HmacMediaSigner in backend/eyetracking/infrastructure/security.py). The payload is the exact
/// text Python's <c>json.dumps</c> writes, so tokens from either service verify in the other.
/// No database lookup to verify.</summary>
public sealed class HmacMediaSigner(string secret, int ttlSeconds = 6 * 3600, Func<double>? unixNow = null) : IMediaSigner
{
    private readonly byte[] _key = Encoding.UTF8.GetBytes(secret);
    private readonly Func<double> _now = unixNow ?? (() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0);

    private string Mac(string payload) => Convert.ToHexStringLower(HMACSHA256.HashData(_key, Encoding.UTF8.GetBytes(payload)));

    public string Sign(int mediaId)
    {
        // json.dumps({"m": media_id, "e": int(time.time()) + ttl}) with its default separators
        var expires = (long)Math.Floor(_now()) + ttlSeconds;
        var payload = Base64Url.EncodeToString(Encoding.UTF8.GetBytes($"{{\"m\": {mediaId}, \"e\": {expires}}}"));
        return $"{payload}.{Mac(payload)}";
    }

    public int? Verify(string token)
    {
        try
        {
            var dot = token.IndexOf('.');
            if (dot < 0)
                return null;
            var payload = token[..dot];
            var mac = token[(dot + 1)..];
            // hmac.compare_digest: constant time, and only ASCII text compares at all
            if (!Ascii.IsValid(mac) || !CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(mac), Encoding.ASCII.GetBytes(Mac(payload))))
                return null;
            if (JsonNode.Parse(Base64Url.DecodeFromChars(payload)) is not JsonObject data)
                return null;
            if (Math.Truncate(Json.Num(data["e"]) ?? throw new FormatException("e")) < _now())
                return null;
            return checked((int)(Json.Num(data["m"]) ?? throw new FormatException("m")));
        }
        catch (Exception e) when (e is FormatException or JsonException or InvalidOperationException or ArgumentException or OverflowException)
        {
            return null;
        }
    }
}
