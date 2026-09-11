using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Pajapan.Api.Data;
using Pajapan.Api.Features.Me;
using Pajapan.Api.Infrastructure;
using Wolverine;

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

// CQRS: endpoints send Commands and Queries through IMessageBus (Global Constraint 17).
// In-process only: no transports, no message persistence, no retry policies (Constraint 8).
builder.Host.UseWolverine(opts =>
{
    // Pinned rather than inferred from the call stack. Static codegen (M0-07) loads
    // pre-generated handlers from this assembly, and Wolverine caches it process-wide.
    opts.ApplicationAssembly = typeof(Program).Assembly;

    // AddDbContext registers DbContextOptions through a factory Wolverine can't inline,
    // and Wolverine 6 refuses service location unless the type is opted in.
    opts.CodeGeneration.AlwaysUseServiceLocationFor<AppDbContext>();

    // Infrastructure/*Handler classes (ASP.NET authorization and exception handlers, e.g.
    // RoleHandler) match Wolverine's "*Handler" + Handle/HandleAsync discovery convention
    // but are not message handlers. Exclude the whole namespace so future infrastructure
    // "*Handler" classes can't be picked up either.
    opts.Discovery.CustomizeHandlerDiscovery(q => q.Excludes.InNamespace("Pajapan.Api.Infrastructure"));
});

// CanConnectAsync() against the real database -- a 200 that never touches it
// tells an orchestrator nothing.
builder.Services.AddHealthChecks().AddDbContextCheck<AppDbContext>();

builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<UnauthorizedExceptionHandler>();

var corsOrigins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>();
if (corsOrigins is null or { Length: 0 })
    throw new InvalidOperationException("Configuration 'Cors:Origins' is not set.");

// No AllowCredentials(): the web app sends the bearer token as an Authorization
// header, never a cookie, so credentialed CORS is unneeded attack surface.
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins(corsOrigins)
    .AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();

// Inside the developer exception page, not outside it: anything this handler
// declines keeps propagating and still renders with its stack trace.
app.UseExceptionHandler();

app.UseCors();

app.UseAuthentication();
app.UseAuthorization();

app.MapMeEndpoints();
app.MapHealthChecks("/health");

app.Run();

public partial class Program;