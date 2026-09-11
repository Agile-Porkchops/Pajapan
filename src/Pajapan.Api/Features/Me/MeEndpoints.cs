using Wolverine;

namespace Pajapan.Api.Features.Me;

public static class MeEndpoints
{
    public static void MapMeEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/me", async (IMessageBus bus, CancellationToken ct) =>
                Results.Ok(await bus.InvokeAsync<MeResponse>(new GetMeQuery(), ct)))
            .RequireAuthorization();
    }
}
