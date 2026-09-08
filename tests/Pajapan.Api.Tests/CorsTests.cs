namespace Pajapan.Api.Tests;

/// CORS headers are added by middleware regardless of auth outcome, so these
/// don't need a token — only the Origin header the browser itself would send.
public class CorsTests(DbFixture fx) : IClassFixture<DbFixture>
{
    [Fact]
    public async Task Allowed_origin_gets_the_cors_header()
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, "/api/me");
        req.Headers.Add("Origin", "http://localhost:5173");

        var response = await fx.Api.CreateClient().SendAsync(req);

        Assert.Equal("http://localhost:5173",
            response.Headers.GetValues("Access-Control-Allow-Origin").Single());
    }

    [Fact]
    public async Task Unlisted_origin_gets_no_cors_header()
    {
        // The header's absence is the enforcement — the browser (not the API)
        // refuses to hand the response to script from an unlisted origin.
        using var req = new HttpRequestMessage(HttpMethod.Get, "/api/me");
        req.Headers.Add("Origin", "http://evil.example");

        var response = await fx.Api.CreateClient().SendAsync(req);

        Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
    }
}
