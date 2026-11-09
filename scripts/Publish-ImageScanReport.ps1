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
        When there are such IDs and the run scanned every image, they leave the ticket's state, so they are reported
        once, and its description and summary are rewritten to what the run found - unless another account edited
        them, which the comment then says.
    A run ticket's state (the IDs it covers, the IDs new since the previous ticket, the run that created it) is
    kept in the issue property named after the label; a ticket created before it gets it from its description.
    A run without vulnerabilities moves the open ticket to Done and comments on it; when some image scans
    failed, it only comments. With no open ticket, it changes nothing in Jira.
    Older open tickets with the label, left open by such runs, are cancelled by the next run that scans every image.
    A failed move is a warning, not a failed run.

    The run summary (GITHUB_STEP_SUMMARY) gets the same table and the ticket.
    Step outputs (GITHUB_OUTPUT): ticketAction (created, commented, updated - rewritten, closed or none), ticketKey, ticketUrl.
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
# The starts of a run ticket's paragraphs that the next runs read back: the first one (the run that created the
# ticket), the IDs new since the previous ticket, and every ID.
$introText = '*** Automatic ticket from the scheduled Trivy image scan ***'
$sincePrefix = 'New since '
$listPrefix = 'All vulnerabilities: '
$runUrl = if ($env:GITHUB_RUN_ID) { "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID" } else { '' }
$sevOrder = @{ 'CRITICAL' = 0; 'HIGH' = 1; 'MEDIUM' = 2; 'LOW' = 3; 'UNKNOWN' = 4 }
function Get-SevRank($severity) { $rank = $sevOrder["$severity"]; if ($null -eq $rank) { 99 } else { $rank } }
# The IDs of a list in a ticket created before the state property, separated by commas or line breaks; of an
# entry, its first word ("CVE-2026-1 (wip)"), without trailing punctuation. Every ID form the scan reports has a
# digit or a dash (CVE-2026-1, GHSA-..., 1096305, RLSA-2023:1234); a word without either is from a note added by hand.
function ConvertTo-IdList([string] $Text) {
    @($Text -split '[,\r\n]+' | ForEach-Object { @($_.Trim() -split '\s+')[0].TrimEnd('.', ';', ')') } | Where-Object { $_ -match '[\d-]' })
}
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
# The IDs the open run ticket covers ($null when unknown), and those this run did not find.
$listedIds = $null
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
# A link to this run, or the plain text when the script runs outside GitHub Actions.
function New-RunRef([string] $Text = 'Scan run') { if ($runUrl) { New-Link $Text $runUrl } else { New-Text $Text } }
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
# Which of the ticket's description and summary any account but this script's (a person, an automation rule)
# changed; the changelog does not include the creation. Those fields are not rewritten, so nothing written there is lost.
function Get-EditedFields([string] $Key) {
    $me = (Invoke-Jira Get '/rest/api/3/myself').accountId
    $edited = [System.Collections.Generic.HashSet[string]]::new()
    $startAt = 0
    do {
        $page = Invoke-Jira Get "/rest/api/3/issue/$Key/changelog?startAt=$startAt&maxResults=100"
        $values = @($page.values)
        # A change without an author is Jira's own, not an edit.
        foreach ($change in @($values | Where-Object { $_.author.accountId -and $_.author.accountId -ne $me })) {
            foreach ($item in @($change.items)) {
                $field = if ($item.fieldId) { "$($item.fieldId)" } else { "$($item.field)" }
                if (@('description', 'summary') -contains $field) { [void] $edited.Add($field) }
            }
        }
        $startAt += $values.Count
    } while ($values.Count -and -not $page.isLast)
    return , @($edited)
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
        fields     = @('summary', 'description', 'created')
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
$runIds = @($vulnerabilities | ForEach-Object { $_.ID })

# The run ticket's state, kept in an issue property named after the label rather than read back from the
# description, which people may edit: { ids: the IDs the ticket covers; sinceKey, sinceIds: the previous run
# ticket and the IDs new since it; runUrl: the run that created the ticket; date: its creation date }.
# $null when the ticket has none (404); any other failure throws.
function Get-TicketState([string] $Key) {
    try { return (Invoke-Jira Get "/rest/api/3/issue/$Key/properties/$Label").value }
    catch {
        if ($_.Exception.Response -and [int] $_.Exception.Response.StatusCode -eq 404) { return $null }
        throw
    }
}
function Set-TicketState([string] $Key, [string[]] $Ids, [string] $SinceKey, [string[]] $SinceIds, [string] $RunUrl, [string] $Date) {
    Invoke-Jira Put "/rest/api/3/issue/$Key/properties/$Label" @{
        ids = @($Ids); sinceKey = $SinceKey; sinceIds = @($SinceIds); runUrl = $RunUrl; date = $Date
    } | Out-Null
}

# A paragraph's text, joined from its nodes (Jira may split or merge them), a hard break as a line break.
function Get-ParagraphText($Node) { (@($Node.content) | ForEach-Object { if ($_.type -eq 'hardBreak') { "`n" } else { "$($_.text)" } }) -join '' }
# A ticket without the property (created before it existed): the state as its description gives it. Read once:
# the run writes the property. $null without an "All vulnerabilities" paragraph.
function Read-DescriptionState($Ticket) {
    $paragraphs = @($Ticket.fields.description.content | Where-Object { $_.type -eq 'paragraph' } | ForEach-Object { [pscustomobject]@{ Node = $_; Text = Get-ParagraphText $_ } })
    $list = @($paragraphs | Where-Object { $_.Text.StartsWith($listPrefix) })[0]
    if (-not $list) { return $null }
    $intro = @($paragraphs | Where-Object { $_.Text.StartsWith($introText) })[0].Node
    $since = @($paragraphs | Where-Object { $_.Text.StartsWith($sincePrefix) })[0].Text
    $sinceMatch = $since -match ('(?s)^' + [regex]::Escape($sincePrefix) + '(\S+?):(.*?)\.?\s*$')
    [pscustomobject]@{
        ids      = @(ConvertTo-IdList $list.Text.Substring($listPrefix.Length) | Select-Object -Unique)
        sinceKey = if ($sinceMatch) { $Matches[1] } else { '' }
        sinceIds = if ($sinceMatch) { @(ConvertTo-IdList $Matches[2]) } else { @() }
        runUrl   = "$(@($intro.content | ForEach-Object { @($_.marks) } | Where-Object { $_.type -eq 'link' })[0].attrs.href)"
        # A summary renamed by hand has no date: the creation date.
        date     = if ("$($Ticket.fields.summary)" -match ', (\d{4}-\d{2}-\d{2})$') { $Matches[1] } else { "$($Ticket.fields.created)".Substring(0, [Math]::Min(10, "$($Ticket.fields.created)".Length)) }
    }
}

$state = $null
# Whether this run may write the state: not when reading it failed, so a good one is not replaced by a guess.
$stateWritable = $false
if ($previous) {
    $previousText = $previous.fields.description | ConvertTo-Json -Depth 100 -Compress
    try {
        $state = Get-TicketState $previous.key
        $stateWritable = $true
        if ($null -eq $state) {
            $state = Read-DescriptionState $previous
            # Stored before anything changes: if this run fails later, the next one still has what the ticket listed.
            if ($state) {
                try { Set-TicketState $previous.key -Ids @($state.ids) -SinceKey "$($state.sinceKey)" -SinceIds @($state.sinceIds) -RunUrl "$($state.runUrl)" -Date "$($state.date)" }
                catch {
                    $stateWritable = $false
                    Write-Host "::warning::Could not store the state of $($previous.key), the next run reads its description again: $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        Write-Host "::warning::Could not read the state of $($previous.key), using its description and storing nothing: $($_.Exception.Message)"
        $state = Read-DescriptionState $previous
    }
    # An ID can also go away with a failed image scan, a new exception or an image taken out of the scan, so they
    # are "no longer found", not "fixed".
    if ($state) {
        $listedIds = @($state.ids | Where-Object { $_ })
        $goneIds = @($listedIds | Where-Object { $runIds -notcontains $_ })
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
    $runRef = New-RunRef
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
        # Against the IDs the ticket covers, the source of the gone IDs too: an ID a note in the description names
        # is still new. A ticket without a state: anywhere in the description, whole IDs only (CVE-2026-3949 is not
        # in CVE-2026-39490).
        $v.New = if ($null -ne $listedIds) { $listedIds -notcontains $v.ID }
        else { -not ($previousText -match ('(?<![\w-])' + [regex]::Escape($v.ID) + '(?![\w-])')) }
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

# The run ticket's summary and description: every vulnerability of the run, as much of the details as fits.
#   $CreatedBy: the URL of the run that created the ticket, linked from the first paragraph ('' - no link).
#   $SinceKey, $NewIds: the previous run ticket and the IDs new since it, marked in the list ($null - none).
#   $Updated: a rewrite by this run, which the counts paragraph links.
function Get-TicketSummary([string] $Date) { "[Vulnerability scan] $($vulnerabilities.Count) vulnerabilities in $($affectedImages.Count) image(s), $Date" }
function Get-DescriptionLength($Content) { (@{ type = 'doc'; version = 1; content = @($Content) } | ConvertTo-Json -Depth 100 -Compress).Length }
function New-TicketDescription([string] $CreatedBy, [string] $SinceKey, [string[]] $NewIds, [switch] $Updated) {
    $intro = if ($CreatedBy) { New-Paragraph (New-Text "$introText ") (New-Link 'Scan run' $CreatedBy) } else { New-Paragraph (New-Text $introText) }
    $counts = New-Text "Scanned images: $scannedText. Vulnerabilities: $($vulnerabilities.Count) in $($affectedImages.Count) image(s)."
    $content = @($intro)
    if ($Updated) {
        $content += New-Paragraph (New-Text 'Updated by the ') (New-RunRef 'scan run') (New-Text " on $(Get-Date -Format 'yyyy-MM-dd'). ") $counts
    }
    else { $content += New-Paragraph $counts }
    if ($SinceKey -and $NewIds.Count) {
        $content += New-Paragraph (New-Text $sincePrefix) (New-Link $SinceKey "$JiraBaseUrl/browse/$SinceKey") (New-Text ": $($NewIds -join ', ').")
    }
    # Every ID, whatever fits of the details below: the next run tells new vulnerabilities from this list.
    $content += New-Paragraph (New-Text "$listPrefix$(($vulnerabilities.ID) -join ', ')")
    if ((Get-DescriptionLength $content) -gt $maxDescriptionLength) {
        throw "$($vulnerabilities.Count) vulnerability IDs alone exceed the Jira description limit: narrow the scan."
    }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($v in $vulnerabilities) {
        $head = @(if ($v.Url) { New-Link $v.ID $v.Url } else { New-Text $v.ID @{ type = 'strong' } })
        $head += New-Text " ($($v.Severity))$(if ($NewIds -contains $v.ID) { ' - new' })"
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
    @{ type = 'doc'; version = 1; content = $content }
}

if ($previous -and $newVulnerabilities.Count -eq 0) {
    $previousUrl = "$JiraBaseUrl/browse/$($previous.key)"
    $runRef = New-RunRef
    # IDs no longer found after a run that scanned every image leave the ticket's state, so they are reported once,
    # and its description is rewritten to this run (keeping the creating run, the creation date and the "New since"
    # IDs still found). After failed scans they may only be unchecked: dropped, they would come back as new.
    # The description and the summary are each rewritten only when no other account edited them, so nothing written
    # there is lost; an edited description keeps listing the IDs, and the comment says so. When the rewrite fails or
    # the ticket cannot be checked, the state is kept, so the next run tries again (and says so again).
    $ticketDate = if ($state.date) { "$($state.date)" } else { Get-Date -Format 'yyyy-MM-dd' }
    $sinceIds = @($state.sinceIds | Where-Object { $runIds -contains $_ })
    $updated = $false
    $descriptionEdited = $false
    $dropGone = $false
    $problem = ''
    if ($goneIds.Count -and $scanComplete) {
        if (-not $stateWritable) { $problem = 'its state could not be read or stored' }
        else {
            try {
                $editedFields = Get-EditedFields $previous.key
                $descriptionEdited = $editedFields -contains 'description'
                $fields = @{}
                if ($editedFields -notcontains 'summary') { $fields.summary = Get-TicketSummary $ticketDate }
                if (-not $descriptionEdited) { $fields.description = New-TicketDescription -CreatedBy "$($state.runUrl)" -SinceKey "$($state.sinceKey)" -NewIds $sinceIds -Updated }
                if ($editedFields.Count) { Write-Host "::notice::$($previous.key): $($editedFields -join ' and ') edited by another account, not rewritten." }
                if ($fields.Count) { Invoke-Jira Put "/rest/api/3/issue/$($previous.key)" @{ fields = $fields } | Out-Null }
                $updated = -not $descriptionEdited
                $dropGone = $true
                if ($updated) { Write-Host "Removed from $($previous.key): $($goneIds -join ', ')." }
            }
            catch {
                $problem = 'it could not be updated'
                Write-Host "::warning::Could not update $($previous.key): $($_.Exception.Message)"
            }
        }
    }
    $comment = @(New-Paragraph $runRef (New-Text ": $($vulnerabilities.Count) vulnerabilities in $($affectedImages.Count) image(s), scanned $scannedText, no new ones since this ticket."))
    if ($goneIds.Count) {
        $note = if ($updated) { ', removed from the description' }
        elseif ($descriptionEdited) { '. The description was edited outside the scan, so it is not rewritten and still lists them' }
        elseif ($problem) { ", but they are still in the description: $problem, see the scan run log" }
        else { ' (not every image was scanned)' }
        $comment += New-Paragraph (New-Text "No longer found: $($goneIds -join ', ')$note.")
    }
    # The comment is the only place in Jira that names the IDs dropped from the state, so the state is written after
    # it: when it fails, the run fails (so the failure is notified) and the next run reports them again.
    try { Add-JiraComment $previous.key $comment }
    catch {
        Publish-Summary "no new vulnerabilities, could not comment on [$($previous.key)]($previousUrl), see the log"
        Set-TicketOutput $(if ($updated) { 'updated' } else { 'none' }) $previous.key $previousUrl
        throw
    }
    if ($dropGone) {
        try { Set-TicketState $previous.key -Ids $runIds -SinceKey "$($state.sinceKey)" -SinceIds $sinceIds -RunUrl "$($state.runUrl)" -Date $ticketDate }
        catch { Write-Host "::warning::Could not store the state of $($previous.key), the next run reports the same IDs again: $($_.Exception.Message)" }
    }
    Close-OlderTickets @((New-Text 'Superseded by '), (New-Link $previous.key $previousUrl))
    $did = if ($updated) { 'updated and commented on' } else { 'commented on' }
    Write-Host "No new vulnerabilities: $did $($previous.key)."
    Publish-Summary "no new vulnerabilities, $did [$($previous.key)]($previousUrl)"
    Set-TicketOutput $(if ($updated) { 'updated' } else { 'commented' }) $previous.key $previousUrl
    exit 0
}

# A new ticket: every vulnerability of the run, the new ones marked.
# Without an open run ticket every ID is new, and none is marked.
$sinceKey = if ($previous) { $previous.key }
$sinceIds = if ($previous) { @($newVulnerabilities.ID) } else { @() }
$fields = @{
    project     = @{ key = $JiraProject }
    issuetype   = @{ name = 'Task' }
    summary     = Get-TicketSummary (Get-Date -Format 'yyyy-MM-dd')
    labels      = @('Vulnerability', $Label)
    assignee    = @{ accountId = $AssigneeAccountId }
    description = New-TicketDescription -CreatedBy $runUrl -SinceKey $sinceKey -NewIds $sinceIds
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
# Without it, the next run reads the same from the description it was just given.
try { Set-TicketState $created.key -Ids $runIds -SinceKey "$sinceKey" -SinceIds $sinceIds -RunUrl $runUrl -Date (Get-Date -Format 'yyyy-MM-dd') }
catch { Write-Host "::warning::Could not store the state of $($created.key), the next run reads its description: $($_.Exception.Message)" }
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
