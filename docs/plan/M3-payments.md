# M3 — Payments

**Goal:** A customer uploads a GCash screenshot, staff verifies it, and the order
becomes Confirmed and eligible for the shopping list.

**Scope note:** manual proof-of-payment only. The gateway is out of scope for all
eight milestones — the `Provider`/`ProviderRef` seam built in M1-01 is the entire
preparation for it (spec §4.5, §11).

**Read first:** spec §4.5, §8.1.
**Estimate:** 3–4 days · **6 tasks**

---

## M3-01 · Submit payment proof

**Depends on:** M2-06, M1-04
**Branch:** `feature/m3-submit-payment`

**Files:**
- Create: `Features/Payments/SubmitPaymentEndpoint.cs`, `PaymentDtos.cs`
- Test: `tests/Pajapan.Api.Tests/PaymentTests.cs`

**Steps:**

- [ ] **1.** `POST /api/orders/{id}/payments`, Customer, own order only, with an
      `Idempotency-Key` header (Global Constraint 8):

```jsonc
{ "method": "GCash", "amountPhp": "2450.00",
  "referenceNo": "0123456789012", "proofPath": "payment-proofs/2026/08/<uuid>.webp" }
```

- [ ] **2.** Validation:
      - order belongs to the caller, else **404**
      - order status is `AwaitingPayment` or `PaymentSubmitted`, else 409
      - `amountPhp > 0`
      - `proofPath` starts with `payment-proofs/` — a client-supplied path pointing at
        another bucket must be rejected, not trusted
      - `referenceNo` is 6–40 chars

- [ ] **3.** A duplicate `referenceNo` hits the unique index from M1-01. Catch it and
      return **409 with a clear message**: "This reference number has already been
      submitted." Do not let it surface as a 500 — the customer needs to know it is
      their screenshot, not your server.

- [ ] **4.** Insert as `Status = Submitted`. Set the order to `PaymentSubmitted`.
      **Do not touch `AmountPaidPhp`** — an unverified payment is not money.

- [ ] **5.** Tests: another customer's order → 404; duplicate reference → 409; a
      `proofPath` of `product-photos/x.webp` → 400; submitting does not change
      `AmountPaidPhp`.

- [ ] **6.** Commit.

**Done when:**
- [ ] All four tests pass
- [ ] A duplicate reference returns 409 with a human-readable message, not a 500

---

## M3-02 · Payment instructions UI

**Depends on:** M3-01
**Branch:** `feature/m3-payment-ui`

**Files:**
- Create: `web/src/features/orders/PaymentPanel.tsx`, `PaymentProofForm.tsx`
- Modify: `web/src/features/orders/OrderDetailPage.tsx`

**Steps:**

- [ ] **1.** Show the payable amount large and copyable, plus the account details per
      method (GCash number, BPI account). Account details come from configuration, not
      hardcoded in a component.

- [ ] **2.** A tap-to-copy button on the amount and on the account number. Most
      payment errors are transcription errors.

- [ ] **3.** Form: method select, amount (prefilled with the balance due), reference
      number, proof upload (reuse `PhotoUploader` from M1-06 with purpose
      `payment-proof`).

- [ ] **4.** Reuse `useIdempotencyKey` from M2-07, generated on mount.

- [ ] **5.** After submit, show "Waiting for verification" with the submitted amount,
      reference and thumbnail. Allow submitting a second payment if a balance remains.

- [ ] **6.** State the timeframe honestly — "usually verified within a few hours" —
      rather than implying it is instant.

- [ ] **7.** Commit.

**Done when:**
- [ ] Tap-to-copy works on iOS Safari and Android Chrome
- [ ] Submitting twice with the same key creates one payment
- [ ] The panel reads clearly at 390 px

---

## M3-03 · Verification queue API

**Depends on:** M3-01
**Branch:** `feature/m3-verify-api`

**Files:**
- Create: `Features/Payments/VerificationEndpoints.cs`,
  `Features/Payments/OrderTotals.cs`

**Steps:**

- [ ] **1.** Endpoints, `Fulfilment | Admin`:

```
GET  /api/admin/payments?status=Submitted&runId=
POST /api/admin/payments/{id}/verify
POST /api/admin/payments/{id}/reject     { reason }
```

- [ ] **2.** The queue returns the payment, a signed read URL for the proof, the
      order code, the customer name, the amount due and the amount already verified —
      everything needed to decide, so the verifier never has to open a second screen.

- [ ] **3.** `VerifiedByUserId` and `VerifiedAt` come from `CurrentUser`. The caller
      cannot supply them (spec §6.1).

- [ ] **4.** Verify and reject are only valid from `Submitted`. From any other state,
      409 — this stops a double-click from double-counting money.

- [ ] **5.** `OrderTotals.RecomputeAsync(order)` — the single place order money is
      recalculated. Every caller in M3–M6 uses it; nothing recomputes totals inline:

```csharp
public static async Task RecomputeAsync(AppDbContext db, Order order, CancellationToken ct)
{
    order.AmountPaidPhp = await db.Payments
        .Where(p => p.OrderId == order.Id && p.Status == PaymentStatus.Verified)
        .SumAsync(p => p.AmountPhp, ct);

    order.AmountRefundedPhp = await db.Refunds
        .Where(r => r.OrderId == order.Id && r.Status == RefundStatus.Completed)
        .SumAsync(r => r.AmountPhp, ct);

    // Confirmation is one-way. A later refund must not un-confirm a bought order.
    if (order.Status == OrderStatus.PaymentSubmitted &&
        order.AmountPaidPhp >= order.GrandTotalPhp)
    {
        order.Status = OrderStatus.Confirmed;
        order.ConfirmedAt ??= DateTimeOffset.UtcNow;
    }
}
```

- [ ] **6.** Reject requires a non-empty reason, shown to the customer, and returns
      the order to `AwaitingPayment`.

- [ ] **7.** Tests: verifying twice → 409 and `AmountPaidPhp` counted once; underpayment
      leaves the order in `PaymentSubmitted`; exact payment confirms; a `JapanBuyer`
      token → 403.

- [ ] **8.** Commit.

**Done when:**
- [ ] The four tests pass
- [ ] Double-clicking verify counts the money once
- [ ] `git grep -n "AmountPaidPhp ="` shows exactly one assignment, inside
      `OrderTotals`

---

## M3-04 · Verification queue UI

**Depends on:** M3-03
**Branch:** `feature/m3-verify-ui`

**Files:**
- Create: `web/src/features/admin/payments/VerifyQueuePage.tsx`, `ProofViewer.tsx`

**Steps:**

- [ ] **1.** Queue, oldest first. Each row: order code, customer, claimed amount,
      amount due, reference number, proof thumbnail, Verify / Reject.

- [ ] **2.** Click the thumbnail to open the full proof in a lightbox with zoom —
      GCash reference numbers are small in a screenshot.

- [ ] **3.** **Highlight a mismatch** between the claimed amount and the amount due
      before the verifier clicks. Catching an underpayment after confirmation is much
      more expensive than catching it here.

- [ ] **4.** Reject opens a required-reason dialog with three common presets (wrong
      amount, unreadable screenshot, reference not found) plus free text.

- [ ] **5.** Optimistic removal from the queue, with rollback and a toast on failure.

- [ ] **6.** Show a queue count badge in the admin nav.

- [ ] **7.** Commit.

**Done when:**
- [ ] A payment 100 pesos short is visibly flagged before verifying
- [ ] Reject with an empty reason is impossible
- [ ] The proof is readable zoomed on a laptop screen

---

## M3-05 · Balance and partial payments

**Depends on:** M3-03
**Branch:** `feature/m3-balances`

**Steps:**

- [ ] **1.** `OrderDto` exposes `amountDuePhp = GrandTotalPhp − AmountPaidPhp +
      AmountRefundedPhp`, computed server-side. The client never does this arithmetic.

- [ ] **2.** Order list filters: Unpaid, Partially paid, Paid, Overpaid. Overpaid is a
      real state that needs a human — surface it rather than hiding it.

- [ ] **3.** Admin can adjust `ShippingFeePhp` and `ServiceFeePhp` while the order is
      `AwaitingPayment` or `PaymentSubmitted`. Doing so recomputes `GrandTotalPhp` and
      calls `OrderTotals.RecomputeAsync`. **Refused once the order is `Confirmed`** —
      changing the price after someone has paid in full is not a thing the system
      should allow silently.

- [ ] **4.** Tests: two partial payments summing to the total confirm the order; a fee
      change on a Confirmed order → 409.

- [ ] **5.** Commit.

**Done when:**
- [ ] Two partial payments confirm the order at exactly the total
- [ ] An overpaid order appears under the Overpaid filter
- [ ] Editing fees on a Confirmed order is refused

---

## M3-06 · Reconciliation check

**Depends on:** M3-05
**Branch:** `feature/m3-reconciliation`

> The cached `AmountPaidPhp` (spec §4.4) is a denormalisation. This task is what makes
> it safe: a check that proves the cache still matches the payment rows.

**Files:**
- Create: `Features/Reports/ReconciliationEndpoint.cs`
- Test: `tests/Pajapan.Api.Tests/ReconciliationTests.cs`

**Steps:**

- [ ] **1.** `GET /api/admin/reconciliation` (Admin) returns every order where the
      cached totals disagree with the sums:

```sql
select o.id, o.order_code, o.amount_paid_php,
       coalesce(p.total, 0) as actual_paid,
       o.amount_refunded_php, coalesce(r.total, 0) as actual_refunded
from   "order" o
left   join (select order_id, sum(amount_php) total from payment
             where status = 1 group by order_id) p on p.order_id = o.id
left   join (select order_id, sum(amount_php) total from refund
             where status = 1 group by order_id) r on r.order_id = o.id
where  o.deleted_at is null
  and (o.amount_paid_php     <> coalesce(p.total, 0)
    or o.amount_refunded_php <> coalesce(r.total, 0));
```

- [ ] **2.** Show it on the finance dashboard in M6. Empty is the normal state; any
      row is a bug worth chasing the same day.

- [ ] **3.** A test that runs the full lifecycle — order, two payments, one refund —
      and asserts the reconciliation query returns zero rows.

- [ ] **4.** `POST /api/admin/reconciliation/repair` (Admin) recomputes the caches for
      a named order. Manual, per-order, logged — never a sweep that quietly rewrites
      every row and destroys the evidence of what went wrong.

- [ ] **5.** Commit.

**Done when:**
- [ ] The lifecycle test ends with zero reconciliation rows
- [ ] Manually corrupting `amount_paid_php` with SQL makes that order appear in the
      report, and `repair` fixes exactly that one order

---

## Milestone exit

- [ ] A real payment has been submitted and verified on staging, confirming an order
- [ ] Only `OrderTotals.RecomputeAsync` writes `AmountPaidPhp`
- [ ] Reconciliation returns zero rows
- [ ] `Payment.Provider` and `ProviderRef` exist, are null everywhere, and no code
      reads them yet
