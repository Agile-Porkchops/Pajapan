using Pajapan.Api.Infrastructure;

namespace Pajapan.Api.Features.Me;

// The reference example for the CQRS convention (docs/plan/README.md, Global
// Constraint 17): one file per use case — the message, its handler, its response.

public sealed record GetMeQuery;

public sealed record MeResponse(Guid Id, string DisplayName, string Email, string Role);

public static class GetMeHandler
{
    // Identity comes from the injected CurrentUser, never from the query itself.
    // CurrentUser creates the AppUser row on first sight: the one write allowed on
    // a read path, because it is identity resolution, not this query's logic.
    public static async Task<MeResponse> Handle(GetMeQuery query, CurrentUser me, CancellationToken ct)
    {
        var u = await me.GetAsync(ct);
        return new MeResponse(u.Id, u.DisplayName, u.Email, u.Role.ToString());
    }
}
