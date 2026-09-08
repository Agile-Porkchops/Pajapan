# M3 — Payments

**Goal:** A customer uploads a GCash screenshot, staff verifies it, and the order
becomes Confirmed and eligible for the shopping list.

**Scope note:** manual proof-of-payment only. The gateway is out of scope for all
eight milestones — the `provider`/`provider_ref` seam built in M1-01 is the entire
preparation for it (spec §4.5, §11). When it does arrive it will be a Supabase Edge
Function holding the secret and receiving the webhook, not a new vendor.

**Read first:** spec §4.5, §8.1, §7.2.
**Estimate:** 3–4 days · **6 tasks**

---

> ## ⚠ Rewritten for the 2026-09-08 pivot — detail deliberately pending
>
> Structural notes only. Write each task's SQL when you start it, against the running
> local stack. Requirements and **Done when** items below still bind.

---

## The one improvement the pivot hands this milestone

The old design had `OrderTotals.RecomputeAsync` — one C# method that every money path
in M3–M6 had to remember to call. The Done-when even said so: *`git grep -n
"AmountPaidPhp ="` shows exactly one assignment*. That is a convention enforced by
grep, which is to say enforced by whoever remembers to run it.

In Postgres this becomes a **trigger on `payment` and `refund` that recomputes the
parent order**. Nothing has to remember; a row cannot be written without the recompute
happening. The forget-to-call bug stops existing rather than being tested for.

Two things to verify rather than assume when writing it:

- the trigger must not recurse (it writes `order`, which must not re-fire it)
- confirmation stays **one-way** — a later refund must not un-confirm a bought order.
  That rule was a comment in the C# version and is easy to lose in translation.

---

## M3-01 · Submit payment proof

**Depends on:** M2-06, M1-04
**Branch:** `feature/m3-submit-payment`

**Becomes:** a `submit_payment_proof` function. `payment` grants no direct insert —
an unverified payment row is still a money row.

**Requirements:**

- [ ] Takes order id, method, amount, reference number, proof path, and an idempotency
      key (Global Constraint 8).
- [ ] Order must belong to the caller — checked from `auth.uid()`, not a parameter.
- [ ] Order status must be `AwaitingPayment` or `PaymentSubmitted`; anything else is
      refused.
- [ ] `amount_php > 0`; `reference_no` 6–40 chars.
- [ ] `proof_path` must be under the caller's own payment-proofs prefix. **Belt and
      braces with M1-04's storage policy** — the policy stops them writing the object,
      this stops them *referencing* someone else's. A path pointing at another bucket
      is rejected, not trusted.
- [ ] Inserts as `Submitted` and sets the order to `PaymentSubmitted`. **Does not touch
      `amount_paid_php`** — an unverified payment is not money.
- [ ] A duplicate `reference_no` hits M1-01's unique index. Return a clear, specific
      refusal — "this reference number has already been submitted" — not a raw
      constraint error. The customer needs to know it is their screenshot, not your
      server.

**Done when:**
- [ ] Another customer's order cannot be paid against
- [ ] A duplicate reference gives a human-readable refusal, not a raw 500
- [ ] A `proof_path` pointing at `product-photos/` is rejected
- [ ] Submitting does not change `amount_paid_php`

---

## M3-02 · Payment instructions UI

**Depends on:** M3-01
**Branch:** `feature/m3-payment-ui`

**Becomes:** unchanged; calls `.rpc()` instead of `POST`.

**Requirements:**

- [ ] Payable amount shown large and copyable, plus per-method account details (GCash
      number, BPI account) **from configuration**, not hardcoded in a component.
- [ ] Tap-to-copy on the amount and the account number. Most payment errors are
      transcription errors.
- [ ] Form: method select, amount prefilled with the balance due, reference number,
      proof upload (`PhotoUploader` from M1-06, `payment-proofs` bucket).
- [ ] Idempotency key generated on mount, reused from M2-07.
- [ ] After submit: "Waiting for verification" with amount, reference and thumbnail.
      Allow a second payment if a balance remains.
- [ ] State the timeframe honestly — "usually verified within a few hours" — rather
      than implying it is instant.

**Done when:**
- [ ] Tap-to-copy works on iOS Safari and Android Chrome
- [ ] Submitting twice with the same key creates one payment
- [ ] The panel reads clearly at 390 px

---

## M3-03 · Verification queue 🔴

**Depends on:** M3-01
**Branch:** `feature/m3-verify`
**Model:** Opus. This decides when money counts.

**Becomes:** a `v_verification_queue` view for the read, plus `verify_payment` and
`reject_payment` functions for the writes.

**Requirements:**

- [ ] The queue view gives the verifier everything needed to decide without opening a
      second screen: payment, a signed read URL for the proof, order code, customer
      name, amount due, amount already verified. Readable by Fulfilment and Admin only.
- [ ] `verified_by_user_id` and `verified_at` come from `auth.uid()` inside the
      function. The caller cannot supply them (spec §6.1).
- [ ] Verify and reject are valid **only from `Submitted`**. From any other state,
      refuse — this is what stops a double-click double-counting money.
- [ ] Reject requires a non-empty reason, shown to the customer, and returns the order
      to `AwaitingPayment`.
- [ ] Totals recomputed by the trigger above, not by the function's own arithmetic.

**Done when:**
- [ ] Verifying twice counts the money once — the second call is refused
- [ ] Underpayment leaves the order in `PaymentSubmitted`; exact payment confirms it
- [ ] A JapanBuyer cannot read the queue view **or** call either function
- [ ] `amount_paid_php` is written in exactly one place — now the trigger, verified by
      searching the migrations rather than the application code

---

## M3-04 · Verification queue UI

**Depends on:** M3-03
**Branch:** `feature/m3-verify-ui`

**Becomes:** unchanged.

**Requirements:**

- [ ] Queue oldest first: order code, customer, claimed amount, amount due, reference,
      proof thumbnail, Verify / Reject.
- [ ] Thumbnail opens a lightbox with zoom — GCash reference numbers are small in a
      screenshot.
- [ ] **Highlight a mismatch** between claimed amount and amount due *before* the
      verifier clicks. Catching an underpayment after confirmation is far more
      expensive than catching it here.
- [ ] Reject opens a required-reason dialog with three presets (wrong amount,
      unreadable screenshot, reference not found) plus free text.
- [ ] Optimistic removal from the queue with rollback and a toast on failure.
- [ ] Queue count badge in the admin nav.

**Done when:**
- [ ] A payment 100 pesos short is visibly flagged before verifying
- [ ] Reject with an empty reason is impossible
- [ ] The proof is readable zoomed on a laptop screen

---

## M3-05 · Balance and partial payments

**Depends on:** M3-03
**Branch:** `feature/m3-balances`

**Becomes:** `amount_due_php` is a computed column in the customer's order view —
`grand_total_php − amount_paid_php + amount_refunded_php`, cast to text. The client
never does this arithmetic, and now cannot: it never receives the operands as numbers.

**Requirements:**

- [ ] Order list filters: Unpaid, Partially paid, Paid, **Overpaid**. Overpaid is a
      real state that needs a human — surface it rather than hiding it.
- [ ] Admin may adjust `shipping_fee_php` and `service_fee_php` while the order is
      `AwaitingPayment` or `PaymentSubmitted`, which recomputes `grand_total_php`.
      **Refused once the order is `Confirmed`** — changing the price after someone has
      paid in full is not something the system should allow silently. This is a
      column-and-state rule, so it belongs in a function or a trigger, not a policy.

**Done when:**
- [ ] Two partial payments summing to the total confirm the order at exactly the total
- [ ] An overpaid order appears under the Overpaid filter
- [ ] Editing fees on a Confirmed order is refused **by the database**

---

## M3-06 · Reconciliation check 🔴

**Depends on:** M3-05
**Branch:** `feature/m3-reconciliation`
**Model:** Opus.

> The cached `amount_paid_php` (spec §4.4) is a denormalisation. This task is what
> makes it safe: a check proving the cache still matches the payment rows.

**Becomes:** a `v_reconciliation` view plus a repair function. **The old task's SQL
carries over essentially unchanged** — it was already SQL, and it is the one piece of
the C# plan that needed no translation at all:

```sql
SELECT o.id, o.order_code, o.amount_paid_php,
       coalesce(p.total, 0) AS actual_paid,
       o.amount_refunded_php, coalesce(r.total, 0) AS actual_refunded
FROM   "order" o
LEFT   JOIN (SELECT order_id, sum(amount_php) total FROM payment
             WHERE status = 'Verified' GROUP BY order_id) p ON p.order_id = o.id
LEFT   JOIN (SELECT order_id, sum(amount_php) total FROM refund
             WHERE status = 'Completed' GROUP BY order_id) r ON r.order_id = o.id
WHERE  o.deleted_at IS NULL
  AND (o.amount_paid_php     <> coalesce(p.total, 0)
    OR o.amount_refunded_php <> coalesce(r.total, 0));
```

**Requirements:**

- [ ] Admin-only. Shown on the M6 finance dashboard. Empty is the normal state; any row
      is a bug worth chasing the same day.
- [ ] A repair function recomputes the caches **for one named order**. Manual,
      per-order, logged — never a sweep that quietly rewrites every row and destroys
      the evidence of what went wrong.
- [ ] A test running the full lifecycle — order, two payments, one refund — ending with
      zero reconciliation rows.

**Done when:**
- [ ] The lifecycle test ends with zero reconciliation rows
- [ ] Manually corrupting `amount_paid_php` with SQL makes that order appear in the
      view, and repair fixes exactly that one order and no others

---

## Milestone exit

- [ ] A real payment has been submitted and verified on staging, confirming an order
- [ ] `amount_paid_php` is written only by the recompute trigger
- [ ] Reconciliation returns zero rows
- [ ] `payment.provider` and `provider_ref` exist, are null everywhere, and nothing
      reads them yet
