# Setup

Getting from a fresh clone to a running API. Assumes you've never used Supabase
before.

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
| `ConnectionStrings__Db` | (secret) | Settings → Database → Connection string (URI), with your DB password filled in |

The **double underscore** (`__`) is ASP.NET Core's syntax for nested config
keys (`Supabase:Url`) in environment variables — not a typo.

Fully close and reopen Visual Studio (or your terminal) after setting these —
already-running processes don't pick up new environment variables.

**Alternative: local file.** If you'd rather use a file, copy
`src\Pajapan.Api\appsettings.Local.json.example` to
`appsettings.Local.json` in the same folder and fill in the real values —
it's gitignored. Either approach works; env vars are preferred for this repo
for the OneDrive-sync reason above.

## 4. Run the API

```powershell
cd src\Pajapan.Api
& "C:\Program Files\dotnet\dotnet.exe" run
```

If any of the three keys above is missing or still `__SET_LOCALLY__`, the app
throws at startup naming the missing key, instead of starting broken.

## Prod

`pajapan-prod` lives on a separate Supabase account and isn't set up yet.
Nothing in local development touches it.
