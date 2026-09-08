# Pajapan — task index

Start here. **One task per session** — a session carrying the spec, three plan files
and a pile of source pays for all of it on every subsequent turn.

- **Spec:** [`docs/specs/2026-08-28-pasabuy-design.md`](../docs/specs/2026-08-28-pasabuy-design.md)
- **Plan:** [`docs/plan/README.md`](../docs/plan/README.md) — global constraints, repo
  layout, testing policy. Read once, then keep to hand.
- **Issues:** <https://github.com/Agile-Porkchops/pajapan/issues> — each issue carries its full instructions inline
- **Board:** <https://github.com/Agile-Porkchops/pajapan/projects> — Priority, Size, Status, grouped by milestone

Every task below maps to one GitHub issue and one branch. **The issue body carries the
full instructions** — steps, code and the Done-when checklist — generated from the plan
file by `scripts/sync-issue-bodies.ps1`. Edit the plan file and re-run the script; never
hand-edit an issue body.

---

> ## ⚠ Architecture pivoted 2026-09-08
>
> Pajapan dropped the custom C# Minimal API for **Supabase-native** access: RLS
> policies plus Postgres `SECURITY DEFINER` functions, no backend server. See
> [`docs/plan/README.md`](../docs/plan/README.md) and spec §5.
>
> **M0-03 and M0-04 are superseded** and their issues stay closed. M0-01, M0-02, M0-06
> and M0-07 are partly reworked. **M0-08, M0-09 and M0-10 are new.**
>
> **M1–M7 have had their structural notes rewritten, not their detailed steps.** Each
> plan file says what its tasks become under RLS/RPC and what the requirements are; the
> step-by-step SQL is written milestone-by-milestone, at implementation time, against a
> running database. Fifty tasks of confident untested SQL was rejected as worse than
> none. **Expect to write the detail as you start each task** — that is the plan, not a
> gap in it.

---

## Progress

| Milestone | Tasks | Est. | Status |
|---|---|---|---|
| [M0 — Foundations](../docs/plan/M0-foundations.md) | 10 | 3–4d | 🟨 In progress — 4 done, 2 superseded, 1 rework, 3 new |
| [M1 — Catalog](../docs/plan/M1-catalog.md) | 7 | 4–5d | ⬜ Not started |
| [M2 — Storefront & orders](../docs/plan/M2-storefront-orders.md) | 9 | 5–6d | ⬜ Not started |
| [M3 — Payments](../docs/plan/M3-payments.md) | 6 | 3–4d | ⬜ Not started |
| [M4 — Runs & procurement](../docs/plan/M4-runs-procurement.md) | 8 | 5–6d | ⬜ Not started |
| [M5 — Shipping](../docs/plan/M5-shipping.md) | 6 | 4–5d | ⬜ Not started |
| [M6 — Finance](../docs/plan/M6-finance.md) | 6 | 4–5d | ⬜ Not started |
| [M7 — Hardening & launch](../docs/plan/M7-hardening.md) | 8 | 4–5d | ⬜ Not started |
| **Total** | **60** | **~33–40d** | |

---

## Which model for which task

Following the workspace convention in `../../CLAUDE.md`.

**Opus 5 — judgment, security, and anything where being plausibly wrong is expensive.**
These eleven are where a cheaper model wires something up plausibly and wrongly, and
where the error is silent:

| Task | Why |
|---|---|
| M0-09 · RLS foundation | Replaces M0-04 as the milestone's riskiest. Every later policy copies this pattern, including the recursion and `search_path` traps. |
| M1-01 · Full schema + RLS | Money precision, unique indexes, check constraints, **and twelve tables' policies**. Wrong here is wrong in every report forever. |
| M2-06 · Place order | Server-side pricing, idempotency under concurrency, address snapshotting. The money path. |
| M3-03 · Verification queue | Decides when money counts. Double-verify must not double-count. |
| M3-06 · Reconciliation | The check that makes the denormalised cache safe. |
| M4-05 · Mark lines | Captures `actual_cost_jpy`. Silently defaulting it to zero flatters every margin report. |
| M4-06 · Refunds | Money out. Over-refund guard. |
| M6-02 · Run P&L | The number the business acts on. An invisible FX rate makes it unauditable. |
| M6-05 · Freight allocation | Rounding remainder distribution. A centavo leak nobody finds — and the rounding mode differs from the C# original. |
| M7-01 · Security pass | The whole point is adversarial thinking, against a boundary that is now entirely in the database. |
| M7-07 · Dry run | Parity judgment on real money. |

**Sonnet 5 — transcription and assembly against a written spec.** Everything else: the
UI screens, the RLS policies that follow M1-01's established pattern, the responsive and
PWA work. Use `/effort low` or `medium`.

> **One caveat the pivot adds.** The plan files no longer carry copy-this-verbatim code
> for the database tasks — that was the thing making them safe for a cheaper model. A
> task marked Sonnet that turns out to need *designed* SQL rather than
> pattern-following SQL should be escalated. The `Done when` lists are the detector.

**Do not use Haiku 4.5** on M1-01, M2-06 or M6-02 — those need the spec and several
files in context at once.

---

## Task list

Legend: 🔴 high-risk (Opus, review carefully) · ✓ done · ✗ superseded · ◐ rework ·
⬜ not started

### M0 — Foundations

| # | Task | Depends on | Risk | Status |
|---|---|---|---|---|
| M0-01 | Repository scaffolding | — | | ◐ .NET parts retired |
| M0-02 | Supabase project and configuration | M0-01 | | ◐ config shape changed |
| M0-03 | EF Core, DbContext, first migration | M0-02 | | ✗ superseded by M0-08/09 |
| M0-04 | JWT validation and CurrentUser | M0-03 | 🔴 | ✗ superseded — `supabase-js` |
| M0-05 | React application scaffold | M0-01 | | ✓ minus `apiClient.ts` |
| M0-06 | Login end to end | M0-05 | | ◐ its no-`.from()` guard is now backwards |
| M0-07 | CI and deployment | M0-06 | | ◐ CI merged, deploy re-scoped |
| M0-08 | Supabase CLI and local stack | M0-02 | | ⬜ new |
| M0-09 | RLS foundation and structural guards | M0-08 | 🔴 | ⬜ new |
| M0-10 | Rewire web to Supabase-native | M0-09 | | ⬜ new |

### M1 — Catalog and admin entry

| # | Task | Depends on | Risk |
|---|---|---|---|
| M1-01 | Full schema migration | M0-09 | 🔴 |
| M1-02 | Category CRUD | M1-01 | |
| M1-03 | Product CRUD | M1-02 | |
| M1-04 | Storage upload policies | M0-09 | |
| M1-05 | Admin product list | M1-03, M0-10 | |
| M1-06 | Admin product form | M1-05, M1-04 | |
| M1-07 | Catalog seed and photo integrity | M1-06 | |

### M2 — Storefront, cart and orders

| # | Task | Depends on | Risk |
|---|---|---|---|
| M2-01 | Public catalog view | M1-03 | |
| M2-02 | Catalog browse UI | M2-01 | |
| M2-03 | Product detail | M2-02 | |
| M2-04 | Cart | M2-03 | |
| M2-05 | Addresses | M1-01, M0-10 | |
| M2-06 | Place order | M2-04, M2-05 | 🔴 |
| M2-07 | Checkout UI | M2-06 | |
| M2-08 | Customer order list and detail | M2-06 | |
| M2-09 | Custom requests | M2-08, M1-03 | |

### M3 — Payments

| # | Task | Depends on | Risk |
|---|---|---|---|
| M3-01 | Submit payment proof | M2-06, M1-04 | |
| M3-02 | Payment instructions UI | M3-01 | |
| M3-03 | Verification queue | M3-01 | 🔴 |
| M3-04 | Verification queue UI | M3-03 | |
| M3-05 | Balance and partial payments | M3-03 | |
| M3-06 | Reconciliation check | M3-05 | 🔴 |

### M4 — Runs and procurement

| # | Task | Depends on | Risk |
|---|---|---|---|
| M4-01 | Run lifecycle | M1-01 | |
| M4-02 | Run admin UI | M4-01 | |
| M4-03 | Shopping list function | M4-01, M3-03 | |
| M4-04 | Shopping list UI | M4-03 | |
| M4-05 | Mark lines bought or unavailable | M4-04 | 🔴 |
| M4-06 | Refunds | M4-05, M3-03 | 🔴 |
| M4-07 | Expense capture | M1-01 | |
| M4-08 | Run cutoff enforcement and notices | M4-02, M4-06 | |

### M5 — Shipping and tracking

| # | Task | Depends on | Risk |
|---|---|---|---|
| M5-01 | Couriers | M1-01 | |
| M5-02 | Shipments | M5-01, M4-05 | |
| M5-03 | Packing UI | M5-02 | |
| M5-04 | Tracking entry | M5-03 | |
| M5-05 | Customer tracking view | M5-04 | |
| M5-06 | Delivery confirmation | M5-05 | |

### M6 — Finance and reporting

| # | Task | Depends on | Risk |
|---|---|---|---|
| M6-01 | Expense management | M4-07 | |
| M6-02 | Run profit and loss | M3-06, M4-05, M5-04 | 🔴 |
| M6-03 | Run P&L screen | M6-02 | |
| M6-04 | Product margin report | M6-02 | |
| M6-05 | Freight allocation | M6-02, M5-04 | 🔴 |
| M6-06 | Finance dashboard | M6-03, M6-04, M3-06 | |

### M7 — Hardening and launch

| # | Task | Depends on | Risk |
|---|---|---|---|
| M7-01 | Cross-tenant security pass | M2–M6 | 🔴 |
| M7-02 | Failure-state audit | M6-06 | |
| M7-03 | Responsive pass | M7-02 | |
| M7-04 | Accessibility pass | M7-03 | |
| M7-05 | PWA and offline behaviour | M7-03 | |
| M7-06 | Backups and restore drill | M0-07 | |
| M7-07 | Dry run on real data | M7-01…M7-06 | 🔴 |
| M7-08 | Launch | M7-07 | |

---

## The shortest useful path

If you want something real in front of customers before building everything:

**M0 → M1 → M2 → M3 → M4** gets you a working pre-order business. Orders are taken,
paid, bought and refunded. Shipping is tracked in WhatsApp for one run while you build
M5, and profit is worked out in a spreadsheet while you build M6.

M5 and M6 are the ones that stop it being a spreadsheet business. M7 is the one that
stops it being an embarrassing one. None of them are optional; they are just later.
