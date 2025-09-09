param(
    [Parameter(Mandatory = $true)]
    [string]$teamsWebhookUrl,
    [Parameter(Mandatory = $true)]
    [hashtable[]]$mentions,
    [string]$stageName,
    [string]$buildDefinitionName,
    [string]$BuildId,
    [string]$adoOrg,
    [string]$adoProject
)
$mentionTags = ($mentions | ForEach-Object { "<at>$($_.name)</at>" }) -join ", "
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
                        text   = "🚨 $stageName Stage Failed!"
                        weight = "Bolder"
                        color  = "Attention"
                        size   = "Large"
                    },
                    @{
                        type = "TextBlock"
                        text = "$mentionTags please check pipeline **$buildDefinitionName** - Run **$BuildId** - [View Run]($adoOrg/$adoProject/_build/results?buildId=$BuildId&view=results)"
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
Invoke-RestMethod -Uri $teamsWebhookUrl -Method Post -Body $body -ContentType 'application/json'