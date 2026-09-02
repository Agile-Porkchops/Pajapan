using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Pajapan.Api.Domain;

namespace Pajapan.Api.Data
{
    public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
    {
        public DbSet<AppUser> Users => Set<AppUser>();
        public DbSet<Category> Categories => Set<Category>();

        protected override void ConfigureConventions(ModelConfigurationBuilder b)
        {
            // Every decimal in the model is money. 12,2 unless a config overrides it.
            b.Properties<decimal>().HavePrecision(12, 2);
        }

        protected override void OnModelCreating(ModelBuilder b)
        {
            b.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
            // snake_case in Postgres, PascalCase in C#.
            foreach (var entity in b.Model.GetEntityTypes())
            {
                entity.SetTableName(ToSnake(entity.GetTableName()!));
                foreach (var p in entity.GetProperties()) p.SetColumnName(ToSnake(p.Name));
            }
        }

        private static string ToSnake(string name) =>
            string.Concat(name.Select((c, i) => 
                i > 0 && char.IsUpper(c) ? "_" + 
                char.ToLowerInvariant(c) : char.ToLowerInvariant(c).ToString()));
    }
}
