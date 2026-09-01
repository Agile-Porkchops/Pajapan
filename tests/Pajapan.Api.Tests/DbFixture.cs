using Microsoft.EntityFrameworkCore;
using Pajapan.Api.Data;
using Testcontainers.PostgreSql;

namespace Pajapan.Api.Tests;

public sealed class DbFixture : IAsyncLifetime
{
#pragma warning disable CS0618 // ponytail: PostgreSqlBuilder() ctor obsolete in 4.14 — revisit migration path
    private readonly PostgreSqlContainer _pg = new PostgreSqlBuilder()
        .WithImage("postgres:17-alpine").Build();
#pragma warning restore CS0618

    public string ConnectionString => _pg.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _pg.StartAsync();
        await using var db = NewContext();
        await db.Database.MigrateAsync();
    }

    public AppDbContext NewContext() => new(new DbContextOptionsBuilder<AppDbContext>()
        .UseNpgsql(ConnectionString).Options);

    public Task DisposeAsync() => _pg.DisposeAsync().AsTask();
}
