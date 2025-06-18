Import-Module `
    -Name "$PSScriptRoot/AzNaming.Config.psm1" `
    -Force

# Build-LocationSource `
#     -Destination "$PSScriptRoot/../src"

# Initialize-ResourceTypeConfig `
#     -Destination "$PSScriptRoot/../src"

Build-Config

exit

$response = Invoke-WebRequest `
    -Uri 'https://raw.githubusercontent.com/MicrosoftDocs/azure-docs/refs/heads/main/articles/reliability/regions-list.md'

$lastLine = $null
$isRegionList = $false
$isTableBody = $false

foreach ($line in ($response.Content -split '\r?\n')) {
    if ($line -match '## Azure regions list') {
        $isRegionList = $true
    }

    if ($isRegionList) {
        if ($lastLine -imatch '^\|-') {
            $isTableBody = $true
        }

        if ($isTableBody) {
            if (-not $line) {
                break
            }

            if ($line -imatch '^\|') {
                $name = (($line -split '\|')[1]).Trim()

                if ($name -inotmatch '^:::.*') {
                    $name = $name -replace ' ', $null

                    $name
                }
            }
        }
    }

    $lastLine = $line
}