using System.Net;

namespace Pajapan.Api.Tests;

public class HealthTests(DbFixture fx) : IClassFixture<DbFixture>
{
    [Fact]
    public async Task Health_is_200_when_db_reachable()
    {
        var response = await fx.Api.CreateClient().GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Health_is_503_when_db_unreachable()
    {
        // A separate host pointed at a connection string that fails fast --
        // "Timeout=1" turns Npgsql's default multi-second connect timeout
        // into an immediate failure, so this doesn't slow the suite down.
        await using var badApi = new ApiFactory(
            "Host=localhost;Port=1;Database=nonexistent;Username=x;Password=x;Timeout=1");

        var response = await badApi.CreateClient().GetAsync("/health");

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }
}
