#requires -Version 7.0
<#
.SYNOPSIS
    Swap required status checks on protected branches of existing module repos.

.DESCRIPTION
    Mirrors the change applied to new repos by
    .github/workflows/create-module-repository.yml (the "Protect branches" step):
    replaces the old required status checks with a single new one on `main` and
    `dev`. Any of the configured old checks that are present get removed and
    collapsed into the new check.

    Read-modify-write: fetches each branch's current protection, updates only the
    contexts list, and PUTs it back. Other settings (reviews, enforce_admins,
    restrictions, etc.) are preserved as-is.

    With -AddIfMissing, the script also creates protection on branches that
    exist but have no protection rules at all, mirroring the default policy
    applied by the create-module-repository workflow. Branches that don't
    exist are still skipped.

.EXAMPLE
    pwsh ./Update-ModuleBranchProtection.ps1 -WhatIf
    pwsh ./Update-ModuleBranchProtection.ps1
    pwsh ./Update-ModuleBranchProtection.ps1 -Repos vc-module-news,vc-module-cart
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Org = 'VirtoCommerce',
    [string[]]$Repos,
    [string[]]$Branches = @('main', 'dev'),
    [string[]]$OldChecks = @(
        'module-katalon-tests / e2e-tests',
        'UI-auto-tests / ui-autotests',
        'UI-auto-tests / dry-run'
    ),
    [string]$NewCheck = 'auto-tests / auto-autotests',
    [switch]$AddIfMissing,
    # PAT with repo admin on the target repos. If omitted, falls back to existing
    # $env:GH_TOKEN or the ambient `gh auth login` session.
    [string]$Token
)

$ErrorActionPreference = 'Stop'

$priorGhToken = $env:GH_TOKEN
if ($Token) { $env:GH_TOKEN = $Token }

function Test-GhReady {
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'gh CLI is not authenticated. Run: gh auth login (needs `repo` + `admin:repo_hook` scopes).'
    }
}

function Get-ModuleRepos {
    param([string]$Org)
    $json = gh repo list $Org --limit 1000 --no-archived --json name 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to list repos for $Org`: $json" }
    ($json | ConvertFrom-Json) |
        Where-Object { $_.name -like 'vc-module-*' } |
        ForEach-Object { "$Org/$($_.name)" } |
        Sort-Object
}

function Get-Enabled {
    param($Obj, [string]$Name)
    if ($Obj -and $Obj.PSObject.Properties.Name -contains $Name) {
        return [bool]$Obj.$Name.enabled
    }
    return $false
}

# Default protection policy for newly-created protection. Mirrors the
# "Protect branches" step in .github/workflows/create-module-repository.yml.
function New-DefaultProtectionPayload {
    param([string]$NewCheck)
    return [ordered]@{
        required_status_checks = [ordered]@{
            strict   = $false
            contexts = @(
                'license/cla',
                'ci',
                'SonarCloud Code Analysis',
                $NewCheck
            )
        }
        enforce_admins                = $false
        required_pull_request_reviews = [ordered]@{
            dismiss_stale_reviews           = $false
            require_code_owner_reviews      = $false
            require_last_push_approval      = $false
            required_approving_review_count = 1
        }
        restrictions                     = $null
        allow_force_pushes               = $false
        allow_deletions                  = $false
        required_conversation_resolution = $false
    }
}

function Invoke-PutProtection {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$RepoFull,
        [string]$Branch,
        [object]$Payload,
        [string]$Action
    )
    if (-not $PSCmdlet.ShouldProcess("$RepoFull/$Branch", $Action)) {
        return [pscustomobject]@{ Status = 'WHATIF'; Reason = $Action }
    }
    $json = $Payload | ConvertTo-Json -Depth 10 -Compress
    $tmp  = New-TemporaryFile
    try {
        # UTF-8 without BOM; gh on Windows mishandles BOM in --input payloads.
        [System.IO.File]::WriteAllText($tmp.FullName, $json, [System.Text.UTF8Encoding]::new($false))
        $out = gh api --method PUT "/repos/$RepoFull/branches/$Branch/protection" --input $tmp.FullName 2>&1
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ Status = 'ERROR'; Reason = "$out" }
        }
    }
    finally {
        Remove-Item $tmp.FullName -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{ Status = 'OK'; Reason = $Action }
}

function Update-BranchProtection {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$RepoFull,
        [string]$Branch,
        [string[]]$OldChecks,
        [string]$NewCheck,
        [bool]$AddIfMissing
    )

    $raw = gh api "/repos/$RepoFull/branches/$Branch/protection" 2>&1
    if ($LASTEXITCODE -ne 0) {
        # "Branch not protected" = branch exists, no rules; create them under -AddIfMissing.
        # "Not Found" without that phrase = branch itself doesn't exist; always skip.
        if ("$raw" -match 'Branch not protected') {
            if (-not $AddIfMissing) {
                return [pscustomobject]@{ Status = 'SKIP'; Reason = 'no protection (use -AddIfMissing to create)' }
            }
            $payload = New-DefaultProtectionPayload -NewCheck $NewCheck
            $action  = "create protection -> [$($payload.required_status_checks.contexts -join ', ')]"
            return Invoke-PutProtection -RepoFull $RepoFull -Branch $Branch -Payload $payload -Action $action
        }
        if ("$raw" -match 'Not Found|HTTP 404') {
            return [pscustomobject]@{ Status = 'SKIP'; Reason = 'branch missing' }
        }
        return [pscustomobject]@{ Status = 'SKIP'; Reason = "$raw" }
    }

    $p   = $raw | ConvertFrom-Json
    $rsc = $p.required_status_checks
    if (-not $rsc) {
        if (-not $AddIfMissing) {
            return [pscustomobject]@{ Status = 'SKIP'; Reason = 'no required_status_checks (use -AddIfMissing to add)' }
        }
        # Branch is protected but status-check enforcement is off; synthesize an
        # empty block so the add-new-check path below enables it without
        # touching the rest of the existing protection.
        $rsc = [pscustomobject]@{ strict = $false; contexts = @() }
    }

    $contexts   = @($rsc.contexts)
    $toRemove   = @($OldChecks | Where-Object { $contexts -contains $_ })
    $hasAnyOld  = $toRemove.Count -gt 0
    $hasNew     = $contexts -contains $NewCheck

    if ($hasAnyOld) {
        $contexts = @($contexts | Where-Object { $toRemove -notcontains $_ })
        if (-not $hasNew) { $contexts += $NewCheck }
    }
    elseif ($AddIfMissing -and -not $hasNew) {
        $contexts += $NewCheck
    }
    else {
        $reason = if ($hasNew) { 'already up to date' } else { 'no old checks present (use -AddIfMissing to add anyway)' }
        return [pscustomobject]@{ Status = 'SKIP'; Reason = $reason }
    }

    # GET returns nested { enabled: bool } objects; PUT expects flat booleans.
    $payload = [ordered]@{
        required_status_checks = [ordered]@{
            strict   = [bool]$rsc.strict
            contexts = @($contexts)
        }
        enforce_admins                   = Get-Enabled $p 'enforce_admins'
        required_pull_request_reviews    = $null
        restrictions                     = $null
        required_linear_history          = Get-Enabled $p 'required_linear_history'
        allow_force_pushes               = Get-Enabled $p 'allow_force_pushes'
        allow_deletions                  = Get-Enabled $p 'allow_deletions'
        block_creations                  = Get-Enabled $p 'block_creations'
        required_conversation_resolution = Get-Enabled $p 'required_conversation_resolution'
        lock_branch                      = Get-Enabled $p 'lock_branch'
        allow_fork_syncing               = Get-Enabled $p 'allow_fork_syncing'
    }

    if ($p.required_pull_request_reviews) {
        $r = $p.required_pull_request_reviews
        $payload.required_pull_request_reviews = [ordered]@{
            dismiss_stale_reviews           = [bool]$r.dismiss_stale_reviews
            require_code_owner_reviews      = [bool]$r.require_code_owner_reviews
            required_approving_review_count = [int]$r.required_approving_review_count
            require_last_push_approval      = [bool]$r.require_last_push_approval
        }
    }

    if ($p.restrictions) {
        $payload.restrictions = [ordered]@{
            users = @($p.restrictions.users | ForEach-Object { $_.login })
            teams = @($p.restrictions.teams | ForEach-Object { $_.slug })
            apps  = @($p.restrictions.apps  | ForEach-Object { $_.slug })
        }
    }

    $action = "contexts -> [$($contexts -join ', ')]"
    return Invoke-PutProtection -RepoFull $RepoFull -Branch $Branch -Payload $payload -Action $action
}

try {
    Test-GhReady

    if (-not $Repos -or $Repos.Count -eq 0) {
        Write-Host "Discovering vc-module-* repos in $Org ..."
        $Repos = Get-ModuleRepos -Org $Org
        Write-Host "Found $($Repos.Count) module repos."
    }
    else {
        $Repos = $Repos | ForEach-Object { if ($_ -match '/') { $_ } else { "$Org/$_" } }
    }

    $results = foreach ($repo in $Repos) {
        foreach ($branch in $Branches) {
            $r = Update-BranchProtection `
                -RepoFull $repo -Branch $branch `
                -OldChecks $OldChecks -NewCheck $NewCheck `
                -AddIfMissing:$AddIfMissing
            $line = [pscustomobject]@{
                Repo   = $repo
                Branch = $branch
                Status = $r.Status
                Reason = $r.Reason
            }
            $color = switch ($r.Status) {
                'OK'     { 'Green' }
                'WHATIF' { 'Cyan' }
                'SKIP'   { 'DarkGray' }
                'ERROR'  { 'Red' }
                default  { 'White' }
            }
            Write-Host ("[{0,-6}] {1}/{2}: {3}" -f $r.Status, $repo, $branch, $r.Reason) -ForegroundColor $color
            $line
        }
    }

    Write-Host ''
    Write-Host 'Summary:' -ForegroundColor Yellow
    $results | Group-Object Status | Select-Object Name, Count | Format-Table -AutoSize

    $errors = @($results | Where-Object Status -eq 'ERROR')
    if ($errors.Count -gt 0) { exit 1 }
}
finally {
    # Restore (or clear) GH_TOKEN so a -Token passed to this script doesn't leak
    # into the caller's session when dot-sourced.
    if ($Token) {
        if ($null -ne $priorGhToken) { $env:GH_TOKEN = $priorGhToken }
        else { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
    }
}
