using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Pajapan.Api.Data;
using Pajapan.Api.Features.Me;
using Pajapan.Api.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

foreach (var key in new[] { "Supabase:Url", "Supabase:ServiceKey", "ConnectionStrings:Db" })
{
    var v = builder.Configuration[key];
    if (string.IsNullOrWhiteSpace(v) || v == "__SET_LOCALLY__")
        throw new InvalidOperationException($"Configuration '{key}' is not set.");
}

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Db")));

builder.Services.AddHttpContextAccessor();

var supabaseUrl = builder.Configuration["Supabase:Url"]!.TrimEnd('/');

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.Authority = $"{supabaseUrl}/auth/v1";
        o.MetadataAddress = $"{supabaseUrl}/auth/v1/.well-known/openid-configuration";
        o.MapInboundClaims = false;
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = $"{supabaseUrl}/auth/v1",
            ValidateAudience = true,
            ValidAudience = "authenticated",
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = "sub",
        };
    });

builder.Services.AddAuthorization(AuthPolicies.Configure);
builder.Services.AddScoped<CurrentUser>();
builder.Services.AddScoped<IAuthorizationHandler, RoleHandler>();

builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<UnauthorizedExceptionHandler>();

var app = builder.Build();

// Inside the developer exception page, not outside it: anything this handler
// declines keeps propagating and still renders with its stack trace.
app.UseExceptionHandler();

app.UseAuthentication();
app.UseAuthorization();

app.MapMeEndpoints();

app.Run();

public partial class Program;