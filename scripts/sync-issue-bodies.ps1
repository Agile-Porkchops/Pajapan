<#
.SYNOPSIS
    Writes the full task instructions from docs/plan/*.md into each GitHub issue body.

.DESCRIPTION
    Each issue carries its complete instructions — steps, code, and the Done-when
    checklist — so nobody has to leave the issue to work the task.

    The plan files stay the source of truth. Edit a plan file, re-run this, and the
    issues catch up. Never hand-edit an issue body: the next run overwrites it.

.EXAMPLE
    pwsh ./scripts/sync-issue-bodies.ps1
    pwsh ./scripts/sync-issue-bodies.ps1 -Only M2-06
    pwsh ./scripts/sync-issue-bodies.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repo    = 'Agile-Porkchops/pajapan',
    [string]$PlanDir = 'docs/plan',
    [string]$Only                       # e.g. 'M2-06' to sync one issue
)

$ErrorActionPreference = 'Stop'
$blob = "https://github.com/$Repo/blob/main"

# Shared rules appended to every issue so each one stands alone.
$constraints = @'
## Global constraints

These apply to every task. Copied from `docs/plan/README.md`.

**Money**
1. All money is `decimal` — C# `decimal`, Postgres `numeric(12,2)`. Never `float`, `double`, `real`, or JS `number` arithmetic on money. Money crosses the wire as a JSON string.
2. Every monetary field names its currency: `AmountPhp`, `ActualCostJpy`. No bare `Amount` anywhere.
3. FX rates are recorded at the moment of use, never looked up at report time.
4. **Prices come from the server.** A request body containing a price is ignored. The client sends `productId` + `qty`.

**Data**

5. Snapshot on write: order lines snapshot product name + price; orders snapshot the full shipping address. Editing a product must never change a past order.
6. Timestamps are `timestamptz`, stored UTC. Run cutoffs are authored/displayed in JST; customer-facing times display Asia/Manila.
7. Soft delete (`DeletedAt`) on anything money touches. Hard delete only on draft catalog entries.

**Correctness**

8. `POST /api/orders` and `POST /api/orders/{id}/payments` require an `Idempotency-Key` header. Double submission produces one record. No automatic retry on any write path.
9. **No silent `catch`.** A screen that cannot load its data says so — it never renders zeros, an empty list, or an all-clear. `catch { }` and `catch { return []; }` fail review.

**Security**

10. `CustomerId` comes from the JWT `sub` claim only. Never from a body, query string, route parameter, or header.
11. Another customer's resource returns `404`, not `403`.
12. Route identifiers are UUIDs. `OrderCode` is displayed but never the lookup key on a customer endpoint.
13. The Supabase service key lives only in the API environment. Never in `web/`, never in a `VITE_*` variable, never committed.

**Process**

14. Branch per task. Never commit to `main`.
15. Conventional commits: `feat:`, `fix:`, `test:`, `chore:`, `docs:`.
16. Verify every **Done when** item by running it — not by reading the code and concluding it should work.

## Versions

.NET SDK 10.0.400 (use `& "C:\Program Files\dotnet\dotnet.exe"` — `dotnet` on PATH is runtime-only) · Node 22 LTS · EF Core 10 + Npgsql · React 19 · Vite 7 · Postgres 17
'@

function Convert-Links([string]$md) {
    # Relative links work in the repo but not in an issue body. Make them absolute.
    $md = $md -replace '\]\(README\.md',              "]($blob/$PlanDir/README.md"
    $md = $md -replace '\]\((M\d-[a-z-]+\.md)',       "]($blob/$PlanDir/`$1"
    $md = $md -replace '\]\(\.\./specs/',             "]($blob/docs/specs/"
    $md = $md -replace '\]\(\.\./\.\./CLAUDE\.md\)',  "]($blob/CLAUDE.md)"
    $md = $md -replace '\]\(\.\./plan/',              "]($blob/$PlanDir/"
    return $md
}

$planFiles = Get-ChildItem -Path $PlanDir -Filter 'M?-*.md' | Sort-Object Name
if (-not $planFiles) { throw "No plan files found in $PlanDir" }

# Map task id -> issue number
$issues = gh issue list --repo $Repo --limit 200 --state all --json number,title | ConvertFrom-Json
$byId = @{}
foreach ($i in $issues) { $byId[($i.title -split ' ')[0]] = $i.number }

$synced = 0; $skipped = 0
foreach ($file in $planFiles) {
    $text = Get-Content $file.FullName -Raw

    # Split into "## " sections, keeping the heading with its body.
    $sections = [regex]::Split($text, '(?m)^## ') | Select-Object -Skip 1

    foreach ($sec in $sections) {
        $head = ($sec -split "`n", 2)[0].Trim()
        if ($head -notmatch '^(M\d-\d\d)\s') { continue }        # skip "Milestone exit" etc.
        $id = $Matches[1]
        if ($Only -and $id -ne $Only) { continue }

        if (-not $byId.ContainsKey($id)) {
            Write-Warning "  no issue found for $id"; $skipped++; continue
        }

        # Body = everything after the heading line, trimmed of the trailing rule.
        $body = ($sec -split "`n", 2)[1].TrimEnd()
        $body = $body -replace '(?m)^---\s*$', ''                # drop section rules
        $body = Convert-Links $body.Trim()

        $full = @"
> Generated from [``$PlanDir/$($file.Name)``]($blob/$PlanDir/$($file.Name)) by ``scripts/sync-issue-bodies.ps1``.
> Edit the plan file and re-run the script — do not hand-edit this body, it gets overwritten.

$body

---

$constraints

---

## Before opening the PR

- [ ] Every **Done when** item above verified by running it
- [ ] Global constraints hold
- [ ] No secret, connection string or real customer data in the diff
- [ ] Build clean, no new warnings, tests pass
- [ ] Branch is ``feature/...``, not ``main``
"@

        if ($PSCmdlet.ShouldProcess("#$($byId[$id]) $id", 'update issue body')) {
            $tmp = New-TemporaryFile
            Set-Content -Path $tmp -Value $full -Encoding utf8
            gh issue edit $byId[$id] --repo $Repo --body-file $tmp | Out-Null
            Remove-Item $tmp
            Write-Host ("  + #{0,-3} {1}  ({2:n0} chars)" -f $byId[$id], $id, $full.Length) -ForegroundColor Green
            $synced++
        }
    }
}

Write-Host "`nsynced $synced issue bodies, skipped $skipped" -ForegroundColor Cyan
