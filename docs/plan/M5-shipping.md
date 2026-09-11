# M5 — Shipping and tracking

**Goal:** Bought orders get packed into a box, the box flies, and each customer can
follow both legs from their order page.

**Scope note:** spec §11 — tracking is a **link**, not an API integration. J&T, LBC
and Flash gate their real APIs behind business accounts and return little beyond the
public page. Resist building three integrations here.

**Read first:** spec §4.6, §8.4, §12 (customs).
**Estimate:** 4–5 days · **6 tasks**

---

## M5-01 · Couriers

**Depends on:** M1-01
**Branch:** `feature/m5-couriers`

**Files:**
- Create: `Features/Shipping/CourierEndpoints.cs`,
  `Data/Migrations/*_SeedCouriers.cs`

**Steps:**

- [ ] **1.** Seed the couriers actually used, with tracking templates. `{0}` is the
      tracking number:

| Name | Template | Leg |
|---|---|---|
| J&T Express PH | `https://www.jtexpress.ph/trajectoryQuery?waybillNo={0}` | last mile |
| LBC Express | `https://www.lbcexpress.com/track/?tracking_no={0}` | last mile |
| Flash Express PH | `https://www.flashexpress.ph/tracking/?se={0}` | last mile |
| Japan Post EMS | `https://trackings.post.japanpost.jp/services/srv/search/direct?reqCodeNo1={0}&searchKind=S002&locale=en` | international |
| Yamato | `https://track.kuronekoyamato.co.jp/english/tracking?number={0}` | international |

  **Verify every URL by pasting a real tracking number into it** before committing.
  A broken tracking link is worse than none — the customer thinks the parcel is lost.

- [ ] **2.** Admin CRUD so a new forwarder can be added without a deploy.

- [ ] **3.** Validate the template contains exactly one `{0}` on save. A template
      without it produces a link to the courier's homepage and a confused customer.

- [ ] **4.** `IsActive` for retiring a courier without breaking historical shipments.

- [ ] **5.** Commit.

**Done when:**
- [ ] Every seeded URL has been opened in a browser with a real number and reached a
      tracking page
- [ ] A template with no `{0}` is rejected on save

---

## M5-02 · Shipments API

**Depends on:** M5-01, M4-05
**Branch:** `feature/m5-shipments`

**Files:**
- Create: `Features/Shipping/ShipmentEndpoints.cs`, `ShipmentDtos.cs`
- Test: `tests/Pajapan.Api.Tests/ShippingTests.cs`

**Steps:**

- [ ] **1.** Endpoints, `Fulfilment | Admin`:

```
POST   /api/admin/shipments                    { runId, type, courierId }
GET    /api/admin/shipments?runId=
PUT    /api/admin/shipments/{id}               tracking, weight, cost, declared value, status
POST   /api/admin/shipments/{id}/orders        { orderIds[] }   assign
DELETE /api/admin/shipments/{id}/orders/{oid}  unassign
```

- [ ] **2.** Assignment rules, each returning a specific 409 message:
      - `International`: the order must be `Fulfilled` or `PartiallyFulfilled`.
        Assigning an unbought order means shipping an empty box.
      - `LastMile`: exactly one order, and it must already be on a landed
        international shipment.
      - An order already assigned to a shipment of that type → 409 naming the
        existing shipment.

- [ ] **3.** `DeclaredValuePhp` defaults to the sum of assigned orders'
      `ItemsTotalPhp`, and is editable. Spec §12: this is the customs figure, so it
      must be visible and deliberate, never a hidden default.

- [ ] **4.** Assigning orders sets `Order.InternationalShipmentId` or
      `LastMileShipmentId`. Setting the shipment to `Dispatched` moves every assigned
      order to `Shipped` / `OutForDelivery` in one transaction.

- [ ] **5.** Shipment status feeds the run: all international shipments `Dispatched`
      → the run may go `Shipped`.

- [ ] **6.** Tests: assigning an unbought order → 409; assigning two orders to a
      LastMile shipment → 409; dispatching updates every assigned order.

- [ ] **7.** Commit.

**Done when:**
- [ ] The three tests pass
- [ ] Declared value defaults to the real sum and is editable
- [ ] Dispatching a box with 12 orders moves all 12 in one transaction

---

## M5-03 · Packing UI

**Depends on:** M5-02
**Branch:** `feature/m5-packing`

**Files:**
- Create: `web/src/features/admin/shipping/PackingPage.tsx`, `ShipmentCard.tsx`,
  `UnassignedOrders.tsx`

**Steps:**

- [ ] **1.** Two panes: unassigned bought orders on the left, shipments on the right.
      Assign by checkbox and a button — not drag-and-drop, which is unusable on the
      tablet this will be operated from.

- [ ] **2.** Running totals per shipment: order count, item count, summed
      `EstWeightGrams`, declared value. The weight estimate is what tells the packer
      whether another order fits before they tape the box.

- [ ] **3.** A visible warning when declared value exceeds ₱10,000 — spec §12, the
      de-minimis threshold applies **per shipment**, not per buyer. Wording:
      "Declared value ₱14,320 exceeds the ₱10,000 de-minimis. Duties likely apply."
      Informational, not a block.

- [ ] **4.** A per-shipment packing list, printable, showing order code, customer,
      items and quantities. This is the piece of paper that goes in the box.

- [ ] **5.** Search unassigned orders by code or customer.

- [ ] **6.** Commit.

**Done when:**
- [ ] Assigning 20 orders to a box takes under a minute
- [ ] The de-minimis warning appears at the right threshold
- [ ] The packing list prints legibly on A4

---

## M5-04 · Tracking entry

**Depends on:** M5-03
**Branch:** `feature/m5-tracking-entry`

**Files:**
- Create: `web/src/features/admin/shipping/TrackingForm.tsx`

**Steps:**

- [ ] **1.** Per shipment: courier select, tracking number, weight, freight cost,
      dispatch date.

- [ ] **2.** After saving, render the built tracking URL as a clickable link **and
      open it once to check it resolves**. A typo'd number is the most common failure
      here and the cheapest to catch immediately.

- [ ] **3.** Freight cost saved on the shipment also creates a `Freight` category
      `Expense` against the run, so M6's profit figure includes it without a second
      data entry step. Editing the cost updates that expense rather than adding a
      duplicate.

- [ ] **4.** Bulk-create last-mile shipments: pick a courier, paste one tracking
      number per order code, one per line. Twenty orders is twenty numbers — a form
      per order is twenty page loads.

```
PJP-2609-0042  SPXPH0412334
PJP-2609-0043  SPXPH0412335
```

- [ ] **5.** Validate every code exists and is on a landed shipment before saving any
      of them. Partial application of a paste is worse than rejecting the whole thing.

- [ ] **6.** Commit.

**Done when:**
- [ ] Freight cost appears as a run expense without double entry, and editing it does
      not create a second expense
- [ ] Bulk paste of 20 rows with one bad order code saves nothing and names the bad row
- [ ] The generated tracking link resolves for every seeded courier

---

## M5-05 · Customer tracking view

**Depends on:** M5-04
**Branch:** `feature/m5-customer-tracking`

**Files:**
- Modify: `web/src/features/orders/OrderDetailPage.tsx`
- Create: `web/src/features/orders/TrackingTimeline.tsx`

**Steps:**

- [ ] **1.** A timeline of the real stages: Ordered → Paid → Bought in Japan →
      Shipped from Japan → Arrived in PH → Out for delivery → Delivered. Each with its
      date where known.

- [ ] **2.** Both tracking links, labelled by leg, opening in a new tab with
      `rel="noopener noreferrer"`.

- [ ] **3.** Estimated arrival from the run, shown as a range, with an honest caveat
      that customs timing is outside your control.

- [ ] **4.** A shipment marked `Held` shows a clear explanation and a contact route —
      not a stalled timeline the customer has to guess about.

- [ ] **5.** Nothing about the box's other customers is exposed: no shipment id, no
      order count, no declared value. Assert this in a test on the JSON.

- [ ] **6.** Commit.

**Done when:**
- [ ] The customer order response contains no other customer's data — verified against
      raw JSON
- [ ] Both tracking links work from a phone
- [ ] A held shipment reads as informative, not broken

---

## M5-06 · Delivery confirmation

**Depends on:** M5-05
**Branch:** `feature/m5-delivery`

**Steps:**

- [ ] **1.** `POST /api/admin/shipments/{id}/delivered` (`Fulfilment | Admin`) sets
      `DeliveredAt` and moves the order to `Delivered`.

- [ ] **2.** Bulk mark-delivered from a list, since the courier reports in batches.

- [ ] **3.** When every order in a run is `Delivered` or `Cancelled`, prompt to
      complete the run. Prompt — do not auto-advance. The admin should decide the run
      is finished.

- [ ] **4.** An admin list of orders shipped more than 14 days ago and not marked
      delivered. This is the "chase the courier" list, and it replaces the scheduled
      job the spec declines to build.

- [ ] **5.** Test: marking the last order delivered surfaces the completion prompt but
      does not change the run status by itself.

- [ ] **6.** Commit.

**Done when:**
- [ ] The stale-shipment list correctly finds orders past 14 days
- [ ] A run never advances to Completed without an explicit admin action

---

## Milestone exit

- [ ] A run has gone Packed → Shipped → Landed → Distributing → Completed on staging
- [ ] Every tracking link resolves to a real courier page
- [ ] Freight cost appears exactly once in the run's expenses
- [ ] No customer can see anything about another customer's order through the shipping
      endpoints
