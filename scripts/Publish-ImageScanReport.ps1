<#
.SYNOPSIS
    Reports a whole image scan run in one Jira ticket.

.DESCRIPTION
    Reads the Trivy JSON results of every scanned image (the artifacts of
    docker-image-vulnerability-process.yml with createJiraTickets: false) and groups the findings
    by vulnerability, listing the images each one was found in.

    Then, in Jira, against the newest open ticket with the label (the previous run's ticket):
      - no open ticket, or the run found vulnerabilities that ticket does not list: a new ticket, and the
        open one is cancelled and gets a comment linking it (stays open when some image scans failed);
      - otherwise: a comment on that ticket with a link to the run and the IDs it lists that the run no longer found.
    A run without vulnerabilities moves the open ticket to Done and comments on it; when some image scans
    failed, it only comments. With no open ticket, it changes nothing in Jira.
    Older open tickets with the label, left open by such runs, are cancelled by the next run that scans every image.
    A failed move is a warning, not a failed run.

    The run summary (GITHUB_STEP_SUMMARY) gets the same table and the ticket.
    Step outputs (GITHUB_OUTPUT): ticketAction (created, commented, closed or none), ticketKey, ticketUrl.
    JIRA_USER and JIRA_TOKEN come from the environment.

.EXAMPLE
    ./scripts/Publish-ImageScanReport.ps1 -ResultsPath ./results -ExpectedImages 11 -JiraProject VCST -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResultsPath,

    # Images the run meant to scan; fewer results means some scans failed. 0 (unknown): no ticket is closed.
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
# Without -ExpectedImages a failed scan cannot be told apart: such a run closes and cancels nothing.
$scanComplete = $ExpectedImages -gt 0 -and $files.Count -ge $ExpectedImages
if ($ExpectedImages -le 0) {
    Write-Host '::warning::No -ExpectedImages: failed image scans cannot be detected, so no ticket is closed.'
}
elseif (-not $scanComplete) {
    Write-Host "::warning::$($ExpectedImages - $files.Count) image scan(s) left no results, see the failed scan jobs."
}

function Set-TicketOutput([string] $Action, [string] $Key = '', [string] $Url = '') {
    if ($env:GITHUB_OUTPUT) { "ticketAction=$Action", "ticketKey=$Key", "ticketUrl=$Url" >> $env:GITHUB_OUTPUT }
}

# The outcome of the check for new vulnerabilities, for the run summary; set once the open run ticket is known.
$newCheck = ''
# The IDs the open run ticket lists that this run did not find; set with the ticket too.
$goneIds = @()

function Format-Cell($value) { "$value" -replace '\|', '\|' }
function Publish-Summary([string] $ticketLine) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## Vulnerabilities in this run')
    $lines.Add('')
    $lines.Add("**Scanned images:** $scannedText &nbsp;|&nbsp; **Vulnerabilities:** $($vulnerabilities.Count) &nbsp;|&nbsp; **Affected images:** $($affectedImages.Count)  ")
    if ($ignoredIds.Count) { $lines.Add("**Skipped (skip list or exceptions):** $(@($ignoredIds) -join ', ')  ") }
    if ($newCheck) { $lines.Add("**New vulnerabilities:** $newCheck  ") }
    if ($goneIds.Count) { $lines.Add("**No longer found (listed in the open run ticket):** $($goneIds -join ', ')  ") }
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

if ($vulnerabilities.Count -eq 0 -and $DryRun) {
    Write-Host 'No vulnerabilities, dry run: no Jira calls.'
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
    if ($null -eq $Body) { return Invoke-RestMethod -Uri "$JiraBaseUrl$Path" -Headers $headers -Method $Method }
    $json = $Body | ConvertTo-Json -Depth 100 -Compress
    Invoke-RestMethod -Uri "$JiraBaseUrl$Path" -Headers $headers -Method $Method -Body ([Text.Encoding]::UTF8.GetBytes($json))
}
function Add-JiraComment([string] $Key, $Content) {
    Invoke-Jira Post "/rest/api/3/issue/$Key/comment" @{ body = @{ type = 'doc'; version = 1; content = @($Content) } } | Out-Null
}
# Whether the newest comment on a ticket already contains $Text: a ticket left open is not told the same every
# night. Comments come oldest first, so the newest is read by its index rather than with a sort parameter.
# A failed lookup counts as no: at worst one comment a night.
function Test-LastComment([string] $Key, [string] $Text) {
    try {
        $page = Invoke-Jira Get "/rest/api/3/issue/$Key/comment?maxResults=1"
        $total = [int] $page.total
        if ($total -eq 0) { return $false }
        if ($total -gt 1) { $page = Invoke-Jira Get "/rest/api/3/issue/$Key/comment?startAt=$($total - 1)&maxResults=1" }
        $last = @($page.comments)[0]
        return [bool] ($last -and ($last.body | ConvertTo-Json -Depth 100 -Compress).Contains($Text))
    }
    catch {
        Write-Host "::warning::Could not read the last comment on $Key, commenting anyway: $($_.Exception.Message)"
        return $false
    }
}
# Moves a ticket through the Done-category transition whose name or target status matches $Status (Done: clean scan; Cancelled: work moved on) and returns the new status, before any comment so the comment can say it.
# Jira offers only the transitions from the current status (skipping steps needs a global transition); without one, or when Jira refuses the move (required field, no permission): a warning and $null, not a failed run.
$doneStatus = '^(Done|Closed|Resolved)$'
$cancelStatus = 'cancel|won.?t do'
function Close-JiraTicket([string] $Key, [string] $Status) {
    try {
        $transitions = @((Invoke-Jira Get "/rest/api/3/issue/$Key/transitions").transitions)
        $close = @($transitions | Where-Object { $_.to.statusCategory.key -eq 'done' -and ($_.name -match $Status -or $_.to.name -match $Status) })[0]
        if (-not $close) {
            Write-Host "::warning::$Key has no transition matching '$Status' from its status (available: $(@($transitions | ForEach-Object { "$($_.name) -> $($_.to.name)" }) -join ', ')): close it by hand."
            return $null
        }
        Invoke-Jira Post "/rest/api/3/issue/$Key/transitions" @{ transition = @{ id = "$($close.id)" } } | Out-Null
        Write-Host "Moved $Key to $($close.to.name)."
        return "$($close.to.name)"
    }
    catch {
        Write-Host "::warning::Could not move $Key to a status matching '$Status', close it by hand: $($_.Exception.Message)"
        return $null
    }
}

# The previous run's ticket: the newest open one with the label. The older open ones were left open by a run
# with failed image scans or a failed move; the newest supersedes them, and a run that scans every image cancels them.
$previous = $null
$olderOpen = @()
if (-not $DryRun) {
    $search = Invoke-Jira Post '/rest/api/3/search/jql' @{
        jql        = "project = `"$JiraProject`" AND labels = `"$Label`" AND statusCategory != Done ORDER BY created DESC"
        fields     = @('summary', 'description')
        maxResults = 20
    }
    $previous = @($search.issues)[0]
    $olderOpen = @($search.issues | Select-Object -Skip 1)
}
# $Reason: the ADF text nodes that start the comment ("Superseded by VCST-1", "Scan run: no vulnerabilities").
# A failed move is said once on the ticket; the next runs try again without repeating it.
function Close-OlderTickets($Reason) {
    if (-not $scanComplete) { return }
    foreach ($ticket in $olderOpen) {
        $status = Close-JiraTicket $ticket.key $cancelStatus
        $outcome = if ($status) { ", moved to $status." } else { ', but the ticket could not be moved to Cancelled, see the scan run log: cancel it by hand.' }
        if (-not $status -and (Test-LastComment $ticket.key $outcome)) { continue }
        try { Add-JiraComment $ticket.key (New-Paragraph @(@($Reason) + (New-Text $outcome))) }
        catch { Write-Host "::warning::Could not comment on $($ticket.key): $($_.Exception.Message)" }
    }
}
if ($previous) {
    $previousText = $previous.fields.description | ConvertTo-Json -Depth 100 -Compress
    # The ticket's "All vulnerabilities: ..." paragraph. An ID can also go away with a failed image scan,
    # a new exception or an image taken out of the scan, so they are "no longer found", not "fixed".
    if ($previousText -match '"text":"All vulnerabilities: ([^"]*)"') {
        $runIds = @($vulnerabilities | ForEach-Object { $_.ID })
        $goneIds = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $runIds -notcontains $_ })
    }
    if ($goneIds.Count) { Write-Host "No longer found, listed in $($previous.key): $($goneIds -join ', ')" }
}

if ($vulnerabilities.Count -eq 0) {
    if (-not $previous) {
        Write-Host 'No vulnerabilities and no open run ticket: nothing to report in Jira.'
        Publish-Summary 'nothing to report'
        Set-TicketOutput 'none'
        exit 0
    }
    $previousUrl = "$JiraBaseUrl/browse/$($previous.key)"
    $runRef = if ($runUrl) { New-Link 'Scan run' $runUrl } else { New-Text 'Scan run' }
    # Failed scans may hide what the ticket lists: it stays open until a run scans every image.
    $closedAs = if ($scanComplete) { Close-JiraTicket $previous.key $doneStatus }
    $outcome = if (-not $scanComplete) { 'not every image was scanned, so the ticket stays open.' }
    elseif ($closedAs) { "ticket moved to $closedAs." }
    else { 'the ticket could not be moved to Done, see the scan run log: close it by hand.' }
    $comment = @(New-Paragraph $runRef (New-Text ": no vulnerabilities, scanned $scannedText, $outcome"))
    if ($goneIds.Count) { $comment += New-Paragraph (New-Text "No longer found: $($goneIds -join ', ').") }
    $repeat = -not $closedAs -and (Test-LastComment $previous.key $outcome)
    if ($repeat) { Write-Host "The last comment on $($previous.key) already says this: no new one." }
    else {
        # The ticket may already be Done: a failed comment is a warning, so the outputs and the summary still follow.
        try { Add-JiraComment $previous.key $comment }
        catch { Write-Host "::warning::Could not comment on $($previous.key): $($_.Exception.Message)" }
    }
    Close-OlderTickets @($runRef, (New-Text ': no vulnerabilities'))

    if ($closedAs) {
        Write-Host "No vulnerabilities: moved $($previous.key) to $closedAs."
        Publish-Summary "no vulnerabilities, closed [$($previous.key)]($previousUrl)"
        Set-TicketOutput 'closed' $previous.key $previousUrl
    }
    else {
        $why = if (-not $scanComplete) { 'not every image was scanned' } else { 'could not move it to Done, see the log' }
        Write-Host "No vulnerabilities, $($previous.key) left open: $why."
        Publish-Summary "no vulnerabilities, [$($previous.key)]($previousUrl) left open: $why"
        Set-TicketOutput $(if ($repeat) { 'none' } else { 'commented' }) $previous.key $previousUrl
    }
    exit 0
}

if ($previous) {
    foreach ($v in $vulnerabilities) {
        # Whole IDs only: CVE-2026-3949 must not match inside CVE-2026-39490.
        $v.New = -not ($previousText -match ('(?<![\w-])' + [regex]::Escape($v.ID) + '(?![\w-])'))
    }
}
$newVulnerabilities = @($vulnerabilities | Where-Object New)

# The check that decides between a new ticket and a comment: the count in the run summary, the IDs with their
# packages and images in the log.
$newCheck = if ($DryRun) {
    "dry run, not compared with an open run ticket ($($vulnerabilities.Count) in this run)"
}
elseif (-not $previous) {
    "no open run ticket, so all $($vulnerabilities.Count) are new"
}
else {
    # The table's New column marks the IDs.
    "$($newVulnerabilities.Count) of $($vulnerabilities.Count) not in the open run ticket [$($previous.key)]($JiraBaseUrl/browse/$($previous.key))"
}
if ($previous) {
    Write-Host "New vulnerabilities: $($newVulnerabilities.Count) of $($vulnerabilities.Count) not in the open run ticket $($previous.key)$(if ($newVulnerabilities.Count) { ': ' + ($newVulnerabilities.ID -join ', ') })."
    foreach ($v in $newVulnerabilities) {
        Write-Host "  + $($v.ID) ($($v.Severity)): $($v.Packages -join '; ') in $($v.Images -join ', ')"
    }
}
else {
    Write-Host "New vulnerabilities: $newCheck."
}

if ($previous -and $newVulnerabilities.Count -eq 0) {
    $previousUrl = "$JiraBaseUrl/browse/$($previous.key)"
    $runRef = if ($runUrl) { New-Link 'Scan run' $runUrl } else { New-Text 'Scan run' }
    $comment = @(New-Paragraph $runRef (New-Text ": $($vulnerabilities.Count) vulnerabilities in $($affectedImages.Count) image(s), scanned $scannedText, no new ones since this ticket."))
    if ($goneIds.Count) {
        $comment += New-Paragraph (New-Text "No longer found: $($goneIds -join ', ')$(if (-not $scanComplete) { ' (not every image was scanned)' }).")
    }
    Add-JiraComment $previous.key $comment
    Close-OlderTickets @((New-Text 'Superseded by '), (New-Link $previous.key $previousUrl))
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
# The outputs first: whatever happens to the old tickets, the notification names the new one.
Set-TicketOutput 'created' $created.key $createdUrl
$reason = if ($previous) { "new vulnerabilities since $($previous.key)" } else { 'no open run ticket' }

# The new ticket lists everything the run found and takes the work over, so the previous one is cancelled, not
# done. After failed scans it may list what this run could not check, and stays open until a run scans every image.
$previousOutcome = ''
if ($previous) {
    $previousUrl = "$JiraBaseUrl/browse/$($previous.key)"
    $cancelledAs = if ($scanComplete) { Close-JiraTicket $previous.key $cancelStatus }
    $outcome = if (-not $scanComplete) { 'this ticket stays open: not every image was scanned.' }
    elseif ($cancelledAs) { "this ticket moved to $cancelledAs." }
    else { 'this ticket could not be moved to Cancelled, see the scan run log: cancel it by hand.' }
    try { Add-JiraComment $previous.key (New-Paragraph (New-Text 'New vulnerabilities, followed up in ') (New-Link $created.key $createdUrl) (New-Text ": $outcome")) }
    catch { Write-Host "::warning::Could not comment on $($previous.key): $($_.Exception.Message)" }
    $previousOutcome = if (-not $scanComplete) { "; [$($previous.key)]($previousUrl) left open: not every image was scanned" }
    elseif ($cancelledAs) { "; cancelled [$($previous.key)]($previousUrl)" }
    else { "; could not cancel [$($previous.key)]($previousUrl), see the log" }
}
Close-OlderTickets @((New-Text 'Superseded by '), (New-Link $created.key $createdUrl))
Publish-Summary "created [$($created.key)]($createdUrl) ($reason)$previousOutcome"
