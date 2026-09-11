# Pajapan Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement these task-by-task. Steps use checkbox
> (`- [ ]`) syntax for tracking.

**Goal:** A pasabuy web app — Japan pre-order catalog, PH customers, batch shipping,
and per-run profit tracking — usable by a 3-person team for a real buying trip.

**Architecture:** React SPA → C# Minimal API → Supabase Postgres. The API is the only
holder of a database credential; the browser never queries Postgres directly.

**Spec:** [`docs/specs/2026-08-28-pasabuy-design.md`](../specs/2026-08-28-pasabuy-design.md)
— read it before starting any task. The plan argues *from* the spec; where they
disagree, the spec wins and the plan is wrong.

**Milestones:** [M0](M0-foundations.md) · [M1](M1-catalog.md) ·
[M2](M2-storefront-orders.md) · [M3](M3-payments.md) · [M4](M4-runs-procurement.md) ·
[M5](M5-shipping.md) · [M6](M6-finance.md) · [M7](M7-hardening.md)

---

## Global Constraints

Every task's requirements implicitly include this section. Copied verbatim from
spec §10 unless noted.

**Money**

1. All money is `decimal` — in C# (`decimal`), in Postgres (`numeric(12,2)`), and in
   TypeScript never arithmetic on a float you got from JSON. **Never `float`,
   `double`, `real`, or JS `number` arithmetic on money.** Money crosses the wire as
   a JSON string, parsed with a decimal-safe helper on the client.
2. Every monetary column and field names its currency: `AmountPhp`, `ActualCostJpy`.
   There is no bare `Amount` anywhere in this codebase.
3. FX rates are recorded at the moment of use (`Expense.FxRateToPhp`), never looked
   up at report time.
4. **Prices come from the server.** A request body containing a price is ignored.
   The client sends `productId` + `qty`; the server looks up `Product.PricePhp`.

**Data**

5. Snapshot on write: order lines snapshot product name + price; orders snapshot the
   full shipping address. Editing a product must never change a past order.
6. Timestamps are `timestamptz`, stored UTC. Convert at render. Run cutoffs are
   authored and displayed in JST (`Asia/Tokyo`); everything customer-facing displays
   `Asia/Manila`.
7. Soft delete (`DeletedAt timestamptz null`) on anything money touches: `Order`,
   `OrderItem`, `Payment`, `Refund`, `Expense`, `Shipment`. Hard delete only on
   draft catalog entries.

**Correctness**

8. `POST /api/orders` and `POST /api/orders/{id}/payments` require an
   `Idempotency-Key` header. Double submission produces **one** record. No automatic
   retry on any write path.
9. **No silent `catch`.** A caught exception is logged and surfaced. A screen that
   cannot load its data says so — it never renders zeros, an empty list, or an
   all-clear. `catch { }` and `catch { return []; }` fail review.

**Security** (spec §6.1)

10. `CustomerId` comes from the JWT `sub` claim only. Never from a body, query
    string, route parameter, or header.
11. Another customer's resource returns `404`, not `403`.
12. Route identifiers are UUIDs. `OrderCode` is displayed but never the lookup key on
    a customer endpoint.
13. The Supabase service key lives only in the API's environment. Never in `web/`,
    never in a `VITE_*` variable, never committed. Committed config uses
    `__SET_LOCALLY__` placeholders.

**Process**

14. Branch per task: `feature/<milestone>-<slug>`, e.g. `feature/m2-place-order`.
    Never commit to `main`.
15. Conventional commits: `feat:`, `fix:`, `test:`, `chore:`, `docs:`.
16. Every task ends with its **Done when** checklist verified by actually running the
    commands — not by reading the code and concluding it should work.

---

## Versions

| Thing | Version | Note |
|---|---|---|
| .NET SDK | 10.0.400 | `& "C:\Program Files\dotnet\dotnet.exe"` — `dotnet` on PATH is the x86 runtime-only install with no SDK |
| Node | 22 LTS | |
| EF Core | 10.x | with `Npgsql.EntityFrameworkCore.PostgreSQL` |
| React | 19 | |
| Vite | 7 | |
| Postgres | 17 | whatever Supabase provisions |

---

## Repository layout

Vertical slices, not technical layers. Files that change together live together.

```
pajapan/
├── Pajapan.sln
├── src/
│   └── Pajapan.Api/
│       ├── Program.cs                  composition root, endpoint registration
│       ├── Domain/                      entities + enums, one file per aggregate
│       │   ├── Catalog.cs               Category, Product, ProductPhoto
│       │   ├── Ordering.cs              Order, OrderItem, CustomRequest
│       │   ├── Money.cs                 Payment, Refund, Expense
│       │   ├── Logistics.cs             Run, Shipment, Courier
│       │   └── Users.cs                 AppUser, Address
│       ├── Data/
│       │   ├── AppDbContext.cs
│       │   ├── Configurations/          one IEntityTypeConfiguration per entity
│       │   └── Migrations/
│       ├── Features/                    one folder per slice: endpoints + DTOs + validators
│       │   ├── Catalog/
│       │   ├── Orders/
│       │   ├── Payments/
│       │   ├── Buying/
│       │   ├── Shipping/
│       │   ├── Reports/
│       │   └── Uploads/
│       └── Infrastructure/
│           ├── CurrentUser.cs           reads JWT sub, loads AppUser + role
│           ├── AuthPolicies.cs          role policy names
│           ├── SupabaseStorage.cs       signed upload URLs
│           └── ProblemDetailsSetup.cs
├── tests/
│   └── Pajapan.Api.Tests/               xUnit + Testcontainers (real Postgres)
├── web/
│   ├── src/
│   │   ├── main.tsx, App.tsx, router.tsx
│   │   ├── lib/                         apiClient, auth, money, formatting
│   │   ├── components/ui/               shadcn/ui, copied in
│   │   └── features/                    catalog, cart, checkout, orders, admin/*
│   └── index.html, vite.config.ts
├── scripts/
├── docs/
│   ├── specs/
│   └── plan/
└── tasks/
```

**Why one file per aggregate rather than one per entity:** `Order` and `OrderItem`
are never edited apart. Splitting them costs a file switch on every change and buys
nothing.

---

## Testing policy

**Test the money and the scoping. Do not test the CRUD.**

Write a test when the thing under test is: a price calculation, a status transition,
an authorization rule, an idempotency guard, or a report aggregate. Do not write a
test that asserts `POST /api/categories` inserts a category — the database already
enforces that, and the test only breaks when you rename a column.

| Layer | Tool | What |
|---|---|---|
| API | xUnit + Testcontainers Postgres | Endpoint tests against a real schema. Not SQLite, not `UseInMemoryDatabase` — the model relies on Postgres types, unique indexes and `numeric` precision that neither reproduces. |
| Web | Vitest | Money formatting, cart math, form validation. No component-render tests for layout. |
| E2E | Manual, scripted in M7-07 | Playwright is not worth the maintenance at this team size. |

Every API test runs against a fresh schema per test class, seeded by a shared
`TestData` helper built in M0-03.

---

## How to work a task

1. Read the task, and the spec sections it cites.
2. `git checkout -b feature/<milestone>-<slug>`
3. Work the steps in order. Each is 2–5 minutes.
4. Verify every line of **Done when** by running it.
5. Commit, push, open a PR using the description template in
   `../../CLAUDE.md`.

If a task turns out to be wrong — the spec disagrees, or an assumption fails — stop
and say so rather than inventing a fix. A task that is wrong in the plan is cheap;
the same wrongness discovered in M6 is not.
