# M2 — Storefront, cart and orders

**Goal:** A customer can browse the catalog, place an order against the open run, and
see it in their order history. Custom requests work end to end.

**The task that matters:** M2-06. Everything else here is screens; M2-06 is where
money is decided, and it is the one to review hardest.

**Read first:** spec §4.4 (orders), §8.1 (order flow), §6.1 (scoping rules).
**Estimate:** 5–6 days · **9 tasks**

---

## M2-01 · Public catalog API

**Depends on:** M1-03
**Branch:** `feature/m2-catalog-api`

**Files:**
- Create: `Features/Catalog/PublicCatalogEndpoints.cs`

**Steps:**

- [ ] **1.** Endpoints, **anonymous**:

```
GET /api/catalog?categoryId=&q=&page=1&pageSize=24    active products only
GET /api/catalog/{slug}                                one product
GET /api/runs/current                                  the open run, or 204
```

- [ ] **2.** The public DTO omits `RefPriceJpy`, `SourceStore`, `IsCustom` and every
      audit field. **Do not reuse the admin DTO.** Your cost price and your supplier
      are not customer-facing, and a shared DTO leaks them the first time someone adds
      a field.

- [ ] **3.** `IsCustom = true` products are excluded from browse and from search. They
      are reachable by slug only — that is how the buyer who requested one gets to it.

- [ ] **4.** `GET /api/runs/current` returns the single `Open` run with
      `ordersCloseAtUtc`, or `204 No Content` when none is open. `204` is meaningful:
      the storefront renders a "next run announced soon" state, not an error.

- [ ] **5.** Cache `GET /api/catalog` for 60 seconds
      (`Cache-Control: public, max-age=60`). The catalog changes a few times a day.

- [ ] **6.** Test: an admin-only field never appears in a public response — assert on
      the raw JSON, not on the DTO type, so adding a property to the entity fails the
      test.

- [ ] **7.** Commit.

**Done when:**
- [ ] `curl /api/catalog | grep -iE "refPriceJpy|sourceStore|isCustom"` is empty
- [ ] With no open run, `/api/runs/current` returns 204 and the storefront renders the
      "no open run" state

---

## M2-02 · Catalog browse UI

**Depends on:** M2-01
**Branch:** `feature/m2-browse`

**Files:**
- Create: `web/src/features/catalog/CatalogPage.tsx`, `ProductCard.tsx`,
  `CategoryFilter.tsx`, `RunBanner.tsx`

**Steps:**

- [ ] **1.** Responsive grid: 2 columns at 390 px, 3 at 768, 4 at 1280.

- [ ] **2.** `ProductCard`: photo (lazy, `aspect-ratio` box to prevent layout shift),
      name, `formatPhp(pricePhp)`, add-to-cart button.

- [ ] **3.** `RunBanner`, persistent at the top: run name and a live countdown to
      `ordersCloseAtUtc`, rendered in **Asia/Manila** for customers. Under 24 hours it
      turns urgent. With no open run it says so and add-to-cart is disabled everywhere.

- [ ] **4.** Infinite scroll with `useInfiniteQuery`. Keep a visible "Load more" button
      as well — infinite scroll alone is unreachable by keyboard.

- [ ] **5.** Use `DataState` from M1-05 for loading, error and empty.

- [ ] **6.** Commit.

**Done when:**
- [ ] Countdown shows Manila time and is correct against a JST cutoff — verify by
      changing the machine timezone
- [ ] With no open run, no add-to-cart button anywhere is clickable
- [ ] Lighthouse CLS under 0.1 on the grid

---

## M2-03 · Product detail

**Depends on:** M2-02
**Branch:** `feature/m2-product-detail`

**Files:**
- Create: `web/src/features/catalog/ProductDetailPage.tsx`, `PhotoGallery.tsx`

**Steps:**

- [ ] **1.** Route `/p/:slug`. Gallery with thumbnails; swipe on touch via native
      CSS scroll-snap — no carousel library.
- [ ] **2.** Name, price, description, category, quantity stepper, add to cart.
- [ ] **3.** A prominent pre-order notice: this is bought on the run closing
      `<date>`, arriving approximately `<estimatedArrival>`, and **if unavailable in
      store you are refunded**. Setting this expectation on the product page is what
      stops the M4 refund from becoming a support argument.
- [ ] **4.** 404 page for an unknown slug; `<title>` and OpenGraph tags per product.
- [ ] **5.** Commit.

**Done when:**
- [ ] The unavailable-and-refunded notice is visible without scrolling on a 390 px
      screen
- [ ] An unknown slug renders a 404 page, not a crash

---

## M2-04 · Cart

**Depends on:** M2-03
**Branch:** `feature/m2-cart`

**Files:**
- Create: `web/src/features/cart/useCart.ts`, `CartPage.tsx`, `CartSheet.tsx`
- Test: `web/src/features/cart/useCart.test.ts`

**Steps:**

- [ ] **1.** Cart in `localStorage`, keyed by run id. Store **only**
      `{ productId, qty }` — never a price. A price in the cart is a price the client
      could be trusted with, and it must not be (Global Constraint 4).

- [ ] **2.** Prices for display are fetched fresh from the catalog on cart render, so
      a repriced product shows its current price before checkout.

- [ ] **3.** Changing run clears the cart, with a confirmation dialog.

- [ ] **4.** If a cart item is no longer active, show it struck through with "no longer
      available", and block checkout until it is removed.

- [ ] **5.** Totals computed with `toCents` from M0-05 — bigint arithmetic, never
      float. Test: 3 × `"333.33"` = `"999.99"`, not `999.9899999999999`.

- [ ] **6.** Commit.

**Done when:**
- [ ] `localStorage` contains no price — inspect it directly
- [ ] The 3 × 333.33 test passes
- [ ] Repricing a product in admin changes the cart total on reload

---

## M2-05 · Addresses

**Depends on:** M1-01, M0-06
**Branch:** `feature/m2-addresses`

**Files:**
- Create: `Features/Addresses/AddressEndpoints.cs`,
  `web/src/features/account/AddressBook.tsx`, `AddressForm.tsx`

**Steps:**

- [ ] **1.** CRUD at `/api/addresses`, scoped to the caller. **`CustomerId` comes from
      `CurrentUser.Id`**, never from the body (Global Constraint 10).

- [ ] **2.** Fetching another user's address id returns **404, not 403**
      (Global Constraint 11).

- [ ] **3.** PH address fields: recipient, phone, line1, line2, barangay, city,
      province, postcode. Province is a `<select>` from a static list of the 82
      provinces — free text produces unusable delivery data.

- [ ] **4.** Phone validated as PH mobile: `^(09|\+639)\d{9}$`. Normalise to `+639…`
      on save — the courier will need it in one format.

- [ ] **5.** Setting a default clears the previous default in the same transaction.

- [ ] **6.** Test: customer A requesting customer B's address id gets 404.

- [ ] **7.** Commit.

**Done when:**
- [ ] The cross-customer test passes and returns 404 (not 403)
- [ ] `09171234567` and `+639171234567` both save as `+639171234567`

---

## M2-06 · Place order

**Depends on:** M2-04, M2-05
**Branch:** `feature/m2-place-order`

> **The highest-risk task in the project.** Every peso the business earns passes
> through this endpoint. Review it against spec §8.1 and Global Constraints 4, 5 and 8
> line by line.

**Files:**
- Create: `Features/Orders/PlaceOrderEndpoint.cs`, `OrderCodeGenerator.cs`,
  `Features/Orders/OrderDtos.cs`
- Test: `tests/Pajapan.Api.Tests/PlaceOrderTests.cs`

**Interfaces produced:**
`POST /api/orders` ← `{ runId, addressId, items: [{ productId, qty }], customerNote? }`
plus an `Idempotency-Key` header → `OrderDto`.

**Steps:**

- [ ] **1.** Write the tests first. These eight are the specification:

```csharp
[Fact] Client_supplied_price_is_ignored();          // body carries pricePhp: "1.00"
[Fact] Same_idempotency_key_returns_the_same_order();// two calls, one order row
[Fact] Order_against_a_closed_run_is_409();
[Fact] Order_containing_an_inactive_product_is_409();
[Fact] Another_customers_address_is_404();
[Fact] Totals_equal_the_sum_of_line_snapshots();
[Fact] Zero_or_negative_qty_is_400();
[Fact] Address_is_snapshotted_not_referenced();      // edit address after; order unchanged
```

- [ ] **2.** Run them. All eight fail. Confirm each fails for the right reason — a
      test passing before the code exists is a broken test.

- [ ] **3.** Implement. The comments mark the four rules that are easy to get
      plausibly wrong:

```csharp
app.MapPost("/api/orders", async (
    PlaceOrderRequest req,
    [FromHeader(Name = "Idempotency-Key")] string? idemKey,
    CurrentUser me, AppDbContext db, CancellationToken ct) =>
{
    if (string.IsNullOrWhiteSpace(idemKey))
        return Results.Problem("Idempotency-Key header is required.", statusCode: 400);

    // Replay: a retried request returns the original order, never a second one.
    var replay = await db.Orders.Include(o => o.Items)
        .FirstOrDefaultAsync(o => o.IdempotencyKey == idemKey, ct);
    if (replay is not null) return Results.Ok(replay.ToDto());

    var user = await me.GetAsync(ct);

    var run = await db.Runs.FirstOrDefaultAsync(
        r => r.Id == req.RunId && r.Status == RunStatus.Open, ct);
    if (run is null)
        return Results.Problem("This run is closed.", statusCode: 409);
    if (run.OrdersCloseAtUtc <= DateTimeOffset.UtcNow)
        return Results.Problem("The cutoff has passed.", statusCode: 409);

    // Scoping: the address must belong to the caller. 404, not 403.
    var address = await db.Addresses.FirstOrDefaultAsync(
        a => a.Id == req.AddressId && a.CustomerId == user.Id, ct);
    if (address is null) return Results.NotFound();

    if (req.Items.Count == 0) return Results.Problem("Empty order.", statusCode: 400);
    if (req.Items.Any(i => i.Qty <= 0))
        return Results.Problem("Quantity must be positive.", statusCode: 400);

    // PRICING: ids in, prices from the database. Nothing about money is read
    // from `req` — see Global Constraint 4.
    var ids = req.Items.Select(i => i.ProductId).Distinct().ToArray();
    var products = await db.Products
        .Where(p => ids.Contains(p.Id) && p.IsActive)
        .ToDictionaryAsync(p => p.Id, ct);
    if (products.Count != ids.Length)
        return Results.Problem("An item is no longer available.", statusCode: 409);

    var order = new Order
    {
        Id = Guid.NewGuid(),
        OrderCode = await OrderCodeGenerator.NextAsync(db, run, ct),
        CustomerId = user.Id,
        RunId = run.Id,
        Status = OrderStatus.AwaitingPayment,
        IdempotencyKey = idemKey,
        PlacedAt = DateTimeOffset.UtcNow,
        CustomerNote = req.CustomerNote,
        // SNAPSHOT: copied, not referenced — Global Constraint 5.
        ShipToRecipient = address.RecipientName, ShipToPhone = address.Phone,
        ShipToLine1 = address.Line1, ShipToLine2 = address.Line2,
        ShipToBarangay = address.Barangay, ShipToCity = address.City,
        ShipToProvince = address.Province, ShipToPostalCode = address.PostalCode,
    };

    foreach (var item in req.Items)
    {
        var p = products[item.ProductId];
        order.Items.Add(new OrderItem
        {
            Id = Guid.NewGuid(),
            ProductId = p.Id,
            NameSnapshot = p.Name,             // snapshot
            UnitPricePhpSnapshot = p.PricePhp, // snapshot — from the DB
            Qty = item.Qty,
            LineStatus = OrderLineStatus.Pending,
        });
    }

    order.ItemsTotalPhp   = order.Items.Sum(i => i.UnitPricePhpSnapshot * i.Qty);
    order.ShippingFeePhp  = 0m;   // set by staff before confirmation — see spec §15
    order.ServiceFeePhp   = 0m;
    order.GrandTotalPhp   = order.ItemsTotalPhp + order.ShippingFeePhp + order.ServiceFeePhp;

    db.Orders.Add(order);
    try { await db.SaveChangesAsync(ct); }
    catch (DbUpdateException e) when (e.IsUniqueViolation("ix_order_idempotency_key"))
    {
        // Concurrent duplicate submit lost the race. Return the winner, not an error.
        var winner = await db.Orders.Include(o => o.Items)
            .FirstAsync(o => o.IdempotencyKey == idemKey, ct);
        return Results.Ok(winner.ToDto());
    }
    return Results.Created($"/api/orders/{order.Id}", order.ToDto());
}).RequireAuthorization();
```

  > The `catch` on the unique violation is what makes idempotency correct under
  > genuine concurrency — two taps that arrive in the same millisecond both pass the
  > replay check. The read-then-write alone is a race. This is the one place a
  > `catch` is doing real work rather than hiding a failure.

- [ ] **4.** `OrderCodeGenerator`: `PJP-{yyMM}-{seq:D4}`, sequence per run, from a
      Postgres sequence or `max+1` inside the same transaction. Never a client value,
      never a random number the customer will have to read aloud over the phone.

- [ ] **5.** Run all eight tests. All pass.

- [ ] **6.** Add a concurrency test: fire 20 parallel requests with the same
      idempotency key; assert exactly one `Order` row exists.

- [ ] **7.** Commit.

**Done when:**
- [ ] All eight tests pass, plus the 20-way concurrency test
- [ ] A request body containing `"pricePhp": "1.00"` produces an order at the real
      catalog price — verified by a test, not by inspection
- [ ] Editing the address after ordering leaves the order's ship-to fields unchanged
- [ ] `GrandTotalPhp` equals the sum of the line snapshots, to the centavo

---

## M2-07 · Checkout UI

**Depends on:** M2-06
**Branch:** `feature/m2-checkout`

**Files:**
- Create: `web/src/features/checkout/CheckoutPage.tsx`, `OrderSummary.tsx`,
  `useIdempotencyKey.ts`

**Steps:**

- [ ] **1.** Steps: review cart → pick or add address → confirm.

- [ ] **2.** Generate the idempotency key with `crypto.randomUUID()` **when the
      checkout page mounts**, and hold it for the life of that checkout. Regenerating
      it on each submit defeats the entire mechanism.

- [ ] **3.** Disable the confirm button while the request is in flight, and keep it
      disabled after success. Double-tap is the exact case this guards.

- [ ] **4.** On success: clear the cart, navigate to
      `/orders/:id` with the payment instructions visible immediately.

- [ ] **5.** On 409, show the server's message ("An item is no longer available"),
      refresh the cart against the catalog, and let them retry — do not silently drop
      the item.

- [ ] **6.** Commit.

**Done when:**
- [ ] Double-tapping confirm on a real phone produces one order
- [ ] Submitting, killing the network, and retrying produces one order
- [ ] A 409 shows the real reason and does not clear the cart

---

## M2-08 · Customer order list and detail

**Depends on:** M2-06
**Branch:** `feature/m2-my-orders`

**Files:**
- Create: `Features/Orders/CustomerOrderEndpoints.cs`,
  `web/src/features/orders/OrdersPage.tsx`, `OrderDetailPage.tsx`,
  `OrderTimeline.tsx`

**Steps:**

- [ ] **1.** `GET /api/orders` and `GET /api/orders/{id}` — **always** filtered by
      `CustomerId == CurrentUser.Id`. Another customer's id returns 404.

- [ ] **2.** List: order code, run, date, item count, total, status pill, payment
      status. Newest first.

- [ ] **3.** Detail: lines with per-line status, ship-to snapshot, payment history,
      refunds, and a timeline of the order's states.

- [ ] **4.** Per-line status is shown to the customer in plain language:
      Pending → "Waiting for the buying trip"; Bought → "Bought in Japan";
      Unavailable → "Not available — refunded"; Substituted → shows the note.

- [ ] **5.** Test: customer A requesting B's order id → 404.

- [ ] **6.** Commit.

**Done when:**
- [ ] The cross-customer test passes with 404
- [ ] An order with a mix of Bought and Unavailable lines reads clearly to a
      non-technical person — check this with an actual person

---

## M2-09 · Custom requests

**Depends on:** M2-08, M1-03
**Branch:** `feature/m2-custom-requests`

> Spec §4.4: this deliberately reuses the whole cart/order/payment path. The only new
> code is the request and the quote. Resist building a parallel order flow.

**Files:**
- Create: `Features/CustomRequests/CustomRequestEndpoints.cs`,
  `web/src/features/requests/NewRequestPage.tsx`, `MyRequestsPage.tsx`,
  `web/src/features/admin/requests/QuoteQueuePage.tsx`

**Steps:**

- [ ] **1.** Endpoints:

```
POST /api/custom-requests               Customer  { title, description, referenceUrl?, photoPath?, budgetPhp }
GET  /api/custom-requests               Customer  own only
GET  /api/admin/custom-requests?status= Staff
POST /api/admin/custom-requests/{id}/quote  Admin  { quotedPricePhp, note }
POST /api/custom-requests/{id}/accept   Customer  own only
POST /api/custom-requests/{id}/decline  Customer  own only
```

- [ ] **2.** `referenceUrl` is stored as text and **rendered as plain text, never as a
      clickable link in the admin view**, and never fetched server-side. It is
      attacker-controlled input; an auto-fetch is an SSRF and an auto-link is a
      phishing vector aimed at your own staff.

- [ ] **3.** On accept: create a `Product` with `IsCustom = true`, `IsActive = true`,
      `PricePhp = QuotedPricePhp`, link it back via `CustomRequest.ProductId`, and
      return its slug. The buyer then adds it to cart through the normal path.

- [ ] **4.** Accept is only valid from `Quoted`. Accepting twice returns 409 and does
      not create a second product.

- [ ] **5.** A quote expires when its target run closes; a `Quoted` request past that
      point shows as `Expired` and cannot be accepted.

- [ ] **6.** Buyer UI: title, description, paste a link, photo upload (purpose
      `custom-request`), budget. Set the expectation plainly — a quote is not a
      promise the item exists.

- [ ] **7.** Admin quote queue: request details, the reference URL as selectable text,
      the photo, a price field, a note, and Quote / Decline.

- [ ] **8.** Tests: accepting a non-Quoted request → 409; accepting twice creates one
      product; another customer accepting your request → 404.

- [ ] **9.** Commit.

**Done when:**
- [ ] The three tests pass
- [ ] An accepted request produces a product that is reachable by slug but **absent**
      from `/api/catalog`
- [ ] `referenceUrl` renders as text in admin — confirm with a `javascript:` URL and
      an `http://` URL

---

## Milestone exit

- [ ] A real customer account has placed a real order on staging, end to end
- [ ] All of M2-06's tests pass, including the 20-way concurrency test
- [ ] Cross-customer access returns 404 on orders, addresses and custom requests
- [ ] No screen in M2 renders an empty state when the API is down
