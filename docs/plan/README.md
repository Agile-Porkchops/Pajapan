# Pajapan Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement these task-by-task. Steps use checkbox
> (`- [ ]`) syntax for tracking.

**Goal:** A pasabuy web app — Japan pre-order catalog, PH customers, batch shipping,
and per-run profit tracking — usable by a 3-person team for a real buying trip.

**Architecture:** React SPA → Supabase, directly. **No backend server.** Reads are
RLS-filtered PostgREST queries through `supabase-js`; money-critical writes are
Postgres `SECURITY DEFINER` functions called via `.rpc()`. Row-Level Security is the
authorization boundary — there is no application layer behind it.

> **Pivoted 2026-09-08**, mid-M0. The original plan was React → C# Minimal API →
> Postgres. `src/Pajapan.Api/` and its tests are retired; M0-04, M0-06 and M0-07 are
> superseded. M1–M7 below have had their **structural** notes rewritten for RLS/RPC;
> their detailed step-by-step content is deliberately still pending, to be written
> milestone-by-milestone against a running database rather than guessed at in bulk.

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

1. All money is `numeric(12,2)` in Postgres. Never `float`/`double precision`/`real`
   — not in a column, not in an RPC function's own locals. In TypeScript, never
   arithmetic on a float you got from JSON: money crosses the wire as a string,
   parsed with a decimal-safe helper on the client.
2. Every monetary column and field names its currency: `amount_php`,
   `actual_cost_jpy`. There is no bare `amount` anywhere in this codebase.
3. FX rates are recorded at the moment of use (`expense.fx_rate_to_php`), never
   looked up at report time.
4. **Prices come from the database.** No RPC function takes a price parameter — not
   "takes it and ignores it", does not have one. The client sends `product_id` +
   `qty`; the function looks up `product.price_php` itself.

**Data**

5. Snapshot on write: order lines snapshot product name + price; orders snapshot the
   full shipping address. Editing a product must never change a past order.
6. Timestamps are `timestamptz`, stored UTC. Convert at render. Run cutoffs are
   authored and displayed in JST (`Asia/Tokyo`); everything customer-facing displays
   `Asia/Manila`.
7. Soft delete (`deleted_at timestamptz null`) on anything money touches: `order`,
   `order_item`, `payment`, `refund`, `expense`, `shipment`. Hard delete only on
   draft catalog entries. **A soft-deleted row must be excluded by the RLS policy
   itself**, not only by a client-side `.is('deleted_at', null)` filter a caller can
   simply omit.

**Correctness**

8. `place_order` and `submit_payment_proof` take a client-generated
   `p_idempotency_key uuid` behind a unique index; the function returns the existing
   row rather than inserting a second. Double submission produces **one** record. No
   automatic retry on any write path — TanStack Query's mutation retry stays off.
9. **No silent error.** `supabase-js` does not throw; it returns `{ data, error }`.
   Every call site checks `error`. Destructuring only `data` fails review — it turns
   a permission denial into an empty list, and a screen that renders zeros because
   the query was refused is worse than one that renders an error.

**Security** (spec §6.1)

10. `auth.uid()` is the only source of identity. No RLS policy and no RPC function
    takes a user id, customer id, or role as a parameter. **A `p_customer_id`
    argument fails review.**
11. Another customer's row returns **zero rows**, by RLS — not by a hand-written
    check that could be forgotten.
12. **Every table in `public` has RLS enabled.** Asserted by a test that enumerates
    `pg_tables` and fails on `rowsecurity = false`, not by remembering to type it. A
    table without RLS is world-readable to anyone holding the anon key, which is
    public by design.
13. **Every `SECURITY DEFINER` function pins `SET search_path` and performs its own
    `auth.uid()` authorization check as its first statement.** These functions bypass
    RLS entirely; one missing its check is a total breach, not a bug. Also asserted
    by a test, over `pg_proc`.
14. Money-touching tables grant **no** direct `INSERT`/`UPDATE`/`DELETE` to
    `authenticated`. The only write path is a function.
15. The browser holds only the **anon** key. A service-role key never appears in
    `web/`, in a `VITE_*` variable, or in the repo. Committed config uses
    `__SET_LOCALLY__` placeholders. The only place a secret may ever live is inside
    an Edge Function.

**Process**

16. Branch per task: `feature/<milestone>-<slug>`, e.g. `feature/m2-place-order`.
    Never commit to `main`.
17. Conventional commits: `feat:`, `fix:`, `test:`, `chore:`, `docs:`.
18. Every task ends with its **Done when** checklist verified by actually running the
    commands — not by reading the code and concluding it should work. For RLS and
    RPC that means running it **as each role against a real database**, not reading
    the policy and concluding it scopes correctly.

---

## Versions

Actual installed versions, verified 2026-09-08 — not aspirational pins.

| Thing | Version | Note |
|---|---|---|
| Node | 24.14.0 | |
| React | 19.2 | |
| Vite | 8.2 | |
| TypeScript | 6.0 | |
| Vitest | 5.0 | |
| Tailwind | 4.3 | |
| `@supabase/supabase-js` | 2.116 | already in `web/` since M0-05 |
| Supabase CLI | **not yet installed** | first task of the reworked M0 — needed for local Postgres, migrations, and every RLS test |
| Postgres | 17 | whatever Supabase provisions; `security_invoker` views need ≥15 |

---

## Repository layout

Vertical slices, not technical layers. Files that change together live together.

```
pajapan/
├── supabase/
│   ├── config.toml
│   ├── migrations/          timestamped SQL — the whole backend lives here
│   ├── functions/           Edge Functions (none yet; the payment webhook lands here)
│   ├── tests/               Vitest, run through supabase-js against the local stack
│   └── seed.sql             users of every role + fixture data for local dev and tests
├── web/
│   ├── src/
│   │   ├── main.tsx, App.tsx, router.tsx
│   │   ├── lib/             supabase client, auth, money, formatting
│   │   ├── components/ui/   shadcn/ui, copied in
│   │   └── features/        catalog, cart, checkout, orders, admin/*
│   └── index.html, vite.config.ts
├── scripts/
├── docs/
│   ├── specs/
│   └── plan/
└── tasks/
```

**One migration per logical change, and a table's RLS policies live in the same
migration as the table itself.** Never `CREATE TABLE` in one migration and
`CREATE POLICY` in a later one — that leaves a window where the table exists
world-readable, and it makes "did this table ever get policies?" a question you have
to answer by reading history instead of by reading one file.

**Migrations are the only way the schema changes.** No edits through the Supabase
dashboard's SQL editor, on any project including staging: a change made there exists
in no file, survives no reset, and reaches production never.

---

## Testing policy

**Test the money and the scoping. Do not test the CRUD.**

Write a test when the thing under test is: a price calculation, a status transition,
an authorization rule, an idempotency guard, or a report aggregate. Do not write a
test that asserts inserting a category inserts a category — the database already
enforces that, and the test only breaks when you rename a column.

| Layer | Tool | What |
|---|---|---|
| Database | Supabase CLI local stack + Vitest through `supabase-js` | RLS policies, RPC behaviour, money arithmetic, idempotency. Real Postgres + real GoTrue + real PostgREST, in Docker. Never a mocked client — a mock proves the test author's belief about a policy, which is the exact thing under test. |
| Web | Vitest | Money formatting, cart math, form validation. No component-render tests for layout. |
| E2E | Manual, scripted in M7-07 | Playwright is not worth the maintenance at this team size. |

**How an RLS test is written.** It signs in — `supabase.auth.signInWithPassword`
against a user seeded in `seed.sql` — and then asserts on what comes back from a real
query. It does **not** read the policy SQL and assert the policy says what you meant.
Every authorization rule gets tested from both sides: the role that should see the
row, and a role that should not.

Three tests are structural rather than per-feature, and must exist before any table
carries real data:

- every table in `public` has `rowsecurity = true` (enumerate `pg_tables`)
- every `SECURITY DEFINER` function pins a `search_path` (enumerate `pg_proc`)
- an anonymous client, holding only the anon key, can read the public catalog and
  nothing else

`supabase db reset` between suites gives a fresh schema plus `seed.sql`; there is no
per-test-class fixture helper to build.

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
