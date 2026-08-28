# M4 — Runs and procurement

**Goal:** The cutoff closes, a shopping list appears on the Japan buyer's phone, they
work it in-store marking got / not-got, and unavailable items produce refunds.

**This is the milestone that makes the app match the business.** M0–M3 could belong to
any store. Spec §3 is the reasoning; re-read it before starting.

**Read first:** spec §3, §3.1, §4.2, §7.1, §8.2, §8.3.
**Estimate:** 5–6 days · **8 tasks**

---

## M4-01 · Run lifecycle API

**Depends on:** M1-01
**Branch:** `feature/m4-runs`

**Files:**
- Create: `Features/Runs/RunEndpoints.cs`, `Features/Runs/RunStateMachine.cs`
- Test: `tests/Pajapan.Api.Tests/RunTests.cs`

**Steps:**

- [ ] **1.** Endpoints, Admin except where noted:

```
GET  /api/admin/runs                     Staff
POST /api/admin/runs                     Admin  { code, name, ordersCloseAtUtc, buyingDate, estimatedArrival }
PUT  /api/admin/runs/{id}                Admin  (only while Open)
POST /api/admin/runs/{id}/status         Admin  { to }
```

- [ ] **2.** `RunStateMachine` — transitions declared once, as data, so no endpoint
      invents its own rule:

```csharp
private static readonly Dictionary<RunStatus, RunStatus[]> Allowed = new()
{
    [RunStatus.Open]         = [RunStatus.Closed, RunStatus.Cancelled],
    [RunStatus.Closed]       = [RunStatus.Buying, RunStatus.Open],   // reopen is allowed
    [RunStatus.Buying]       = [RunStatus.Packed],
    [RunStatus.Packed]       = [RunStatus.Shipped],
    [RunStatus.Shipped]      = [RunStatus.Landed],
    [RunStatus.Landed]       = [RunStatus.Distributing],
    [RunStatus.Distributing] = [RunStatus.Completed],
    [RunStatus.Completed]    = [],
    [RunStatus.Cancelled]    = [],
};
```

  > `Closed → Open` is deliberate. Cutoffs slip, and a system that cannot reopen a run
  > forces staff to fake data to get around it.

- [ ] **3.** **At most one `Open` run at a time.** Enforce with a partial unique index,
      not application code:

```sql
create unique index ux_run_single_open on run ((status)) where status = 0;
```

- [ ] **4.** Closing a run reports what it is leaving behind: the count and value of
      orders still `AwaitingPayment` or `PaymentSubmitted`. It does not cancel them —
      spec §15 leaves that a manual decision.

- [ ] **5.** Transitioning `Closed → Buying` is refused if the run has zero Confirmed
      orders. That is always a mistake.

- [ ] **6.** Tests: an illegal transition → 409; a second Open run → 409;
      `Closed → Buying` with no confirmed orders → 409.

- [ ] **7.** Commit.

**Done when:**
- [ ] Creating a second Open run fails at the database, not just in C#
- [ ] Every illegal transition in the table returns 409

---

## M4-02 · Run admin UI

**Depends on:** M4-01
**Branch:** `feature/m4-run-ui`

**Files:**
- Create: `web/src/features/admin/runs/RunListPage.tsx`, `RunDetailPage.tsx`,
  `RunStatusStepper.tsx`

**Steps:**

- [ ] **1.** Run list with status, cutoff, order count, confirmed count, total value.
- [ ] **2.** Detail page with a stepper showing the eight states, current highlighted,
      next actions as buttons. Illegal transitions are not rendered at all.
- [ ] **3.** Cutoff entered in **JST** with the timezone shown on the label — the
      person setting it is standing in Japan. Store UTC.
- [ ] **4.** Closing shows a confirmation dialog naming the unpaid orders it will
      strand, with a link to them.
- [ ] **5.** Commit.

**Done when:**
- [ ] A cutoff entered as 21:00 JST stores the correct UTC and displays as the correct
      Manila time on the storefront
- [ ] Closing a run with unpaid orders warns with the actual count and value

---

## M4-03 · Shopping list API

**Depends on:** M4-01, M3-03
**Branch:** `feature/m4-shopping-list`

> Spec §7.1: no new table. This is a query.

**Files:**
- Create: `Features/Buying/ShoppingListEndpoint.cs`

**Steps:**

- [ ] **1.** `GET /api/buying/list?runId=`, `JapanBuyer | Admin`. Grouped by product,
      ordered by store then name, so the list walks the shop:

```csharp
var rows = await db.OrderItems
    .Where(i => i.Order.RunId == runId
             && i.Order.Status == OrderStatus.Confirmed
             && i.Order.DeletedAt == null)
    .GroupBy(i => new { i.ProductId, i.NameSnapshot })
    .Select(g => new ShoppingListRow(
        g.Key.ProductId,
        g.Key.NameSnapshot,
        g.Sum(i => i.Qty),
        g.Sum(i => i.QtyFulfilled),
        g.Count(i => i.LineStatus == OrderLineStatus.Pending)))
    .ToListAsync(ct);
```

  Join `Product` for `SourceStore`, `RefPriceJpy` and the thumbnail. Products deleted
  since the order still appear — that is what `NameSnapshot` is for.

- [ ] **2.** **Confirmed orders only.** An unpaid order must never appear on the
      shopping list; buying for it means fronting cash, which spec §2 rules out.

- [ ] **3.** Include a total estimated JPY spend (`Σ RefPriceJpy × qty`) so the buyer
      knows what to carry.

- [ ] **4.** `GET /api/buying/list/{productId}/orders` — which orders want this
      product, for partial-fulfilment decisions. Returns order code and qty only, no
      customer contact details: a `JapanBuyer` has no need for them (spec §6).

- [ ] **5.** Tests: an `AwaitingPayment` order does not appear; a `JapanBuyer` sees no
      customer phone or address in any response.

- [ ] **6.** Commit.

**Done when:**
- [ ] Unpaid orders are absent from the list
- [ ] No response on `/api/buying/*` contains a customer name, phone or address
- [ ] The list is ordered by store, then name

---

## M4-04 · Shopping list UI

**Depends on:** M4-03
**Branch:** `feature/m4-shopping-ui`

> Used one-handed, in a crowded shop, on Japanese mobile data, possibly with gloves on.
> Design for that. It is the second screen after M1-06 where the physical context
> should drive the design.

**Files:**
- Create: `web/src/features/buying/ShoppingListPage.tsx`, `ShoppingListRow.tsx`,
  `StoreGroup.tsx`

**Steps:**

- [ ] **1.** Mobile-first, single column. Grouped by `sourceStore` with sticky group
      headers.

- [ ] **2.** Each row: thumbnail (tap to enlarge), name, **quantity needed in large
      type**, reference JPY price, and a big Got it / Not available pair. Minimum 56 px
      tall — larger than the 44 px baseline, because this is used while walking.

- [ ] **3.** Progress header: "18 of 34 items done", plus running JPY spend against
      the estimate.

- [ ] **4.** Filter chips: All / Remaining / Done. Default Remaining — the list
      shortens as they work, which is the whole point.

- [ ] **5.** Keep the screen awake while the page is open (`navigator.wakeLock`),
      degrading silently where unsupported.

- [ ] **6.** Optimistic marking with rollback and a toast on failure. On a flaky
      connection the buyer must never be left unsure whether a tap registered.

- [ ] **7.** Commit.

**Done when:**
- [ ] Usable one-handed on a 390 px phone — verify by actually holding one
- [ ] Every tap target is at least 56 px
- [ ] With the network off, marking shows a clear failed state and retries when it
      returns

---

## M4-05 · Mark lines bought or unavailable

**Depends on:** M4-04
**Branch:** `feature/m4-mark-lines`

> Where the actual cost enters the system. Spec §3.1: `ActualCostJpy` is half of the
> margin calculation, and it is only ever captured here. If this is skipped in a rush,
> M6's reports are worthless.

**Files:**
- Create: `Features/Buying/MarkLineEndpoint.cs`
- Test: `tests/Pajapan.Api.Tests/BuyingTests.cs`

**Steps:**

- [ ] **1.** Two endpoints, `JapanBuyer | Admin`:

```
POST /api/buying/products/{productId}/mark   { runId, status, actualCostJpy?, note? }   // all lines
POST /api/buying/lines/{orderItemId}         { status, qtyFulfilled, actualCostJpy?, note? }
```

  The bulk one is what gets used: one tap marks every order wanting that product.

- [ ] **2.** Rules:
      - `Bought` requires `actualCostJpy` — a bought line with no cost is refused, not
        defaulted to zero. Zero would silently read as infinite margin in M6.
      - `Bought` sets `QtyFulfilled = Qty`; `PartiallyBought` takes an explicit
        `qtyFulfilled` where `0 < qtyFulfilled < Qty`
      - `Unavailable` sets `QtyFulfilled = 0` and queues a refund (M4-06)
      - `Substituted` requires a note and an `actualCostJpy`
      - only valid while the run is `Buying`; otherwise 409

- [ ] **3.** After marking, recompute the parent order:

```
all lines Bought                   → OrderStatus.Fulfilled
any Bought and any Unavailable     → OrderStatus.PartiallyFulfilled
all lines Unavailable              → OrderStatus.PartiallyFulfilled + a full refund
```

- [ ] **4.** Marking is idempotent — re-marking a line to the same status with the same
      cost changes nothing and returns 200. The buyer will double-tap.

- [ ] **5.** Tests: `Bought` without cost → 400; marking outside `Buying` → 409;
      bulk-mark updates every affected order; re-marking is a no-op;
      partial `qtyFulfilled` of `0` or `Qty` → 400.

- [ ] **6.** Commit.

**Done when:**
- [ ] All five tests pass
- [ ] A `Bought` line always has a non-null, non-zero `ActualCostJpy`
- [ ] Bulk-marking one product correctly updates twelve different orders

---

## M4-06 · Refunds

**Depends on:** M4-05, M3-03
**Branch:** `feature/m4-refunds`

> Spec §8.3: **refunds are never automatic.** The system creates the obligation; a
> human moves the money and records the proof.

**Files:**
- Create: `Features/Payments/RefundEndpoints.cs`,
  `web/src/features/admin/refunds/RefundQueuePage.tsx`

**Steps:**

- [ ] **1.** Marking a line `Unavailable` creates a `Refund` with
      `Status = Pending`, `Reason = ItemUnavailable`, and
      `AmountPhp = Qty × UnitPricePhpSnapshot`. It does **not** move money and does not
      touch `AmountRefundedPhp` — pending is an obligation, not a payment.

- [ ] **2.** Endpoints, `Fulfilment | Admin`:

```
GET  /api/admin/refunds?status=Pending
POST /api/admin/refunds                       manual refund { orderId, amountPhp, reason, reasonNote }
POST /api/admin/refunds/{id}/complete         { method, referenceNo, proofPath }
POST /api/admin/refunds/{id}/fail             { note }
```

- [ ] **3.** `complete` requires a reference number and proof — the same evidence
      standard as money coming in. It sets `Status = Completed`, then calls
      `OrderTotals.RecomputeAsync`.

- [ ] **4.** Guard: total completed refunds for an order may never exceed
      `AmountPaidPhp`. Refunding more than was received is either a bug or theft, and
      the check costs one line.

- [ ] **5.** Refund queue UI: order code, customer, amount, reason, the item that
      caused it, and a complete form. Grouped by customer so several unavailable items
      across one person's orders can be sent as one transfer.

- [ ] **6.** Customer sees the refund on their order detail with its status and, once
      complete, the reference number.

- [ ] **7.** Tests: unavailable line creates a Pending refund of exactly
      `qty × snapshot`; completing updates `AmountRefundedPhp`; over-refunding → 409;
      completing without proof → 400.

- [ ] **8.** Commit.

**Done when:**
- [ ] The four tests pass
- [ ] A Pending refund does not change `AmountRefundedPhp`; completing it does
- [ ] Attempting to refund more than was paid is refused

---

## M4-07 · Expense capture

**Depends on:** M1-01
**Branch:** `feature/m4-expenses`

**Files:**
- Create: `Features/Expenses/ExpenseEndpoints.cs`,
  `web/src/features/admin/expenses/ExpenseFormPage.tsx`, `ExpenseListPage.tsx`

**Steps:**

- [ ] **1.** CRUD at `/api/expenses`, `JapanBuyer | Fulfilment | Admin`. A JapanBuyer
      may create and edit their own; only Admin may delete.

- [ ] **2.** JPY expenses require `FxRateToPhp`, and `AmountPhp` is computed and
      **stored** at save time (spec §4.7, Global Constraint 3). Never recomputed later.

- [ ] **3.** Prefill the rate from the last expense on the same run, so the buyer
      types it once per trip rather than once per receipt.

- [ ] **4.** Receipt photo upload (purpose `receipt`), reusing `PhotoUploader`.

- [ ] **5.** Mobile-first form — receipts get photographed on the spot, in Japan, not
      typed up later at a desk.

- [ ] **6.** Test: changing a run's later expense rate does not alter an earlier
      expense's stored `AmountPhp`.

- [ ] **7.** Commit.

**Done when:**
- [ ] A JPY expense stores both the rate used and the resulting PHP amount
- [ ] An earlier expense's PHP amount is untouched by a later, different rate

---

## M4-08 · Run cutoff automation and notices

**Depends on:** M4-02, M4-06
**Branch:** `feature/m4-cutoff`

> Spec §11: no background job runner. The cutoff is enforced on read, not by a timer.

**Steps:**

- [ ] **1.** `POST /api/orders` already rejects a past cutoff (M2-06). Verify it also
      rejects while the run is still nominally `Open` — the clock is authoritative, not
      the status column.

- [ ] **2.** The storefront banner switches to "Orders closed" from the timestamp
      alone, without waiting for an admin to press Close.

- [ ] **3.** Admin dashboard card: "Run 2026-09A cutoff passed 4 hours ago — 3 orders
      unpaid." The nudge that replaces the scheduled job.

- [ ] **4.** `GET /api/admin/runs/{id}/close-preview`: confirmed count and value,
      unpaid count and value, and the products that will be on the shopping list.

- [ ] **5.** Test: an order posted one second after the cutoff, against a run still
      marked Open, returns 409.

- [ ] **6.** Commit.

**Done when:**
- [ ] Ordering after the cutoff fails even while the run is still Open
- [ ] The dashboard shows the passed-cutoff nudge with correct counts

---

## Milestone exit

- [ ] A full cycle has been run on staging: open → orders → pay → close → shopping list
      → mark bought and unavailable → refund raised and completed
- [ ] Every Bought line has a real `ActualCostJpy`
- [ ] The shopping list was used on a phone and is genuinely usable one-handed
- [ ] No unpaid order ever reached the shopping list
