# M1 — Catalog and admin entry

**Goal:** Standing in Don Quijote on mobile data, the Japan buyer can photograph an
item and have it listed in under a minute.

**Why this first:** It is the input to everything. Until products exist, there is
nothing to order, ship, or report on. It is also the only screen used in a shop aisle
on a phone, so it sets the mobile bar for the whole app.

**Read first:** spec §4.1 (catalog), §4 conventions, §5.1 (uploads).
**Estimate:** 4–5 days · **7 tasks**

---

## M1-01 · Full schema migration

**Depends on:** M0-03
**Branch:** `feature/m1-schema`

> One migration for all remaining twelve entities. Doing the whole model at once —
> rather than a table per milestone — means foreign keys are right the first time and
> M4 never has to rewrite M2's tables.

**Files:**
- Create: `Domain/Catalog.cs`, `Domain/Ordering.cs`, `Domain/Money.cs`,
  `Domain/Logistics.cs`; `Data/Configurations/*.cs` (one per entity)
- Modify: `Data/AppDbContext.cs`
- Test: `tests/Pajapan.Api.Tests/SchemaTests.cs`

**Steps:**

- [ ] **1.** Write every entity from spec §4.1–§4.7. Enums as `int`. Follow the file
      grouping in [`README.md#repository-layout`](README.md#repository-layout).

- [ ] **2.** Add `Order.IdempotencyKey` (`text`, nullable, **unique**) — spec §4.4,
      required by M2-06.

- [ ] **3.** Add `DeletedAt` (`timestamptz`, nullable) to `Order`, `OrderItem`,
      `Payment`, `Refund`, `Expense`, `Shipment` — Global Constraint 7 — and a global
      query filter so soft-deleted rows never appear by accident:

```csharp
b.Entity<Order>().HasQueryFilter(o => o.DeletedAt == null);
```

- [ ] **4.** Indexes. These are not optional; they are the queries the app actually
      runs every day:

```csharp
b.Entity<Order>().HasIndex(o => o.OrderCode).IsUnique();
b.Entity<Order>().HasIndex(o => new { o.RunId, o.Status });      // shopping list
b.Entity<Order>().HasIndex(o => new { o.CustomerId, o.PlacedAt });// my orders
b.Entity<Order>().HasIndex(o => o.IdempotencyKey).IsUnique()
    .HasFilter("idempotency_key is not null");
b.Entity<Payment>().HasIndex(p => p.ReferenceNo).IsUnique()
    .HasFilter("reference_no is not null");                       // spec §4.5
b.Entity<OrderItem>().HasIndex(i => new { i.OrderId, i.LineStatus });
b.Entity<Product>().HasIndex(p => p.Slug).IsUnique();
b.Entity<Run>().HasIndex(r => r.Code).IsUnique();
```

  > The unique index on `Payment.ReferenceNo` is a fraud control, not a tidiness
  > measure: the same GCash reference submitted against two orders is either a
  > mistake or someone reusing a screenshot. The database is the cheapest place to
  > catch it, and the only place it cannot be bypassed.

- [ ] **5.** Check constraints — invariants the application must not be trusted to
      hold alone:

```csharp
t.HasCheckConstraint("ck_orderitem_qty_positive", "qty > 0");
t.HasCheckConstraint("ck_orderitem_fulfilled_le_qty", "qty_fulfilled <= qty");
t.HasCheckConstraint("ck_payment_amount_positive", "amount_php > 0");
t.HasCheckConstraint("ck_refund_amount_positive", "amount_php > 0");
```

- [ ] **6.** Seed `Courier` rows in the migration — see M5-01 for the templates.

- [ ] **7.** Generate the migration and **read the SQL**:

```bash
"/c/Program Files/dotnet/dotnet.exe" ef migrations add FullSchema -p src/Pajapan.Api
"/c/Program Files/dotnet/dotnet.exe" ef migrations script -p src/Pajapan.Api > /tmp/schema.sql
grep -nE "numeric|double|real" /tmp/schema.sql
```

- [ ] **8.** Schema tests — the guards on Global Constraints 1 and 5:

```csharp
[Fact]
public async Task All_money_columns_are_numeric_12_2()
{
    await using var db = _fx.NewContext();
    var bad = await db.Database.SqlQuery<string>($"""
        select table_name || '.' || column_name
        from information_schema.columns
        where table_schema = 'public'
          and (column_name like '%_php' or column_name like '%_jpy')
          and not (data_type = 'numeric'
                   and numeric_precision = 12 and numeric_scale = 2)
        """).ToListAsync();
    Assert.Empty(bad);   // names the offending column if it fails
}

[Fact]
public async Task Duplicate_payment_reference_is_rejected() { /* expect DbUpdateException */ }

[Fact]
public async Task Negative_payment_amount_is_rejected() { /* check constraint */ }
```

**Done when:**
- [ ] `grep -E "double precision|real" /tmp/schema.sql` returns nothing
- [ ] The `All_money_columns_are_numeric_12_2` test passes
- [ ] Inserting two payments with the same `reference_no` raises a unique violation
- [ ] `dotnet ef database update` then `dotnet ef migrations list` shows one pending
      migration applied and no model drift

---

## M1-02 · Category CRUD

**Depends on:** M1-01
**Branch:** `feature/m1-categories`

**Files:**
- Create: `Features/Catalog/CategoryEndpoints.cs`, `Features/Catalog/CategoryDtos.cs`

**Steps:**

- [ ] **1.** Endpoints. Read is public; writes are `Admin` only:

```
GET    /api/categories                    anonymous
POST   /api/admin/categories              Admin
PUT    /api/admin/categories/{id}         Admin
DELETE /api/admin/categories/{id}         Admin — 409 if any product references it
```

- [ ] **2.** Slug generated from the name, lowercased, non-alphanumerics collapsed to
      `-`. On collision append `-2`, `-3`. Slug is immutable after creation — a
      changing slug breaks every link a customer has saved.

- [ ] **3.** Delete returns `409 Conflict` with a ProblemDetails naming the count of
      products still in the category. It does not cascade, and it does not silently
      reassign them.

- [ ] **4.** Two tests: the 409-on-in-use path, and `Customer` role receiving 403 on
      `POST /api/admin/categories`.

- [ ] **5.** Commit.

**Done when:**
- [ ] Deleting a category with products returns 409 and the products still exist
- [ ] A `Customer` token gets 403 on every `/api/admin/categories` verb

---

## M1-03 · Product CRUD

**Depends on:** M1-02
**Branch:** `feature/m1-products`

**Files:**
- Create: `Features/Catalog/ProductEndpoints.cs`, `ProductDtos.cs`,
  `ProductValidators.cs`
- Test: `tests/Pajapan.Api.Tests/ProductTests.cs`

**Interfaces produced:** `ProductDto { id, name, slug, description, categoryId,
pricePhp: string, refPriceJpy: string, estWeightGrams, sourceStore, isActive,
photos: [{ id, url, sortOrder }] }`.

**Steps:**

- [ ] **1.** Endpoints:

```
GET    /api/admin/products?q=&categoryId=&isActive=&page=   Staff
GET    /api/admin/products/{id}                             Staff
POST   /api/admin/products                                  JapanBuyer | Admin
PUT    /api/admin/products/{id}                             JapanBuyer | Admin
POST   /api/admin/products/{id}/photos                      JapanBuyer | Admin
DELETE /api/admin/products/{id}/photos/{photoId}            JapanBuyer | Admin
PUT    /api/admin/products/{id}/photos/order                JapanBuyer | Admin
```

- [ ] **2.** `PricePhp` is settable by `Admin` only. `JapanBuyer` may create a product
      and set `RefPriceJpy`, but a `JapanBuyer` PUT that changes `PricePhp` returns
      403. Pricing is an Admin decision (spec §6).

- [ ] **3.** Validation: name 1–200 chars; `PricePhp > 0`; `RefPriceJpy >= 0`;
      `EstWeightGrams` 1–50000; `CategoryId` must exist.

- [ ] **4.** Money crosses the wire as a **string**. Configure
      `JsonSerializerOptions` with a converter writing `decimal` as a quoted string,
      so a JavaScript client cannot silently receive a float. Round-trip test it.

- [ ] **5.** Search: `where p.Name ILIKE '%' || @q || '%'`. Add a trigram index if the
      catalog passes ~2,000 rows — not before (spec §11).

- [ ] **6.** Photo URLs in responses are **signed read URLs** with a 1-hour expiry,
      generated at read time from `StoragePath` (the bucket is private). Never a bare
      public URL.

- [ ] **7.** Tests: JapanBuyer-cannot-set-price (403); price serialises as a string
      and parses back to the same decimal; deleting a product with orders is refused.

- [ ] **8.** Commit.

**Done when:**
- [ ] `curl` on a product shows `"pricePhp": "1250.00"` — quoted, two decimals
- [ ] A JapanBuyer token changing `pricePhp` gets 403 and the value is unchanged in
      the database
- [ ] A product referenced by any `OrderItem` cannot be hard-deleted

---

## M1-04 · Signed upload URLs

**Depends on:** M0-04
**Branch:** `feature/m1-uploads`

> The one place the API hands out write access to Storage. Spec §5.1: the server
> decides who may upload and where; the bytes never pass through it.

**Files:**
- Create: `Infrastructure/SupabaseStorage.cs`, `Features/Uploads/UploadEndpoints.cs`
- Test: `tests/Pajapan.Api.Tests/UploadTests.cs`

**Steps:**

- [ ] **1.** `POST /api/uploads/sign`, authenticated:

```jsonc
// request
{ "purpose": "product-photo", "contentType": "image/webp" }
// response
{ "uploadUrl": "https://…", "storagePath": "product-photos/2026/08/<uuid>.webp",
  "expiresInSeconds": 300 }
```

- [ ] **2.** **The client never chooses the path.** The server generates
      `<purpose>/<yyyy>/<MM>/<guid><ext>`. A client-supplied path is a directory
      traversal and an overwrite-someone-else's-file bug in one.

- [ ] **3.** Allowlist `purpose` → (bucket, permitted roles, max bytes):

| purpose | bucket | roles | max |
|---|---|---|---|
| `product-photo` | `product-photos` | JapanBuyer, Admin | 5 MB |
| `payment-proof` | `payment-proofs` | Customer (own order), Fulfilment, Admin | 5 MB |
| `receipt` | `receipts` | JapanBuyer, Fulfilment, Admin | 5 MB |
| `custom-request` | `custom-requests` | Customer | 5 MB |

  An unknown `purpose` is `400`, never a default bucket.

- [ ] **4.** Allowlist content types: `image/jpeg`, `image/png`, `image/webp`. Reject
      `image/svg+xml` — SVG is a script execution vector when served inline.

- [ ] **5.** Sign with `createSignedUploadUrl` via the service key, 5-minute expiry.
      The service key is read from configuration and never logged.

- [ ] **6.** Tests: unknown purpose → 400; `image/svg+xml` → 400; Customer requesting
      `product-photo` → 403; a client-supplied `storagePath` in the body is ignored.

- [ ] **7.** Commit.

**Done when:**
- [ ] Posting `{"purpose":"product-photo","storagePath":"../../evil.svg"}` returns a
      server-generated path and ignores the supplied one
- [ ] `image/svg+xml` is rejected
- [ ] The service key appears in no log line — check with the API at Debug level

---

## M1-05 · Admin product list

**Depends on:** M1-03, M0-06
**Branch:** `feature/m1-product-list`

**Files:**
- Create: `web/src/features/admin/products/ProductListPage.tsx`,
  `useProducts.ts`, `web/src/components/DataState.tsx`

**Steps:**

- [ ] **1.** Build `DataState` **once**, here, and use it on every list in the app.
      It is the mechanical enforcement of Global Constraint 9:

```tsx
export function DataState<T>({ query, empty, children }: {
  query: UseQueryResult<T>; empty: React.ReactNode; children: (d: T) => React.ReactNode;
}) {
  if (query.isPending) return <Skeleton />;
  if (query.isError)   return <ErrorPanel error={query.error} onRetry={query.refetch} />;
  if (isEmpty(query.data)) return <>{empty}</>;
  return <>{children(query.data!)}</>;
}
```

  > Every list screen in M2–M6 uses this. A screen that renders an empty table when
  > the API is down is the failure mode the spec calls out by name; making the correct
  > thing the easiest thing is how you avoid it fifty times over.

- [ ] **2.** Table: thumbnail, name, category, `PricePhp`, `RefPriceJpy`, active
      toggle, edit link. Search box (debounced 300 ms), category filter, active filter.

- [ ] **3.** Mobile: below 768 px the table becomes cards. This screen gets used on a
      phone.

- [ ] **4.** Active toggle is optimistic with rollback on error — and the rollback
      must show a toast, not fail silently.

- [ ] **5.** Commit.

**Done when:**
- [ ] With the API stopped, the page shows an error panel with a working Retry — not
      an empty table
- [ ] Renders correctly at 390 px, 1024 px and 1440 px
- [ ] A failed toggle reverts the switch **and** shows an error toast

---

## M1-06 · Admin product form

**Depends on:** M1-05, M1-04
**Branch:** `feature/m1-product-form`

> The most-used screen in the app, operated one-handed in a shop aisle on Japanese
> mobile data. Optimise for that, not for the desktop case.

**Files:**
- Create: `web/src/features/admin/products/ProductFormPage.tsx`,
  `PhotoUploader.tsx`, `useUpload.ts`

**Steps:**

- [ ] **1.** Zod schema mirroring M1-03's validation, wired via
      `@hookform/resolvers/zod`. Client validation is UX; the server is the gate.

- [ ] **2.** Fields in the order a person in a shop fills them: **photos first**, then
      name, JPY price, category, source store, weight, PHP price (Admin only),
      description, active.

- [ ] **3.** `PhotoUploader`:
      `<input type="file" accept="image/*" capture="environment" multiple>` — the
      native camera, no library. Ladder rung 4.

- [ ] **4.** Resize client-side before upload — the single biggest win for shop-floor
      usability. A 4 MB phone photo on Japanese mobile data is a 30-second wait; 1600
      px WebP is under 300 KB:

```ts
async function shrink(file: File): Promise<Blob> {
  const bmp = await createImageBitmap(file);
  const scale = Math.min(1, 1600 / Math.max(bmp.width, bmp.height));
  const canvas = new OffscreenCanvas(bmp.width * scale, bmp.height * scale);
  canvas.getContext("2d")!.drawImage(bmp, 0, 0, canvas.width, canvas.height);
  return canvas.convertToBlob({ type: "image/webp", quality: 0.82 });
}
```

- [ ] **5.** Upload flow per photo: `POST /api/uploads/sign` → `PUT` the blob to the
      signed URL → `POST /api/admin/products/{id}/photos` with the returned
      `storagePath`. Show a per-photo progress bar and a per-photo retry. One failed
      photo must not lose the other four or the typed form.

- [ ] **6.** Drag-to-reorder photos; the first is the thumbnail. Use the native
      HTML5 drag events — no dnd library for a list of five.

- [ ] **7.** Warn on navigate-away with unsaved changes (`beforeunload` + a router
      blocker).

- [ ] **8.** `source_store` is a datalist of previously used values — the buyer types
      "Don Quijote Shinjuku" once, not forty times.

- [ ] **9.** Commit.

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

**Files:**
- Create: `scripts/seed-dev.ps1`, `Features/Catalog/PhotoCleanup.cs`

**Steps:**

- [ ] **1.** `seed-dev.ps1`: 3 categories, 15 products, no photos. **Staging and local
      only** — it must refuse to run against a connection string it did not read from
      `appsettings.Local.json`.

- [ ] **2.** Deleting a `ProductPhoto` row must also delete the Storage object.
      Deleting a `Product` deletes all of its objects. Otherwise the bucket grows
      forever with files nothing references and no one can tell which.

- [ ] **3.** `GET /api/admin/photos/orphans` (Admin): Storage objects with no
      `ProductPhoto` row. A cleanup you run occasionally by hand — not a scheduled
      job (spec §11, no job runner).

- [ ] **4.** Test: deleting a product removes its Storage objects.

- [ ] **5.** Commit.

**Done when:**
- [ ] After deleting a seeded product, its objects are gone from the bucket
- [ ] `seed-dev.ps1` refuses to run against the production connection string

---

## Milestone exit

- [ ] The Japan buyer has created 10 real products with real photos on staging, from
      a phone
- [ ] Every money column is `numeric(12,2)` — the schema test proves it
- [ ] Every list screen uses `DataState` and shows a real error when the API is down
