<#
.SYNOPSIS
    Creates the Pajapan labels, milestones, 57 issues and the org Project board.

.DESCRIPTION
    Idempotent-ish: labels and milestones are created only if missing. Issues are
    matched by their "M0-01 · " title prefix and skipped if one already exists, so a
    re-run tops up rather than duplicating.

    Requires: gh CLI authenticated with 'repo' and 'project' scopes.

.EXAMPLE
    pwsh ./scripts/create-github-board.ps1
    pwsh ./scripts/create-github-board.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Owner       = 'Agile-Porkchops',
    [string]$Repo        = 'Agile-Porkchops/pajapan',
    [string]$ProjectName = 'Pajapan'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- labels --
$labels = @(
    @{ name = 'area:api';      color = '1d76db'; desc = 'ASP.NET Core API' }
    @{ name = 'area:web';      color = '5319e7'; desc = 'React frontend' }
    @{ name = 'area:db';       color = '0e8a16'; desc = 'Schema, EF Core, migrations' }
    @{ name = 'area:infra';    color = '5a5a5a'; desc = 'CI, hosting, deployment' }
    @{ name = 'area:security'; color = 'b60205'; desc = 'Auth, scoping, authorization' }
    @{ name = 'area:money';    color = 'd93f0b'; desc = 'Pricing, payments, refunds, reporting' }
    @{ name = 'risk:high';     color = 'b60205'; desc = 'Plausibly-wrong is expensive. Use Opus. Review carefully.' }
    @{ name = 'model:opus';    color = 'fbca04'; desc = 'Judgment or security work' }
    @{ name = 'model:sonnet';  color = 'c2e0c6'; desc = 'Transcription against a written spec' }
)

# ------------------------------------------------------------ milestones --
$milestones = @(
    @{ n = 'M0 — Foundations';              d = 'Auth, migrations and deployment working end to end.' }
    @{ n = 'M1 — Catalog';                  d = 'Products listed from a phone in a Japanese shop.' }
    @{ n = 'M2 — Storefront & orders';      d = 'Browse, cart, place an order, custom requests.' }
    @{ n = 'M3 — Payments';                 d = 'Manual proof-of-payment submitted and verified.' }
    @{ n = 'M4 — Runs & procurement';       d = 'Cutoff, shopping list, bought/unavailable, refunds.' }
    @{ n = 'M5 — Shipping';                 d = 'Consolidate, ship, track both legs.' }
    @{ n = 'M6 — Finance';                  d = 'Run P&L and per-product margin.' }
    @{ n = 'M7 — Hardening & launch';       d = 'Security, failure states, a11y, dry run, launch.' }
)

# ----------------------------------------------------------------- tasks --
# id | title | milestone index | plan file | anchor | depends | labels | goal
$tasks = @(
  @{ id='M0-01'; t='Repository scaffolding';               m=0; f='M0-foundations';      dep='—';                   l='area:infra,model:sonnet';                  g='Solution, SDK pin, warnings-as-errors, gitignore.' }
  @{ id='M0-02'; t='Supabase project and configuration';   m=0; f='M0-foundations';      dep='M0-01';               l='area:infra,area:security,model:sonnet';    g='Two Supabase projects, asymmetric JWT keys, private buckets, placeholder config with a startup guard.' }
  @{ id='M0-03'; t='EF Core, DbContext, first migration';  m=0; f='M0-foundations';      dep='M0-02';               l='area:db,model:sonnet';                     g='DbContext with a global decimal(12,2) convention and snake_case mapping; Testcontainers fixture.' }
  @{ id='M0-04'; t='JWT validation and CurrentUser';       m=0; f='M0-foundations';      dep='M0-03';               l='area:security,area:api,risk:high,model:opus'; g='Validate Supabase JWTs against JWKS. Role comes from our table, never the token.' }
  @{ id='M0-05'; t='React application scaffold';           m=0; f='M0-foundations';      dep='M0-01';               l='area:web,model:sonnet';                    g='Vite, TS, Tailwind, Query, router, and the decimal-safe money helpers.' }
  @{ id='M0-06'; t='Login end to end';                     m=0; f='M0-foundations';      dep='M0-04, M0-05';        l='area:web,area:security,model:sonnet';      g='Sign up, get a JWT, hit /api/me, render by role. CI guard that web never queries Supabase directly.' }
  @{ id='M0-07'; t='CI and deployment';                    m=0; f='M0-foundations';      dep='M0-06';               l='area:infra,model:sonnet';                  g='CI with secret-scanning greps; staging deploy; migrations run from CI; a health check that touches the DB.' }

  @{ id='M1-01'; t='Full schema migration';                m=1; f='M1-catalog';          dep='M0-03';               l='area:db,area:money,risk:high,model:opus';  g='All 14 tables in one migration. Money precision, unique indexes, check constraints, soft-delete filters.' }
  @{ id='M1-02'; t='Category CRUD';                        m=1; f='M1-catalog';          dep='M1-01';               l='area:api,model:sonnet';                    g='Public read, admin write. Immutable slugs. 409 rather than cascade on delete.' }
  @{ id='M1-03'; t='Product CRUD';                         m=1; f='M1-catalog';          dep='M1-02';               l='area:api,area:money,model:sonnet';         g='Admin product endpoints. Only Admin sets PricePhp. Money serialised as strings.' }
  @{ id='M1-04'; t='Signed upload URLs';                   m=1; f='M1-catalog';          dep='M0-04';               l='area:api,area:security,model:sonnet';      g='Server generates the storage path and enforces a purpose/role/MIME allowlist. Bytes never touch the API.' }
  @{ id='M1-05'; t='Admin product list';                   m=1; f='M1-catalog';          dep='M1-03, M0-06';        l='area:web,model:sonnet';                    g='Product table with search and filters. Builds the shared DataState component used by every later list.' }
  @{ id='M1-06'; t='Admin product form';                   m=1; f='M1-catalog';          dep='M1-05, M1-04';        l='area:web,model:sonnet';                    g='Mobile-first entry with native camera capture and client-side WebP resize. Used one-handed in a shop aisle.' }
  @{ id='M1-07'; t='Catalog seed and photo integrity';     m=1; f='M1-catalog';          dep='M1-06';               l='area:api,model:sonnet';                    g='Dev seed that refuses production, and Storage cleanup so deleted photos leave no orphans.' }

  @{ id='M2-01'; t='Public catalog API';                   m=2; f='M2-storefront-orders'; dep='M1-03';              l='area:api,model:sonnet';                    g='Anonymous catalog. A separate DTO so cost price and supplier never leak.' }
  @{ id='M2-02'; t='Catalog browse UI';                    m=2; f='M2-storefront-orders'; dep='M2-01';              l='area:web,model:sonnet';                    g='Responsive grid and a run banner with a Manila-time countdown to the JST cutoff.' }
  @{ id='M2-03'; t='Product detail';                       m=2; f='M2-storefront-orders'; dep='M2-02';              l='area:web,model:sonnet';                    g='Gallery, quantity, and a prominent pre-order and refund notice.' }
  @{ id='M2-04'; t='Cart';                                 m=2; f='M2-storefront-orders'; dep='M2-03';              l='area:web,area:money,model:sonnet';         g='localStorage cart holding ids and quantities only — never a price. Totals in bigint centavos.' }
  @{ id='M2-05'; t='Addresses';                            m=2; f='M2-storefront-orders'; dep='M1-01, M0-06';       l='area:api,area:web,area:security,model:sonnet'; g='PH address book scoped to the caller. Another customer gets 404, not 403.' }
  @{ id='M2-06'; t='Place order';                          m=2; f='M2-storefront-orders'; dep='M2-04, M2-05';       l='area:api,area:money,risk:high,model:opus'; g='THE money endpoint. Server-side pricing, idempotency under concurrency, address snapshotting.' }
  @{ id='M2-07'; t='Checkout UI';                          m=2; f='M2-storefront-orders'; dep='M2-06';              l='area:web,model:sonnet';                    g='Idempotency key generated on mount, not per submit. Double-tap produces one order.' }
  @{ id='M2-08'; t='Customer order list and detail';       m=2; f='M2-storefront-orders'; dep='M2-06';              l='area:web,area:api,model:sonnet';           g='Own orders only. Per-line status in plain language.' }
  @{ id='M2-09'; t='Custom requests';                      m=2; f='M2-storefront-orders'; dep='M2-08, M1-03';       l='area:api,area:web,model:sonnet';           g='Submit, quote, accept. Accepting creates a hidden product and reuses the normal cart path.' }

  @{ id='M3-01'; t='Submit payment proof';                 m=3; f='M3-payments';         dep='M2-06, M1-04';        l='area:api,area:money,model:sonnet';         g='GCash screenshot and reference. Duplicate reference is a clean 409, not a 500.' }
  @{ id='M3-02'; t='Payment instructions UI';              m=3; f='M3-payments';         dep='M3-01';               l='area:web,model:sonnet';                    g='Copyable amount and account details, proof upload, honest verification timeframe.' }
  @{ id='M3-03'; t='Verification queue API';               m=3; f='M3-payments';         dep='M3-01';               l='area:api,area:money,risk:high,model:opus'; g='Verify/reject. The single place order totals are recomputed. Double-verify must not double-count.' }
  @{ id='M3-04'; t='Verification queue UI';                m=3; f='M3-payments';         dep='M3-03';               l='area:web,model:sonnet';                    g='Queue with a zoomable proof viewer and an amount-mismatch warning before verifying.' }
  @{ id='M3-05'; t='Balance and partial payments';         m=3; f='M3-payments';         dep='M3-03';               l='area:api,area:money,model:sonnet';         g='Server-computed balance due. Fee edits refused once confirmed. Overpaid is a visible state.' }
  @{ id='M3-06'; t='Reconciliation check';                 m=3; f='M3-payments';         dep='M3-05';               l='area:money,risk:high,model:opus';          g='The check that makes the denormalised totals safe. Per-order repair, never a silent sweep.' }

  @{ id='M4-01'; t='Run lifecycle API';                    m=4; f='M4-runs-procurement'; dep='M1-01';               l='area:api,model:sonnet';                    g='State machine declared as data. At most one Open run, enforced by a partial unique index.' }
  @{ id='M4-02'; t='Run admin UI';                         m=4; f='M4-runs-procurement'; dep='M4-01';               l='area:web,model:sonnet';                    g='Status stepper. Cutoff entered in JST. Closing warns about the unpaid orders it strands.' }
  @{ id='M4-03'; t='Shopping list API';                    m=4; f='M4-runs-procurement'; dep='M4-01, M3-03';        l='area:api,model:sonnet';                    g='A GROUP BY, not a table. Confirmed orders only. No customer contact data in the response.' }
  @{ id='M4-04'; t='Shopping list UI';                     m=4; f='M4-runs-procurement'; dep='M4-03';               l='area:web,model:sonnet';                    g='One-handed, in a crowded shop, on Japanese mobile data. 56px targets, wake lock, optimistic marking.' }
  @{ id='M4-05'; t='Mark lines bought or unavailable';     m=4; f='M4-runs-procurement'; dep='M4-04';               l='area:api,area:money,risk:high,model:opus'; g='Captures ActualCostJpy — half of every margin figure. Bought with no cost is refused, never defaulted to zero.' }
  @{ id='M4-06'; t='Refunds';                              m=4; f='M4-runs-procurement'; dep='M4-05, M3-03';        l='area:api,area:money,risk:high,model:opus'; g='Unavailable raises an obligation; a human moves the money and records proof. Over-refund refused.' }
  @{ id='M4-07'; t='Expense capture';                      m=4; f='M4-runs-procurement'; dep='M1-01';               l='area:api,area:web,area:money,model:sonnet'; g='JPY expenses store the FX rate used and the resulting PHP amount. Never recomputed later.' }
  @{ id='M4-08'; t='Run cutoff automation and notices';    m=4; f='M4-runs-procurement'; dep='M4-02, M4-06';        l='area:api,area:web,model:sonnet';           g='The clock is authoritative, not the status column. Dashboard nudge replaces a scheduled job.' }

  @{ id='M5-01'; t='Couriers';                             m=5; f='M5-shipping';         dep='M1-01';               l='area:api,model:sonnet';                    g='Seed J&T, LBC, Flash, EMS, Yamato with verified tracking URL templates.' }
  @{ id='M5-02'; t='Shipments API';                        m=5; f='M5-shipping';         dep='M5-01, M4-05';        l='area:api,model:sonnet';                    g='One table, two legs. Assignment rules, declared value defaulting, transactional dispatch.' }
  @{ id='M5-03'; t='Packing UI';                           m=5; f='M5-shipping';         dep='M5-02';               l='area:web,model:sonnet';                    g='Assign orders to a box with running weight and value. De-minimis warning at ₱10,000. Printable packing list.' }
  @{ id='M5-04'; t='Tracking entry';                       m=5; f='M5-shipping';         dep='M5-03';               l='area:web,area:money,model:sonnet';         g='Tracking numbers with bulk paste. Freight cost becomes a run expense without double entry.' }
  @{ id='M5-05'; t='Customer tracking view';               m=5; f='M5-shipping';         dep='M5-04';               l='area:web,area:security,model:sonnet';      g='Both legs on a timeline. Nothing about the box other customers share is exposed.' }
  @{ id='M5-06'; t='Delivery confirmation';                m=5; f='M5-shipping';         dep='M5-05';               l='area:api,area:web,model:sonnet';           g='Bulk mark delivered, and a stale-shipment list to chase couriers. Runs never auto-complete.' }

  @{ id='M6-01'; t='Expense management';                   m=6; f='M6-finance';          dep='M4-07';               l='area:web,area:money,model:sonnet';         g='Filterable expense table with category totals and CSV export. Amount edits go through the full form.' }
  @{ id='M6-02'; t='Run profit and loss';                  m=6; f='M6-finance';          dep='M3-06, M4-05, M5-04'; l='area:money,risk:high,model:opus';          g='The number the business acts on. The FX rate used must be visible. Missing costs surface as warnings.' }
  @{ id='M6-03'; t='Run P&L screen';                       m=6; f='M6-finance';          dep='M6-02';               l='area:web,model:sonnet';                    g='Waterfall and headline figures, every one of them drillable to the rows behind it.' }
  @{ id='M6-04'; t='Product margin report';                m=6; f='M6-finance';          dep='M6-02';               l='area:money,area:web,model:sonnet';         g='Per-product margin plus times-unavailable. Sorted worst-first. Unknown cost shows unknown, never zero.' }
  @{ id='M6-05'; t='Freight allocation';                   m=6; f='M6-finance';          dep='M6-02, M5-04';        l='area:money,risk:high,model:opus';          g='Apportion by order value with the rounding remainder distributed. Allocations must sum exactly.' }
  @{ id='M6-06'; t='Finance dashboard';                    m=6; f='M6-finance';          dep='M6-03, M6-04, M3-06'; l='area:web,model:sonnet';                    g='Admin landing page. Every card fails independently and never renders zero on error.' }

  @{ id='M7-01'; t='Cross-tenant security pass';           m=7; f='M7-hardening';        dep='M2–M6';               l='area:security,risk:high,model:opus';       g='Adversarial tests across every scoped endpoint, plus a route-enumeration test that catches future unprotected endpoints.' }
  @{ id='M7-02'; t='Failure-state audit';                  m=7; f='M7-hardening';        dep='M6-06';               l='area:web,area:api,model:sonnet';           g='Sweep for silent catches. Every screen checked with the API down, erroring, and empty.' }
  @{ id='M7-03'; t='Responsive pass';                      m=7; f='M7-hardening';        dep='M7-02';               l='area:web,model:sonnet';                    g='390/768/1024/1440. The four phone-critical screens tested on real hardware.' }
  @{ id='M7-04'; t='Accessibility pass';                   m=7; f='M7-hardening';        dep='M7-03';               l='area:web,model:sonnet';                    g='Keyboard, focus, measured contrast, no colour-only meaning, axe clean.' }
  @{ id='M7-05'; t='PWA and offline behaviour';            m=7; f='M7-hardening';        dep='M7-03';               l='area:web,model:sonnet';                    g='Installable, app-shell caching only. Never serve a cached price.' }
  @{ id='M7-06'; t='Backups and restore drill';            m=7; f='M7-hardening';        dep='M0-07';               l='area:infra,model:sonnet';                  g='Perform an actual restore and time it. Document the Storage backup position either way.' }
  @{ id='M7-07'; t='Dry run on real data';                 m=7; f='M7-hardening';        dep='M7-01…M7-06';         l='area:infra,area:money,model:opus';         g='Full cycle with the whole team in their real roles. P&L checked against a hand-worked figure.' }
  @{ id='M7-08'; t='Launch';                               m=7; f='M7-hardening';        dep='M7-07';               l='area:infra,model:sonnet';                  g='Production project, real accounts, refund policy published, invite-only first run.' }
)

function Get-Anchor([string]$id, [string]$title) {
    # GitHub slug for "## M2-06 · Place order" -> "m2-06--place-order"
    $s = "$id · $title".ToLowerInvariant()
    $s = ($s -replace '[^\p{L}\p{Nd} -]', '') -replace ' ', '-'
    return $s
}

Write-Host "== labels ==" -ForegroundColor Cyan
$existingLabels = (gh label list --repo $Repo --limit 100 --json name | ConvertFrom-Json).name
foreach ($l in $labels) {
    if ($existingLabels -contains $l.name) { Write-Host "  = $($l.name)"; continue }
    if ($PSCmdlet.ShouldProcess($l.name, 'create label')) {
        gh label create $l.name --repo $Repo --color $l.color --description $l.desc | Out-Null
        Write-Host "  + $($l.name)" -ForegroundColor Green
    }
}

Write-Host "== milestones ==" -ForegroundColor Cyan
$existingMs = (gh api "repos/$Repo/milestones?state=all" --jq '.[].title') -split "`n"
$msNumbers = @{}
for ($i = 0; $i -lt $milestones.Count; $i++) {
    $m = $milestones[$i]
    if ($existingMs -contains $m.n) {
        $msNumbers[$i] = gh api "repos/$Repo/milestones?state=all" --jq ".[] | select(.title==`"$($m.n)`") | .number"
        Write-Host "  = $($m.n)"
        continue
    }
    if ($PSCmdlet.ShouldProcess($m.n, 'create milestone')) {
        $msNumbers[$i] = gh api "repos/$Repo/milestones" -f title="$($m.n)" -f description="$($m.d)" --jq '.number'
        Write-Host "  + $($m.n)" -ForegroundColor Green
    }
}

Write-Host "== issues ==" -ForegroundColor Cyan
$existingIssues = (gh issue list --repo $Repo --limit 200 --state all --json title | ConvertFrom-Json).title
$created = @()
foreach ($t in $tasks) {
    $title = "$($t.id) · $($t.t)"
    if ($existingIssues | Where-Object { $_ -like "$($t.id) *" }) { Write-Host "  = $title"; continue }

    $anchor    = Get-Anchor $t.id $t.t
    $planPath  = "docs/plan/$($t.f).md"
    $risk      = if ($t.l -like '*risk:high*') {
        "`n> **High risk.** Being plausibly wrong here is expensive and often silent. Use Opus, and get a second reviewer on the PR.`n"
    } else { '' }

    $body = @"
$($t.g)
$risk
**Instructions:** [``$planPath``](https://github.com/$Repo/blob/main/$planPath#$anchor) — the full steps, code and *Done when* checklist live there. Work from the plan file, not from this issue body.

**Depends on:** $($t.dep)
**Branch:** ``feature/$($t.id.ToLower())-<slug>``

---

Before opening the PR:

- [ ] Every *Done when* item in the plan section verified by **running it**, not by reading the code
- [ ] Global constraints hold — see [``docs/plan/README.md``](https://github.com/$Repo/blob/main/docs/plan/README.md#global-constraints)
- [ ] No secret, connection string or real customer data in the diff
- [ ] Build clean, tests pass
- [ ] PR description follows the template in ``CLAUDE.md``
"@

    if ($PSCmdlet.ShouldProcess($title, 'create issue')) {
        $url = gh issue create --repo $Repo --title $title --body $body `
                   --label $t.l --milestone $milestones[$t.m].n
        $created += $url
        Write-Host "  + $title" -ForegroundColor Green
    }
}

Write-Host "== project ==" -ForegroundColor Cyan
$proj = gh project list --owner $Owner --format json | ConvertFrom-Json |
        Select-Object -ExpandProperty projects |
        Where-Object { $_.title -eq $ProjectName } | Select-Object -First 1

if (-not $proj) {
    if ($PSCmdlet.ShouldProcess($ProjectName, 'create project')) {
        $proj = gh project create --owner $Owner --title $ProjectName --format json | ConvertFrom-Json
        Write-Host "  + project $ProjectName (#$($proj.number))" -ForegroundColor Green
    }
} else {
    Write-Host "  = project $ProjectName (#$($proj.number))"
}

if ($proj) {
    $all = gh issue list --repo $Repo --limit 200 --state all --json url | ConvertFrom-Json
    foreach ($i in $all) {
        gh project item-add $proj.number --owner $Owner --url $i.url 2>$null | Out-Null
    }
    Write-Host "  added $($all.Count) issues to the board" -ForegroundColor Green
}

Write-Host "`nDone. Board: https://github.com/orgs/$Owner/projects" -ForegroundColor Cyan
