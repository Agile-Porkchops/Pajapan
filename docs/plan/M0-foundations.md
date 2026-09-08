# M0 — Foundations

**Goal:** A logged-in user reaches their own row and nothing else, enforced by the
database, with a local Supabase stack anyone on the team can reset and re-seed.

**Why this order:** Every later milestone assumes auth, migrations and the RLS
pattern work. Discovering in M3 that a policy was wrong costs a day; discovering it
here costs ten minutes.

**Read first:** spec §5 (architecture), §5.1 (trust boundary), §6.1 (the rules that
must be tested), §7.2 (view vs function vs direct write).
**Constraints:** [`README.md#global-constraints`](README.md#global-constraints).

---

> ## ⚠ Architecture pivoted 2026-09-08, mid-milestone
>
> M0-01…M0-07 were built against React → **C# Minimal API** → Postgres. That API is
> retired. Each task below now carries a status line saying what survived, what is
> dead, and what replaced it. **Do not follow a superseded task's instructions** —
> the detail has been removed rather than left lying around to be copied by mistake.
> It is recoverable from git history if ever needed.
>
> M0-08…M0-10 are the new work that actually completes this milestone.

**Status:** 4 tasks stand, 2 superseded, 1 needs rework, 3 new · **estimate** 1–2 days
remaining

| # | Task | Status |
|---|---|---|
| M0-01 | Repository scaffolding | ◐ partly retired — .NET solution goes, repo hygiene stays |
| M0-02 | Supabase project and configuration | ◐ rework — config shape changed |
| M0-03 | EF Core, DbContext, first migration | ✗ **superseded** by M0-08/M0-09 |
| M0-04 | JWT validation and CurrentUser | ✗ **superseded** — `supabase-js` does this |
| M0-05 | React application scaffold | ✓ stands, minus `apiClient.ts` |
| M0-06 | Login end to end | ◐ mostly stands — but its no-`.from()` guard is now backwards |
| M0-07 | CI and deployment | ◐ rework — CI merged in [#66](https://github.com/Agile-Porkchops/pajapan/pull/66); deploy re-scoped |
| M0-08 | Supabase CLI and local stack | ⬜ new |
| M0-09 | RLS foundation and structural guards | ⬜ new · 🔴 |
| M0-10 | Rewire web to Supabase-native | ⬜ new |

---

## M0-01 · Repository scaffolding

**Status:** ◐ **partly retired.** `.gitignore`, `.editorconfig` and `README.md` stand.
`Pajapan.sln`, `global.json` and `Directory.Build.props` exist only to build the
retired API and are removed with it.

**Done when:** (unchanged) `git status` is clean; `bin/`, `obj/`, `node_modules/` are
not tracked.

---

## M0-02 · Supabase project and configuration

**Status:** ◐ **rework.** The `pajapan-staging` project, the `product-photos` bucket
and `docs/SETUP.md` all stand. What changed is the set of values that exist at all.

**What the config is now:**

| Key | Secret? | Where |
|---|---|---|
| `VITE_SUPABASE_URL` | no | `web/` |
| `VITE_SUPABASE_ANON_KEY` | no | `web/` — public by design; RLS is what protects data |
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` | **yes** | CI only, for `supabase db push` |

Gone: `ConnectionStrings:Db`, `Supabase:ServiceKey`, `Supabase:JwksUrl`,
`appsettings*.json`, and the `Program.cs` startup guard. No part of this system holds
a database credential any more except the migration step in CI.

Asymmetric JWT signing keys stay enabled — `supabase-js` and PostgREST both want
them — but nothing of ours validates a token by hand now.

**Rework needed:**

- [ ] Strip the retired keys from `docs/SETUP.md`; replace the "connection string"
      section with Supabase CLI setup (M0-08)
- [ ] Confirm the `product-photos` bucket is **private** and reachable only through
      storage policies, not a public URL

**Done when:**
- [ ] `git grep -nE "eyJ|supabase\.co|postgres://|sb_secret"` (excluding `*.example`,
      `docs/`, lockfiles, workflows) returns nothing
- [ ] `docs/SETUP.md` describes only values that still exist

---

## M0-03 · EF Core, DbContext, first migration

**Status:** ✗ **Superseded** by M0-08 (local stack) and M0-09 (first migration).

EF Core, `AppDbContext`, the entity classes, `DbFixture` and Testcontainers are all
retired with the API. Two things this task got right are carried forward as
requirements on M0-09 rather than lost:

- **Money precision is set once, globally, not per column.** The EF convention
  `HavePrecision(12,2)` was the single most valuable line in the old `AppDbContext`.
  Its replacement is a domain: `CREATE DOMAIN money_php AS numeric(12,2)`, used by
  every monetary column, so no later migration can create a bare `numeric` and
  silently change rounding.
- **snake_case is the schema's native casing** — it was a translation layer before;
  now it is simply how the tables are written, and TypeScript sees it directly.

---

## M0-04 · JWT validation and CurrentUser

**Status:** ✗ **Superseded.** `supabase-js` obtains and refreshes the token; PostgREST
validates it; `auth.uid()` exposes it inside the database. There is nothing left for
us to validate.

The one rule this task existed to protect **survives and moves to M0-09**:

> **Role is read from our own table, never from the token.** A role claim in a JWT is
> something Supabase's admin API can set and a client can attempt to forge. The
> equivalent mistake under RLS is a policy that trusts `auth.jwt()`. Policies read
> `app_user.role`; the old test `Role_claim_in_token_is_ignored` becomes an RLS test
> in M0-09.

---

## M0-05 · React application scaffold

**Status:** ✓ **Stands**, with one deletion. `web/`, `lib/money.ts` and its tests, the
router and the Tailwind/shadcn setup are all unaffected — `money.ts` never knew what
the backend was.

`lib/apiClient.ts` is deleted in M0-10: there is no API to call. Note what it was
*for*, because the requirement outlives it — it threw on non-2xx so that a failed
request could not silently become an empty list. `supabase-js` returns
`{ data, error }` instead of throwing, so Global Constraint 9 now has to be met at
every call site rather than once in a wrapper. That is a downgrade in ergonomics and
worth knowing about deliberately.

---

## M0-06 · Login end to end

**Status:** ◐ **Mostly stands.** `LoginPage`, `useCurrentUser`, `RequireRole` and the
three-state (loading / error / wrong-role) rendering all survive — those were always
client concerns.

**Two things must be undone:**

1. **CORS on the API** — gone with the API.
2. **The `supabase.from(` / `supabase.rpc(` ban is now backwards.** M0-06 added an
   ESLint `no-restricted-properties` rule and M0-07 added a CI grep, both failing the
   build if `web/` queried Supabase directly. That was correct mechanical enforcement
   of the old trust boundary. Under the new architecture it forbids the only way the
   app can work, and would fail CI on the first M1 feature. Both are removed in M0-10.

> Worth naming plainly: this guard did its job. It was not wrong, it is just enforcing
> a decision that no longer holds. The replacement guard — "every table has RLS
> enabled" (M0-09) — protects the same property the old one did.

**Still true, still worth keeping:** `useCurrentUser` reads the role from `app_user`,
not from the token. It just reads it with `supabase.from('app_user')` now instead of
`GET /api/me`.

---

## M0-07 · CI and deployment

**Status:** ◐ **Rework.** CI landed in
[#66](https://github.com/Agile-Porkchops/pajapan/pull/66) and works; the deploy half
was deliberately deferred and is now re-scoped to different targets.

**What stands:** the `guards` and `web` jobs, and the secrets grep — including both of
its hard-won exclusions (`package-lock.json`'s base64 integrity hashes, and
`.github/workflows/` where the pattern text self-matches). Those were verified against
real CI runs and the reasoning is unchanged by the pivot.

**What changes:**

- [ ] Delete the `api` job (`dotnet restore`/`build`/`test`)
- [ ] Delete the "Web never queries Supabase directly" guard — see M0-06
- [ ] Add a guard that fails if any migration adds a table without enabling RLS
- [ ] Bump `node-version` from 22 to 24, matching what is actually installed
- [ ] Add a `db` job: `supabase start`, `supabase db reset`, run the database tests
- [ ] Deploy `web/` to **Cloudflare Pages** (not Vercel), project root `web/`
- [ ] Migrations via `supabase db push` in the deploy workflow, staging first

Gone entirely: `Dockerfile`, `.dockerignore`, `fly.toml`, the `GET /health` endpoint
and its tests. A health check exists to tell you whether *your* server is up; there
is no longer a server of ours to be down.

> Migrations run from CI, never by hand against a deployed database — unchanged, and
> more important now that migrations carry the authorization rules too. A policy
> hand-applied in the dashboard exists in no file and reaches production never.

**Done when:**
- [ ] A PR runs CI and it passes
- [ ] A PR containing a fake JWT still fails the secrets grep — re-verify by pushing
      one, as #66 did; the exclusions changed around it
- [ ] A migration creating a table without `ENABLE ROW LEVEL SECURITY` fails CI —
      verify by actually writing one
- [ ] Staging web can log in against staging Supabase over HTTPS

---

## M0-08 · Supabase CLI and local stack

**Depends on:** M0-02
**Branch:** `feature/m0-supabase-cli`

> Replaces M0-03's Testcontainers fixture. Every RLS and RPC test in every later
> milestone runs against this, so it comes before anything that needs testing.

**Files:** `supabase/config.toml`, `supabase/seed.sql`, `docs/SETUP.md`

**Requirements:**

- [ ] Supabase CLI installed and pinned in `docs/SETUP.md`; `supabase init` committed
- [ ] `supabase start` brings up Postgres + GoTrue + PostgREST + Realtime locally
- [ ] `supabase/seed.sql` creates **one confirmed user per role** — Customer,
      JapanBuyer, Fulfilment, Admin — plus a second Customer. The second one is not
      padding: every cross-customer isolation test needs someone to be isolated *from*.
- [ ] Seeded users have known passwords so tests can `signInWithPassword`. These are
      local-only fixtures and belong in the committed seed file; the secrets grep must
      not trip on them
- [ ] `supabase db reset` returns to a known state, applying migrations then seed
- [ ] `docs/SETUP.md`: clone → `supabase start` → `npm run dev`, assuming no prior
      Supabase knowledge

**Done when:**
- [ ] A clean clone reaches a running local stack following only `docs/SETUP.md`
- [ ] `supabase db reset` twice in a row gives byte-identical state
- [ ] A Vitest test can sign in as each seeded role and read back its own `app_user`
      row

---

## M0-09 · RLS foundation and structural guards 🔴

**Depends on:** M0-08
**Branch:** `feature/m0-rls-foundation`
**Model:** Opus. This replaces M0-04 as the highest-risk task in M0 — every
authorization rule in the app rests on the pattern established here.

**Files:** `supabase/migrations/<ts>_app_user_and_rls.sql`,
`supabase/tests/rls-structural.test.ts`

**Requirements:**

- [ ] `money_php` domain (`numeric(12,2)`) — see M0-03's carried-forward note. Every
      monetary column in M1-01 uses it.
- [ ] `app_user` table, `id` = `auth.users.id`, with `role`, `display_name`, `email`,
      `phone`, `is_blocked`. Spec §4.3.
- [ ] A trigger on `auth.users` insert creates the `app_user` row with role
      `Customer`. This replaces `CurrentUser.GetAsync()`'s create-on-first-sight — and
      is strictly better, because a user can no longer exist in auth with no
      application row.
- [ ] RLS enabled on `app_user`: a user reads and updates their own row; only Admin
      may write `role`.
- [ ] A role helper used by every later policy.

> **The recursion trap, flagged because it will bite otherwise.** A policy on
> `app_user` that calls a helper which itself selects from `app_user` recurses
> infinitely and Postgres aborts the query. The helper must be `SECURITY DEFINER`
> (so it bypasses RLS and cannot re-enter the policy) **and** `STABLE` (so Postgres
> evaluates it once per statement rather than once per row — this is the difference
> between a role check that is free and one that is a query per row):
>
> ```sql
> CREATE FUNCTION current_app_role() RETURNS text
> LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
>   SELECT role FROM app_user WHERE id = auth.uid();
> $$;
> ```
>
> Shape, not gospel — verify the recursion and the plan against the running stack
> before building M1 on top of it.

**The three structural tests.** These are not about `app_user`; they are the guards
that make every *future* migration safe, which is why they belong here and not in
M7-01:

- [ ] Every table in `public` has `rowsecurity = true` — enumerate `pg_tables`. Fails
      loudly on any table added later without a policy. Global Constraint 12.
- [ ] Every `SECURITY DEFINER` function pins a `search_path` — enumerate `pg_proc`.
      Global Constraint 13.
- [ ] An anonymous client, holding only the anon key, can read the public catalog and
      **nothing else**.

**Done when:**
- [ ] Signing up a brand-new user creates exactly one `app_user` row, role `Customer`
- [ ] Customer A cannot read Customer B's `app_user` row — asserted from a real
      signed-in client, not by reading the policy
- [ ] A customer cannot promote themselves: `update app_user set role='Admin'` where
      id = own id changes nothing
- [ ] A forged `role` claim in the JWT grants nothing — the M0-04 test, ported
- [ ] All three structural tests pass, and each has been seen to **fail** by
      temporarily introducing the thing it detects

---

## M0-10 · Rewire web to Supabase-native

**Depends on:** M0-09
**Branch:** `feature/m0-web-rewire`

**Requirements:**

- [ ] Delete `web/src/lib/apiClient.ts` and `VITE_API_URL`
- [ ] Remove the `no-restricted-properties` ESLint rule banning `supabase.from`/`.rpc`
      — M0-06
- [ ] `useCurrentUser()` reads `app_user` via `supabase.from()` instead of `GET /api/me`
- [ ] Establish the **error-handling convention every later task follows**: a shared
      helper that takes `{ data, error }` and throws on `error`, so TanStack Query's
      error state does the work `apiClient`'s throw used to. Without one, Global
      Constraint 9 has to be remembered at every call site, and it will not be.

**Done when:**
- [ ] Login, `/admin` role gating, and sign-out all still work
- [ ] With the local Supabase stack **stopped**, the app shows an error state — not a
      spinner forever, not an empty page, not zeros
- [ ] `git grep -n "VITE_API_URL\|apiClient"` returns nothing

---

## Milestone exit

- [ ] M0-07 reworked and M0-08…M0-10 merged to `main`
- [ ] A teammate can clone, follow `docs/SETUP.md`, run `supabase start`, and log in
- [ ] Staging is live and all three team members have accounts with the right roles
- [ ] The three structural guards are in CI and have each been seen to fail
- [ ] No secret is in git history — `git log -p | grep -E "eyJ|sb_secret_"` is empty
