# M2 — Storefront, cart and orders

**Goal:** A customer can browse the catalog, place an order against the open run, and
see it in their order history. Custom requests work end to end.

**The task that matters:** M2-06. Everything else here is screens; M2-06 is where
money is decided, and it is the one to review hardest.

**Read first:** spec §4.4 (orders), §8.1 (order flow), §6.1 (the rules that must be
tested), §7.2 (view vs function vs direct write).
**Estimate:** 5–6 days · **9 tasks**

---

> ## ⚠ Rewritten for the 2026-09-08 pivot — detail deliberately pending
>
> Structural notes only. Write each task's SQL when you start it, against the running
> local stack. Requirements and **Done when** items below still bind.

---

## The column-exposure problem, stated once

M1 hit this twice (the price column in M1-03, the shopping list in §7.1) and M2 hits
it again in M2-01. It is **the** recurring hazard of this architecture, so here it is
in one place:

**RLS is row-level. It has nothing to say about columns.** A policy that lets a
customer read the `product` table lets them read *every column* of the rows it
matches — `ref_price_jpy` (your cost) and `source_store` (your supplier) included,
whatever the UI asks for. `select('*')` is a client-side choice, and the client is
the attacker in this model.

The three tools, in order of preference:

1. **A view exposing only the public columns**, with the base table not readable by
   that role at all. This is the default answer.
2. **A `SECURITY DEFINER` function**, when the caller must not see the underlying rows
   even in aggregate (§7.1).
3. **A trigger**, when the caller may read a column but not *write* it (M1-03).

The old design got this for free — a DTO is a column allowlist by construction. Here
it is a thing you have to remember, so: **no customer-facing screen reads a base table
directly.** It reads a view.

---

## M2-01 · Public catalog view

**Depends on:** M1-03
**Branch:** `feature/m2-catalog-view`

**Becomes:** a `v_catalog` view, not endpoints. This carries the whole weight of the
old task's most important step.

> The C# version said: *the public DTO omits `RefPriceJpy`, `SourceStore`, `IsCustom`
> and every audit field. **Do not reuse the admin DTO.** Your cost price and your
> supplier are not customer-facing, and a shared DTO leaks them the first time someone
> adds a field.*
>
> That reasoning is unchanged and now applies to the view. The difference is the
> failure mode: forgetting a DTO gave you a compile error or a visibly wrong response.
> Forgetting the view means the base table is readable and **nothing looks wrong at
> all** until someone runs `select('*')`.

**Requirements:**

- [ ] `v_catalog` exposes: id, name, slug, description, category, `price_php::text`,
      photos, `est_weight_grams`. Nothing else.
- [ ] The `product` base table has **no** customer or anonymous read policy. Staff read
      the base table; everyone else reads the view.
- [ ] `is_custom = true` products are excluded from the view's browse listing but
      reachable by slug — that is how the buyer who requested one gets to it.
- [ ] The open run and its cutoff are readable by anyone. When no run is open, the
      storefront must render a "next run announced soon" state, not an error and not an
      empty catalog.
- [ ] Money as text (milestone convention, M1).

**Done when:**
- [ ] `supabase.from('product').select('*')` as a customer returns **zero rows or an
      error** — not rows with the cost price in them
- [ ] A `select('*')` against `v_catalog` contains no `ref_price_jpy`, `source_store`
      or `is_custom` — assert on the returned keys, so adding a column to `product`
      later cannot silently leak into the view
- [ ] An anonymous client can read the catalog
- [ ] With no open run, the storefront renders the no-run state

---

## M2-02 · Catalog browse UI

**Depends on:** M2-01
**Branch:** `feature/m2-browse`

**Becomes:** unchanged apart from the data source (`v_catalog` via `supabase-js`).

**Requirements:** responsive grid — 2 columns at 390 px, 3 at 768, 4 at 1280;
`ProductCard` with a lazy photo in an `aspect-ratio` box to prevent layout shift;
`RunBanner` pinned at the top with a live countdown to the cutoff rendered in
**Asia/Manila**, urgent under 24 hours, and add-to-cart disabled everywhere when no
run is open; infinite scroll via `useInfiniteQuery` **plus a visible "Load more"
button**, because infinite scroll alone is unreachable by keyboard; `DataState` from
M1-05 for loading, error and empty.

**Done when:**
- [ ] Countdown shows Manila time and is correct against a JST cutoff — verify by
      changing the machine timezone
- [ ] With no open run, no add-to-cart button anywhere is clickable
- [ ] Lighthouse CLS under 0.1 on the grid

---

## M2-03 · Product detail

**Depends on:** M2-02
**Branch:** `feature/m2-product-detail`

**Becomes:** unchanged. Route `/p/:slug` reads `v_catalog`.

**Requirements:** gallery with thumbnails, swipe via native CSS scroll-snap — no
carousel library; name, price, description, category, quantity stepper, add to cart;
a prominent pre-order notice stating that this is bought on the run closing `<date>`,
arriving approximately `<estimatedArrival>`, and **if unavailable in store you are
refunded**; a 404 page for an unknown slug; per-product `<title>` and OpenGraph tags.

> Setting the refund expectation on the product page is what stops the M4 refund from
> becoming a support argument. It is a product decision wearing a UI hat.

**Done when:**
- [ ] The unavailable-and-refunded notice is visible without scrolling at 390 px
- [ ] An unknown slug renders a 404 page, not a crash

---

## M2-04 · Cart

**Depends on:** M2-03
**Branch:** `feature/m2-cart`

**Becomes:** unchanged — the cart was always client-side and never knew about the
backend.

**Requirements:**

- [ ] Cart in `localStorage`, keyed by run id. Store **only** `{ productId, qty }` —
      never a price. A price in the cart is a price the client could be trusted with,
      and it must not be (Global Constraint 4).
- [ ] Display prices fetched fresh from `v_catalog` on cart render, so a repriced
      product shows its current price before checkout.
- [ ] Changing run clears the cart, with a confirmation dialog.
- [ ] A no-longer-active item shows struck through with "no longer available" and
      blocks checkout until removed.
- [ ] Totals via `toCents` from M0-05 — bigint arithmetic, never float.

**Done when:**
- [ ] `localStorage` contains no price — inspect it directly
- [ ] 3 × `"333.33"` = `"999.99"`, not `999.9899999999999`
- [ ] Repricing a product in admin changes the cart total on reload

---

## M2-05 · Addresses

**Depends on:** M1-01, M0-10
**Branch:** `feature/m2-addresses`

**Becomes:** direct table writes under RLS — §7.2's fourth row. Addresses are the
caller's own non-money data, so no function is justified.

**Requirements:**

- [ ] RLS scopes every read and write to `customer_id = auth.uid()`. The old rule
      "`CustomerId` comes from `CurrentUser.Id`, never from the body" becomes: the
      policy's `WITH CHECK` clause forces `customer_id = auth.uid()` on insert, so a
      forged body value is rejected by the database rather than ignored by code.
- [ ] Another customer's address returns **zero rows** — the 404-not-403 property,
      now free (spec §6.1).
- [ ] PH fields: recipient, phone, line1, line2, barangay, city, province, postcode.
      Province is a `<select>` from the static list of 82 — free text produces
      unusable delivery data.
- [ ] Phone validated as PH mobile `^(09|\+639)\d{9}$`, normalised to `+639…` on save.
      The courier needs one format. Normalise in a trigger, not only in the form.
- [ ] Setting a default clears the previous default **in the same transaction** — a
      trigger, so it holds regardless of how the row was written.

**Done when:**
- [ ] Customer A selecting Customer B's address id gets zero rows
- [ ] An insert with a forged `customer_id` is rejected by the policy
- [ ] `09171234567` and `+639171234567` both store as `+639171234567`
- [ ] Two addresses cannot both be default

---

## M2-06 · Place order 🔴

**Depends on:** M2-04, M2-05
**Branch:** `feature/m2-place-order`
**Model:** Opus.

> **The highest-risk task in the project.** Every peso the business earns passes
> through it. Review against spec §8.1 and Global Constraints 4, 5 and 8, line by line.

**Becomes:** a `place_order` `SECURITY DEFINER` function. `order` and `order_item`
grant **no** direct insert to anyone — this function is the only way an order comes
into existence.

**Write the tests first.** These eight were the specification under the old
architecture and every one of them survives the pivot verbatim, because they describe
behaviour rather than implementation:

- [ ] a client-supplied price is ignored
- [ ] the same idempotency key returns the same order, never a second row
- [ ] an order against a closed run is refused
- [ ] an order containing an inactive product is refused
- [ ] another customer's address is not usable
- [ ] totals equal the sum of the line snapshots
- [ ] zero or negative qty is refused
- [ ] the address is snapshotted, not referenced — edit it afterwards, the order is
      unchanged

Run them, watch all eight fail, and confirm each fails *for the right reason* before
implementing. A test that passes before the code exists is a broken test.

**The rules the function must hold** — carried over from the C# implementation's
annotated version:

- [ ] **Identity:** `auth.uid()`, first statement. Never a parameter.
- [ ] **Replay:** look up the idempotency key first and return the existing order.
- [ ] **Pricing:** ids and quantities in; `price_php` read from `product` inside the
      function. Nothing about money comes from the caller. There is no `p_price`
      parameter *to* ignore.
- [ ] **Snapshot:** `name_snapshot` and `unit_price_php_snapshot` per line; the eight
      ship-to fields copied from the address, not referenced.
- [ ] **Run state:** must be `Open` *and* before `orders_close_at_utc`. Two separate
      checks — a run left `Open` past its cutoff is the likely operational reality.
- [ ] **Order code:** `PJP-{yyMM}-{seq:D4}`, sequence per run, allocated inside the
      transaction. Never a client value, never a random number a customer has to read
      aloud over the phone.

> **Idempotency under real concurrency.** The C# version did a replay check, then
> caught the unique-violation on `idempotency_key` and returned the winner — because
> two taps arriving in the same millisecond both pass the replay check, and
> read-then-write alone is a race. The same hazard exists here and SQL expresses the
> fix better: `INSERT … ON CONFLICT (idempotency_key) DO NOTHING`, then select the
> row. Do not lose this by writing the naive check-then-insert; it will pass every
> sequential test and fail on a real double-tap.

**Done when:**
- [ ] All eight tests pass, plus a 20-way parallel test with one idempotency key
      producing exactly one `order` row
- [ ] Calling `place_order` with an extra price-shaped argument fails — the function
      has no such parameter
- [ ] Editing the address after ordering leaves the order's ship-to fields unchanged
- [ ] `grand_total_php` equals the sum of the line snapshots, to the centavo
- [ ] A direct `insert into "order"` from a customer's client is refused

---

## M2-07 · Checkout UI

**Depends on:** M2-06
**Branch:** `feature/m2-checkout`

**Becomes:** the idempotency key moves from an HTTP header to an RPC argument.
Everything else stands.

**Requirements:**

- [ ] Steps: review cart → pick or add address → confirm.
- [ ] Generate the key with `crypto.randomUUID()` **when the checkout page mounts**,
      and hold it for the life of that checkout. Regenerating it per submit defeats the
      entire mechanism.
- [ ] Disable confirm while in flight, and keep it disabled after success.
- [ ] **Mutation retry stays off** (Global Constraint 8). A retried `.rpc()` is exactly
      the double-submission the key absorbs — it should not be relied on as routine.
- [ ] On success: clear the cart, navigate to `/orders/:id` with payment instructions
      visible immediately.
- [ ] On a refusal, show the real reason, refresh the cart against the catalog, and let
      them retry — never silently drop the item.

**Done when:**
- [ ] Double-tapping confirm on a real phone produces one order
- [ ] Submitting, killing the network, and retrying produces one order
- [ ] A refusal shows the real reason and does not clear the cart

---

## M2-08 · Customer order list and detail

**Depends on:** M2-06
**Branch:** `feature/m2-my-orders`

**Becomes:** RLS-scoped reads. The `order` table's customer read policy is
`customer_id = auth.uid()` and excludes soft-deleted rows; no per-screen filtering is
needed or trusted.

> Check whether the customer-facing order read needs its own view. `order` carries
> `internal_note` (staff only, spec §4.4) — that is the column-exposure problem again,
> on a table the customer legitimately reads rows from. It is the clearest case in the
> app of a row the caller may see and a column they may not.

**Requirements:**

- [ ] List: order code, run, date, item count, total, status pill, payment status,
      newest first.
- [ ] Detail: lines with per-line status, ship-to snapshot, payment history, refunds,
      and a timeline of states.
- [ ] Per-line status in plain language: Pending → "Waiting for the buying trip";
      Bought → "Bought in Japan"; Unavailable → "Not available — refunded";
      Substituted → shows the note.

**Done when:**
- [ ] Customer A reading B's order id gets zero rows
- [ ] `internal_note` never reaches a customer's client — assert on returned keys
- [ ] An order mixing Bought and Unavailable lines reads clearly to a non-technical
      person — check with an actual person

---

## M2-09 · Custom requests

**Depends on:** M2-08, M1-03
**Branch:** `feature/m2-custom-requests`

> Spec §4.4: this deliberately reuses the whole cart/order/payment path. The only new
> code is the request and the quote. Resist building a parallel order flow.

**Becomes:** a mix. Submitting a request is a direct insert under RLS (the customer's
own non-money data). Quoting and accepting are functions — accepting creates a
`Product`, which a customer must not be able to do directly.

**Requirements:**

- [ ] `reference_url` is stored as text and **rendered as plain text in the admin view,
      never as a clickable link**, and never fetched server-side. It is
      attacker-controlled input: an auto-fetch is an SSRF and an auto-link is a
      phishing vector aimed at your own staff.
- [ ] On accept: create a product with `is_custom = true`, `is_active = true`,
      `price_php = quoted_price_php`, link it back via `custom_request.product_id`,
      return its slug. Inside one function, one transaction.
- [ ] Accept is valid only from `Quoted`. Accepting twice is refused and does not
      create a second product.
- [ ] A quote expires when its target run closes; a `Quoted` request past that point
      shows as `Expired` and cannot be accepted.
- [ ] Buyer UI: title, description, pasted link, photo upload (`custom-requests`
      bucket, M1-04), budget. State plainly that a quote is not a promise the item
      exists.
- [ ] Admin quote queue: details, the reference URL as selectable text, the photo, a
      price field, a note, Quote / Decline.

**Done when:**
- [ ] Accepting a non-`Quoted` request is refused; accepting twice yields one product
- [ ] Another customer cannot accept your request
- [ ] An accepted request produces a product reachable by slug but **absent** from
      `v_catalog`'s browse listing
- [ ] `reference_url` renders as text in admin — confirm with a `javascript:` URL and
      an `http://` URL

---

## Milestone exit

- [ ] A real customer account has placed a real order on staging, end to end
- [ ] All of M2-06's tests pass, including the 20-way concurrency test
- [ ] Cross-customer reads return zero rows on orders, addresses and custom requests
- [ ] No customer-facing screen reads a base table directly — every one reads a view
- [ ] No screen in M2 renders an empty state when the database is unreachable
