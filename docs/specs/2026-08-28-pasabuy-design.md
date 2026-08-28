# Pajapan — Design Spec

**Status:** Draft, for review
**Date:** 2026-08-28
**Repo:** `pajapan` (greenfield, nothing built yet)
**Reviewer:** please read §14 first — it lists the specific things I want challenged.

---

## 1. What this is

A *pasabuy* (proxy-buying / personal shopping) web app. The team buys goods in
Japan on customers' behalf and ships them to the Philippines.

Physical process today:

1. One team member is in Japan. They walk Don Quijote and nearby stores,
   photograph items, note prices.
2. Those items get listed on a website.
3. Filipino customers order and pay.
4. The Japan member buys the ordered items on a shopping trip.
5. Everything is consolidated into a shipment, flown to PH, then handed to a
   local courier for last-mile delivery.

The app must cover all five steps, plus track sales, costs and profit.

**Team:** 3 people — 1 in Japan (buys), 2 in the Philippines (fulfilment,
finance). Roles must be distinct in the system.

**Volume assumption:** under ~100 orders/month. Every sizing decision in this
document assumes that. Several are explicitly wrong at 10x and are flagged as
such in §11.

---

## 2. Decisions already taken

These were settled before this spec was written. They are inputs, not open
questions.

| Decision | Choice | Consequence |
|---|---|---|
| Sales model | **Pre-order only** — nothing is held in stock | There is no inventory level. The catalog is a list of things that *can be bought*, not things *on hand*. |
| Custom requests | **Yes** — buyer can submit a link/photo of something not listed | Needs a quote/accept flow |
| Payment collection | **Manual proof-of-payment now** (GCash / BPI / Maya screenshot), online gateway later | No PCI scope, no merchant account. Schema must leave a seam for a gateway. |
| Payment timing | **Full payment before the buying trip** | Team never fronts its own cash. Makes the refund path mandatory, not optional. |
| Pricing | **Locked PHP price**; the team absorbs FX and store-price drift | Buyer never gets a surprise bill. Margin is discovered after the fact. |
| Shipping | **Consolidate into a batch**, one international leg, then a PH courier for last mile | Two shipment legs per order |
| Accounts | **Required** for buyers (Supabase Auth) | Buyers self-serve order status; less DM support load |
| Stack | React frontend, C# backend, Supabase Postgres via EF Core | As specified by the project owner |

---

## 3. The central modelling decision

**This is a trip-cycle system, not a shop.**

Because everything is pre-order, there is no stock level and no "add to
inventory" event. The spine of the domain is the **Run** — one buying cycle.

```
Run: Open ──▶ Closed ──▶ Buying ──▶ Packed ──▶ Shipped ──▶ Landed ──▶ Distributing ──▶ Completed
      │          │          │           │          │           │            │
      │          │          │           │          │           │            └─ per-order local courier
      │          │          │           │          │           └─ cleared, in PH
      │          │          │           │          └─ international leg in transit
      │          │          │           └─ boxed, weighed, declared
      │          │          └─ Japan member is in the store, marking got / not-got
      │          └─ cutoff passed; shopping list generated; no new orders
      └─ customers place and pay for orders
```

Every feature hangs off this. Modelling it as a conventional e-commerce store
with stock quantities would fight the real process on every screen.

### 3.1 The two hard cases, made first-class

Both of these are guaranteed to happen on every single run. They are in the core
model, not bolted on later.

**Item unavailable at the store.** The Japan member is standing in Don Quijote
and the item is gone. Because payment is taken upfront, an unavailable item
means the business owes money back *immediately*. Therefore:

- Every order line carries its own status (`Bought` / `Unavailable` /
  `Substituted`), independent of the order.
- An order can be partially fulfilled.
- A refund record is a real entity with proof of payment out.

**Price drift.** The team absorbs it, so the buyer is unaffected — but the
business needs to see it. Therefore every order line stores **both**:

- `UnitPricePhpSnapshot` — what the customer was charged
- `ActualCostJpy` — what was actually paid at the till

The difference, converted, is the real per-product margin. This is the single
most valuable number the app produces: it tells you which products are quietly
losing money across runs.

---

## 4. Data model

14 tables. Several tables a conventional design would include are deliberately
absent — see §11.

Conventions:

- Primary keys are `uuid` (`gen_random_uuid()`).
- All money is `decimal(12,2)`. **Never `float`/`double`/`real`.**
- Every monetary column names its currency in the column name (`...Php`,
  `...Jpy`) — there is no ambiguous `Amount`.
- Timestamps are `timestamptz`, stored UTC. Display is Asia/Manila for
  customers, Asia/Tokyo for run cutoffs.
- Every table has `CreatedAt`; mutable tables also have `UpdatedAt`.

### 4.1 Catalog

**`Category`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| Name | text | "Snacks", "Cosmetics", "Toys" |
| Slug | text | unique |
| SortOrder | int | |

**`Product`** — a catalog entry: a thing that *can be bought again*, not a unit
in stock.

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| Name | text | |
| Slug | text | unique |
| Description | text | |
| CategoryId | uuid | FK |
| RefPriceJpy | decimal(12,2) | observed shelf price, for margin sanity checks |
| PricePhp | decimal(12,2) | **what the customer is charged** |
| EstWeightGrams | int | for freight estimation |
| SourceStore | text | "Don Quijote Shinjuku" — where to find it again |
| IsActive | bool | offered in the current run |
| IsCustom | bool | created from a custom request; hidden from public browse |
| CreatedByUserId | uuid | |

**`ProductPhoto`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| ProductId | uuid | FK, cascade delete |
| StoragePath | text | Supabase Storage object path, not a full URL |
| SortOrder | int | first photo is the thumbnail |

> Storing the path and not a URL means the bucket or CDN can move without a data
> migration.

### 4.2 The run

**`Run`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| Code | text | unique, human-readable: `2026-09A` |
| Name | text | "September Don Qui run" |
| Status | enum | Open, Closed, Buying, Packed, Shipped, Landed, Distributing, Completed, Cancelled |
| OrdersCloseAtUtc | timestamptz | the cutoff; **displayed in JST** |
| BuyingDate | date | when the Japan member shops |
| EstimatedArrival | date | shown to customers as a range |
| Notes | text | internal |

### 4.3 People

**`AppUser`** — maps a Supabase Auth user to an application role.

| Column | Type | Notes |
|---|---|---|
| Id | uuid | **= Supabase Auth `sub`**, not generated |
| Role | enum | Customer, JapanBuyer, Fulfilment, Admin |
| DisplayName | text | |
| Phone | text | |
| Email | text | mirrored from auth for search |
| IsBlocked | bool | |

> Role lives in a table rather than in the JWT's `app_metadata` so an admin can
> change someone's role from inside the app without touching Supabase's admin
> API, and without waiting for a token to expire. The API reads it per request;
> it is a single indexed lookup and can be cached later if it ever shows up in a
> profile.

**`Address`** — a customer's saved delivery addresses.

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| CustomerId | uuid | FK → AppUser |
| Label | text | "Home", "Office" |
| RecipientName | text | |
| Phone | text | |
| Line1, Line2 | text | |
| Barangay | text | |
| City | text | |
| Province | text | |
| PostalCode | text | |
| IsDefault | bool | |

### 4.4 Orders

**`Order`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| OrderCode | text | unique, human-readable: `PJP-2609-0042` |
| CustomerId | uuid | FK |
| RunId | uuid | FK |
| Status | enum | see §4.4.1 |
| ShipTo* | text × 9 | **snapshot** of the address fields at order time |
| ItemsTotalPhp | decimal(12,2) | |
| ShippingFeePhp | decimal(12,2) | |
| ServiceFeePhp | decimal(12,2) | |
| GrandTotalPhp | decimal(12,2) | |
| AmountPaidPhp | decimal(12,2) | cached sum of verified payments |
| AmountRefundedPhp | decimal(12,2) | cached sum of completed refunds |
| PlacedAt | timestamptz | |
| ConfirmedAt | timestamptz | when payment was verified |
| InternationalShipmentId | uuid | FK, nullable |
| LastMileShipmentId | uuid | FK, nullable |
| CustomerNote | text | |
| InternalNote | text | staff only |
| IdempotencyKey | text | unique, nullable — see §8.1 |

> **The shipping address is snapshotted onto the order**, not referenced by FK.
> If a customer edits their saved address after ordering, an already-shipped
> order must not silently change where it says it went.

> `AmountPaidPhp` and `AmountRefundedPhp` are caches of a sum over `Payment` /
> `Refund`. The payment rows are the source of truth. A reconciliation check
> that recomputes them belongs in the test suite and in the finance screen.

**`OrderItem`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| OrderId | uuid | FK |
| ProductId | uuid | FK, **nullable** (custom one-offs) |
| NameSnapshot | text | product name at order time |
| UnitPricePhpSnapshot | decimal(12,2) | **charged price, frozen** |
| Qty | int | |
| QtyFulfilled | int | default 0 |
| LineStatus | enum | Pending, Bought, PartiallyBought, Unavailable, Substituted |
| ActualCostJpy | decimal(12,2) | nullable; filled in at the till |
| SubstituteNote | text | what was bought instead |
| RefundedPhp | decimal(12,2) | default 0 |

> Snapshotting name and price is what makes historical orders and past-run
> reporting stable when a product is renamed or repriced.

#### 4.4.1 Order status

`Draft → AwaitingPayment → PaymentSubmitted → Confirmed → Shopping →
Fulfilled | PartiallyFulfilled → Packed → Shipped → Landed → OutForDelivery →
Delivered`, plus `Cancelled`.

> Reviewer: this is 12 states and I suspect 3–4 are derivable rather than
> stored (e.g. `Shopping` and `Packed` are arguably just the parent Run's
> status). Flagged in §14.

**`CustomRequest`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| CustomerId | uuid | FK |
| RunId | uuid | FK, nullable — which run it's targeted at |
| Title | text | |
| Description | text | |
| ReferenceUrl | text | link the buyer pasted |
| PhotoPath | text | image the buyer uploaded |
| BudgetPhp | decimal(12,2) | what they're willing to pay |
| Status | enum | Submitted, Quoted, Accepted, Declined, Expired |
| QuotedPricePhp | decimal(12,2) | staff's answer |
| QuotedNote | text | |
| ProductId | uuid | nullable — set when accepted |
| RespondedAt | timestamptz | |

**Flow:** buyer submits → staff quotes a PHP price → buyer accepts → staff
creates a `Product` with `IsCustom = true` → buyer adds it to cart and pays
through the normal path.

> This deliberately reuses the entire existing cart/order/payment pipeline
> rather than building a parallel "custom order" flow. The only new code is the
> request and the quote.

### 4.5 Money in

**`Payment`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| OrderId | uuid | FK |
| Method | enum | GCash, Maya, BPI, BDO, Cash, Gateway |
| AmountPhp | decimal(12,2) | |
| ReferenceNo | text | the GCash/bank reference the buyer types in |
| ProofPath | text | uploaded screenshot |
| Status | enum | Submitted, Verified, Rejected |
| SubmittedAt | timestamptz | |
| VerifiedByUserId | uuid | nullable |
| VerifiedAt | timestamptz | nullable |
| RejectionReason | text | shown to the buyer |
| **Provider** | text | **nullable — the gateway seam** |
| **ProviderRef** | text | **nullable — gateway transaction id** |

> `Provider` / `ProviderRef` are null for every manual payment. When a gateway
> is added later, gateway payments are simply rows with those fields populated
> and `Status = Verified` set by a webhook. **Orders and totals do not change
> shape.** This is the entire cost of deferring the gateway.

> `ReferenceNo` should have a unique index (filtered to non-null) — the same
> GCash reference being submitted against two orders is either a mistake or
> fraud, and the database is the cheapest place to catch it.

**`Refund`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| OrderId | uuid | FK |
| OrderItemId | uuid | FK, nullable — which line caused it |
| AmountPhp | decimal(12,2) | |
| Reason | enum | ItemUnavailable, OrderCancelled, Overpayment, Other |
| ReasonNote | text | |
| Method | enum | as Payment |
| ReferenceNo | text | proof the money went out |
| ProofPath | text | |
| Status | enum | Pending, Completed, Failed |
| CreatedByUserId | uuid | |

### 4.6 Shipping

**`Courier`**

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| Name | text | "J&T Express", "LBC", "Flash Express", "EMS" |
| TrackingUrlTemplate | text | e.g. `https://www.jtexpress.ph/trajectoryQuery?waybillNo={0}` |
| IsActive | bool | |

**`Shipment`** — one table covers both legs.

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| RunId | uuid | FK |
| Type | enum | International, LastMile |
| CourierId | uuid | FK |
| TrackingNumber | text | |
| WeightGrams | int | |
| CostPhp | decimal(12,2) | freight paid |
| DeclaredValuePhp | decimal(12,2) | for customs |
| Status | enum | Preparing, Dispatched, InTransit, Delivered, Held, Lost |
| DispatchedAt | timestamptz | |
| DeliveredAt | timestamptz | |
| Notes | text | |

Orders link to shipments by two FKs on `Order` (`InternationalShipmentId`,
`LastMileShipmentId`). An International shipment therefore has many orders; a
LastMile shipment has exactly one.

**Tracking is a link, not an integration.** The app renders
`string.Format(courier.TrackingUrlTemplate, shipment.TrackingNumber)`. J&T, LBC
and Flash all gate their real APIs behind business accounts and return little
beyond what the public page shows. See §11.

### 4.7 Money out

**`Expense`** — every cost that isn't the goods themselves.

| Column | Type | Notes |
|---|---|---|
| Id | uuid | PK |
| RunId | uuid | FK, nullable (general business costs) |
| Category | enum | Freight, Customs, Transport, Packaging, PlatformFees, Supplies, Other |
| Description | text | |
| Amount | decimal(12,2) | as incurred |
| Currency | char(3) | JPY or PHP |
| FxRateToPhp | decimal(12,6) | rate used, recorded at entry time |
| AmountPhp | decimal(12,2) | stored, = Amount × FxRateToPhp |
| IncurredOn | date | |
| ReceiptPath | text | |
| CreatedByUserId | uuid | |

> The FX rate is **stored per expense**, not looked up at report time. A report
> run six months later must reproduce the same peso figure it showed on the day.

---

## 5. Architecture

```
┌────────────────────┐        HTTPS + JWT        ┌──────────────────────────┐
│  React (Vite, TS)  │ ────────────────────────▶ │  ASP.NET Core 10         │
│  SPA, PWA          │ ◀──────────────────────── │  Minimal APIs            │
└────────┬───────────┘                           └───────┬──────────┬───────┘
         │                                               │ EF Core  │
         │ login only                                    ▼          │
         │                                    ┌────────────────────┐│
         └───────────────────────────────────▶│ Supabase Postgres  ││
                    Supabase Auth             └────────────────────┘│
                    (returns JWT)                                   │
                                                 signed upload URLs │
                                              ┌─────────────────────▼──┐
         browser PUTs bytes directly ────────▶│  Supabase Storage      │
                                              └────────────────────────┘
```

### 5.1 The trust-boundary decision

**The React app talks only to the C# API. It never queries Supabase Postgres
directly with the JS client.**

Consequences, stated plainly because this is the decision most worth
challenging:

- **One place enforces authorization** — the API. There is no second set of RLS
  policies to keep in sync with it.
- **Therefore: no Row Level Security initially.** This is safe *only* because
  nothing but the API holds a database credential. **If the browser is ever
  given direct Supabase database access, RLS becomes mandatory that same day.**
  This is written here so it cannot be forgotten.
- Photo uploads still go straight to Storage: the API issues a short-lived
  signed upload URL, the browser PUTs the bytes to it. The server never proxies
  file bytes, but the server decides who may upload and where.
- The Supabase service key exists only in the API's environment. It is never in
  frontend code, never in a `VITE_*` variable, never in the repo.

### 5.2 Stack

| Layer | Choice | Rationale / rejected alternative |
|---|---|---|
| Frontend | React 19 + Vite + TypeScript | Not Next.js: a login-walled store gains nothing from SSR and it complicates hosting |
| Routing | React Router | |
| Server state | TanStack Query | Handles caching, refetch, optimistic updates. No Redux needed. |
| Client state | React state + a small cart store | Cart persists to `localStorage` |
| Forms | React Hook Form + Zod | Zod schemas double as the shared request contract |
| Styling | Tailwind CSS | |
| Components | shadcn/ui | Copied into the repo, so no library lock-in and no upgrade treadmill |
| Backend | .NET 10, **Minimal APIs** | Not MVC controllers: far less ceremony for what is mostly CRUD |
| ORM | EF Core 10 + Npgsql | As specified |
| Migrations | EF Core migrations | Applied by CI, never by hand against production |
| Auth | Supabase Auth; API validates JWT against Supabase JWKS | One auth system serves customers *and* staff |
| Images | Supabase Storage + signed upload URLs | |
| Validation | FluentValidation on the API, Zod on the client | Client validation is UX; **server validation is the actual gate** |
| Logging | Serilog → console (structured) | Whatever the host aggregates |
| Errors | RFC 7807 ProblemDetails | Uniform error shape for the client |
| Tests | xUnit + Testcontainers (Postgres) for the API; Vitest for the frontend | Real Postgres in tests, not SQLite or InMemory — the model uses Postgres types and constraints |

### 5.3 Hosting

| Piece | Where | Approx cost |
|---|---|---|
| React SPA | Vercel or Netlify, static | free |
| C# API | Fly.io or Railway (single small instance) | ~$5–10/mo |
| Postgres + Storage + Auth | Supabase | free tier → $25/mo Pro |

Deployment is push-to-deploy from `main` via GitHub Actions, with a `staging`
environment that mirrors production and gets the migration first.

---

## 6. Roles and permissions

Four roles, enforced **server-side per endpoint**. The React app hides controls a
role cannot use, but hiding is cosmetic — the API is the real gate. A reviewer
should assume any hidden button can be reached by hand.

| Role | Can see and do |
|---|---|
| **Customer** | Browse the catalog, place orders, submit payment proof, submit custom requests, view own order history and tracking. Nothing else, and nothing belonging to another customer. |
| **JapanBuyer** | The shopping list for the current run; mark lines Bought / Unavailable / Substituted; enter actual JPY cost; upload receipts; create and edit products and photos; record JPY expenses. **No access to customer payment details or finance reports.** |
| **Fulfilment** | Verify or reject payments; issue refunds; pack orders into shipments; enter tracking numbers; mark delivered; view customer contact and address. |
| **Admin** | Everything above, plus pricing, run creation, user roles, and all finance reporting. |

### 6.1 Authorization rules that must be tested, not assumed

These are the rules a reviewer should specifically try to break:

- A customer requesting `GET /api/orders/{id}` for someone else's order gets
  `404`, not `403` — a 403 confirms the order exists.
- Order identifiers in URLs are UUIDs, never sequential integers. `OrderCode` is
  displayed but is not the lookup key on customer endpoints.
- `CustomerId` is taken **from the JWT only**. It is never accepted from the
  request body, a query string, or a header. This is the single most likely
  place for a scoping bug.
- `JapanBuyer` hitting any finance or payment endpoint gets `403`.
- Payment verification records `VerifiedByUserId` from the JWT; it cannot be
  supplied by the caller.
- Price is **never** read from the client. A cart request sends product ids and
  quantities; the server looks up the price. Nothing about a submitted order's
  money comes from the browser.

---

## 7. API surface

Representative, not exhaustive. `/api` prefix, JWT bearer auth on everything
except the public catalog.

**Public / customer**

```
GET    /api/catalog                       list active products (paged, filter by category)
GET    /api/catalog/{slug}                product detail
GET    /api/runs/current                  open run + cutoff time
POST   /api/orders                        place order  { runId, addressId, items:[{productId, qty}] }
GET    /api/orders                        own orders
GET    /api/orders/{id}                   own order detail + tracking links
POST   /api/orders/{id}/payments          submit proof { method, amountPhp, referenceNo, proofPath }
POST   /api/uploads/sign                  get a signed upload URL { purpose, contentType }
GET    /api/addresses                     CRUD own addresses
POST   /api/custom-requests               submit a request
GET    /api/custom-requests               own requests + quotes
POST   /api/custom-requests/{id}/accept   accept a quote
```

**JapanBuyer**

```
GET    /api/buying/list?runId=            the shopping list: products × total qty across all orders
POST   /api/buying/lines/{orderItemId}    { status, qtyFulfilled, actualCostJpy, substituteNote }
POST   /api/products                      create catalog entry
PUT    /api/products/{id}
POST   /api/expenses                      record a JPY cost
```

**Fulfilment**

```
GET    /api/admin/payments?status=Submitted    verification queue
POST   /api/admin/payments/{id}/verify
POST   /api/admin/payments/{id}/reject         { reason }
POST   /api/admin/refunds                      { orderId, orderItemId?, amountPhp, reason }
POST   /api/admin/shipments                    create a box
POST   /api/admin/shipments/{id}/orders        assign orders to it
PUT    /api/admin/shipments/{id}               tracking, weight, cost, status
```

**Admin**

```
POST   /api/admin/runs                    create a run
POST   /api/admin/runs/{id}/status        advance the run state
GET    /api/admin/reports/run/{id}        revenue, COGS, expenses, margin
GET    /api/admin/reports/products        margin by product across runs
GET    /api/admin/reports/pnl?from=&to=
PUT    /api/admin/users/{id}/role
```

### 7.1 The shopping list

The single most-used screen for the Japan member, and it needs **no table of its
own**:

```sql
SELECT p.Id, p.Name, p.SourceStore, p.RefPriceJpy, SUM(oi.Qty) AS TotalQty
FROM   OrderItem oi
JOIN   "Order" o     ON o.Id = oi.OrderId
LEFT   JOIN Product p ON p.Id = oi.ProductId
WHERE  o.RunId = @runId
  AND  o.Status = 'Confirmed'
GROUP  BY p.Id, p.Name, p.SourceStore, p.RefPriceJpy
ORDER  BY p.SourceStore, p.Name;
```

Grouped by store so the shopping route is walkable. Marking a product bought
updates every order line for that product in one call.

---

## 8. Key flows

### 8.1 Order → confirmed

```
Customer adds to cart (localStorage)
  → POST /api/orders   ← server recomputes every price from the DB
  → Order = AwaitingPayment, shows payment instructions + exact PHP amount
  → Customer pays via GCash, uploads screenshot
  → POST /api/orders/{id}/payments → Payment = Submitted, Order = PaymentSubmitted
  → Fulfilment sees it in the verification queue, checks the GCash app, verifies
  → Payment = Verified; Order.AmountPaidPhp recomputed
  → if AmountPaidPhp >= GrandTotalPhp → Order = Confirmed, ConfirmedAt set
  → Confirmed orders, and only Confirmed orders, enter the shopping list
```

**Idempotency:** `POST /api/orders` accepts an `Idempotency-Key` header. Double
submission — a double-tap on a phone, a retried request on flaky mobile data —
must produce **one** order, not two. There is no automatic retry on any write
path.

### 8.2 Run cutoff → buying

```
Run.OrdersCloseAtUtc passes → Admin sets Run = Closed
  → Unpaid orders are cancelled or rolled to the next run (manual decision)
  → Shopping list generates from Confirmed orders
  → Japan member works the list in-store, marking each line:
       Bought        → ActualCostJpy recorded
       Unavailable   → triggers a refund task for Fulfilment
       Substituted   → note + actual cost, buyer notified
  → Run = Buying → Packed
```

### 8.3 Unavailable item → refund

The path that exists *because* money is taken upfront:

```
Line marked Unavailable
  → Order.Status → PartiallyFulfilled
  → a Refund row is created as Pending for qty × UnitPricePhpSnapshot
  → Fulfilment sends the money back, records reference + proof
  → Refund = Completed; Order.AmountRefundedPhp recomputed
  → customer is notified, and can see it in their order
```

> Refunds are **never** automatic. The money moves by a human hand and the row
> records who and when. Nothing in this app moves money on its own.

### 8.4 Shipping

```
Fulfilment creates Shipment(Type=International)
  → assigns Confirmed+Bought orders to it, enters weight, freight cost, declared value
  → enters courier + tracking number → Run = Shipped
  → customers see the international tracking link
  → arrival → Run = Landed
  → per order: Shipment(Type=LastMile) with local courier + tracking
  → Delivered
```

---

## 9. Reporting

All computed by query. No aggregate tables, no scheduled rollup jobs — at this
volume a `GROUP BY` over a few thousand rows is instant.

**Per run**

```
Revenue   = Σ verified payments − Σ completed refunds
COGS      = Σ (OrderItem.ActualCostJpy × run FX rate)
Expenses  = Σ Expense.AmountPhp for the run
Profit    = Revenue − COGS − Expenses
```

**Per product, across runs** — the one that changes buying decisions:

```
sold qty | revenue | actual cost | margin ₱ | margin % | times unavailable
```

`times unavailable` is worth as much as the margin column: a product that is
frequently out of stock generates refunds, apologies and support work, and
should probably be delisted regardless of its margin.

**Freight allocation.** Computed at report time, apportioned across a shipment's
orders by order value. Not stored — see §11.

---

## 10. Correctness rules

Non-negotiable. These are the ones that cause silent, expensive, hard-to-detect
wrongness.

1. **Money is `decimal`.** Never `float`, `double` or `real`, in C#, in
   Postgres, or in TypeScript arithmetic. Format for display only at the edge.
2. **Currency is explicit** on every amount. No bare `Amount` column anywhere.
3. **FX rates are recorded at the moment of use**, never looked up at report
   time. Historical reports must be reproducible.
4. **Prices come from the server.** The client sends product ids and quantities.
   Any price arriving in a request body is ignored.
5. **Snapshots on write.** Order lines snapshot name and price; orders snapshot
   the shipping address. Editing a product must never alter a past order.
6. **Timestamps are UTC in the database.** Timezone conversion happens at
   render. Run cutoffs are authored and displayed in JST because that is where
   the shopping happens.
7. **Writes are idempotent where the user can retry them.** Order placement and
   payment submission both take an `Idempotency-Key`.
8. **No silent `catch`.** A failure surfaces as an error state in the UI. A
   screen that cannot load its data says so — it never renders zeros, an empty
   list, or an all-clear. A dashboard showing ₱0 profit because the API is down
   is worse than a dashboard showing an error.
9. **Deletes are soft** for anything money touches (orders, payments, refunds,
   expenses). Hard delete is available only on draft catalog entries.

---

## 11. Deliberately not built

Each of these is a real thing a bigger system would have. Each is omitted on
purpose, with the trigger for adding it. **These are the cheapest items to argue
about now and the most expensive to discover later, so they are listed
explicitly rather than left implicit.**

| Omitted | Instead | Add it when |
|---|---|---|
| **`RunListing` table** (per-run price and per-run quantity cap) | `Product.IsActive` + price snapshot on the order line | You want different prices in different runs, or "only 10 of these available" |
| **Shopping-list table** | A `GROUP BY` query (§7.1) | Never, probably |
| **Freight allocation table** | Apportioned by order value at report time | You start billing shipping to customers separately per parcel |
| **Store credit ledger** | Straight refunds | Refunds get frequent enough that keeping the money in is worth the code |
| **Line-level packing** (`ShipmentItem`) | One FK on `Order` — an order rides in exactly one box | An order genuinely has to split across two boxes; until then, split the order |
| **Courier API integration** | Courier + tracking number + a URL template | Manual tracking checks become a real time cost. J&T/LBC/Flash gate their APIs behind business accounts and return little more than the public page. |
| **Payment gateway** | Manual proof-of-payment | Volume justifies the fees, or DTI/BIR registration is done. The `Provider`/`ProviderRef` seam is already in `Payment`. |
| **Row Level Security** | API-only database access (§5.1) | **Immediately**, if the browser is ever given direct Supabase DB access |
| **Full audit log** | `CreatedByUserId` / `VerifiedByUserId` on the tables that matter | More than ~5 staff, or a dispute you cannot reconstruct |
| **Multi-currency display** | PHP for customers, JPY only in admin cost entry | Never, at this scale |
| **Search engine** (Meilisearch, pg full-text) | Postgres `ILIKE` + a trigram index | The catalog passes a few thousand products |
| **Background job runner** (Hangfire, Quartz) | Everything is request-driven; staff push the buttons | You want scheduled cutoff closing or automated notification batches |
| **Email/SMS notifications** | In-app status the customer can check | See §14 — this may be wrong; flagged for the reviewer |

---

## 12. Risks outside the code

Flagged because they are expensive surprises, not because the app must solve
them. **Not legal or accounting advice — items to check with the appropriate
professional.**

1. **Customs classification.** Consolidating multiple paying customers' goods
   into one box is commercial importation. Balikbayan boxes are for a returning
   resident's own personal effects and are not the right vehicle for this;
   misdeclaration is how shipments get held. Realistically this needs a freight
   forwarder handling informal entry. The de-minimis threshold (₱10,000) applies
   **per shipment**, not per buyer — which matters a great deal when one box
   holds twenty customers' orders. Schema impact is small (`DeclaredValuePhp` on
   the shipment, duties as a run `Expense`); business impact is not. **Worth one
   conversation with a forwarder before the first run.**
2. **Taking full payment upfront for goods not yet purchased** raises the stakes
   on DTI/BIR registration and on having a written, published refund policy —
   especially given that unavailable items are a certainty, not a risk. The app
   implements the refund mechanics; the policy wording is a business decision.
3. **Photographing products in-store and reselling** — some retailers object to
   in-store photography. Not a legal blocker, but worth knowing before a staff
   member is asked to stop.
4. **Prohibited items.** Certain cosmetics, food, supplements, batteries and
   aerosols are restricted into PH. A `Category`-level "restricted" flag would
   be a cheap addition if this bites; not in scope now.

---

## 13. Milestones

Ordered so that each milestone ends with something that demonstrably works, and
so that a real trip could be run after M5. A full task breakdown with per-task
instructions is a separate document.

| # | Milestone | Ends when | Est. |
|---|---|---|---|
| 0 | **Foundations** | Repo, CI, EF migrations, deployed hello-world on real infra, login works end to end | 3–4d |
| 1 | **Catalog + admin entry** | A product with photos can be added from a phone, in Japan, over mobile data | 4–5d |
| 2 | **Storefront + cart + orders** | A customer can browse and place an order; custom requests work | 5–6d |
| 3 | **Payments** | Buyer uploads GCash proof, staff verifies, order confirms | 3–4d |
| 4 | **Runs + procurement** | Cutoff closes, shopping list generates, bought/unavailable marking works, refunds fire | 5–6d |
| 5 | **Shipping + tracking** | Orders packed into a box, tracking on both legs, customer sees it | 4–5d |
| 6 | **Finance** | Per-run and per-product P&L, expense entry, margin by product | 4–5d |
| 7 | **Hardening + launch** | PWA install, mobile pass at 390px, a11y, backups verified, dry run on real data | 4–5d |

Custom requests land in M2. The payment gateway is explicitly out of scope for
all eight milestones.

---

## 14. What I want the reviewer to challenge

Ranked by how expensive it is to get wrong. Please push hardest at the top.

1. **§3 — is the Run the right spine?** Everything else is downstream of this.
   If a run should actually be able to contain sub-trips, or if orders should be
   able to move between runs freely, the model needs to know now.
2. **§5.1 — no RLS, API-only database access.** This is a real security
   decision. Is single-boundary-with-no-RLS the right call, or is
   defence-in-depth worth the double maintenance here?
3. **§4.4 — one box per order** (`Order.InternationalShipmentId` as a plain FK).
   How often will an order actually need to split across two boxes? If the
   answer is "most runs", this is wrong and `ShipmentItem` should exist from day
   one.
4. **§4.4.1 — 12 order states.** I think 3–4 are derivable from the parent Run's
   status rather than needing to be stored. Which ones would you cut?
5. **§11 — no `RunListing`.** Per-run quantity caps are the one omission I'm
   least sure about. "Only 10 of these" seems likely to be wanted on a real run.
6. **§11 — no notifications.** The plan is that customers check the app. Is that
   realistic in the PH market, or does this need email/SMS/Messenger from day
   one? This is the omission most likely to be wrong.
7. **§4.4 — cached `AmountPaidPhp` on `Order`.** Denormalised sum. Worth it, or
   should it always be computed?
8. **§5.2 — Minimal APIs over controllers**, and **shadcn/ui copied in** rather
   than a component library. Both are reversible; both are worth a second
   opinion.
9. **Anything in §10 that you would add.** That list is the one where an
   omission is silent.

---

## 15. Open questions for the project owner

Not blocking the build, but each changes some detail:

- How is the shipping fee decided — flat per order, by weight, by order value?
  Currently modelled as a flat `ShippingFeePhp` set by staff at order time.
- Is there a service fee / markup separate from the item price? There is a
  column for it (`ServiceFeePhp`) but no rule behind it yet.
- Can a customer order across two runs at once, or is it one open run at a time?
  Currently: one open run.
- What happens to an unpaid order when the cutoff passes — cancel, or roll to
  the next run? Currently a manual decision by staff.
- Minimum order value, or a maximum per customer per run?
