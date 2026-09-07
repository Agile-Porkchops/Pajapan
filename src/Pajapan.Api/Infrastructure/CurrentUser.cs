using Microsoft.EntityFrameworkCore;
using Pajapan.Api.Data;
using Pajapan.Api.Domain;

namespace Pajapan.Api.Infrastructure;

public sealed class CurrentUser(IHttpContextAccessor http, AppDbContext db)
{
    private AppUser? _cached;

    public Guid Id => Guid.TryParse(
        http.HttpContext?.User.FindFirst("sub")?.Value, out var id)
            ? id
            : throw new UnauthorizedAccessException("No sub claim on the token.");

    /// Loads the AppUser row, creating it on first sight of a Supabase user.
    public async ValueTask<AppUser> GetAsync(CancellationToken ct = default)
    {
        if (_cached is not null) return _cached;
        var id = Id;
        _cached = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct);
        if (_cached is null)
        {
            _cached = new AppUser
            {
                Id = id,
                Email = http.HttpContext!.User.FindFirst("email")?.Value ?? "",
                Role = AppUserRole.Customer,   // never trust a role claim from the token
            };
            db.Users.Add(_cached);
            await db.SaveChangesAsync(ct);
        }
        if (_cached.IsBlocked) throw new UnauthorizedAccessException("User is blocked.");
        return _cached;
    }
}