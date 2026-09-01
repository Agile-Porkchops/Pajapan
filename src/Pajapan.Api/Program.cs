using Microsoft.EntityFrameworkCore;
using Pajapan.Api.Data;

var builder = WebApplication.CreateBuilder(args);

foreach (var key in new[] { "Supabase:Url", "Supabase:ServiceKey", "ConnectionStrings:Db" })
{
    var v = builder.Configuration[key];
    if (string.IsNullOrWhiteSpace(v) || v == "__SET_LOCALLY__")
        throw new InvalidOperationException($"Configuration '{key}' is not set.");
}

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Db")));

var app = builder.Build();
