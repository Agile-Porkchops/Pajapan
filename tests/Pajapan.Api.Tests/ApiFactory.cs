using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;

namespace Pajapan.Api.Tests;

public sealed class ApiFactory(string connectionString) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("Supabase:Url", TestJwt.SupabaseUrl);
        builder.UseSetting("Supabase:ServiceKey", "not-a-real-key");
        builder.UseSetting("ConnectionStrings:Db", connectionString);
        // Same reasoning as the three above: don't depend on appsettings.Development.json
        // resolving from disk, which is exactly the assumption that breaks on CI.
        builder.UseSetting("Cors:Origins:0", "http://localhost:5173");
        builder.UseEnvironment("Development");

        builder.ConfigureTestServices(services =>
            services.PostConfigure<JwtBearerOptions>(
                JwtBearerDefaults.AuthenticationScheme,
                o =>
                {
                    o.Authority = null;
                    o.MetadataAddress = null!;
                    o.ConfigurationManager = null;
                    o.TokenValidationParameters.IssuerSigningKey = TestJwt.SigningKey;
                }));
    }
}