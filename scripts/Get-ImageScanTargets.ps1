<#
.SYNOPSIS
    Lists the container images to scan for vulnerabilities, by repository and tag masks.

.DESCRIPTION
    Reads the targets from the config file (see .github/image-vulnerability-scan.json) and returns
    them as a compact JSON array, one entry per image digest:
        [{ "image": "ghcr.io/virtocommerce/x", "tag": "2.60.0@sha256:...", "name": "2.60.0",
           "floatingTag": "latest", "digest": "sha256:...", "artifactName": "...", "username": "" }]

    "tag" pins the scan to the digest, so it scans the image that was listed even if a floating
    tag moves meanwhile, and the real tag in it stays in the scan results and Jira tickets after
    the floating tag has moved on. "name" is the image's first tag that is not floating
    (floatingTags in the config, "*latest" by default); "floatingTag" is the tag that selected
    the image when that one is floating.

    A target is one registry with:
      - repositories: masks (-like) of repository names, e.g. "virtostart/*";
      - includeTags:  tag masks; for each mask the newest maxTagsPerMask image versions that carry a
                      matching tag are taken, so "latest" gives one image and "[0-9]*" the last releases;
      - excludeTags:  tag masks that never count, e.g. "*-alpha.*";
      - username:     ACR only, the password comes from the ACR_PASSWORD environment variable.

    Registries:
      - ghcr.io: GitHub Packages API via gh; GH_TOKEN needs read:packages for the owner's packages.
      - *.azurecr.io: az acr with the registry username and password, no az login.

.EXAMPLE
    $env:GH_TOKEN = gh auth token
    ./scripts/Get-ImageScanTargets.ps1 -ConfigPath ./.github/image-vulnerability-scan.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ConfigPath,

    # A GitHub Actions matrix holds at most 256 jobs, one per image.
    [int] $MaxImages = 256
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Test-AnyLike([string] $Value, [string[]] $Masks) {
    foreach ($mask in $Masks) {
        if ($Value -like $mask) { return $true }
    }
    return $false
}

# Versions are { Digest; Tags; Updated }. Returns digest -> the tag that selected it.
function Select-ImageVersions($Versions, [string[]] $IncludeTags, [string[]] $ExcludeTags, [int] $Limit) {
    $newestFirst = @($Versions | Sort-Object Updated -Descending)
    $picked = [ordered]@{}
    foreach ($mask in $IncludeTags) {
        $count = 0
        foreach ($version in $newestFirst) {
            if ($count -ge $Limit) { break }
            $tag = $version.Tags |
                Where-Object { $_ -like $mask -and -not (Test-AnyLike $_ $ExcludeTags) } |
                Select-Object -First 1
            if (-not $tag) { continue }
            $count++
            if (-not $picked.Contains($version.Digest)) { $picked[$version.Digest] = [pscustomobject]@{ Tag = $tag; Version = $version } }
        }
    }
    return $picked
}

function Get-GhcrRepositories([string] $Owner) {
    @(gh api --paginate "/orgs/$Owner/packages?package_type=container&per_page=100" --jq '.[].name')
}

function Get-GhcrVersions([string] $Owner, [string] $Repository, [int] $MaxPages) {
    $encoded = [uri]::EscapeDataString($Repository)
    for ($page = 1; $page -le $MaxPages; $page++) {
        $items = @(gh api "/orgs/$Owner/packages/container/$encoded/versions?per_page=100&page=$page" | ConvertFrom-Json)
        if ($items.Count -eq 0) { break }
        foreach ($item in $items) {
            $tags = @($item.metadata.container.tags)
            # Untagged versions are platform manifests and attestations of a tagged image.
            if ($tags.Count -eq 0) { continue }
            [pscustomobject]@{ Digest = $item.name; Tags = $tags; Updated = [datetime] $item.updated_at }
        }
    }
}

function Get-AcrRepositories([string] $Registry, [string] $Username) {
    @(az acr repository list --name $Registry --username $Username --password $env:ACR_PASSWORD --only-show-errors -o json | ConvertFrom-Json)
}

function Get-AcrVersions([string] $Registry, [string] $Username, [string] $Repository) {
    $items = @(az acr manifest list-metadata --registry $Registry --name $Repository --username $Username --password $env:ACR_PASSWORD --orderby time_desc --only-show-errors -o json | ConvertFrom-Json)
    foreach ($item in $items) {
        $tags = @($item.tags)
        if ($tags.Count -eq 0) { continue }
        [pscustomobject]@{ Digest = $item.digest; Tags = $tags; Updated = [datetime] $item.lastUpdateTime }
    }
}

$config = Get-Content -Raw $ConfigPath | ConvertFrom-Json
$defaultLimit = if ($config.maxTagsPerMask) { [int] $config.maxTagsPerMask } else { 3 }
$maxPages = if ($config.maxGhcrVersionPages) { [int] $config.maxGhcrVersionPages } else { 5 }
$floatingTags = if ($config.floatingTags) { @($config.floatingTags) } else { @('*latest') }

$images = [System.Collections.Generic.List[object]]::new()
foreach ($target in $config.targets) {
    $registry = "$($target.registry)".ToLowerInvariant()
    $limit = if ($target.maxTagsPerMask) { [int] $target.maxTagsPerMask } else { $defaultLimit }
    $includeTags = @($target.includeTags)
    $excludeTags = @($target.excludeTags | Where-Object { $_ })

    if ($registry -eq 'ghcr.io') {
        if (-not $env:GH_TOKEN) { throw "GH_TOKEN is not set: it is needed to list the $($target.owner) packages on ghcr.io." }
        $owner = "$($target.owner)"
        $prefix = "ghcr.io/$($owner.ToLowerInvariant())"
        $username = ''
        $repositories = Get-GhcrRepositories $owner
        $getVersions = { param($repository) Get-GhcrVersions $owner $repository $maxPages }
    }
    elseif ($registry -like '*.azurecr.io') {
        if (-not $env:ACR_PASSWORD) { throw "ACR_PASSWORD is not set: it is needed to read $registry." }
        $acrName = $registry.Split('.')[0]
        $prefix = $registry
        $username = "$($target.username)"
        $repositories = Get-AcrRepositories $acrName $username
        $getVersions = { param($repository) Get-AcrVersions $acrName $username $repository }
    }
    else {
        throw "Unsupported registry '$registry': only ghcr.io and *.azurecr.io."
    }

    $matched = @($repositories | Where-Object { Test-AnyLike $_ @($target.repositories) } | Sort-Object)
    Write-Host "$registry`: $($matched.Count) of $($repositories.Count) repositories match $($target.repositories -join ', ')"
    foreach ($repository in $matched) {
        $picked = Select-ImageVersions @(& $getVersions $repository) $includeTags $excludeTags $limit
        $names = @()
        foreach ($digest in $picked.Keys) {
            $selectedBy = $picked[$digest].Tag
            # excludeTags only limit what selects an image: an excluded alpha tag is still the real name of dev-latest.
            $name = $picked[$digest].Version.Tags | Where-Object { -not (Test-AnyLike $_ $floatingTags) } | Select-Object -First 1
            if (-not $name) { $name = $selectedBy }
            $floatingTag = if ($name -ne $selectedBy) { $selectedBy } else { '' }
            $names += if ($floatingTag) { "$floatingTag -> $name" } else { $name }
            $image = "$prefix/$repository"
            $images.Add([ordered]@{
                image        = $image
                tag          = "$name@$digest"
                name         = $name
                floatingTag  = $floatingTag
                digest       = $digest
                artifactName = ("$image`_$name.json" -replace '[^A-Za-z0-9._-]', '_')
                username     = $username
            })
        }
        Write-Host "  $repository`: $(if ($names.Count) { $names -join ', ' } else { 'no matching tags' })"
    }
}

if ($images.Count -gt $MaxImages) {
    throw "$($images.Count) images match, more than ${MaxImages}: narrow the masks or lower maxTagsPerMask."
}
Write-Host "Images to scan: $($images.Count)"

ConvertTo-Json -InputObject @($images) -Compress -Depth 5
