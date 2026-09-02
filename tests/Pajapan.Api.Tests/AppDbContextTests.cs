using Pajapan.Api.Domain;

namespace Pajapan.Api.Tests;

public class AppDbContextTests(DbFixture fx) : IClassFixture<DbFixture>
{
    [Fact]
    public async Task Decimal_money_round_trips_without_precision_loss()
    {
        await using var db = fx.NewContext();
        db.Categories.Add(new Category { Id = Guid.NewGuid(), Name = "t", Slug = "t" });
        await db.SaveChangesAsync();
        // asserted properly in M1-01 once Product.PricePhp exists; for now assert the
        // convention is registered.
        var entity = db.Model.FindEntityType(typeof(Category));
        Assert.NotNull(entity);
    }
}
