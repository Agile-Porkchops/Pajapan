# M7 — Hardening and launch

**Goal:** Run a real buying trip on the real system without discovering something
expensive halfway through.

**Read first:** spec §6.1, §10, §12.
**Estimate:** 4–5 days · **8 tasks**

---

## M7-01 · Cross-tenant security pass

**Depends on:** all of M2–M6
**Branch:** `feature/m7-security-tests`

> Spec §6.1 lists rules. Individual milestones tested them one at a time. This task
> tests them **together**, as an attacker would, and writes down what was tried.

**Files:**
- Create: `tests/Pajapan.Api.Tests/Security/CrossTenantTests.cs`,
  `docs/SECURITY-TESTING.md`

**Steps:**

- [ ] **1.** A test fixture with two customers (A, B), a JapanBuyer, a Fulfilment user
      and an Admin, each with real tokens.

- [ ] **2.** For **every** customer-scoped endpoint, assert A cannot reach B's
      resource, and that the response is **404, not 403**:

```csharp
public static IEnumerable<object[]> CustomerScopedEndpoints => [
    ["GET",  "/api/orders/{id}"],          ["GET",  "/api/addresses/{id}"],
    ["PUT",  "/api/addresses/{id}"],       ["DELETE","/api/addresses/{id}"],
    ["POST", "/api/orders/{id}/payments"], ["GET",  "/api/custom-requests/{id}"],
    ["POST", "/api/custom-requests/{id}/accept"],
];

[Theory, MemberData(nameof(CustomerScopedEndpoints))]
public async Task Customer_A_cannot_reach_customer_B(string verb, string template) { … }
```

- [ ] **3.** For every `/api/admin/*` and `/api/buying/*` endpoint, assert a `Customer`
      token gets 403. Enumerate the routes from `EndpointDataSource` so a new endpoint
      added later without a policy **fails this test automatically**:

```csharp
[Fact]
public void Every_admin_route_has_an_authorization_policy()
{
    var unprotected = _endpoints.Endpoints
        .OfType<RouteEndpoint>()
        .Where(e => e.RoutePattern.RawText!.StartsWith("/api/admin"))
        .Where(e => e.Metadata.GetMetadata<IAuthorizeData>() is null)
        .Select(e => e.RoutePattern.RawText);
    Assert.Empty(unprotected);
}
```

  > This is the one test that keeps working as the codebase grows. Everything else in
  > this file tests today's routes; this tests tomorrow's too.

- [ ] **4.** Assert `JapanBuyer` cannot reach payments, refunds, finance reports, or
      any customer contact detail.

- [ ] **5.** Assert no endpoint accepts `customerId` from body or query — enumerate
      request DTOs by reflection and fail on any property named `CustomerId`.

- [ ] **6.** Manually attempt the attacks against staging: alter UUIDs in URLs, replay
      another user's token, forge a `role` claim, submit another customer's
      `addressId`, POST to `/api/admin/*` with a customer token. Record each attempt
      and its result in `docs/SECURITY-TESTING.md`.

- [ ] **7.** Commit.

**Done when:**
- [ ] Every cross-tenant test passes with 404
- [ ] `Every_admin_route_has_an_authorization_policy` passes, and **fails** when you
      temporarily add an unprotected admin route — verify this
- [ ] `docs/SECURITY-TESTING.md` records every attempt with its outcome and date

---

## M7-02 · Failure-state audit

**Depends on:** M6-06
**Branch:** `feature/m7-failure-states`

> Global Constraint 9. This task is a sweep for the places it decayed.

**Steps:**

- [ ] **1.** Grep for silent failure and fix every hit:

```bash
git grep -nE "catch\s*\{\s*\}|catch\s*\(.*\)\s*\{\s*(return|//)" -- src/
git grep -nE "\?\?\s*\[\]|\|\|\s*\[\]|catch.*return \[\]" -- web/src/
```

- [ ] **2.** Walk every screen with the API stopped. Each must show an error with a
      retry — not a spinner, not an empty state, not zeros. Keep a checklist.

- [ ] **3.** Walk every screen with the API returning 500. Same standard.

- [ ] **4.** Walk every screen with an empty but successful response. Each must show a
      real empty state that is visibly different from the error state.

- [ ] **5.** Verify every list uses `DataState` from M1-05:
      `git grep -L "DataState" web/src/**/*Page.tsx`

- [ ] **6.** Set an API request timeout of 30 s in `apiClient`; a hung request must
      surface as an error rather than a permanent spinner.

- [ ] **7.** Commit.

**Done when:**
- [ ] The two greps return nothing
- [ ] Every screen has been checked in all three failure modes, with the checklist
      committed
- [ ] No screen shows ₱0 or an empty table when its data failed to load

---

## M7-03 · Responsive pass

**Depends on:** M7-02
**Branch:** `feature/m7-responsive`

**Steps:**

- [ ] **1.** Every screen at 390, 768, 1024 and 1440 px. Screenshot each.
- [ ] **2.** No horizontal body scroll at 390 px anywhere. Wide tables scroll inside
      their own container.
- [ ] **3.** Tap targets: 44 px minimum everywhere; 56 px on the shopping list (M4-04)
      and the product form (M1-06).
- [ ] **4.** The four phone-critical screens re-tested on a real device on throttled
      data: product form, shopping list, checkout, payment submission.
- [ ] **5.** Test at 200% browser zoom — content must reflow, not clip.
- [ ] **6.** Commit screenshots to `docs/screenshots/`.

**Done when:**
- [ ] No horizontal scroll at 390 px on any screen
- [ ] The four critical screens are verified on real hardware, not just DevTools
- [ ] Screenshots at all four widths are committed

---

## M7-04 · Accessibility pass

**Depends on:** M7-03
**Branch:** `feature/m7-a11y`

**Steps:**

- [ ] **1.** Every interactive element reachable by keyboard, with a visible focus ring.
      Tab through checkout and the shopping list end to end without a mouse.
- [ ] **2.** Contrast measured against WCAG AA — 4.5:1 for text, 3:1 for large text and
      UI boundaries. **Measured with a tool, not eyeballed.**
- [ ] **3.** No information conveyed by colour alone: order status pills carry text;
      profit carries a sign and a label.
- [ ] **4.** Labels on every form control. Errors linked with `aria-describedby` and
      announced via `role="alert"`.
- [ ] **5.** Images have alt text. Product photos use the product name; decorative
      images use `alt=""`.
- [ ] **6.** Run axe DevTools on every screen; fix all criticals and serious issues.
- [ ] **7.** Commit.

**Done when:**
- [ ] Checkout is completable with the keyboard alone
- [ ] axe reports zero critical or serious issues
- [ ] Contrast ratios are recorded in the PR, with numbers

---

## M7-05 · PWA and offline behaviour

**Depends on:** M7-03
**Branch:** `feature/m7-pwa`

**Steps:**

- [ ] **1.** `manifest.json`, icons, theme colour. Installable on Android and iOS.
- [ ] **2.** A service worker caching the **app shell only**. Do **not** cache API
      responses: stale prices and stale order statuses are worse than an error.
- [ ] **3.** An offline page saying the connection is down. No fake data.
- [ ] **4.** An offline indicator in the header via `navigator.onLine`, plus disabling
      submit buttons while offline. Relevant in a Japanese shop basement.
- [ ] **5.** Verify the service worker updates cleanly — a stale shell serving against
      a new API is a support nightmare. Test a deploy while a client is open.
- [ ] **6.** Commit.

**Done when:**
- [ ] Installs on a real Android and a real iPhone
- [ ] Offline shows the offline page; no cached prices are ever displayed
- [ ] Deploying while a client is open prompts a refresh rather than breaking silently

---

## M7-06 · Backups and restore drill

**Depends on:** M0-07
**Branch:** `feature/m7-backups`

> An untested backup is not a backup.

**Steps:**

- [ ] **1.** Confirm Supabase daily backups are on for production, and note the
      retention period.
- [ ] **2.** `scripts/backup.ps1` — `pg_dump` to a local file, for a copy that does not
      live in the same account as the thing it protects.
- [ ] **3.** **Do a real restore.** Restore yesterday's production backup into a scratch
      project, run the API against it, and confirm orders and payments are intact.
- [ ] **4.** Time it and write down the number. "Restore takes about 40 minutes" is the
      fact you need at the moment you need it.
- [ ] **5.** Storage objects are **not** in the Postgres backup. Script a bucket
      export, or accept the risk explicitly and write that down.
- [ ] **6.** `docs/RUNBOOK.md`: what to do when the API is down, when a payment is
      double-verified, when a shipment is lost, when a restore is needed.
- [ ] **7.** Commit.

**Done when:**
- [ ] A restore has actually been performed and the restored data verified
- [ ] Restore time is recorded in the runbook
- [ ] The Storage backup position is documented either way

---

## M7-07 · Dry run on real data

**Depends on:** M7-01 … M7-06
**Branch:** `feature/m7-dry-run`

> The last chance to find something expensive before a customer does.

**Steps:**

- [ ] **1.** On staging, run a complete cycle with the whole team, each in their real
      role: create a run, list 20 real products, place 5 orders from 3 accounts, pay
      them (real GCash references, small amounts), verify, close, generate the shopping
      list, buy 15 items, mark 5 unavailable, refund them, pack, ship, land, deliver,
      complete.

- [ ] **2.** Check the P&L against a hand-worked figure. If they differ, stop and find
      out why before launch.

- [ ] **3.** Deliberately break things mid-flow: double-submit an order, verify a
      payment twice, mark a line bought twice, refund more than was paid. Each must be
      refused cleanly.

- [ ] **4.** Time each staff task. Anything slower than the current WhatsApp-and-
      spreadsheet process is a bug in the design, not a training problem.

- [ ] **5.** Write down every friction point. Fix the ones that would cause a mistake
      with real money; defer the rest to a post-launch list.

- [ ] **6.** Commit the findings to `docs/DRY-RUN-2026-XX.md`.

**Done when:**
- [ ] The full cycle completed with all three team members
- [ ] P&L matches the hand-computed figure to the centavo
- [ ] All four deliberate breakages were refused cleanly
- [ ] Findings are written down and triaged

---

## M7-08 · Launch

**Depends on:** M7-07
**Branch:** `feature/m7-launch`

**Steps:**

- [ ] **1.** Production Supabase project, separate from staging, its own keys.
- [ ] **2.** Run migrations against production from CI. Verify the schema matches
      staging: `dotnet ef migrations list` on both.
- [ ] **3.** Create the three real staff accounts with correct roles. Verify each sees
      only their own surface.
- [ ] **4.** Seed real categories and the first run's products.
- [ ] **5.** Custom domain, HTTPS, correct CORS origins, security headers
      (`Strict-Transport-Security`, `X-Content-Type-Options`, a CSP).
- [ ] **6.** Confirm no staging key, seed script, or test account exists in production:

```bash
git grep -n "seed-dev" -- ':!scripts/' ; # should be empty
```

- [ ] **7.** Publish the refund policy page — spec §12, and a genuine obligation given
      that unavailable items are certain.
- [ ] **8.** Soft launch: one run, invite-only, ~10 trusted customers. Do not open
      publicly until one full run has completed on production.
- [ ] **9.** Commit and tag `v1.0.0`.

**Done when:**
- [ ] Production and staging schemas match exactly
- [ ] All three staff can log in with the right role and surface
- [ ] The refund policy is published and linked from checkout
- [ ] One full run has completed on production before any public announcement

---

## Milestone exit

- [ ] Every security test passes, and the attempts are documented
- [ ] No screen fails silently in any of the three failure modes
- [ ] A restore has been performed and timed
- [ ] One real run has completed on production, and the P&L matched reality
