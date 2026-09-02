using Pajapan.Api.Enums;

namespace Pajapan.Api.Domain
{
    public class AppUser
    {
        public Guid Id { get; set; }
        public AppUserRole Role { get; set; } = AppUserRole.Customer;
        public string DisplayName { get; set; } = string.Empty;
        public string? Phone {  get; set; }
        public string Email { get; set; } = string.Empty;
        public bool IsBlocked { get; set; }
        public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    }
}
