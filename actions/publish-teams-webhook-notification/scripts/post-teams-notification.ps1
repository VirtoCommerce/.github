param(
    [Parameter(Mandatory = $true)]
    [string]$teamsWebhookUrl,
    [hashtable[]]$mentions,
    [string]$title,
    [string]$workflowName,
    [string]$buildId,
    [string]$githubRepo
)
# No mentions ('@()' evaluates to $null) must not become an empty <at></at> and a mention without an id.
$mentions = @($mentions | Where-Object { $_ })
$mentionTags = ($mentions | ForEach-Object { "<at>$($_.name)</at>" }) -join ", "
$checkText = if ($mentionTags) { "$mentionTags please check" } else { 'Please check' }
$body = @{
    type        = "message"
    attachments = @(@{
            contentType = "application/vnd.microsoft.card.adaptive"
            contentUrl  = $null
            content     = @{
                type    = "AdaptiveCard"
                version = "1.4"
                body    = @(
                    @{
                        type   = "TextBlock"
                        text   = "🚨 $title"
                        weight = "Bolder"
                        color  = "Attention"
                        size   = "Large"
                    },
                    @{
                        type = "TextBlock"
                        text = "$checkText pipeline **$workflowName** - Run **$buildId** - [View Run](https://github.com/$githubRepo/actions/runs/$buildId)"
                        wrap = $true
                    }
                )
                msteams = @{
                    entities = @(
                        $mentions | ForEach-Object {
                            @{
                                type      = "mention"
                                text      = "<at>$($_.name)</at>"
                                mentioned = @{
                                    id   = $_.id
                                    name = $_.name
                                }
                            }
                        }
                    )
                }
            }
        })
} | ConvertTo-Json -Depth 10
# An Office 365 connector answers 200 "1" (an error as 200 with its text), a Teams Workflows webhook 202 with no
# body; a non-2xx status throws.
try {
    $response = Invoke-WebRequest -Uri $teamsWebhookUrl -Method Post -Body $body -ContentType 'application/json' -UseBasicParsing
    # Without a text Content-Type the body comes as bytes.
    $content = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { "$($response.Content)" }
    $callResult = $content.Trim()
}
catch {
    Write-Output "There was an error sending the message to Teams"
    Write-Output "Call result: $($_.Exception.Message)"
    exit 1
}
if ($callResult -and $callResult -ne '1') {
    Write-Output "There was an error sending the message to Teams"
    Write-Output "Call result: $callResult"
    exit 1
}
Write-Output "Message sent to Teams (HTTP $($response.StatusCode))"