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

function Get-Section([string]$md, [string]$heading, [string]$from) {
    # Everything under "## <heading>" up to the next "## " heading.
    $pattern = "(?ms)^##\s+$([regex]::Escape($heading))\s*\r?\n(.*?)(?=^##\s)"
    $m = [regex]::Match($md, $pattern)
    if (-not $m.Success) { throw "Section '## $heading' not found in $from" }
    # Drop the horizontal rule that separates it from the next section.
    return ($m.Groups[1].Value -replace '(?m)^---\s*$', '').Trim()
}

# Shared rules appended to every issue so each one stands alone.
#
# Read from docs/plan/README.md rather than duplicated here. This used to be a
# hardcoded copy, and it silently went stale the moment the plan changed -- after
# the 2026-09-08 architecture pivot it was still telling every one of 57 issues to
# use EF Core and an Idempotency-Key header. One copy, or it drifts.
$readmePath = Join-Path $PlanDir 'README.md'
if (-not (Test-Path $readmePath)) { throw "Cannot find $readmePath" }
$readme = Get-Content $readmePath -Raw

$constraints = @"
## Global constraints

Generated from ``$PlanDir/README.md`` -- do not edit here.

$(Get-Section $readme 'Global Constraints' $readmePath)

## Versions

$(Get-Section $readme 'Versions' $readmePath)
"@

function Convert-Links([string]$md) {
    # Relative links work in the repo but not in an issue body. Make them absolute.
    $md = $md -replace '\]\(README\.md',              "]($blob/$PlanDir/README.md"
    $md = $md -replace '\]\((M\d-[a-z-]+\.md)',       "]($blob/$PlanDir/`$1"
    $md = $md -replace '\]\(\.\./specs/',             "]($blob/docs/specs/"
    $md = $md -replace '\]\(\.\./\.\./CLAUDE\.md\)',  "]($blob/CLAUDE.md)"
    $md = $md -replace '\]\(\.\./plan/',              "]($blob/$PlanDir/"
    return $md
}

$constraints = Convert-Links $constraints

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
- [ ] No secret or real customer data in the diff
- [ ] ``npm run build`` / ``test`` / ``lint`` clean; database tests pass against the local stack
- [ ] Any new table has RLS enabled and a negative test proving isolation
- [ ] Any new ``SECURITY DEFINER`` function pins ``search_path`` and checks ``auth.uid()`` first
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
