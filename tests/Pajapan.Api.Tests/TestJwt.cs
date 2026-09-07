using System.Security.Cryptography;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace Pajapan.Api.Tests;

/// The key the test host trusts in place of Supabase's JWKS, and a minter for
/// tokens signed with it. Everything else about validation stays production's.
public static class TestJwt
{
    public const string SupabaseUrl = "https://test.supabase.co";
    private const string Issuer = SupabaseUrl + "/auth/v1";

    private static readonly ECDsaSecurityKey Key =
        new(ECDsa.Create(ECCurve.NamedCurves.nistP256)) { KeyId = "test-key" };

    public static SecurityKey SigningKey => Key;

    public static string Mint(
        Guid? sub = null,
        string audience = "authenticated",
        string? email = null,
        string? role = null,
        DateTime? expires = null)
    {
        var id = sub ?? Guid.NewGuid();
        var exp = expires ?? DateTime.UtcNow.AddMinutes(5);

        var claims = new Dictionary<string, object>
        {
            ["sub"] = id.ToString(),
            // Derived from sub, not a constant: app_user.Email is uniquely indexed,
            // and Supabase guarantees one email per auth user. A shared literal here
            // makes any two new-user tests collide on the second insert.
            ["email"] = email ?? $"{id}@example.test",
        };
        if (role is not null) claims["role"] = role;

        return new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = Issuer,
            Audience = audience,
            Claims = claims,
            NotBefore = exp.AddMinutes(-30),
            Expires = exp,
            SigningCredentials = new SigningCredentials(Key, SecurityAlgorithms.EcdsaSha256),
        });
    }
}