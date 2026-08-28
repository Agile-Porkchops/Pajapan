# M6 — Finance and reporting

**Goal:** After a run closes, one page says whether it made money, and one page says
which products are worth carrying next time.

**The point of the whole app.** M1–M5 capture the data; this is where it pays for
itself. Spec §3.1: `UnitPricePhpSnapshot` minus `ActualCostJpy` is the number the
business does not currently have.

**Read first:** spec §9, §4.7, §11 (freight allocation).
**Estimate:** 4–5 days · **6 tasks**

---

## M6-01 · Expense management

**Depends on:** M4-07
**Branch:** `feature/m6-expense-admin`

**Files:**
- Create: `web/src/features/admin/expenses/ExpenseTablePage.tsx`

**Steps:**

- [ ] **1.** Table with filters: run, category, date range, currency. Totals per
      category in the footer.
- [ ] **2.** Inline edit of description, category and date. Editing an **amount or
      rate** requires the full form — it changes stored `AmountPhp` and should not be a
      casual click.
- [ ] **3.** Receipt thumbnails, click to enlarge.
- [ ] **4.** Uncategorised expenses ("Other") are highlighted — "Other" swallowing 40%
      of costs makes the whole report useless.
- [ ] **5.** CSV export of the filtered set.
- [ ] **6.** Commit.

**Done when:**
- [ ] Category totals reconcile with the sum of rows
- [ ] Editing an amount goes through the full form and recomputes `AmountPhp`

---

## M6-02 · Run profit and loss

**Depends on:** M3-06, M4-05, M5-04
**Branch:** `feature/m6-run-pnl`

> The one report that decides whether the business works. Every figure must be
> traceable to rows a person can open and check.

**Files:**
- Create: `Features/Reports/RunPnlEndpoint.cs`, `Features/Reports/ReportDtos.cs`
- Test: `tests/Pajapan.Api.Tests/RunPnlTests.cs`

**Steps:**

- [ ] **1.** `GET /api/admin/reports/run/{runId}` (Admin), returning:

```jsonc
{
  "run": { "code": "2026-09A", "status": "Completed" },
  "revenue": {
    "verifiedPaymentsPhp": "184500.00",
    "refundsPhp": "6400.00",
    "netPhp": "178100.00"
  },
  "cogs": {
    "actualCostJpy": "412300.00",
    "fxRateUsed": "0.3820",
    "actualCostPhp": "157499.00"
  },
  "expenses": { "byCategory": { "Freight": "18000.00", "Customs": "4200.00" },
                "totalPhp": "22200.00" },
  "profitPhp": "-1599.00",
  "marginPercent": "-0.90",
  "counts": { "orders": 47, "confirmed": 44, "unavailableLines": 6 },
  "warnings": ["3 bought lines have no actualCostJpy"]
}
```

- [ ] **2.** **The FX rate for COGS.** `ActualCostJpy` is per line; converting needs a
      rate. Use the weighted average of `FxRateToPhp` across the run's JPY expenses;
      if the run has none, fall back to a rate stored on the run
      (add `Run.FxRateToPhp`, nullable) and **report which was used**. A profit figure
      whose exchange rate is invisible is not auditable.

- [ ] **3.** `warnings` is not decoration. Bought lines with no `ActualCostJpy` make
      COGS understate and profit overstate — the failure mode that flatters you. Name
      the count and link to the lines.

- [ ] **4.** Every figure is a string decimal, computed in SQL/`decimal`, never in
      JavaScript.

- [ ] **5.** Test with a hand-built fixture whose correct answer is worked out on
      paper: 3 orders, 2 payments, 1 refund, 4 bought lines, 2 expenses. Assert every
      field to the centavo.

- [ ] **6.** Commit.

**Done when:**
- [ ] The hand-computed fixture matches to the centavo
- [ ] A run with a missing `ActualCostJpy` produces a warning naming the count
- [ ] The FX rate used is visible in the response

---

## M6-03 · Run P&L screen

**Depends on:** M6-02
**Branch:** `feature/m6-pnl-ui`

**Files:**
- Create: `web/src/features/admin/reports/RunPnlPage.tsx`, `PnlWaterfall.tsx`

**Steps:**

- [ ] **1.** Headline: revenue, costs, profit, margin %. Profit in green or red — with
      a sign and a label too, never colour alone (Global Constraint: accessibility).

- [ ] **2.** A waterfall: revenue → COGS → expenses → profit. Plain SVG; no chart
      library for one chart.

- [ ] **3.** Every figure is a link to the rows behind it. Clicking COGS opens the
      lines with their `ActualCostJpy`. A report you cannot drill into is a report
      nobody trusts twice.

- [ ] **4.** Warnings shown at the top, in a panel, before the numbers — not below
      them where they will be scrolled past.

- [ ] **5.** Run-over-run comparison: this run against the previous three, as a small
      table.

- [ ] **6.** Commit.

**Done when:**
- [ ] Every headline figure drills through to its underlying rows
- [ ] Profit is legible in greyscale
- [ ] Warnings appear above the numbers

---

## M6-04 · Product margin report

**Depends on:** M6-02
**Branch:** `feature/m6-product-margin`

> Spec §9: `times unavailable` is worth as much as the margin column. A product that
> is repeatedly out of stock generates refunds and support work regardless of margin.

**Files:**
- Create: `Features/Reports/ProductMarginEndpoint.cs`,
  `web/src/features/admin/reports/ProductMarginPage.tsx`

**Steps:**

- [ ] **1.** `GET /api/admin/reports/products?from=&to=` (Admin), one row per product:

```
name | qty sold | qty unavailable | revenue PHP | cost PHP | margin PHP | margin % | times unavailable | last bought
```

- [ ] **2.** Sortable on every column. Default sort: margin % ascending — the losers
      first. A report that opens on your best sellers tells you nothing you did not
      already know.

- [ ] **3.** Flag rows with negative margin, and rows unavailable in more than 30% of
      runs they appeared in.

- [ ] **4.** Products with no `ActualCostJpy` on any line show margin as "unknown",
      **not zero**. Zero would read as break-even; unknown reads as missing data.

- [ ] **5.** CSV export.

- [ ] **6.** Test: a product bought at ¥500 (rate 0.38) and sold at ₱250 shows a
      margin of ₱60.00 and 24%.

- [ ] **7.** Commit.

**Done when:**
- [ ] The worked example matches to the centavo
- [ ] Unknown-cost products show "unknown", never 0
- [ ] Default sort surfaces loss-making products first

---

## M6-05 · Freight allocation

**Depends on:** M6-02, M5-04
**Branch:** `feature/m6-freight-allocation`

> Spec §11: allocated at report time by order value, not stored. Keep it that way.

**Files:**
- Create: `Features/Reports/FreightAllocation.cs`

**Steps:**

- [ ] **1.** For a shipment, apportion `CostPhp` across its orders in proportion to
      `ItemsTotalPhp`.

- [ ] **2.** **Distribute the rounding remainder** — do not let it vanish. Largest
      remainder to the largest order:

```csharp
var totalValue = orders.Sum(o => o.ItemsTotalPhp);
var shares = orders.ToDictionary(o => o.Id,
    o => decimal.Round(shipment.CostPhp * o.ItemsTotalPhp / totalValue, 2));
var drift = shipment.CostPhp - shares.Values.Sum();
if (drift != 0m) shares[orders.MaxBy(o => o.ItemsTotalPhp)!.Id] += drift;
// Post: shares.Values.Sum() == shipment.CostPhp, exactly.
```

- [ ] **3.** Assert the postcondition in code, not only in a test. A silent centavo
      leak across hundreds of orders is exactly the kind of error nobody finds.

- [ ] **4.** Show allocated freight on the admin order detail as "estimated shipping
      cost" — clearly a derived figure, not a charge.

- [ ] **5.** Test: ₱1,000 across three orders of ₱333.33 sums to exactly ₱1,000.00.

- [ ] **6.** Commit.

**Done when:**
- [ ] Allocations always sum to exactly the freight cost — property-tested over 100
      random splits
- [ ] A zero-value order does not divide by zero

---

## M6-06 · Finance dashboard

**Depends on:** M6-03, M6-04, M3-06
**Branch:** `feature/m6-dashboard`

**Files:**
- Create: `Features/Reports/DashboardEndpoint.cs`,
  `web/src/features/admin/reports/DashboardPage.tsx`

**Steps:**

- [ ] **1.** Admin landing page. Cards: current run status and value, payments awaiting
      verification, refunds pending, orders shipped over 14 days ago, reconciliation
      mismatches.

- [ ] **2.** Any non-zero reconciliation count is shown as an **alert**, not a stat
      tile. It means the books disagree with themselves.

- [ ] **3.** Last three runs' profit as a small bar chart, plain SVG.

- [ ] **4.** `GET /api/admin/reports/pnl?from=&to=` across runs, plus CSV export for
      the accountant.

- [ ] **5.** **Every card handles its own error state independently.** One failing
      query must not blank the dashboard, and must not render as zero — a dashboard
      showing ₱0 profit because a query failed is the exact failure Global Constraint 9
      exists to prevent.

- [ ] **6.** Commit.

**Done when:**
- [ ] Breaking one endpoint leaves the other cards working and shows an error on that
      card only
- [ ] No card ever displays 0 when its data failed to load
- [ ] CSV opens cleanly in Excel with correct decimal separators

---

## Milestone exit

- [ ] A completed run shows a P&L that the team agrees matches reality, checked
      against their own notes
- [ ] The product margin report has changed at least one buying decision
- [ ] Reconciliation shows zero mismatches
- [ ] Freight allocations sum exactly
