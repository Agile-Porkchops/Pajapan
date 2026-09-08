# M4 — Runs and procurement

**Goal:** The cutoff closes, a shopping list appears on the Japan buyer's phone, they
work it in-store marking got / not-got, and unavailable items produce refunds.

**This is the milestone that makes the app match the business.** M0–M3 could belong to
any store. Spec §3 is the reasoning; re-read it before starting.

**Read first:** spec §3, §3.1, §4.2, §7.1, §8.2, §8.3.
**Estimate:** 5–6 days · **8 tasks**

---

> ## ⚠ Rewritten for the 2026-09-08 pivot — detail deliberately pending
>
> Structural notes only. Write each task's SQL when you start it, against the running
> local stack. Requirements and **Done when** items below still bind.

---

## M4-01 · Run lifecycle

**Depends on:** M1-01
**Branch:** `feature/m4-runs`

**Becomes:** an `advance_run_status` function plus database constraints. The old
`RunStateMachine` dictionary becomes a transition table or a `CHECK`-backed function —
either way **declared once, as data**, so nothing invents its own rule.

Allowed transitions, unchanged:

| From | To |
|---|---|
| Open | Closed, Cancelled |
| Closed | Buying, **Open** |
| Buying | Packed |
| Packed | Shipped |
| Shipped | Landed |
| Landed | Distributing |
| Distributing | Completed |
| Completed, Cancelled | — |

> `Closed → Open` is deliberate. Cutoffs slip, and a system that cannot reopen a run
> forces staff to fake data to get around it.

**Requirements:**

- [ ] **At most one `Open` run at a time**, enforced by a partial unique index — this
      carries over verbatim, it was already the right answer:
      `CREATE UNIQUE INDEX ux_run_single_open ON run ((status)) WHERE status = 'Open';`
- [ ] Closing a run reports what it leaves behind: count and value of orders still
      `AwaitingPayment` or `PaymentSubmitted`. It does **not** cancel them — spec §15
      leaves that a manual decision.
- [ ] `Closed → Buying` is refused if the run has zero Confirmed orders. That is always
      a mistake.
- [ ] Runs are readable by all staff; only Admin may create, edit or transition. Edits
      only while `Open`.

**Done when:**
- [ ] Creating a second Open run fails **at the database**, not in application code
- [ ] Every illegal transition in the table above is refused
- [ ] `Closed → Buying` with no confirmed orders is refused

---

## M4-02 · Run admin UI

**Depends on:** M4-01
**Branch:** `feature/m4-run-ui`

**Becomes:** unchanged.

**Requirements:** run list with status, cutoff, order count, confirmed count, total
value; detail page with a stepper over the eight states, current highlighted, next
actions as buttons, illegal transitions not rendered at all; cutoff entered in **JST**
with the timezone on the label — the person setting it is standing in Japan — stored
UTC; closing shows a confirmation naming the unpaid orders it will strand, with a link
to them.

**Done when:**
- [ ] A cutoff entered as 21:00 JST stores the correct UTC and displays as the correct
      Manila time on the storefront
- [ ] Closing a run with unpaid orders warns with the actual count and value

---

## M4-03 · Shopping list function

**Depends on:** M4-01, M3-03
**Branch:** `feature/m4-shopping-list`

> Spec §7.1: no new table. This is a query — and specifically a **`SECURITY DEFINER`
> function, not a view.** Spec §7.1 explains why at length; the short version is
> directly below, because this task is where the reasoning actually bites.

**Becomes:** `get_shopping_list(p_run_id)`, role-checked internally.

> The old task's rule was: *`GET /api/buying/*` returns order code and qty only, no
> customer contact details — a `JapanBuyer` has no need for them (spec §6).* A DTO made
> that easy. Here, a `security_invoker` view would require granting JapanBuyer `SELECT`
> on `order`, and `order` carries the snapshotted recipient name, phone and full
> delivery address. The aggregate is safe to show; the rows behind it are not. Hence
> the function.

**Requirements:**

- [ ] Grouped by product, ordered by **store then name**, so the list walks the shop.
- [ ] Joins `product` for `source_store`, `ref_price_jpy` and the thumbnail. Products
      deleted since the order still appear — that is what `name_snapshot` is for.
- [ ] **Confirmed orders only.** An unpaid order must never appear; buying for it means
      fronting cash, which spec §2 rules out.
- [ ] Total estimated JPY spend (`Σ ref_price_jpy × qty`) so the buyer knows what to
      carry.
- [ ] A per-product breakdown of which orders want it, for partial-fulfilment
      decisions: **order code and qty only**, no customer contact details.

**Done when:**
- [ ] Unpaid orders are absent from the list
- [ ] Signed in as JapanBuyer, **no** query reachable to them returns a customer name,
      phone or address — including a direct `select('*')` against `order`
- [ ] The list is ordered by store, then name

---

## M4-04 · Shopping list UI

**Depends on:** M4-03
**Branch:** `feature/m4-shopping-ui`

> Used one-handed, in a crowded shop, on Japanese mobile data, possibly with gloves on.
> Design for that. It is the second screen after M1-06 where the physical context
> should drive the design.

**Becomes:** unchanged.

**Requirements:** mobile-first single column, grouped by `source_store` with sticky
headers; each row has a tap-to-enlarge thumbnail, name, **quantity needed in large
type**, reference JPY price, and a big Got it / Not available pair at **minimum 56 px**
— larger than the 44 px baseline, because this is used while walking; progress header
("18 of 34 items done") with running JPY spend against the estimate; filter chips All /
Remaining / Done defaulting to **Remaining**, so the list shortens as they work;
`navigator.wakeLock` to keep the screen on, degrading silently; optimistic marking with
rollback and a toast, because on a flaky connection the buyer must never be left unsure
whether a tap registered.

**Done when:**
- [ ] Usable one-handed on a 390 px phone — verify by actually holding one
- [ ] Every tap target is at least 56 px
- [ ] With the network off, marking shows a clear failed state and retries when it
      returns

---

## M4-05 · Mark lines bought or unavailable 🔴

**Depends on:** M4-04
**Branch:** `feature/m4-mark-lines`
**Model:** Opus.

> Where the actual cost enters the system. Spec §3.1: `actual_cost_jpy` is half of the
> margin calculation and is only ever captured here. If this is skipped in a rush, M6's
> reports are worthless.

**Becomes:** `mark_order_item` and a bulk `mark_product_lines` function. The bulk one is
what actually gets used: one tap marks every order wanting that product.

**Requirements** — all carried over:

- [ ] `Bought` **requires** `actual_cost_jpy`. A bought line with no cost is refused,
      not defaulted to zero. Zero would silently read as infinite margin in M6.
- [ ] `Bought` sets `qty_fulfilled = qty`; `PartiallyBought` takes an explicit value
      where `0 < qty_fulfilled < qty`; `Unavailable` sets `0` and queues a refund;
      `Substituted` requires a note **and** a cost.
- [ ] Valid only while the run is `Buying`.
- [ ] Parent order status recomputed after marking: all Bought → `Fulfilled`; any Bought
      and any Unavailable → `PartiallyFulfilled`; all Unavailable → `PartiallyFulfilled`
      plus a full refund.
- [ ] **Idempotent.** Re-marking a line to the same status with the same cost changes
      nothing and succeeds. The buyer will double-tap.

> Spec §8.3: the line status change and the `Pending` refund row are written **in the
> same transaction**. An unavailable item whose refund row failed to appear is money
> quietly owed to a customer with nothing in the system saying so. Inside one function
> this is the default rather than something two calls have to arrange — which is the
> main thing the pivot improves here.

**Done when:**
- [ ] `Bought` without a cost is refused
- [ ] Marking outside `Buying` is refused
- [ ] Bulk-marking one product correctly updates twelve different orders
- [ ] Re-marking is a no-op
- [ ] `qty_fulfilled` of `0` or `qty` on a `PartiallyBought` is refused
- [ ] Every `Bought` line has a non-null, non-zero `actual_cost_jpy`

---

## M4-06 · Refunds 🔴

**Depends on:** M4-05, M3-03
**Branch:** `feature/m4-refunds`
**Model:** Opus. Money out.

> Spec §8.3: **refunds are never automatic.** The system creates the obligation; a
> human moves the money and records the proof.

**Becomes:** `issue_refund`, `complete_refund`, `fail_refund` functions plus a
Fulfilment/Admin-scoped queue view.

**Requirements:**

- [ ] Marking a line `Unavailable` creates a refund with `Pending`,
      `reason = ItemUnavailable`, `amount_php = qty × unit_price_php_snapshot`. It does
      **not** move money and does not touch `amount_refunded_php` — pending is an
      obligation, not a payment.
- [ ] `complete` requires a reference number **and** proof — the same evidence standard
      as money coming in. Totals then follow from M3's recompute trigger.
- [ ] **Guard: total completed refunds may never exceed `amount_paid_php`.** Refunding
      more than was received is either a bug or theft, and the check costs one line.
- [ ] Queue UI grouped **by customer**, so several unavailable items across one person's
      orders can be sent as one transfer.
- [ ] The customer sees the refund on their order detail with its status and, once
      complete, the reference number.

**Done when:**
- [ ] An unavailable line creates a Pending refund of exactly `qty × snapshot`
- [ ] A Pending refund does not change `amount_refunded_php`; completing it does
- [ ] Over-refunding is refused
- [ ] Completing without proof is refused

---

## M4-07 · Expense capture

**Depends on:** M1-01
**Branch:** `feature/m4-expenses`

**Becomes:** direct writes under RLS, plus a trigger for the FX arithmetic. Expenses
are staff-entered records rather than customer money, so §7.2's fourth row applies —
with one exception: `amount_php` must not be client-supplied.

**Requirements:**

- [ ] JapanBuyer, Fulfilment and Admin may create; a JapanBuyer may edit their own; only
      Admin may delete.
- [ ] A JPY expense requires `fx_rate_to_php`, and `amount_php` is **computed and
      stored at save time** (spec §4.7, Global Constraint 3). Compute it in a trigger,
      not in the form — that way it cannot be supplied, and it cannot be skipped.
- [ ] Never recomputed later. A report run six months on must reproduce the same peso
      figure it showed on the day.
- [ ] Prefill the rate from the last expense on the same run, so the buyer types it once
      per trip rather than once per receipt.
- [ ] Receipt photo upload (`receipts` bucket), reusing `PhotoUploader`.
- [ ] Mobile-first form — receipts get photographed on the spot, in Japan, not typed up
      later at a desk.

**Done when:**
- [ ] A JPY expense stores both the rate used and the resulting PHP amount
- [ ] An earlier expense's PHP amount is untouched by a later, different rate
- [ ] A client-supplied `amount_php` is overwritten by the trigger, not trusted

---

## M4-08 · Run cutoff enforcement and notices

**Depends on:** M4-02, M4-06
**Branch:** `feature/m4-cutoff`

> Spec §11: no background job runner. The cutoff is enforced **on read**, not by a
> timer. Unchanged by the pivot — and if this ever does need automating, the answer is
> `pg_cron` or a scheduled Edge Function, not a server.

**Requirements:**

- [ ] `place_order` already rejects a past cutoff (M2-06). Verify it also rejects while
      the run is still nominally `Open` — **the clock is authoritative, not the status
      column.**
- [ ] The storefront banner switches to "Orders closed" from the timestamp alone,
      without waiting for an admin to press Close.
- [ ] Admin dashboard card: "Run 2026-09A cutoff passed 4 hours ago — 3 orders unpaid."
      The nudge that replaces the scheduled job.
- [ ] A close-preview: confirmed count and value, unpaid count and value, and the
      products that will be on the shopping list.

**Done when:**
- [ ] An order placed one second after the cutoff, against a run still marked Open, is
      refused
- [ ] The dashboard shows the passed-cutoff nudge with correct counts

---

## Milestone exit

- [ ] A full cycle has been run on staging: open → orders → pay → close → shopping list
      → mark bought and unavailable → refund raised and completed
- [ ] Every Bought line has a real `actual_cost_jpy`
- [ ] The shopping list was used on a phone and is genuinely usable one-handed
- [ ] No unpaid order ever reached the shopping list
- [ ] Signed in as JapanBuyer, no customer contact detail is reachable by any query
