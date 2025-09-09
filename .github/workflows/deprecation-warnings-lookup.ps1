# $repos = gh repo list VirtoCommerce --json name -q '.[].name'
[array]$repos = 'vc-platform', 'vc-build', 'vc-module-x-api'
$fields = 'databaseId,name,conclusion'
$result = @()
$skipValues = @('angular-cookies@1.8.3', 'angular-translate-loader-url@2.', 'glob@7.1.7')

foreach ($repo in $repos) {
    echo "Checking repo: $repo"
    [array]$runs = gh run list -R VirtoCommerce/$repo --limit 5 --json $fields | ConvertFrom-Json
    foreach ($run in $runs) {
        $runId = "$($run.databaseId)"
        $deprecationWarnings = gh run view $runId -R VirtoCommerce/$repo | Select-String -Pattern "deprecated"
        if ($deprecationWarnings) {
            # echo "Deprecation warnings found in run $repo/$runId"
            # echo $deprecationWarnings
            foreach ($warning in $deprecationWarnings) {
                $skip = $false
                foreach ($skipValue in $skipValues) {
                    if ($warning.Line -match $skipValue) {
                        # continue
                        $skip = $true
                        break
                    }
                }
                if (!$skip) {
                    $result += @{
                        $run.name = @{
                            "https://github.com/VirtoCommerce/$repo/actions/runs/$runId" = $warning.Line
                        }
                    }
                }
            }
        }
    }
    echo "Done"
}
if ($result) {
    echo $result | ConvertTo-Json -Depth 10 | Out-File -FilePath "deprecation-warnings.json"

}