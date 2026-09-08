# M7 — Hardening and launch

**Goal:** Run a real buying trip on the real system without discovering something
expensive halfway through.

**Read first:** spec §6.1, §10, §12.
**Estimate:** 4–5 days · **8 tasks**

---

> ## ⚠ Rewritten for the 2026-09-08 pivot — detail deliberately pending
>
> Structural notes only. Write each task's detail when you start it. Requirements and
> **Done when** items below still bind.

---

## M7-01 · Cross-tenant security pass 🔴

**Depends on:** all of M2–M6
**Branch:** `feature/m7-security-tests`
**Model:** Opus. The whole point is adversarial thinking.

> Spec §6.1 lists the rules. Individual milestones tested them one at a time. This task
> tests them **together**, as an attacker would, and writes down what was tried.

**Becomes:** the most changed task in M7 — and the one where the pivot moved the target
rather than shrinking it.

> **What the old task protected, and how that translates.** Its best idea was
> `Every_admin_route_has_an_authorization_policy`: enumerate the routes and fail on any
> without a policy, so *a route added later* is caught automatically. As the task itself
> said — *this is the one test that keeps working as the codebase grows.*
>
> The direct equivalents already exist as M0-09's structural guards: enumerate
> `pg_tables` for RLS, enumerate `pg_proc` for `search_path`. M7-01's job is to extend
> that idea to the things a growing schema can still get wrong:
>
> - a table with RLS **enabled but no policies at all** — locked to everyone, which
>   looks safe and silently breaks a feature
> - a table with a **`USING (true)`** policy — RLS on, enforcing nothing. This is the
>   dangerous one, because it passes M0-09's guard.
> - a `SECURITY DEFINER` function whose body **never references `auth.uid()`** — a
>   heuristic, not a proof, but it catches the exact omission that is a full breach
> - a view over a money table **without** `security_invoker`

**Requirements:**

- [ ] A fixture with two customers (A, B), a JapanBuyer, a Fulfilment user and an
      Admin, all really signed in against the local stack.
- [ ] **The full matrix, driven by data, not by hand:** for every table and view, for
      every role, assert what is readable and what is not. A table added later with no
      matrix entry fails the test.
- [ ] Customer A reaches **zero rows** of B's orders, addresses, payments, refunds,
      custom requests and shipments — by direct `supabase-js` calls, not through the UI.
- [ ] `JapanBuyer` reaches no payment, refund, finance view, or customer contact detail.
- [ ] No RPC function accepts a caller identity. Enumerate `pg_proc` arguments and fail
      on any parameter matching `customer_id`, `user_id`, or `role`. This is the direct
      descendant of the old reflection-over-DTOs check.
- [ ] The four structural checks listed in the callout above.
- [ ] **Manually attempt the attacks against staging**, with the browser devtools and a
      raw client: alter UUIDs, replay another user's token, forge a `role` claim,
      reference another customer's address in `place_order`, call every admin RPC as a
      customer, `select('*')` every table. Record each attempt and its result in
      `docs/SECURITY-TESTING.md`.

**Done when:**
- [ ] Every cross-tenant assertion returns zero rows or a refusal
- [ ] The matrix test **fails** when you temporarily add a table without a policy, and
      again when you temporarily add a `USING (true)` policy — verify both
- [ ] `docs/SECURITY-TESTING.md` records every attempt with its outcome and date

---

## M7-02 · Failure-state audit

**Depends on:** M6-06
**Branch:** `feature/m7-failure-states`

> Global Constraint 9. A sweep for the places it decayed.

**Becomes:** the same audit, hunting a different shape. There are no `catch {}` blocks
to grep for; the silent failure of this architecture is **an ignored `error` field**.

**Requirements:**

- [ ] Grep for the new shape and fix every hit — a destructured `data` with no `error`
      check, `?? []`, `|| []`, `data ?? 0`:

```bash
git grep -nE "const \{ data \} = await supabase" -- web/src/
git grep -nE "\?\?\s*\[\]|\|\|\s*\[\]|\?\?\s*0" -- web/src/
```

- [ ] Verify every list uses `DataState` from M1-05:
      `git grep -L "DataState" web/src/**/*Page.tsx`
- [ ] Verify every Supabase call goes through M0-10's throwing helper rather than
      handling `{ data, error }` inline.
- [ ] Walk every screen with the **database unreachable**. Each must show an error with
      a retry — not a spinner, not an empty state, not zeros.
- [ ] Walk every screen **signed in as a role that is denied** — a genuinely new failure
      mode. RLS returns *zero rows*, not an error, so a denied read looks exactly like
      an empty result. Every screen must distinguish "nothing here" from "not yours",
      and neither may look like a broken page.
- [ ] Walk every screen with an **empty but successful** response. The empty state must
      be visibly different from the error state.
- [ ] Set a request timeout so a hung query surfaces as an error rather than a permanent
      spinner.

**Done when:**
- [ ] The greps return nothing
- [ ] Every screen has been checked in all four failure modes, checklist committed
- [ ] No screen shows ₱0 or an empty table when its data failed to load **or was
      refused**

---

## M7-03 · Responsive pass

**Depends on:** M7-02
**Branch:** `feature/m7-responsive`

**Becomes:** unchanged.

**Requirements:** every screen at 390, 768, 1024 and 1440 px, screenshotted; no
horizontal body scroll at 390 px anywhere, wide tables scrolling inside their own
container; 44 px minimum tap targets, 56 px on the shopping list (M4-04) and product
form (M1-06); the four phone-critical screens — product form, shopping list, checkout,
payment submission — re-tested **on real hardware** on throttled data; 200% browser
zoom reflows rather than clips.

**Done when:**
- [ ] No horizontal scroll at 390 px on any screen
- [ ] The four critical screens are verified on real hardware, not just DevTools
- [ ] Screenshots at all four widths are committed to `docs/screenshots/`

---

## M7-04 · Accessibility pass

**Depends on:** M7-03
**Branch:** `feature/m7-a11y`

**Becomes:** unchanged.

**Requirements:** every interactive element keyboard-reachable with a visible focus
ring — tab through checkout and the shopping list end to end without a mouse; contrast
**measured with a tool**, 4.5:1 text and 3:1 for large text and UI boundaries; no
information by colour alone (status pills carry text, profit carries a sign and a
label); labels on every control, errors linked with `aria-describedby` and announced
via `role="alert"`; alt text on images, product name for photos, `alt=""` for
decorative; axe DevTools clean of criticals and serious issues on every screen.

**Done when:**
- [ ] Checkout is completable with the keyboard alone
- [ ] axe reports zero critical or serious issues
- [ ] Contrast ratios are recorded in the PR, with numbers

---

## M7-05 · PWA and offline behaviour

**Depends on:** M7-03
**Branch:** `feature/m7-pwa`

> Spec: "mobile" means **a responsive PWA**, not native app-store apps. This task is
> the whole of that commitment — there is no Expo/React Native track.

**Becomes:** unchanged, with one sharpened rule.

**Requirements:**

- [ ] `manifest.json`, icons, theme colour. Installable on Android and iOS.
- [ ] A service worker caching **the app shell only**. Do **not** cache Supabase
      responses — stale prices and stale order statuses are worse than an error. This
      matters more now: `supabase-js` requests are ordinary `fetch` calls to an API
      origin, so a broadly-scoped runtime caching rule will hoover them up by accident
      in a way the old separate API origin made harder.
- [ ] An offline page saying the connection is down. No fake data.
- [ ] An offline indicator via `navigator.onLine`, plus disabled submit buttons while
      offline. Relevant in a Japanese shop basement.
- [ ] The service worker updates cleanly — test a deploy while a client is open.

**Done when:**
- [ ] Installs on a real Android and a real iPhone
- [ ] Offline shows the offline page; no cached prices are ever displayed
- [ ] The Network tab confirms no Supabase response is served from the cache
- [ ] Deploying while a client is open prompts a refresh rather than breaking silently

---

## M7-06 · Backups and restore drill

**Depends on:** M0-07
**Branch:** `feature/m7-backups`

> An untested backup is not a backup.

**Becomes:** higher stakes, because **the database now holds the application logic as
well as the data.** Losing the schema means losing every RLS policy and every RPC
function — the entire authorization model. Migrations in git are the real recovery path
for that half; the backup covers the data.

**Requirements:**

- [ ] Confirm Supabase daily backups are on for production; note the retention period.
- [ ] A `pg_dump` script to a local file, for a copy that does not live in the same
      account as the thing it protects. **Production lives on a different Supabase
      account from staging** — verify the backup lands outside both.
- [ ] **Do a real restore.** Restore yesterday's production backup into a scratch
      project, point a local web build at it, and confirm orders and payments are intact
      **and that RLS still denies cross-customer reads** — a restore that loses policies
      is a restore that silently opens the data.
- [ ] Time it and write the number down. "Restore takes about 40 minutes" is the fact
      you need at the moment you need it.
- [ ] Storage objects are **not** in the Postgres backup. Script a bucket export, or
      accept the risk explicitly and write that down.
- [ ] `docs/RUNBOOK.md`: what to do when the database is unreachable, when a payment is
      double-verified, when a shipment is lost, when a restore is needed, and **when a
      migration must be rolled back** — there is no blue/green deploy to hide behind.

**Done when:**
- [ ] A restore has actually been performed and the restored data verified
- [ ] The restored copy still enforces RLS — checked with a real cross-customer read
- [ ] Restore time is recorded in the runbook
- [ ] The Storage backup position is documented either way

---

## M7-07 · Dry run on real data 🔴

**Depends on:** M7-01 … M7-06
**Branch:** `feature/m7-dry-run`
**Model:** Opus.

> The last chance to find something expensive before a customer does.

**Becomes:** unchanged. This task never depended on the architecture.

**Requirements:**

- [ ] On staging, a complete cycle with the whole team, each in their real role: create
      a run, list 20 real products, place 5 orders from 3 accounts, pay them (real GCash
      references, small amounts), verify, close, generate the shopping list, buy 15
      items, mark 5 unavailable, refund them, pack, ship, land, deliver, complete.
- [ ] Check the P&L against a hand-worked figure. If they differ, **stop** and find out
      why before launch.
- [ ] Deliberately break things mid-flow: double-submit an order, verify a payment
      twice, mark a line bought twice, refund more than was paid. Each must be refused
      cleanly.
- [ ] Time each staff task. Anything slower than the current WhatsApp-and-spreadsheet
      process is a bug in the design, not a training problem.
- [ ] Write down every friction point. Fix the ones that would cause a mistake with real
      money; defer the rest.

**Done when:**
- [ ] The full cycle completed with all three team members
- [ ] P&L matches the hand-computed figure to the centavo
- [ ] All four deliberate breakages were refused cleanly
- [ ] Findings are written to `docs/DRY-RUN-2026-XX.md` and triaged

---

## M7-08 · Launch

**Depends on:** M7-07
**Branch:** `feature/m7-launch`

**Becomes:** simpler in the deploy, stricter in the schema check.

**Requirements:**

- [ ] Production Supabase project, **on a separate account from staging**, its own keys.
- [ ] Run migrations against production from CI. Verify the schema matches staging with
      `supabase db diff` — **an empty diff is the acceptance criterion**, and it now
      covers policies and functions, not only tables. This is a stronger check than the
      old migration-list comparison.
- [ ] Create the three real staff accounts with correct roles. Verify each sees only
      their own surface — actually log in as each.
- [ ] Seed real categories and the first run's products.
- [ ] Custom domain, HTTPS, and security headers on Cloudflare Pages
      (`Strict-Transport-Security`, `X-Content-Type-Options`, a CSP). **No CORS
      configuration** — there is no origin of ours for the browser to be blocked from.
- [ ] Confirm no staging key, seed data, or test account exists in production. The
      local-only seed users from M0-08 must not exist there — check explicitly, since
      they have known passwords.
- [ ] Publish the refund policy page — spec §12, and a genuine obligation given that
      unavailable items are certain.
- [ ] Soft launch: one run, invite-only, ~10 trusted customers. Do not open publicly
      until one full run has completed on production.
- [ ] Tag `v1.0.0`.

**Done when:**
- [ ] `supabase db diff` between staging and production is empty
- [ ] No M0-08 seed user exists in production
- [ ] All three staff can log in with the right role and surface
- [ ] The refund policy is published and linked from checkout
- [ ] One full run has completed on production before any public announcement

---

## Milestone exit

- [ ] Every security test passes, and the manual attempts are documented
- [ ] No screen fails silently in any of the four failure modes
- [ ] A restore has been performed, timed, and verified to still enforce RLS
- [ ] One real run has completed on production, and the P&L matched reality
