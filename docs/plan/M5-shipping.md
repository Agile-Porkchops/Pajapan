# M5 — Shipping and tracking

**Goal:** Bought orders get packed into a box, the box flies, and each customer can
follow both legs from their order page.

**Scope note:** spec §11 — tracking is a **link**, not an API integration. J&T, LBC
and Flash gate their real APIs behind business accounts and return little beyond the
public page. Resist building three integrations here.

**Read first:** spec §4.6, §8.4, §12 (customs).
**Estimate:** 4–5 days · **6 tasks**

---

> ## ⚠ Rewritten for the 2026-09-08 pivot — detail deliberately pending
>
> Structural notes only. Write each task's SQL when you start it, against the running
> local stack. Requirements and **Done when** items below still bind.

---

## M5-01 · Couriers

**Depends on:** M1-01
**Branch:** `feature/m5-couriers`

**Becomes:** seeded in the M1-01 migration; RLS gives everyone read (customers need the
template to build their tracking link) and Admin write.

**Seed data, unchanged** — `{0}` is the tracking number:

| Name | Template | Leg |
|---|---|---|
| J&T Express PH | `https://www.jtexpress.ph/trajectoryQuery?waybillNo={0}` | last mile |
| LBC Express | `https://www.lbcexpress.com/track/?tracking_no={0}` | last mile |
| Flash Express PH | `https://www.flashexpress.ph/tracking/?se={0}` | last mile |
| Japan Post EMS | `https://trackings.post.japanpost.jp/services/srv/search/direct?reqCodeNo1={0}&searchKind=S002&locale=en` | international |
| Yamato | `https://track.kuronekoyamato.co.jp/english/tracking?number={0}` | international |

> **Verify every URL by pasting a real tracking number into it** before committing. A
> broken tracking link is worse than none — the customer thinks the parcel is lost.

**Requirements:**

- [ ] Admin CRUD so a new forwarder can be added without a deploy.
- [ ] The template must contain exactly one `{0}` — a check constraint, since it is a
      property of the value rather than of who is writing it. A template without it
      produces a link to the courier's homepage and a confused customer.
- [ ] `is_active` for retiring a courier without breaking historical shipments.

**Done when:**
- [ ] Every seeded URL has been opened in a browser with a real number and reached a
      tracking page
- [ ] A template with no `{0}` is rejected by the database

---

## M5-02 · Shipments

**Depends on:** M5-01, M4-05
**Branch:** `feature/m5-shipments`

**Becomes:** `create_shipment`, `assign_orders_to_shipment`, `unassign_order` and
`dispatch_shipment` functions. Assignment and dispatch both write rows the caller does
not own and cascade status onto orders, so §7.2's third row applies.

**Requirements** — assignment rules, each with a specific refusal message:

- [ ] `International`: the order must be `Fulfilled` or `PartiallyFulfilled`. Assigning
      an unbought order means shipping an empty box.
- [ ] `LastMile`: exactly one order, already on a landed international shipment.
- [ ] An order already assigned to a shipment of that type is refused, **naming the
      existing shipment**.
- [ ] `declared_value_php` defaults to the sum of assigned orders' `items_total_php`
      and is editable. Spec §12: this is the customs figure, so it must be visible and
      deliberate, never a hidden default.
- [ ] Setting a shipment to `Dispatched` moves every assigned order to `Shipped` /
      `OutForDelivery` **in one transaction**.
- [ ] All international shipments `Dispatched` → the run may go `Shipped`.

**Done when:**
- [ ] Assigning an unbought order is refused
- [ ] Assigning a second order to a LastMile shipment is refused
- [ ] Dispatching a box with 12 orders moves all 12 in one transaction — verified by
      killing the call midway and confirming nothing partial persisted
- [ ] Declared value defaults to the real sum and is editable

---

## M5-03 · Packing UI

**Depends on:** M5-02
**Branch:** `feature/m5-packing`

**Becomes:** unchanged.

**Requirements:**

- [ ] Two panes: unassigned bought orders left, shipments right. Assign by checkbox and
      a button — **not** drag-and-drop, which is unusable on the tablet this is operated
      from.
- [ ] Running totals per shipment: order count, item count, summed `est_weight_grams`,
      declared value. The weight estimate is what tells the packer whether another order
      fits before they tape the box.
- [ ] A visible warning when declared value exceeds ₱10,000 — spec §12, the de-minimis
      threshold applies **per shipment**, not per buyer: "Declared value ₱14,320 exceeds
      the ₱10,000 de-minimis. Duties likely apply." Informational, not a block.
- [ ] A printable per-shipment packing list — order code, customer, items, quantities.
      This is the piece of paper that goes in the box.
- [ ] Search unassigned orders by code or customer.

**Done when:**
- [ ] Assigning 20 orders to a box takes under a minute
- [ ] The de-minimis warning appears at the right threshold
- [ ] The packing list prints legibly on A4

---

## M5-04 · Tracking entry

**Depends on:** M5-03
**Branch:** `feature/m5-tracking-entry`

**Becomes:** mostly unchanged, with one improvement — the freight-cost-to-expense link
becomes a trigger.

> The old step read: *freight cost saved on the shipment also creates a `Freight`
> category `Expense` against the run… Editing the cost updates that expense rather than
> adding a duplicate.* That "rather than adding a duplicate" is a rule someone has to
> remember on every write path. As a trigger on `shipment.cost_php` it is upsert-shaped
> and cannot be forgotten — the duplicate-expense bug stops being possible.

**Requirements:**

- [ ] Per shipment: courier select, tracking number, weight, freight cost, dispatch
      date.
- [ ] After saving, render the built tracking URL as a clickable link **and open it once
      to check it resolves**. A typo'd number is the most common failure here and the
      cheapest to catch immediately.
- [ ] Freight cost flows into a `Freight` run expense with no second data-entry step,
      and editing it updates rather than duplicates.
- [ ] Bulk-create last-mile shipments: pick a courier, paste one tracking number per
      order code, one per line. Twenty orders is twenty numbers; a form per order is
      twenty page loads.
- [ ] **Validate every code before saving any of them.** Partial application of a paste
      is worse than rejecting the whole thing — which means the whole paste is one
      function call, one transaction.

**Done when:**
- [ ] Freight cost appears as a run expense without double entry, and editing it does
      not create a second expense
- [ ] A bulk paste of 20 rows with one bad order code saves nothing and names the bad row
- [ ] The generated tracking link resolves for every seeded courier

---

## M5-05 · Customer tracking view

**Depends on:** M5-04
**Branch:** `feature/m5-customer-tracking`

> **The column-exposure problem again, and this is its sharpest case.** A customer
> legitimately needs to read the shipment their order is on — to get the courier and
> tracking number. That same row carries `cost_php` (your freight margin) and
> `declared_value_php` (the whole box, i.e. what twenty other customers' goods are
> worth). A row-level policy granting read on `shipment` hands all of it over.
>
> The customer reads a view exposing courier, tracking number, status and dates. Never
> the `shipment` table.

**Requirements:**

- [ ] Timeline of the real stages: Ordered → Paid → Bought in Japan → Shipped from Japan
      → Arrived in PH → Out for delivery → Delivered, each with its date where known.
- [ ] Both tracking links, labelled by leg, opening in a new tab with
      `rel="noopener noreferrer"`.
- [ ] Estimated arrival from the run as a range, with an honest caveat that customs
      timing is outside your control.
- [ ] A `Held` shipment shows a clear explanation and a contact route — not a stalled
      timeline the customer has to guess about.
- [ ] **Nothing about the box's other customers is exposed**: no shipment id, no order
      count, no declared value, no freight cost.

**Done when:**
- [ ] `supabase.from('shipment').select('*')` as a customer returns zero rows
- [ ] The customer-facing view's returned keys contain no `cost_php` or
      `declared_value_php` — asserted on keys, so a later column addition cannot leak
- [ ] Both tracking links work from a phone
- [ ] A held shipment reads as informative, not broken

---

## M5-06 · Delivery confirmation

**Depends on:** M5-05
**Branch:** `feature/m5-delivery`

**Becomes:** a `mark_delivered` function plus an admin view for the chase list.

**Requirements:**

- [ ] Fulfilment/Admin sets `delivered_at` and moves the order to `Delivered`.
- [ ] Bulk mark-delivered from a list, since the courier reports in batches.
- [ ] When every order in a run is `Delivered` or `Cancelled`, **prompt** to complete the
      run. Prompt — do not auto-advance. The admin decides the run is finished.
- [ ] An admin list of orders shipped more than 14 days ago and not marked delivered.
      This is the "chase the courier" list, and it replaces the scheduled job the spec
      declines to build (§11).

**Done when:**
- [ ] The stale-shipment list correctly finds orders past 14 days
- [ ] Marking the last order delivered surfaces the completion prompt but does **not**
      change the run status by itself

---

## Milestone exit

- [ ] A run has gone Packed → Shipped → Landed → Distributing → Completed on staging
- [ ] Every tracking link resolves to a real courier page
- [ ] Freight cost appears exactly once in the run's expenses
- [ ] A customer can reach nothing about another customer's order, or about the box's
      economics, through any shipping query
