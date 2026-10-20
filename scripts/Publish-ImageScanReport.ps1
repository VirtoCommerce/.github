<#
.SYNOPSIS
    Reports a whole image scan run in one Jira ticket.

.DESCRIPTION
    Reads the Trivy JSON results of every scanned image (the artifacts of
    docker-image-vulnerability-process.yml with createJiraTickets: false) and groups the findings
    by vulnerability, listing the images each one was found in.

    Then, in Jira, against the newest open ticket with the label (the previous run's ticket):
      - no open ticket, or the run found vulnerabilities that ticket does not list: a new ticket;
      - otherwise: a comment on that ticket with a link to the run.
    A run without vulnerabilities changes nothing in Jira.

    The run summary (GITHUB_STEP_SUMMARY) gets the same table and the ticket.
    Step outputs (GITHUB_OUTPUT): ticketAction (created, commented or none), ticketKey, ticketUrl.
    JIRA_USER and JIRA_TOKEN come from the environment.

.EXAMPLE
    ./scripts/Publish-ImageScanReport.ps1 -ResultsPath ./results -ExpectedImages 11 -JiraProject VCST -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResultsPath,

    # Images the run meant to scan; fewer results means some scans failed.
    [int] $ExpectedImages = 0,

    [string] $JiraBaseUrl = 'https://virtocommerce.atlassian.net',

    [Parameter(Mandatory)]
    [string] $JiraProject,

    [string] $AssigneeAccountId = '621c47c0302c6b006af0a1cd',

    # Marks the run tickets, to find the previous one.
    [string] $Label = 'image-vulnerability-scan',

    # Comma separated vulnerability IDs to leave out.
    [string] $VulnerabilitySkipList = '',

    # The org-wide exceptions list (vulnerability-exceptions.json). Empty - none.
    [string] $VulnerabilityExceptionsUrl = 'https://raw.githubusercontent.com/VirtoCommerce/.github/main/vulnerability-exceptions.json',

    # No Jira calls: print the ticket that would be created.
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

# Jira limits the description to 32767 characters; this budget is checked on the description JSON, which is
# longer than its text. The details of each vulnerability go in while they fit; the run summary has them all.
$maxDescriptionLength = 30000
$runUrl = if ($env:GITHUB_RUN_ID) { "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID" } else { '' }
$sevOrder = @{ 'CRITICAL' = 0; 'HIGH' = 1; 'MEDIUM' = 2; 'LOW' = 3; 'UNKNOWN' = 4 }
function Get-SevRank($severity) { $rank = $sevOrder["$severity"]; if ($null -eq $rank) { 99 } else { $rank } }
$skipList = @("$VulnerabilitySkipList".Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# Valid, not expired org exceptions: { IDs (the key and its aliases); Repositories; Images }. The same rules as docker-image-vulnerability-process.yml.
$exceptions = @()
if ($VulnerabilityExceptionsUrl) {
    try {
        $list = (Invoke-WebRequest -Uri $VulnerabilityExceptionsUrl -UseBasicParsing).Content | ConvertFrom-Json
        $today = [datetime]::UtcNow.Date
        foreach ($entry in @($list.PSObject.Properties)) {
            $e = $entry.Value
            $expires = [datetime]::MinValue
            if (-not "$($e.reason)".Trim() -or -not [datetime]::TryParseExact("$($e.expires)", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, 'None', [ref] $expires)) {
                Write-Host "::warning::Vulnerability exception $($entry.Name) needs a reason and expires (yyyy-MM-dd): not applied."
                continue
            }
            # "scope" was one list for repositories and images together; an entry still using it is not widened to everywhere.
            if ($null -ne $e.scope) { Write-Host "::warning::Vulnerability exception $($entry.Name) uses scope: list it as repositories and images instead. Not applied."; continue }
            if ($expires -lt $today) { Write-Host "Vulnerability exception $($entry.Name) expired on $($e.expires): not applied."; continue }
            $exceptions += [pscustomobject]@{
                IDs          = @($entry.Name) + @($e.aliases | Where-Object { $_ })
                Repositories = @($e.repositories | Where-Object { $_ })
                Images       = @($e.images | Where-Object { $_ })
            }
        }
    }
    catch {
        Write-Host "::warning::Could not read the vulnerability exceptions from $VulnerabilityExceptionsUrl, none applied: $($_.Exception.Message)"
    }
}
# An exception applies when it lists no repositories and no images, when a repositories mask matches this
# repository, or when an images mask matches the image (with and without its tag).
function Test-Excepted([string] $Id, [string] $Image) {
    $imageTargets = @($Image, ($Image -replace '@sha256:[0-9a-f]+$', '' -replace ':[^:/]+$', ''))
    foreach ($ex in $exceptions) {
        if ($ex.IDs -notcontains $Id) { continue }
        if ($ex.Repositories.Count + $ex.Images.Count -eq 0) { return $true }
        if (@($ex.Repositories | Where-Object { "$env:GITHUB_REPOSITORY" -like $_ }).Count) { return $true }
        foreach ($mask in $ex.Images) { if (@($imageTargets | Where-Object { $_ -like $mask }).Count) { return $true } }
    }
    return $false
}

# --- Collect the findings of every image ---
$files = @(Get-ChildItem -Path $ResultsPath -Filter '*.json' -Recurse -File)
if ($files.Count -eq 0) { throw "No scan results in '$ResultsPath': every image scan failed." }

$occurrences = [System.Collections.Generic.List[object]]::new()
$images = [System.Collections.Generic.List[string]]::new()
$ignoredIds = [System.Collections.Generic.SortedSet[string]]::new()
foreach ($file in $files) {
    $scan = Get-Content -Raw $file.FullName | ConvertFrom-Json
    $image = if ($scan.ArtifactName) { "$($scan.ArtifactName)" } else { $file.BaseName }
    $images.Add($image)
    foreach ($result in @($scan.Results)) {
        foreach ($vuln in @($result.Vulnerabilities)) {
            if ($null -eq $vuln -or -not $vuln.VulnerabilityID) { continue }
            if ($skipList -contains $vuln.VulnerabilityID -or (Test-Excepted $vuln.VulnerabilityID $image)) { [void] $ignoredIds.Add($vuln.VulnerabilityID); continue }
            $occurrences.Add([pscustomobject]@{ Vuln = $vuln; Image = $image })
        }
    }
}

$vulnerabilities = @($occurrences |
    Group-Object { $_.Vuln.VulnerabilityID } |
    ForEach-Object {
        $group = @($_.Group)
        $top = ($group | Sort-Object { Get-SevRank $_.Vuln.Severity })[0].Vuln
        [pscustomobject]@{
            ID       = $_.Name
            Severity = "$($top.Severity)"
            Url      = "$($top.PrimaryURL)"
            # One CVE often hits several packages (openssl, libssl3...), with their own versions.
            Packages = @($group | ForEach-Object {
                $fixed = if ($_.Vuln.FixedVersion) { $_.Vuln.FixedVersion } else { 'no fix' }
                "$($_.Vuln.PkgName) $($_.Vuln.InstalledVersion) -> $fixed"
            } | Sort-Object -Unique)
            Images   = @($group | ForEach-Object { $_.Image } | Sort-Object -Unique)
            New      = $true
        }
    } |
    Sort-Object @{ Expression = { Get-SevRank $_.Severity } }, ID)

$affectedImages = @($vulnerabilities | ForEach-Object { $_.Images } | Sort-Object -Unique)
$scannedText = if ($ExpectedImages -gt 0) { "$($files.Count) of $ExpectedImages" } else { "$($files.Count)" }
Write-Host "Scanned images: $scannedText. Vulnerabilities: $($vulnerabilities.Count) in $($affectedImages.Count) image(s)."
if ($ignoredIds.Count) { Write-Host "Skipped (skip list or exceptions): $(@($ignoredIds) -join ', ')" }
if ($ExpectedImages -gt $files.Count) {
    Write-Host "::warning::$($ExpectedImages - $files.Count) image scan(s) left no results, see the failed scan jobs."
}

function Set-TicketOutput([string] $Action, [string] $Key = '', [string] $Url = '') {
    if ($env:GITHUB_OUTPUT) { "ticketAction=$Action", "ticketKey=$Key", "ticketUrl=$Url" >> $env:GITHUB_OUTPUT }
}

function Format-Cell($value) { "$value" -replace '\|', '\|' }
function Publish-Summary([string] $ticketLine) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## Vulnerabilities in this run')
    $lines.Add('')
    $lines.Add("**Scanned images:** $scannedText &nbsp;|&nbsp; **Vulnerabilities:** $($vulnerabilities.Count) &nbsp;|&nbsp; **Affected images:** $($affectedImages.Count)  ")
    if ($ignoredIds.Count) { $lines.Add("**Skipped (skip list or exceptions):** $(@($ignoredIds) -join ', ')  ") }
    $lines.Add("**Jira:** $ticketLine")
    if ($vulnerabilities.Count -gt 0) {
        $lines.Add('')
        $lines.Add('| Vulnerability | Severity | Packages | Images | New |')
        $lines.Add('| --- | --- | --- | --- | --- |')
        foreach ($v in $vulnerabilities) {
            $id = if ($v.Url) { "[$(Format-Cell $v.ID)]($($v.Url))" } else { Format-Cell $v.ID }
            $packages = ($v.Packages | ForEach-Object { Format-Cell $_ }) -join '<br>'
            $imageList = ($v.Images | ForEach-Object { '`' + (Format-Cell $_) + '`' }) -join '<br>'
            $lines.Add("| $id | $(Format-Cell $v.Severity) | $packages | $imageList | $(if ($v.New) { 'yes' } else { '' }) |")
        }
    }
    if ($env:GITHUB_STEP_SUMMARY) { $lines -join "`n" >> $env:GITHUB_STEP_SUMMARY }
}

if ($vulnerabilities.Count -eq 0) {
    Write-Host 'No vulnerabilities: nothing to report in Jira.'
    Publish-Summary 'nothing to report'
    Set-TicketOutput 'none'
    exit 0
}

# --- Jira ---
function New-Text($text, $marks) { $node = @{ type = 'text'; text = "$text" }; if ($marks) { $node.marks = @($marks) }; $node }
function New-Link($text, $href) { New-Text $text @{ type = 'link'; attrs = @{ href = "$href" } } }
function New-Paragraph { @{ type = 'paragraph'; content = @($args | ForEach-Object { $_ }) } }
function New-BulletList($items) { @{ type = 'bulletList'; content = @($items | ForEach-Object { @{ type = 'listItem'; content = @($_) } }) } }

if (-not $DryRun) {
    if (-not $env:JIRA_USER -or -not $env:JIRA_TOKEN) { throw 'JIRA_USER and JIRA_TOKEN are required.' }
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($env:JIRA_USER):$($env:JIRA_TOKEN)"))
    $headers = @{ Authorization = "Basic $auth"; 'Content-Type' = 'application/json' }
}
function Invoke-Jira([string] $Method, [string] $Path, $Body) {
    $json = $Body | ConvertTo-Json -Depth 100 -Compress
    Invoke-RestMethod -Uri "$JiraBaseUrl$Path" -Headers $headers -Method $Method -Body ([Text.Encoding]::UTF8.GetBytes($json))
}

# The previous run's ticket: the newest open one with the label.
$previous = $null
if (-not $DryRun) {
    $search = Invoke-Jira Post '/rest/api/3/search/jql' @{
        jql        = "project = `"$JiraProject`" AND labels = `"$Label`" AND statusCategory != Done ORDER BY created DESC"
        fields     = @('summary', 'description')
        maxResults = 1
    }
    $previous = @($search.issues)[0]
}
if ($previous) {
    $previousText = $previous.fields.description | ConvertTo-Json -Depth 100 -Compress
    foreach ($v in $vulnerabilities) {
        # Whole IDs only: CVE-2026-3949 must not match inside CVE-2026-39490.
        $v.New = -not ($previousText -match ('(?<![\w-])' + [regex]::Escape($v.ID) + '(?![\w-])'))
    }
}
$newVulnerabilities = @($vulnerabilities | Where-Object New)

if ($previous -and $newVulnerabilities.Count -eq 0) {
    $previousUrl = "$JiraBaseUrl/browse/$($previous.key)"
    $runRef = if ($runUrl) { New-Link 'Scan run' $runUrl } else { New-Text 'Scan run' }
    Invoke-Jira Post "/rest/api/3/issue/$($previous.key)/comment" @{
        body = @{ type = 'doc'; version = 1; content = @(
            (New-Paragraph $runRef (New-Text ": $($vulnerabilities.Count) vulnerabilities in $($affectedImages.Count) image(s), scanned $scannedText, no new ones since this ticket."))
        ) }
    } | Out-Null
    Write-Host "No new vulnerabilities: commented on $($previous.key)."
    Publish-Summary "no new vulnerabilities, commented on [$($previous.key)]($previousUrl)"
    Set-TicketOutput 'commented' $previous.key $previousUrl
    exit 0
}

# A new ticket: every vulnerability of the run, the new ones marked.
function Get-DescriptionLength($Content) { (@{ type = 'doc'; version = 1; content = @($Content) } | ConvertTo-Json -Depth 100 -Compress).Length }

$intro = @(New-Text '*** Automatic ticket from the scheduled Trivy image scan *** ')
if ($runUrl) { $intro += New-Link 'Scan run' $runUrl }
$content = @(
    (New-Paragraph @intro)
    (New-Paragraph (New-Text "Scanned images: $scannedText. Vulnerabilities: $($vulnerabilities.Count) in $($affectedImages.Count) image(s)."))
)
if ($previous) {
    $content += New-Paragraph (New-Text "New since ") (New-Link $previous.key "$JiraBaseUrl/browse/$($previous.key)") (New-Text ": $(($newVulnerabilities.ID) -join ', ').")
}
# Every ID, whatever fits of the details below: the next run tells new vulnerabilities from this list.
$content += New-Paragraph (New-Text "All vulnerabilities: $(($vulnerabilities.ID) -join ', ')")
if ((Get-DescriptionLength $content) -gt $maxDescriptionLength) {
    throw "$($vulnerabilities.Count) vulnerability IDs alone exceed the Jira description limit: narrow the scan."
}

$items = [System.Collections.Generic.List[object]]::new()
foreach ($v in $vulnerabilities) {
    $head = @(if ($v.Url) { New-Link $v.ID $v.Url } else { New-Text $v.ID @{ type = 'strong' } })
    $head += New-Text " ($($v.Severity))$(if ($previous -and $v.New) { ' - new' })"
    $item = @(
        (New-Paragraph @head)
        (New-BulletList @(
            @($v.Packages | ForEach-Object { New-Paragraph (New-Text 'Package: ') (New-Text $_) })
            @($v.Images | ForEach-Object { New-Paragraph (New-Text 'Image: ') (New-Text $_ @{ type = 'code' }) })
        ))
    )
    $items.Add($item)
    # Room is left for the "Details of N more" paragraph.
    if ((Get-DescriptionLength ($content + (New-BulletList $items))) -gt $maxDescriptionLength - 200) {
        $items.RemoveAt($items.Count - 1)
        break
    }
}
if ($items.Count -gt 0) { $content += New-BulletList $items }
if ($vulnerabilities.Count -gt $items.Count) {
    $content += New-Paragraph (New-Text "Details of $($vulnerabilities.Count - $items.Count) more are in the scan run summary.")
}

$fields = @{
    project     = @{ key = $JiraProject }
    issuetype   = @{ name = 'Task' }
    summary     = "[Vulnerability scan] $($vulnerabilities.Count) vulnerabilities in $($affectedImages.Count) image(s), $(Get-Date -Format 'yyyy-MM-dd')"
    labels      = @('Vulnerability', $Label)
    assignee    = @{ accountId = $AssigneeAccountId }
    description = @{ type = 'doc'; version = 1; content = $content }
}

if ($DryRun) {
    Write-Host 'Dry run, the ticket that would be created:'
    @{ fields = $fields } | ConvertTo-Json -Depth 100
    Publish-Summary 'dry run, no ticket'
    Set-TicketOutput 'none'
    exit 0
}

$created = Invoke-Jira Post '/rest/api/3/issue' @{ fields = $fields }
$createdUrl = "$JiraBaseUrl/browse/$($created.key)"
Write-Host "Created $($created.key): $createdUrl"
$reason = if ($previous) { "new vulnerabilities since $($previous.key)" } else { 'no open run ticket' }
Publish-Summary "created [$($created.key)]($createdUrl) ($reason)"
Set-TicketOutput 'created' $created.key $createdUrl
