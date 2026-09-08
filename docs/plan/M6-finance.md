# M6 — Finance and reporting

**Goal:** After a run closes, one page says whether it made money, and one page says
which products are worth carrying next time.

**The point of the whole app.** M1–M5 capture the data; this is where it pays for
itself. Spec §3.1: `unit_price_php_snapshot` minus `actual_cost_jpy` is the number the
business does not currently have.

**Read first:** spec §9, §4.7, §11 (freight allocation), §7.2.
**Estimate:** 4–5 days · **6 tasks**

---

> ## ⚠ Rewritten for the 2026-09-08 pivot — detail deliberately pending
>
> Structural notes only. Write each task's SQL when you start it, against the running
> local stack. Requirements and **Done when** items below still bind.

---

## Reports are views, and this is the one milestone the pivot makes simpler

Every report here is an Admin-only read over rows an Admin may already see. That is
§7.2's first row: a **`security_invoker` view**, with base-table RLS doing the
authorization. No function, no role check to write, no endpoint.

It also removes a whole layer of translation. The old plan computed these figures in
C# from EF queries; the spec's §9 formulas were always SQL wearing a C# coat. Now they
are just SQL.

**The one thing that gets harder:** every figure must still reach the browser as a
**string**, so every money column in every report view is cast to text (M1's milestone
convention). A report is exactly where a float64 would go unnoticed.

---

## M6-01 · Expense management

**Depends on:** M4-07
**Branch:** `feature/m6-expense-admin`

**Becomes:** unchanged as a screen; reads a view, writes go through M4-07's table
policies and trigger.

**Requirements:**

- [ ] Table with filters: run, category, date range, currency. Per-category totals in
      the footer.
- [ ] Inline edit of description, category and date. Editing an **amount or rate**
      requires the full form — it changes stored `amount_php` and should not be a casual
      click.
- [ ] Receipt thumbnails, click to enlarge.
- [ ] Uncategorised ("Other") expenses highlighted — "Other" swallowing 40% of costs
      makes the whole report useless.
- [ ] CSV export of the filtered set.

**Done when:**
- [ ] Category totals reconcile with the sum of rows
- [ ] Editing an amount goes through the full form and recomputes `amount_php`

---

## M6-02 · Run profit and loss 🔴

**Depends on:** M3-06, M4-05, M5-04
**Branch:** `feature/m6-run-pnl`
**Model:** Opus.

> The one report that decides whether the business works. Every figure must be
> traceable to rows a person can open and check.

**Becomes:** a `v_run_pnl` view. Spec §9's formulas translate directly:
revenue = Σ verified payments − Σ completed refunds; COGS = Σ (`actual_cost_jpy` × run
FX rate); expenses = Σ `expense.amount_php` for the run; profit = revenue − COGS −
expenses.

**Requirements:**

- [ ] Returns run identity, revenue (verified payments, refunds, net), COGS (JPY total,
      FX rate used, PHP total), expenses by category and total, profit, margin %, counts
      (orders, confirmed, unavailable lines), and **warnings**.
- [ ] **The FX rate for COGS.** `actual_cost_jpy` is per line; converting needs a rate.
      Use the weighted average of `fx_rate_to_php` across the run's JPY expenses; if the
      run has none, fall back to a nullable `run.fx_rate_to_php` — and **report which
      was used**. A profit figure whose exchange rate is invisible is not auditable.
- [ ] **`warnings` is not decoration.** Bought lines with no `actual_cost_jpy` make COGS
      understate and profit overstate — the failure mode that flatters you. Name the
      count and link to the lines.
- [ ] Every figure computed in SQL and returned as a string. Never arithmetic in
      JavaScript.

**Done when:**
- [ ] A hand-built fixture whose answer was worked out on paper — 3 orders, 2 payments,
      1 refund, 4 bought lines, 2 expenses — matches **to the centavo** on every field
- [ ] A run with a missing `actual_cost_jpy` produces a warning naming the count
- [ ] The FX rate used, and which source it came from, is visible in the output
- [ ] No money value in the response is a JSON number

---

## M6-03 · Run P&L screen

**Depends on:** M6-02
**Branch:** `feature/m6-pnl-ui`

**Becomes:** unchanged.

**Requirements:**

- [ ] Headline: revenue, costs, profit, margin %. Profit in green or red — **with a sign
      and a label too, never colour alone.**
- [ ] A waterfall: revenue → COGS → expenses → profit. Plain SVG; no chart library for
      one chart.
- [ ] **Every figure links to the rows behind it.** Clicking COGS opens the lines with
      their `actual_cost_jpy`. A report you cannot drill into is a report nobody trusts
      twice.
- [ ] Warnings in a panel **above** the numbers, not below where they will be scrolled
      past.
- [ ] Run-over-run comparison: this run against the previous three, as a small table.

**Done when:**
- [ ] Every headline figure drills through to its underlying rows
- [ ] Profit is legible in greyscale
- [ ] Warnings appear above the numbers

---

## M6-04 · Product margin report

**Depends on:** M6-02
**Branch:** `feature/m6-product-margin`

> Spec §9: `times unavailable` is worth as much as the margin column. A product that is
> repeatedly out of stock generates refunds and support work regardless of margin.

**Becomes:** a `v_product_margin` view, filtered by date range from the client.

**Requirements:**

- [ ] One row per product: name, qty sold, qty unavailable, revenue PHP, cost PHP,
      margin PHP, margin %, times unavailable, last bought.
- [ ] Sortable on every column. **Default sort: margin % ascending — the losers first.**
      A report that opens on your best sellers tells you nothing you did not already
      know.
- [ ] Flag negative-margin rows, and rows unavailable in more than 30% of the runs they
      appeared in.
- [ ] Products with no `actual_cost_jpy` on any line show margin as **"unknown", not
      zero**. Zero reads as break-even; unknown reads as missing data. In SQL this means
      `NULL` must survive to the client rather than being `coalesce`d to `0` — the
      easiest and most damaging shortcut in this view.
- [ ] CSV export.

**Done when:**
- [ ] A product bought at ¥500 (rate 0.38) and sold at ₱250 shows margin ₱60.00 and 24%
- [ ] Unknown-cost products show "unknown", never 0
- [ ] Default sort surfaces loss-making products first

---

## M6-05 · Freight allocation 🔴

**Depends on:** M6-02, M5-04
**Branch:** `feature/m6-freight-allocation`
**Model:** Opus. Rounding remainder distribution — a centavo leak nobody finds.

> Spec §11: allocated **at report time by order value, not stored**. Keep it that way.

**Becomes:** a function returning a table. It could be written as a view with window
functions, but the largest-remainder step is the entire point of the task and deserves
to be readable.

**The algorithm, unchanged:** apportion `shipment.cost_php` across its orders in
proportion to `items_total_php`; round each to 2dp; compute the drift between the sum
of the rounded shares and the true cost; **add the drift to the largest order.**
Postcondition: the shares sum to exactly `cost_php`.

> **Watch the rounding mode when porting.** C#'s `decimal.Round(x, 2)` uses banker's
> rounding (half-to-even) by default; Postgres `round(numeric, 2)` rounds half away from
> zero. The remainder distribution makes the *total* correct either way, but individual
> allocations can differ by a centavo from what the C# version would have produced —
> so do not port the old expected values, recompute them.

**Requirements:**

- [ ] **Assert the postcondition inside the function**, not only in a test. A silent
      centavo leak across hundreds of orders is exactly the kind of error nobody finds.
- [ ] Show allocated freight on the admin order detail as "estimated shipping cost" —
      clearly a derived figure, not a charge.
- [ ] A zero-value order must not divide by zero.

**Done when:**
- [ ] ₱1,000 across three orders of ₱333.33 sums to exactly ₱1,000.00
- [ ] Allocations always sum to exactly the freight cost — property-tested over 100
      random splits
- [ ] A shipment containing a zero-value order does not error

---

## M6-06 · Finance dashboard

**Depends on:** M6-03, M6-04, M3-06
**Branch:** `feature/m6-dashboard`

**Becomes:** several independent view queries rather than one endpoint — which happens
to make requirement 5 below easier, since each card already owns its own query.

**Requirements:**

- [ ] Admin landing page. Cards: current run status and value, payments awaiting
      verification, refunds pending, orders shipped over 14 days ago, reconciliation
      mismatches.
- [ ] Any non-zero reconciliation count is an **alert**, not a stat tile. It means the
      books disagree with themselves.
- [ ] Last three runs' profit as a small bar chart, plain SVG.
- [ ] A cross-run P&L over a date range, plus CSV export for the accountant.
- [ ] **Every card handles its own error state independently.** One failing query must
      not blank the dashboard, and must not render as zero — a dashboard showing ₱0
      profit because a query failed is the exact failure Global Constraint 9 exists to
      prevent. With `supabase-js` returning `{ data, error }` rather than throwing, an
      unchecked card degrades to "₱0" by default. Use the throwing helper from M0-10 and
      `DataState` from M1-05 on every card.

**Done when:**
- [ ] Revoking read on one view leaves the other cards working and shows an error on
      that card only
- [ ] No card ever displays 0 when its data failed to load
- [ ] CSV opens cleanly in Excel with correct decimal separators

---

## Milestone exit

- [ ] A completed run shows a P&L the team agrees matches reality, checked against their
      own notes
- [ ] The product margin report has changed at least one buying decision
- [ ] Reconciliation shows zero mismatches
- [ ] Freight allocations sum exactly
- [ ] No money figure anywhere in M6 reaches the browser as a JSON number
