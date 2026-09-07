using Microsoft.AspNetCore.Authorization;
using Pajapan.Api.Domain;

namespace Pajapan.Api.Infrastructure;

/// Policy names, and the role each one admits. Admin satisfies every policy —
/// spec §6: "Admin — everything above."
public static class AuthPolicies
{
    public const string Admin = nameof(Admin);
    public const string Fulfilment = nameof(Fulfilment);
    public const string JapanBuyer = nameof(JapanBuyer);
    public const string Staff = nameof(Staff);

    public static void Configure(AuthorizationOptions o)
    {
        o.AddPolicy(Admin, p => p.AddRequirements(
            new RoleRequirement(AppUserRole.Admin)));

        o.AddPolicy(Fulfilment, p => p.AddRequirements(
            new RoleRequirement(AppUserRole.Fulfilment, AppUserRole.Admin)));

        o.AddPolicy(JapanBuyer, p => p.AddRequirements(
            new RoleRequirement(AppUserRole.JapanBuyer, AppUserRole.Admin)));

        // "Any non-customer."
        o.AddPolicy(Staff, p => p.AddRequirements(
            new RoleRequirement(AppUserRole.JapanBuyer, AppUserRole.Fulfilment, AppUserRole.Admin)));
    }
}

public sealed class RoleRequirement(params AppUserRole[] allowed) : IAuthorizationRequirement
{
    public IReadOnlyList<AppUserRole> Allowed { get; } = allowed;
}

/// Resolves the caller's role from the app_user table, never from the token.
/// Registered scoped, because CurrentUser is.
public sealed class RoleHandler(CurrentUser current) : AuthorizationHandler<RoleRequirement>
{
    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context, RoleRequirement requirement)
    {
        if (context.User.Identity?.IsAuthenticated is not true) return;

        var user = await current.GetAsync();
        if (requirement.Allowed.Contains(user.Role)) context.Succeed(requirement);
    }
}
