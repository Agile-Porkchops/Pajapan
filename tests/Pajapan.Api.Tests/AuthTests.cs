using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Pajapan.Api.Enums;

namespace Pajapan.Api.Tests;

public class AuthTests(DbFixture fx) : IClassFixture<DbFixture>
{
    private HttpClient Client(string? token = null)
    {
        var client = fx.Api.CreateClient();
        if (token is not null)
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    [Fact]
    public async Task No_token_is_401()
    {
        var response = await Client().GetAsync("/api/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Anon_key_token_is_401()
    {
        // Supabase issues anon tokens with the same issuer and signing key as a
        // logged-in user's. Only the audience separates them.
        var response = await Client(TestJwt.Mint(audience: "anon")).GetAsync("/api/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Expired_token_is_401()
    {
        var expired = TestJwt.Mint(expires: DateTime.UtcNow.AddMinutes(-10));

        var response = await Client(expired).GetAsync("/api/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task First_login_creates_AppUser_as_Customer()
    {
        var sub = Guid.NewGuid();

        var response = await Client(TestJwt.Mint(sub)).GetAsync("/api/me");

        var body = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, body);

        await using var db = fx.NewContext();
        var user = await db.Users.SingleOrDefaultAsync(u => u.Id == sub);
        Assert.NotNull(user);
        Assert.Equal(AppUserRole.Customer, user.Role);
    }

    [Fact]
    public async Task Role_claim_in_token_is_ignored()
    {
        var sub = Guid.NewGuid();

        // A forged role claim. Supabase's admin API can set app_metadata, so a role
        // claim is not something the API may act on. Authority lives in our table.
        var response = await Client(TestJwt.Mint(sub, role: "admin")).GetAsync("/api/me");

        var raw = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, raw);

        var body = JsonDocument.Parse(raw).RootElement;
        Assert.Equal("Customer", body.GetProperty("role").GetString());

        await using var db = fx.NewContext();
        var user = await db.Users.SingleOrDefaultAsync(u => u.Id == sub);
        Assert.NotNull(user);
        Assert.Equal(AppUserRole.Customer, user.Role);
    }
}
