using Pajapan.Api.Infrastructure;

namespace Pajapan.Api.Features.Me;

public static class MeEndpoints
{
    public static void MapMeEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/me", async (CurrentUser me, CancellationToken ct) =>
        {
            var u = await me.GetAsync(ct);
            return Results.Ok(new
            {
                id = u.Id,
                displayName = u.DisplayName,
                email = u.Email,
                role = u.Role.ToString(),
            });
        })
        .RequireAuthorization();
    }
}