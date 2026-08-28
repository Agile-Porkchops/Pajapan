# M0 — Foundations

**Goal:** A logged-in user can hit a deployed API endpoint that knows who they are and
what role they have. Nothing else works yet, and that is fine.

**Why this order:** Every later milestone assumes auth, migrations and deployment
work. Discovering in M3 that the JWT audience was wrong costs a day; discovering it
here costs ten minutes.

**Read first:** spec §5 (architecture), §5.1 (trust boundary), §6 (roles).
**Constraints:** [`README.md#global-constraints`](README.md#global-constraints).

**Estimate:** 3–4 days · **7 tasks**

---

## M0-01 · Repository scaffolding

**Depends on:** nothing
**Branch:** `feature/m0-scaffolding`

**Files:**
- Create: `Pajapan.sln`, `.gitignore`, `.editorconfig`, `README.md`,
  `Directory.Build.props`, `global.json`

**Steps:**

- [ ] **1.** Pin the SDK so a machine with a different default doesn't silently build
      differently. `global.json`:

```json
{ "sdk": { "version": "10.0.400", "rollForward": "latestFeature" } }
```

- [ ] **2.** Create the solution and projects:

```bash
"/c/Program Files/dotnet/dotnet.exe" new sln -n Pajapan
"/c/Program Files/dotnet/dotnet.exe" new web -o src/Pajapan.Api -f net10.0
"/c/Program Files/dotnet/dotnet.exe" new xunit -o tests/Pajapan.Api.Tests -f net10.0
"/c/Program Files/dotnet/dotnet.exe" sln add src/Pajapan.Api tests/Pajapan.Api.Tests
"/c/Program Files/dotnet/dotnet.exe" add tests/Pajapan.Api.Tests reference src/Pajapan.Api
```

- [ ] **3.** `Directory.Build.props` — turn warnings into errors now, while there are
      zero of them. Doing this in M7 means fixing 200 at once:

```xml
<Project>
  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  </PropertyGroup>
</Project>
```

- [ ] **4.** `.gitignore` — start from the standard set and add:
      `appsettings.Local.json`, `.env`, `.env.local`, `web/node_modules`, `web/dist`,
      `**/bin`, `**/obj`, `.vs`, `*.user`.

- [ ] **5.** `README.md`: one paragraph on what Pajapan is, a link to
      `docs/specs/2026-08-28-pasabuy-design.md` and `docs/plan/README.md`, and a
      "Running locally" section (filled in by M0-05).

- [ ] **6.** Commit.

```bash
git add -A && git commit -m "chore: solution scaffolding, SDK pin, warnings-as-errors"
```

**Done when:**
- [ ] `"/c/Program Files/dotnet/dotnet.exe" build` exits 0 with no warnings
- [ ] `git status` is clean and `bin/`, `obj/`, `node_modules/` are not tracked

---

## M0-02 · Supabase project and configuration

**Depends on:** M0-01
**Branch:** `feature/m0-supabase-config`

**Files:**
- Create: `src/Pajapan.Api/appsettings.json`,
  `src/Pajapan.Api/appsettings.Local.json.example`,
  `docs/SETUP.md`

**Steps:**

- [ ] **1.** In the Supabase dashboard create two projects: `pajapan-staging` and
      `pajapan-prod`. Do M0 through M7 entirely against staging.

- [ ] **2.** In each project, enable **asymmetric JWT signing keys** (Settings → API →
      JWT Keys). This publishes a JWKS at
      `https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`, which is what M0-04
      validates against. If the project is on the legacy shared-secret (HS256) scheme,
      M0-04 has a documented fallback — but prefer asymmetric: it means the API never
      needs to hold the JWT secret.

- [ ] **3.** Create a Storage bucket named `product-photos`, **private**, 10 MB file
      size limit, allowed MIME types `image/jpeg,image/png,image/webp`.

- [ ] **4.** Record these five values. Note which are secret:

| Key | Secret? | Where used |
|---|---|---|
| `Supabase:Url` | no | API + web |
| `Supabase:AnonKey` | no | web only (login) |
| `Supabase:ServiceKey` | **yes** | API only — signed upload URLs |
| `ConnectionStrings:Db` | **yes** | API only |
| `Supabase:JwksUrl` | no | API — derived from Url |

- [ ] **5.** `appsettings.json` — committed, placeholders only:

```json
{
  "Supabase": {
    "Url": "__SET_LOCALLY__",
    "ServiceKey": "__SET_LOCALLY__",
    "PhotoBucket": "product-photos"
  },
  "ConnectionStrings": { "Db": "__SET_LOCALLY__" }
}
```

- [ ] **6.** Real values go in `appsettings.Local.json` (gitignored) locally, and in
      the host's environment variables in staging/prod. Commit
      `appsettings.Local.json.example` showing the shape with fake values.

- [ ] **7.** Add a startup guard so a misconfigured deploy fails loudly at boot
      instead of quietly at the first request — in `Program.cs`:

```csharp
foreach (var key in new[] { "Supabase:Url", "Supabase:ServiceKey", "ConnectionStrings:Db" })
{
    var v = builder.Configuration[key];
    if (string.IsNullOrWhiteSpace(v) || v == "__SET_LOCALLY__")
        throw new InvalidOperationException($"Configuration '{key}' is not set.");
}
```

- [ ] **8.** Write `docs/SETUP.md`: how a new developer gets from a clone to a running
      API. Assume they have never used Supabase.

- [ ] **9.** Commit.

**Done when:**
- [ ] `git grep -nE "eyJ|supabase\.co|postgres://|sb_secret" -- ':!*.example' ':!docs/'`
      returns nothing
- [ ] Deleting `appsettings.Local.json` and running the API throws the guard exception
      naming the missing key, and does not start

---

## M0-03 · EF Core, DbContext, first migration

**Depends on:** M0-02
**Branch:** `feature/m0-efcore`

**Files:**
- Create: `src/Pajapan.Api/Domain/Users.cs`, `src/Pajapan.Api/Domain/Catalog.cs`,
  `src/Pajapan.Api/Data/AppDbContext.cs`,
  `src/Pajapan.Api/Data/Configurations/AppUserConfiguration.cs`,
  `tests/Pajapan.Api.Tests/DbFixture.cs`

**Interfaces produced:** `AppDbContext` with `DbSet<AppUser> Users`,
`DbSet<Category> Categories`; `AppUserRole` enum; `DbFixture` giving tests a
migrated Postgres.

**Steps:**

- [ ] **1.** Add packages:

```bash
cd src/Pajapan.Api
"/c/Program Files/dotnet/dotnet.exe" add package Npgsql.EntityFrameworkCore.PostgreSQL
"/c/Program Files/dotnet/dotnet.exe" add package Microsoft.EntityFrameworkCore.Design
cd ../../tests/Pajapan.Api.Tests
"/c/Program Files/dotnet/dotnet.exe" add package Testcontainers.PostgreSql
"/c/Program Files/dotnet/dotnet.exe" add package Microsoft.AspNetCore.Mvc.Testing
```

- [ ] **2.** `Domain/Users.cs` — only the two entities M0 needs. The remaining twelve
      arrive in M1-01, as one migration, once the whole model is settled:

```csharp
namespace Pajapan.Api.Domain;

public enum AppUserRole { Customer = 0, JapanBuyer = 1, Fulfilment = 2, Admin = 3 }

public class AppUser
{
    public Guid Id { get; set; }              // == Supabase auth `sub`. Never generated.
    public AppUserRole Role { get; set; } = AppUserRole.Customer;
    public string DisplayName { get; set; } = "";
    public string? Phone { get; set; }
    public string Email { get; set; } = "";
    public bool IsBlocked { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
```

- [ ] **3.** `Data/AppDbContext.cs`. Two conventions applied globally, so no later task
      has to remember them:

```csharp
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
```

  > `HavePrecision(12,2)` at the convention level is the single most valuable line in
  > this file. It means no future task can accidentally create a `numeric` column with
  > default precision and silently truncate or over-round money.

- [ ] **4.** `AppUserConfiguration`: `Id` is `ValueGeneratedNever()` (it comes from
      Supabase), `Email` has a unique index, `Role` is stored as `int`.

- [ ] **5.** Create and inspect the migration. **Read the generated SQL** — do not
      apply it blind:

```bash
"/c/Program Files/dotnet/dotnet.exe" ef migrations add InitialUsers -p src/Pajapan.Api
"/c/Program Files/dotnet/dotnet.exe" ef migrations script -p src/Pajapan.Api
```

- [ ] **6.** `DbFixture` — spins a real Postgres container and migrates it:

```csharp
public sealed class DbFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _pg = new PostgreSqlBuilder()
        .WithImage("postgres:17-alpine").Build();

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
```

- [ ] **7.** One test that proves precision survives a round trip — this is the guard
      on Global Constraint 1:

```csharp
[Fact]
public async Task Decimal_money_round_trips_without_precision_loss()
{
    await using var db = _fx.NewContext();
    db.Categories.Add(new Category { Id = Guid.NewGuid(), Name = "t", Slug = "t" });
    await db.SaveChangesAsync();
    // asserted properly in M1-01 once Product.PricePhp exists; for now assert the
    // convention is registered:
    var prop = db.Model.FindEntityType(typeof(Category))!;
    Assert.NotNull(prop);
}
```

- [ ] **8.** Run tests, then commit.

```bash
"/c/Program Files/dotnet/dotnet.exe" test
```

**Done when:**
- [ ] `dotnet ef migrations script` output has been read, and every money column in it
      reads `numeric(12,2)` — not `numeric` and not `double precision`
- [ ] `dotnet test` passes against a real Postgres container
- [ ] Running the migration twice is a no-op, not an error

---

## M0-04 · JWT validation and CurrentUser

**Depends on:** M0-03
**Branch:** `feature/m0-auth`

> **This is the highest-risk task in M0.** Every authorization rule in the app rests
> on it. Spec §6.1 lists what must be true. Get a second pair of eyes on the PR.

**Files:**
- Create: `src/Pajapan.Api/Infrastructure/CurrentUser.cs`,
  `src/Pajapan.Api/Infrastructure/AuthPolicies.cs`,
  `src/Pajapan.Api/Features/Me/MeEndpoints.cs`
- Modify: `src/Pajapan.Api/Program.cs`
- Test: `tests/Pajapan.Api.Tests/AuthTests.cs`

**Interfaces produced:** `CurrentUser` (scoped, `Id`, `GetAsync()`),
`AuthPolicies.Admin` / `.Fulfilment` / `.JapanBuyer` / `.Staff`,
`GET /api/me` → `{ id, displayName, email, role }`.

**Steps:**

- [ ] **1.** Add `Microsoft.AspNetCore.Authentication.JwtBearer`.

- [ ] **2.** Configure bearer auth against Supabase's JWKS:

```csharp
var supabaseUrl = builder.Configuration["Supabase:Url"]!.TrimEnd('/');

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.Authority = $"{supabaseUrl}/auth/v1";
        o.MetadataAddress = $"{supabaseUrl}/auth/v1/.well-known/openid-configuration";
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer   = true,  ValidIssuer   = $"{supabaseUrl}/auth/v1",
            ValidateAudience = true,  ValidAudience = "authenticated",
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = "sub",
        };
    });
```

  > **Fallback if the Supabase project is on legacy HS256:** replace
  > `Authority`/`MetadataAddress` with
  > `IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(cfg["Supabase:JwtSecret"]!))`.
  > Prefer asymmetric — it keeps the signing secret out of the API entirely.
  > `ValidateAudience` is not optional: Supabase issues `anon` tokens with the same
  > issuer, and skipping it lets an unauthenticated anon key act as a logged-in user.

- [ ] **3.** `CurrentUser` — the only place the caller's identity is ever read:

```csharp
public sealed class CurrentUser(IHttpContextAccessor http, AppDbContext db)
{
    private AppUser? _cached;

    public Guid Id => Guid.TryParse(
        http.HttpContext?.User.FindFirst("sub")?.Value, out var id)
            ? id
            : throw new UnauthorizedAccessException("No sub claim on the token.");

    /// Loads the AppUser row, creating it on first sight of a Supabase user.
    public async ValueTask<AppUser> GetAsync(CancellationToken ct = default)
    {
        if (_cached is not null) return _cached;
        var id = Id;
        _cached = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct);
        if (_cached is null)
        {
            _cached = new AppUser
            {
                Id = id,
                Email = http.HttpContext!.User.FindFirst("email")?.Value ?? "",
                Role = AppUserRole.Customer,   // never trust a role claim from the token
            };
            db.Users.Add(_cached);
            await db.SaveChangesAsync(ct);
        }
        if (_cached.IsBlocked) throw new UnauthorizedAccessException("User is blocked.");
        return _cached;
    }
}
```

  > Role is read from **our** table, never from the JWT. A role claim in a token is
  > something Supabase's admin API can set; keeping authority in our database means
  > role changes are immediate and are ours to audit.

- [ ] **4.** `AuthPolicies` — a policy per role, plus `Staff` for "any non-customer".
      Register with `AddAuthorization`, each policy asserting on the loaded `AppUser`
      via an `IAuthorizationHandler` that resolves `CurrentUser`.

- [ ] **5.** `GET /api/me`, `RequireAuthorization()`. Returns id, display name, email,
      role. This is the endpoint the web app calls right after login.

- [ ] **6.** Write the authorization tests **before** wiring any business endpoint.
      These four are the contract every later milestone depends on:

```csharp
[Fact] public async Task No_token_is_401() { … }
[Fact] public async Task Anon_key_token_is_401()            // audience check
[Fact] public async Task Expired_token_is_401() { … }
[Fact] public async Task First_login_creates_AppUser_as_Customer() { … }
[Fact] public async Task Role_claim_in_token_is_ignored()
    // forge a token with "role": "admin"; assert GET /api/me returns Customer
```

- [ ] **7.** Run the tests, confirm all five pass, commit.

**Done when:**
- [ ] All five auth tests pass
- [ ] A token whose `aud` is `anon` is rejected with 401
- [ ] A forged `role: admin` claim does **not** grant admin — verified by a test, not
      by reading the code
- [ ] `git grep -n "FindFirst(\"role\")"` returns nothing

---

## M0-05 · React application scaffold

**Depends on:** M0-01
**Branch:** `feature/m0-web-scaffold`
**Runs in parallel with** M0-03/M0-04.

**Files:**
- Create: `web/` (Vite scaffold), `web/src/lib/apiClient.ts`,
  `web/src/lib/money.ts`, `web/src/router.tsx`, `web/tailwind.config.ts`,
  `web/.env.example`

**Steps:**

- [ ] **1.** Scaffold and install:

```bash
npm create vite@latest web -- --template react-ts
cd web
npm i react-router @tanstack/react-query @supabase/supabase-js
npm i react-hook-form @hookform/resolvers zod
npm i -D tailwindcss @tailwindcss/vite vitest
npx shadcn@latest init
```

- [ ] **2.** `web/.env.example` — anon key only. **The service key must never appear
      in this directory.** Anything in a `VITE_*` variable is shipped to the browser:

```
VITE_SUPABASE_URL=__SET_LOCALLY__
VITE_SUPABASE_ANON_KEY=__SET_LOCALLY__
VITE_API_URL=http://localhost:5100
```

- [ ] **3.** `lib/money.ts` — Global Constraint 1 on the client side. Money arrives as
      a string and is never turned into a float for arithmetic:

```ts
/** Money is transported as a decimal string. Parse to cents (bigint) for maths. */
export const toCents = (php: string): bigint => {
  const m = /^-?\d+(\.\d{1,2})?$/.exec(php.trim());
  if (!m) throw new Error(`Not a money string: ${php}`);
  const [whole, frac = ""] = php.trim().split(".");
  return BigInt(whole + frac.padEnd(2, "0"));
};

export const fromCents = (c: bigint): string =>
  `${c / 100n}.${(c < 0n ? -c : c) % 100n}`.replace(/\.(\d)$/, ".0$1");

export const formatPhp = (php: string) =>
  new Intl.NumberFormat("en-PH", { style: "currency", currency: "PHP" })
    .format(Number(php));   // display only — never feed this back into arithmetic
```

- [ ] **4.** `lib/apiClient.ts` — attaches the Supabase access token to every request
      and **throws on non-2xx**. Throwing is what makes Global Constraint 9 achievable:
      a client that returns `[]` on error makes silent failure the default.

```ts
export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const { data } = await supabase.auth.getSession();
  const res = await fetch(`${import.meta.env.VITE_API_URL}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(data.session ? { Authorization: `Bearer ${data.session.access_token}` } : {}),
      ...init.headers,
    },
  });
  if (!res.ok) throw new ApiError(res.status, await res.json().catch(() => null));
  return res.status === 204 ? (undefined as T) : res.json();
}
```

- [ ] **5.** Wire `QueryClientProvider` and a router with three routes: `/` (catalog
      placeholder), `/login`, `/admin` (placeholder).

- [ ] **6.** Vitest test for `toCents`: `"1234.50"` → `123450n`; `"0.05"` → `5n`;
      `"12.345"` throws; `"abc"` throws.

- [ ] **7.** Commit.

**Done when:**
- [ ] `npm run build` succeeds with no TypeScript errors
- [ ] `npm test` passes the money tests
- [ ] `grep -ri "service" web/.env.example web/src` finds no service key

---

## M0-06 · Login end to end

**Depends on:** M0-04, M0-05
**Branch:** `feature/m0-login`

**Files:**
- Create: `web/src/lib/supabase.ts`, `web/src/features/auth/LoginPage.tsx`,
  `web/src/features/auth/useCurrentUser.ts`,
  `web/src/features/auth/RequireRole.tsx`
- Modify: `web/src/router.tsx`, `src/Pajapan.Api/Program.cs` (CORS)

**Steps:**

- [ ] **1.** CORS on the API — an explicit allowlist from configuration, never
      `AllowAnyOrigin` combined with credentials:

```csharp
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins(builder.Configuration.GetSection("Cors:Origins").Get<string[]>()!)
    .AllowAnyHeader().AllowAnyMethod()));
```

- [ ] **2.** `lib/supabase.ts`: `createClient(url, anonKey)` with
      `persistSession: true`. This client is used for **auth only** — never
      `.from()`, never `.rpc()`. Spec §5.1.

- [ ] **3.** Add an ESLint rule or a CI grep that fails the build on
      `supabase.from(` / `supabase.rpc(` anywhere in `web/`. This is the mechanical
      enforcement of the no-RLS decision; without it the constraint decays the first
      time someone is in a hurry.

- [ ] **4.** `LoginPage`: email + password sign-in, and email magic link. Show the
      server's error message; never a generic "something went wrong".

- [ ] **5.** `useCurrentUser()`: a TanStack Query hook calling `GET /api/me`,
      `staleTime: 5min`. Returns `{ user, isLoading, error }` — three states, all of
      which the UI must render distinctly.

- [ ] **6.** `RequireRole`: a route wrapper. Loading → spinner. Error → an error panel
      with a retry button. Wrong role → "You don't have access to this page", not a
      redirect that looks like a bug.

- [ ] **7.** Manually verify: sign up a new email, land on `/`, confirm an `app_user`
      row exists with `role = 0`. Promote yourself with SQL:

```sql
update app_user set role = 3 where email = 'you@example.com';
```

- [ ] **8.** Commit.

**Done when:**
- [ ] A brand-new email can sign up, and `GET /api/me` returns their row with role
      `Customer`
- [ ] After the SQL promotion, `/admin` renders instead of the access message
- [ ] Signing out and hitting `/api/me` returns 401 and the UI shows the login page
- [ ] With the API stopped, the app shows an error state — **not** a spinner forever
      and not an empty page

---

## M0-07 · CI and deployment

**Depends on:** M0-06
**Branch:** `feature/m0-cicd`

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/deploy-staging.yml`,
  `src/Pajapan.Api/Dockerfile`, `fly.toml`

**Steps:**

- [ ] **1.** `ci.yml`, on every PR: restore, build, `dotnet test`, `npm ci`,
      `npm run build`, `npm test`. Plus the two guard greps:

```yaml
      - name: No secrets committed
        run: |
          ! git grep -nE "eyJ[A-Za-z0-9_-]{20,}|sb_secret_|postgres://[^_]" \
            -- ':!*.example' ':!docs/'
      - name: Web never queries Supabase directly
        run: ! git grep -nE "supabase\.(from|rpc)\(" -- web/
```

- [ ] **2.** Dockerfile for the API: `mcr.microsoft.com/dotnet/sdk:10.0` build stage,
      `aspnet:10.0` runtime stage, non-root user, `EXPOSE 8080`.

- [ ] **3.** Deploy the API to Fly.io staging. Set secrets with
      `fly secrets set` — never in `fly.toml`, which is committed.

- [ ] **4.** Deploy `web/` to Vercel, project root `web/`, with the staging env vars.

- [ ] **5.** Migrations run in the deploy workflow, before the new image takes traffic:

```yaml
      - run: dotnet ef database update -p src/Pajapan.Api
        env:
          ConnectionStrings__Db: ${{ secrets.STAGING_DB }}
```

  > Migrations run from CI, never by hand against a deployed database. A hand-run
  > migration is how staging and production drift apart.

- [ ] **6.** Add a `GET /health` endpoint that checks the database connection and
      returns 503 if it cannot reach it. A health check that returns 200 without
      touching the database tells you nothing.

- [ ] **7.** Commit and confirm both deploys are green.

**Done when:**
- [ ] A PR runs CI and it passes
- [ ] A PR containing a fake JWT string fails CI on the secrets grep — verify by
      actually pushing one, then removing it
- [ ] Staging web can log in against staging API over HTTPS
- [ ] `GET /health` returns 503 when the database is unreachable
- [ ] `README.md` "Running locally" is accurate enough for someone else to follow

---

## Milestone exit

- [ ] All 7 tasks merged to `main`
- [ ] A teammate can clone, follow `docs/SETUP.md`, and log in locally
- [ ] Staging is live and all three team members have accounts with the right roles
- [ ] No secret is in git history — `git log -p | grep -E "eyJ|sb_secret_"` is empty
