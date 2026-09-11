using MediatR;
using Pajapan.Api.Infrastructure;

namespace Pajapan.Api.Features.Me;

// The reference example for the CQRS convention (docs/plan/README.md, Global
// Constraint 17): one file per use case — the request, its handler, its response.

public sealed record GetMeQuery : IRequest<MeResponse>;

public sealed record MeResponse(Guid Id, string DisplayName, string Email, string Role);

public sealed class GetMeHandler(CurrentUser me) : IRequestHandler<GetMeQuery, MeResponse>
{
    public async Task<MeResponse> Handle(GetMeQuery query, CancellationToken ct)
    {
        // Identity comes from the injected CurrentUser, never from the query itself.
        // CurrentUser creates the AppUser row on first sight: the one write allowed on
        // a read path, because it is identity resolution, not this query's logic.
        var u = await me.GetAsync(ct);
        return new MeResponse(u.Id, u.DisplayName, u.Email, u.Role.ToString());
    }
}
