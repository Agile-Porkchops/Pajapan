using MediatR;

namespace Pajapan.Api.Features.Me;

public static class MeEndpoints
{
    public static void MapMeEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/me", async (ISender sender, CancellationToken ct) =>
                Results.Ok(await sender.Send(new GetMeQuery(), ct)))
            .RequireAuthorization();
    }
}