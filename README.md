# Pajapan

A *pasabuy* (proxy-buying) web app: the team buys goods in Japan on customers'
behalf, ships them to the Philippines, and the app tracks the whole flow —
catalog, orders, payments, procurement runs, shipping, and profit.

- Design spec: [`docs/specs/2026-08-28-pasabuy-design.md`](docs/specs/2026-08-28-pasabuy-design.md)
- Build plan: [`docs/plan/README.md`](docs/plan/README.md)
- Task index: [`tasks/00-INDEX.md`](tasks/00-INDEX.md)

## Running locally

First time on this repo: follow [`docs/SETUP.md`](docs/SETUP.md) — .NET SDK,
Supabase access, environment variables (the API and the web app each need
their own, in two different formats), and applying the database schema.

Once that's done, two terminals:

```powershell
cd src\Pajapan.Api
dotnet run
```
```powershell
cd web
npm run dev
```

API: `http://localhost:5260` · Web: `http://localhost:5173`

Running the tests:

```powershell
dotnet test tests\Pajapan.Api.Tests\Pajapan.Api.Tests.csproj
```
```powershell
cd web
npm test
```

The API tests need Docker Desktop running — they spin up a real Postgres
container per test class rather than mocking the database.
