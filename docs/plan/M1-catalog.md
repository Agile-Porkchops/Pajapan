# M1 — Catalog and admin entry

**Goal:** Standing in Don Quijote on mobile data, the Japan buyer can photograph an
item and have it listed in under a minute.

**Why this first:** It is the input to everything. Until products exist, there is
nothing to order, ship, or report on. It is also the only screen used in a shop aisle
on a phone, so it sets the mobile bar for the whole app.

**Read first:** spec §4.1 (catalog), §4 conventions, §5.1 (trust boundary),
§7.2 (view vs function vs direct write).
**Estimate:** 4–5 days · **7 tasks**

---

> ## ⚠ Rewritten for the 2026-09-08 pivot — detail deliberately pending
>
> These tasks were written as C# endpoints against EF Core. The **structural** notes
> below say what each becomes under RLS/RPC. The detailed steps and SQL are *not*
> written yet, on purpose: fifty tasks of confident, untested SQL is worse than none.
> Write each task's detail when you start it, against the running local stack from
> M0-08 — the same discipline that made M0 trustworthy.
>
> Requirements and **Done when** items below still bind. Those are architecture-
> neutral statements about behaviour, and most survived the pivot untouched.

---

## Milestone-wide conventions established here

Three decisions land in M1 and every later milestone inherits them. They are the
reason M1 is worth doing carefully rather than quickly.

**1. Money crosses the wire as a string — and this now takes deliberate work.**
PostgREST serialises `numeric` as a **JSON number**, so `price_php` arrives in
JavaScript as a float64. The old design prevented this with a C# JSON converter;
there is no equivalent hook now. Every view and every RPC return type therefore casts
money to text:

```sql
SELECT p.price_php::text AS price_php, ...
```

Global Constraint 1 is unchanged; only the mechanism moved. Getting this wrong is
silent — the numbers look right until one of them doesn't.

**2. Column-level permission needs a trigger, not a policy.** RLS is row-level. There
is no way to write "JapanBuyer may update this row but not *this column*" as a
policy, and Postgres column grants attach to database roles — every logged-in user
here shares `authenticated`, so they cannot help. See M1-03.

**3. The client now chooses the storage path.** That was the server's job under the
old design, for good reason. See M1-04 — this is the task whose risk went *up* in the
pivot, and the only one that did.

---

## M1-01 · Full schema migration 🔴

**Depends on:** M0-09
**Branch:** `feature/m1-schema`
**Model:** Opus.

> One migration for all remaining twelve entities, **each with its RLS policies in the
> same migration as its table** (plan README, repository layout). Doing the whole
> model at once means foreign keys are right the first time and M4 never has to
> rewrite M2's tables.

**Becomes:** hand-written SQL in `supabase/migrations/`, not generated from entity
classes. This is more work than `ef migrations add` and better: the RLS policies, the
check constraints and the indexes are all first-class text you read and review,
rather than output you inspect after the fact.

**Carried over unchanged from the C# version** — all of this was database-level
already and survives verbatim:

- [ ] Every monetary column uses the `money_php` / `numeric(12,2)` domain from M0-09.
      No bare `numeric`.
- [ ] `order.idempotency_key` — text, nullable, **unique**. Required by M2-06.
- [ ] `deleted_at timestamptz` on `order`, `order_item`, `payment`, `refund`,
      `expense`, `shipment`. **The RLS policy excludes soft-deleted rows** — this
      replaces EF's global query filter, and is stronger, because a caller cannot
      opt out of it the way they could omit a `.is('deleted_at', null)` filter.
- [ ] Indexes — these are the queries the app runs every day, not tidiness:
      `order.order_code` unique; `(run_id, status)` for the shopping list;
      `(customer_id, placed_at)` for "my orders"; `order.idempotency_key` unique
      filtered on not-null; `payment.reference_no` unique filtered on not-null;
      `(order_id, line_status)` on `order_item`; `product.slug` unique;
      `run.code` unique.
- [ ] Check constraints: `qty > 0`; `qty_fulfilled <= qty`; `payment.amount_php > 0`;
      `refund.amount_php > 0`.
- [ ] Seed `courier` rows in the migration — templates in M5-01.

> The unique index on `payment.reference_no` is a fraud control, not a tidiness
> measure: the same GCash reference submitted against two orders is either a mistake
> or someone reusing a screenshot. The database is the cheapest place to catch it, and
> now the only place — there is no application layer left to check it twice.

**New, and the substance of this task:** an RLS policy set per table. Twelve tables ×
four roles is where this milestone's risk actually lives. Work table by table and
write the negative test for each before moving on.

**Done when:**
- [ ] No column anywhere is `double precision` or `real` — assert over
      `information_schema.columns`, as the C# version did
- [ ] Every money column is `numeric(12,2)` — the same query, ported
- [ ] Inserting two payments with the same `reference_no` raises a unique violation
- [ ] The M0-09 structural test still passes: no table added here has RLS off
- [ ] For every table, a test proves a Customer cannot read another customer's rows
- [ ] `supabase db reset` applies cleanly from empty, twice

---

## M1-02 · Category CRUD

**Depends on:** M1-01
**Branch:** `feature/m1-categories`

**Becomes:** RLS policies, no endpoints. Public read (including anonymous); insert,
update and delete restricted to Admin. §7.2 says direct table writes are correct
here — categories are not money and an Admin owns all of them, so no function earns
its keep.

**Requirements:**

- [ ] Slug generated from the name, lowercased, non-alphanumerics collapsed to `-`,
      `-2`/`-3` on collision. Slug is **immutable after creation** — a changing slug
      breaks every saved link. Enforce immutability with a trigger, not a convention.
- [ ] Deleting a category that still has products must fail. Under the old design this
      was a hand-written `409 Conflict`; here it is `ON DELETE RESTRICT` on the foreign
      key — the database refuses, and it cannot be forgotten or bypassed. It does not
      cascade and it does not silently reassign.

**Done when:**
- [ ] Deleting a category with products fails and the products still exist
- [ ] A Customer's client cannot insert, update or delete a category
- [ ] An anonymous client can read the category list

---

## M1-03 · Product CRUD

**Depends on:** M1-02
**Branch:** `feature/m1-products`

**Becomes:** RLS policies for read and write, **plus a trigger** for the price rule.

> **The structural problem in this task.** Spec §6 says JapanBuyer may create a product
> and set `ref_price_jpy`, but only Admin may set `price_php` — the customer-facing
> price. That is a *column*-level rule, and RLS is row-level. A policy can say "you may
> update this row"; it cannot say "you may update this row except that column".
> Postgres column grants exist but attach to a database role, and every signed-in user
> shares `authenticated`.
>
> The answer is a `BEFORE UPDATE` trigger that raises if `price_php` changed and
> `current_app_role()` is not Admin. Write the negative test first: it is the kind of
> rule that looks enforced because the UI hides the field.

**Requirements:**

- [ ] Read: active, non-custom products readable by anyone including anonymous. Staff
      read all, including inactive and custom.
- [ ] Write: JapanBuyer and Admin may insert and update. Price rule per the trigger
      above.
- [ ] Validation moves to check constraints — name 1–200 chars, `price_php > 0`,
      `ref_price_jpy >= 0`, `est_weight_grams` 1–50000. `category_id` is an FK, which
      already enforces existence.
- [ ] Money as text in every view — the milestone convention above.
- [ ] Search: `name ILIKE '%' || q || '%'`, expressible directly as a PostgREST
      `.ilike()` filter. Trigram index only past ~2,000 rows (spec §11).
- [ ] Photo read URLs are **signed, 1-hour expiry**, generated from `storage_path` at
      read time — the bucket is private. Never a bare public URL. The client can call
      `createSignedUrl` itself now; the storage policy is what decides if it may.
- [ ] A product referenced by any `order_item` cannot be hard-deleted — FK restrict.

**Done when:**
- [ ] A product read returns `"price_php": "1250.00"` — quoted string, two decimals
- [ ] A JapanBuyer's own client updating `price_php` is **rejected by the database**,
      and the stored value is unchanged — verified from a signed-in client, not the UI
- [ ] A JapanBuyer *can* still update `ref_price_jpy` on the same row
- [ ] A product referenced by an `order_item` cannot be deleted

---

## M1-04 · Storage upload policies

**Depends on:** M0-09
**Branch:** `feature/m1-uploads`

> **This is the one task whose risk went up in the pivot.** Read the old rationale
> before writing the new policy.
>
> The C# design's rule was: *the client never chooses the path*. The server generated
> `<purpose>/<yyyy>/<MM>/<guid><ext>`, because a client-supplied path is a directory
> traversal and an overwrite-someone-else's-file bug in one. There is no server now —
> the browser calls `createSignedUploadUrl(path)` and picks the path itself.
>
> The protection has to move into the storage policy, which can constrain the path by
> prefix. A payment proof must land under the uploader's own uid; a product photo must
> land in the product-photos bucket and only for JapanBuyer/Admin. **A storage bucket
> with a policy of "authenticated users may insert" is an
> overwrite-anyone's-file bug**, and it is the default shape people reach for.

**Requirements:**

- [ ] One bucket per purpose, all private, each with its own insert policy:

| bucket | who may insert | path must be under |
|---|---|---|
| `product-photos` | JapanBuyer, Admin | `product-photos/` |
| `payment-proofs` | Customer (own), Fulfilment, Admin | `<auth.uid()>/` |
| `receipts` | JapanBuyer, Fulfilment, Admin | `receipts/` |
| `custom-requests` | Customer | `<auth.uid()>/` |

- [ ] Insert policies must also **forbid overwriting an existing object**, not only
      constrain where new ones go
- [ ] Allowlist content types at the bucket level: `image/jpeg`, `image/png`,
      `image/webp`. **Reject `image/svg+xml`** — SVG is a script execution vector when
      served inline. This was right in the C# design and is unchanged.
- [ ] 5 MB per object

**Done when:**
- [ ] Customer A cannot write into Customer B's payment-proof prefix — attempted from
      a real signed-in client
- [ ] A Customer cannot write to `product-photos` at all
- [ ] Uploading to a path that already exists fails
- [ ] `image/svg+xml` is rejected by the bucket, not by the UI

---

## M1-05 · Admin product list

**Depends on:** M1-03, M0-10
**Branch:** `feature/m1-product-list`

**Becomes:** unchanged as a screen; `useProducts` calls `supabase.from('product')`
instead of `apiClient`. The one thing that must not be lost:

- [ ] Build `DataState` **once**, here, and use it on every list in the app: pending →
      skeleton, error → panel with retry, empty → empty state, else render. It is the
      mechanical enforcement of Global Constraint 9, and it matters *more* now — with
      `supabase-js` returning `{ data, error }` rather than throwing, an unchecked
      error becomes an empty table by default rather than by mistake. Pair it with the
      throwing helper from M0-10.

**Requirements:** table of thumbnail, name, category, `price_php`, `ref_price_jpy`,
active toggle, edit link; debounced search; category and active filters; cards below
768 px; optimistic active-toggle with rollback **and a toast** on failure.

**Done when:**
- [ ] With the local Supabase stack stopped, the page shows an error panel with a
      working Retry — not an empty table
- [ ] Renders correctly at 390 px, 1024 px and 1440 px
- [ ] A failed toggle reverts the switch **and** shows an error toast

---

## M1-06 · Admin product form

**Depends on:** M1-05, M1-04
**Branch:** `feature/m1-product-form`

> The most-used screen in the app, operated one-handed in a shop aisle on Japanese
> mobile data. Optimise for that, not for the desktop case.

**Becomes:** the upload flow loses a round trip. Previously: sign via the API → PUT →
register the photo row via the API. Now: `createSignedUploadUrl` → PUT → insert the
`product_photo` row directly under RLS. Everything else about this screen is
unchanged.

**Requirements** — all carried over, none affected by the pivot:

- [ ] Zod schema mirroring M1-03's constraints. Client validation is UX; the database
      is the gate.
- [ ] Field order as a person in a shop fills them: **photos first**, then name, JPY
      price, category, source store, weight, PHP price (Admin only), description,
      active.
- [ ] `<input type="file" accept="image/*" capture="environment" multiple>` — the
      native camera, no library.
- [ ] **Resize client-side before upload.** The single biggest usability win: a 4 MB
      phone photo on Japanese mobile data is a 30-second wait; 1600 px WebP is under
      300 KB. `createImageBitmap` → `OffscreenCanvas` → `convertToBlob({ type:
      "image/webp", quality: 0.82 })`.
- [ ] Per-photo progress and per-photo retry. One failed photo must not lose the other
      four or the typed form.
- [ ] Drag-to-reorder, first photo is the thumbnail. Native HTML5 drag events — no dnd
      library for a list of five.
- [ ] Warn on navigate-away with unsaved changes.
- [ ] `source_store` is a datalist of previously used values — typed once, not forty
      times.

**Done when:**
- [ ] On a real phone, throttled to Slow 4G, a product with 3 photos is created in
      under 60 seconds
- [ ] A 4 MB JPEG uploads as a WebP under 400 KB — check the Network tab
- [ ] Killing the network mid-upload shows a retry on that photo and preserves the form
- [ ] Every control is at least 44 px tall

---

## M1-07 · Catalog seed and photo integrity

**Depends on:** M1-06
**Branch:** `feature/m1-seed`

**Becomes:** the dev seed folds into `supabase/seed.sql` from M0-08 — one seed
mechanism, not two. The guard that mattered survives in a stronger form: `seed.sql`
runs via `supabase db reset` against the **local** stack and has no way to address a
remote project, where the old PowerShell script had to refuse a production connection
string by inspection.

**Requirements:**

- [ ] Extend `supabase/seed.sql`: 3 categories, 15 products, no photos
- [ ] Deleting a `product_photo` row must delete the Storage object; deleting a
      `product` must delete all of its objects. Otherwise the bucket grows forever with
      files nothing references and nobody can tell which. A trigger is the natural home
      for this now.
- [ ] An orphan report — Storage objects with no `product_photo` row — as an
      Admin-only function, run occasionally by hand. Not a scheduled job (spec §11).

**Done when:**
- [ ] After deleting a seeded product, its objects are gone from the bucket
- [ ] `supabase db reset` gives the same catalog every time

---

## Milestone exit

- [ ] The Japan buyer has created 10 real products with real photos on staging, from
      a phone
- [ ] Every money column is `numeric(12,2)`, and every money field arrives in the
      browser as a **string** — both proven by test
- [ ] Every list screen uses `DataState` and shows a real error when the database is
      unreachable
- [ ] Every table added in M1-01 has RLS enabled and a negative test proving isolation
