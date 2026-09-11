# Setup

Getting from a fresh clone to a running API and web app. Assumes you've never
used Supabase before.

## 1. Install the .NET SDK

10.0.400 or later. `global.json` pins the exact version — a mismatched SDK
fails the build on purpose rather than silently using a different one.

```powershell
& "C:\Program Files\dotnet\dotnet.exe" --list-sdks
```

If `dotnet` on your PATH doesn't show 10.0.400, use the full path above, or fix
PATH order for your user profile (`C:\Program Files\dotnet` before any x86
runtime-only install).

## 2. Get access to the Supabase project

Ask a teammate to add you as a member of the `pajapan-staging` project in the
Supabase dashboard (`https://rgkajxgxuwnkhpnlbwek.supabase.co`). Everyone
develops against staging — there is no local Postgres to install.

## 3. Configure local secrets

The repo only commits `appsettings.json` with placeholder values
(`__SET_LOCALLY__`) — real values never get committed.

**Recommended: user-level environment variables**, not a local file. This repo
lives under `Documents\GitHub`, which OneDrive sync (on by default on many
Windows setups) would otherwise upload — gitignore only stops git, not
OneDrive. Env vars never touch disk as a file.

Settings → System → About → Advanced system settings → Environment Variables
→ **User variables** → New, for each of:

| Variable name | Value | Where to find it |
|---|---|---|
| `Supabase__Url` | `https://rgkajxgxuwnkhpnlbwek.supabase.co` | Project home page, or Settings → API |
| `Supabase__ServiceKey` | (secret) | Settings → API → Project API keys → `service_role` |
| `ConnectionStrings__Db` | (secret) | Settings → Database → **Session pooler** URI → see **below** — do not use it as-is |
| `MEDIATR_LICENSE_KEY` | (keep private) | Register pajapan for MediatR's free Community license at [luckypennysoftware.com](https://luckypennysoftware.com). Single underscore: this is MediatR's own variable name, not ASP.NET config. **Required in production** by MediatR's license terms. Locally and in tests the API runs without it and logs a notice that it is missing |

The **double underscore** (`__`) is ASP.NET Core's syntax for nested config
keys (`Supabase:Url`) in environment variables — not a typo.

**`ConnectionStrings__Db` needs ADO.NET keyword format, not the URI Supabase
shows by default.** Npgsql's connection string parser does not accept
`postgresql://user:pass@host:port/db` — passing it throws
`Format of the initialization string does not conform to specification`
the first time EF actually opens a connection (which is lazy, so this can sit
broken for a while before anyone notices).

**Copy the Session pooler URI** — host `*.pooler.supabase.com`, port 5432,
username `postgres.<project-ref>`. Not "Direct connection": the direct host
`db.<ref>.supabase.co` is IPv6-only, so it works from a PC with IPv6 and then
fails on Railway, which has no outbound IPv6 (`ENETUNREACH`). Not the
Transaction pooler on 6543 either — it breaks Npgsql's prepared statements.
Use the same pooler string locally so what you test is what deploys.

Then convert it with this one-liner in PowerShell (reads the clipboard, so copy
the URI first):

```powershell
$uri = [Uri](Get-Clipboard)
$userInfo = $uri.UserInfo -split ':', 2 | ForEach-Object { [Uri]::UnescapeDataString($_) }   # UserInfo stays %-encoded: p@ss would arrive as p%40ss
$connString = "Host=$($uri.Host);Port=$($uri.Port);Database=$($uri.AbsolutePath.TrimStart('/'));Username=$($userInfo[0]);Password=$($userInfo[1]);SSL Mode=Require;Trust Server Certificate=true"
$connString
```

Set `ConnectionStrings__Db` to the printed value. **Do not wrap the password
in `{ }`** — that's SQL Server/ODBC escaping, not Npgsql's; the braces become
literal characters in the password and every connection attempt fails with
`28P01: password authentication failed`.

Fully close and reopen Visual Studio (or your terminal) after setting these —
already-running processes don't pick up new environment variables. This means
closing the terminal **window**, not just stopping the process inside it: a
new process still inherits its environment from its parent window, so
re-running a command in the same window never sees a variable added after
that window opened.

When editing User variables through Windows' Environment Variables dialog,
clicking OK on the "New/Edit Variable" popup only saves to that popup's list —
the edit isn't committed until you *also* click OK on the outer
"Environment Variables" window itself. A variable that appears in the list but
then shows blank in a freshly-opened terminal almost always means this second
OK was missed.

**Alternative: local file.** If you'd rather use a file, copy
`src\Pajapan.Api\appsettings.Local.json.example` to
`appsettings.Local.json` in the same folder and fill in the real values —
it's gitignored. Either approach works; env vars are preferred for this repo
for the OneDrive-sync reason above.

## 4. Apply the database schema

The API does not run migrations automatically at startup — `Database.Migrate()`
is never called. In CI/CD (M0-07), migrations run from the deploy workflow
before the new image takes traffic; locally, apply them by hand. The first
time you point at a fresh database — including the shared `pajapan-staging`
project, if nobody has run this yet — do:

```powershell
cd src\Pajapan.Api
dotnet ef database update
```

If this hasn't been run against staging yet, every query will fail with
`relation "users" does not exist` even though the API starts up fine — the
config guard only checks that a connection string is *present*, not that the
schema exists.

## 5. Run the API

```powershell
cd src\Pajapan.Api
& "C:\Program Files\dotnet\dotnet.exe" run
```

If any of the three keys above is missing or still `__SET_LOCALLY__`, the app
throws at startup naming the missing key, instead of starting broken. Local
URL: `http://localhost:5260`.

## 6. Run the web app

`web/` needs its own env vars — a **separate mechanism** from the three
above, because Vite reads a different naming convention than ASP.NET Core.
Setting one does *not* set the other.

| Variable name | Value | Where to find it |
|---|---|---|
| `VITE_SUPABASE_URL` | same value as `Supabase__Url` above | — |
| `VITE_SUPABASE_ANON_KEY` | (different from the service key — public/low-privilege) | Settings → API → Project API keys → `anon` / `public` |
| `VITE_API_URL` | `http://localhost:5260` | the API's local port, from `launchSettings.json` |

Same User-variable mechanism as above (or `web/.env.local`, gitignored, if
you'd rather use a file — Vite reads both). **Do not reuse the service key
for `VITE_SUPABASE_ANON_KEY`** — it's a different value on the same dashboard
page, and shipping the service key to a browser is a full-privilege leak
(Global Constraint 13).

```powershell
cd web
npm install
npm run dev
```

Local URL: `http://localhost:5173`.

## Prod

`pajapan-prod` lives on a separate Supabase account and isn't set up yet.
Nothing in local development touches it.
