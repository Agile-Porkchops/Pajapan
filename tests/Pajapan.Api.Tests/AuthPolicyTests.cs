using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Pajapan.Api.Domain;
using Pajapan.Api.Infrastructure;

namespace Pajapan.Api.Tests;

/// Exercises the policies through the API's own container — AuthPolicies.Configure,
/// RoleRequirement, RoleHandler and CurrentUser — against a real app_user row.
///
/// No endpoint carries a policy yet; M1 is the first consumer. These tests are what
/// stops that machinery reaching M1 unproven.
public class AuthPolicyTests(DbFixture fx) : IClassFixture<DbFixture>
{
    /// Seeds a user with the given role and asks the real IAuthorizationService
    /// whether they satisfy the named policy.
    private async Task<bool> Allowed(AppUserRole role, string policy, bool authenticated = true)
    {
        var id = Guid.NewGuid();
        await using (var db = fx.NewContext())
        {
            db.Users.Add(new AppUser { Id = id, Email = $"{id}@example.test", Role = role });
            await db.SaveChangesAsync();
        }

        // An identity with no authentication type reports IsAuthenticated false.
        var identity = authenticated
            ? new ClaimsIdentity([new Claim("sub", id.ToString())], "Test")
            : new ClaimsIdentity([new Claim("sub", id.ToString())]);
        var principal = new ClaimsPrincipal(identity);

        using var scope = fx.Api.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<IHttpContextAccessor>().HttpContext =
            new DefaultHttpContext { User = principal, RequestServices = scope.ServiceProvider };

        var authz = scope.ServiceProvider.GetRequiredService<IAuthorizationService>();
        return (await authz.AuthorizeAsync(principal, resource: null, policy)).Succeeded;
    }

    [Theory]
    [InlineData(AppUserRole.Customer, false)]
    [InlineData(AppUserRole.JapanBuyer, false)]
    [InlineData(AppUserRole.Fulfilment, false)]
    [InlineData(AppUserRole.Admin, true)]
    public async Task Admin_policy_admits_only_Admin(AppUserRole role, bool expected) =>
        Assert.Equal(expected, await Allowed(role, AuthPolicies.Admin));

    [Theory]
    [InlineData(AppUserRole.Customer, false)]
    [InlineData(AppUserRole.JapanBuyer, false)]   // spec §6.1: no finance or payment access
    [InlineData(AppUserRole.Fulfilment, true)]
    [InlineData(AppUserRole.Admin, true)]         // spec §6: "Admin — everything above"
    public async Task Fulfilment_policy_admits_Fulfilment_and_Admin(AppUserRole role, bool expected) =>
        Assert.Equal(expected, await Allowed(role, AuthPolicies.Fulfilment));

    [Theory]
    [InlineData(AppUserRole.Customer, false)]     // "any non-customer"
    [InlineData(AppUserRole.JapanBuyer, true)]
    [InlineData(AppUserRole.Fulfilment, true)]
    [InlineData(AppUserRole.Admin, true)]
    public async Task Staff_policy_admits_any_non_customer(AppUserRole role, bool expected) =>
        Assert.Equal(expected, await Allowed(role, AuthPolicies.Staff));

    [Fact]
    public async Task Unauthenticated_principal_is_denied_even_with_an_admin_row() =>
        Assert.False(await Allowed(AppUserRole.Admin, AuthPolicies.Admin, authenticated: false));
}
