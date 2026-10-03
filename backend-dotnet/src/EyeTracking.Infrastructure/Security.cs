using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using EyeTracking.Application;
using Isopoh.Cryptography.Argon2;

namespace EyeTracking.Infrastructure;

/// <summary>Argon2id in the PHC string format, the same parameters as argon2-cffi's defaults
/// (t=3, m=64 MiB, p=4), so hashes written by the Python service verify here too.</summary>
public sealed class Argon2Hasher : IPasswordHasher
{
    public string Hash(string password) =>
        Argon2.Hash(password, timeCost: 3, memoryCost: 65536, parallelism: 4, type: Argon2Type.HybridAddressing, hashLength: 32);

    public bool Verify(string password, string passwordHash)
    {
        try
        {
            return passwordHash.StartsWith("$argon2", StringComparison.Ordinal) && Argon2.Verify(passwordHash, password);
        }
        catch
        {
            return false;
        }
    }
}

/// <summary>HS256 bearer tokens: <c>sub</c> (user id), <c>role</c>, <c>iat</c>, <c>exp</c>.
/// Written by hand because the Microsoft JWT library refuses secrets shorter than 32 bytes.</summary>
public sealed class JwtTokens(string secret, int expireMinutes = 120) : ITokenIssuer
{
    private readonly byte[] _key = Encoding.UTF8.GetBytes(secret);
    private static readonly string Header = B64(Encoding.UTF8.GetBytes("""{"alg":"HS256","typ":"JWT"}"""));

    public string Issue(int userId, string role)
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var payload = new JsonObject { ["sub"] = userId.ToString(), ["role"] = role, ["iat"] = now, ["exp"] = now + expireMinutes * 60 };
        var signingInput = Header + "." + B64(Encoding.UTF8.GetBytes(payload.ToJsonString()));
        return signingInput + "." + B64(HMACSHA256.HashData(_key, Encoding.ASCII.GetBytes(signingInput)));
    }

    public int? Parse(string token)
    {
        try
        {
            var parts = token.Split('.');
            if (parts.Length != 3)
                return null;
            var header = JsonNode.Parse(Base64Url.DecodeFromChars(parts[0]))!;
            if ((string?)header["alg"] != "HS256")
                return null;
            var expected = HMACSHA256.HashData(_key, Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]));
            if (!CryptographicOperations.FixedTimeEquals(expected, Base64Url.DecodeFromChars(parts[2])))
                return null;
            var payload = JsonNode.Parse(Base64Url.DecodeFromChars(parts[1]))!;
            var exp = payload["exp"]?.GetValue<double>();
            if (exp is null || exp.Value <= DateTimeOffset.UtcNow.ToUnixTimeSeconds())
                return null;
            return int.Parse((string)payload["sub"]!);
        }
        catch (Exception e) when (e is FormatException or JsonException or InvalidOperationException or ArgumentException or OverflowException)
        {
            return null;
        }
    }

    private static string B64(byte[] bytes) => Base64Url.EncodeToString(bytes);
}

/// <summary>UTC to the microsecond, the precision of the datetime2(6) columns.</summary>
public sealed class SystemClock : IClock
{
    public DateTime Now()
    {
        var ticks = DateTime.UtcNow.Ticks;
        return new DateTime(ticks - ticks % 10, DateTimeKind.Unspecified);
    }
}
