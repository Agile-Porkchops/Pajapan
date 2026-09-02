using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Pajapan.Api.Domain;

namespace Pajapan.Api.Data.Configurations
{
    public class AppUserConfiguration : IEntityTypeConfiguration<AppUser>
    {
        public void Configure(EntityTypeBuilder<AppUser> b)
        {
            b.Property(u => u.Id).ValueGeneratedNever();
            b.HasIndex(u => u.Email).IsUnique();
            b.Property(u => u.Role).HasConversion<int>();
        }
    }
}
