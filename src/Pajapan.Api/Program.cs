var builder = WebApplication.CreateBuilder(args);

foreach (var key in new[] { "Supabase:Url", "Supabase:ServiceKey", "ConnectionStrings:Db" })
{
    var v = builder.Configuration[key];
    if (string.IsNullOrWhiteSpace(v) || v == "__SET_LOCALLY__")
        throw new InvalidOperationException($"Configuration '{key}' is not set.");
}

var app = builder.Build();

app.MapGet("/", () => "Hello World!");

app.Run();
