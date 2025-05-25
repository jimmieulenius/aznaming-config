$Script:AzureUri = @{
    RegionList = 'https://raw.githubusercontent.com/MicrosoftDocs/azure-docs/refs/heads/main/articles/reliability/regions-list.md'
    ResourceNameRule = 'https://raw.githubusercontent.com/MicrosoftDocs/azure-docs/refs/heads/main/articles/azure-resource-manager/management/resource-name-rules.md'
    ResourceType = 'https://raw.githubusercontent.com/Azure/bicep-types-az/a1f912858bde4b99de09da237394f87d9ecaac48/generated/index.md'
}

$Destination = 'C:\Users\J63443\OneDrive - E.ON\Source\personal\aznaming-config\config'

function Initialize-Object {
    param (
        [String]
        $Path
    )

    if (
        ($Path) `
        -and (
            Test-Path `
                -Path $Path `
                -PathType 'Leaf'
        )
    ) {
        return (
            Get-Content `
                -Path $Path `
                -Raw `
            | ConvertFrom-Json `
                -AsHashtable
        ) ?? [Ordered]@{}
    }
    
    return [Ordered]@{}
}

function Get-WebResponse {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $Uri,

        [Switch]
        $AsCustomObject
    )

    $webrequest = [System.Net.HttpWebRequest]::Create($Uri)
    $response = $webrequest.GetResponse()
    $responseStream = $response.GetResponseStream()
    $streamReader = [System.IO.StreamReader]::new($responseStream)

    if ($AsCustomObject) {
        $result = [PSCustomObject]@{
            StreamReader = $streamReader
            Response = $response
            ResponseStream = $responseStream
        }

        $result `
        | Add-Member `
            -MemberType 'ScriptMethod' `
            -Name 'Dispose' `
            -Value {
                @(
                    $this.Response,
                    $this.ResponseStream,
                    $this.StreamReader
                ) `
                | ForEach-Object {
                    if ($_ -is [System.IDisposable]) {
                        $_.Dispose()
                    }
                }
            } `
            -Force

        return $result
    }

    try {
        while ($streamReader.Peek() -ge 0)
        {
            $streamReader.ReadLine()
        }
    }
    finally {
        @(
            $response,
            $responseStream,
            $streamReader
        ) `
        | ForEach-Object {
            if ($_ -is [System.IDisposable]) {
                $_.Dispose()
            }
        }
    }
}

function Get-CheckNameAvailabilityRequest {
    param (
        [String]
        $SubscriptionId,

        [Parameter(Mandatory = $true)]
        [String]
        $Provider,

        [Parameter(Mandatory = $true)]
        [String[]]
        $ApiVersion,

        [Parameter(Mandatory = $true)]
        [String]
        $ResourceType
    )

    $uriFormat = "https://management.azure.com"
    $name = 'checkNameAvailability'

    if ($SubscriptionId) {
        $uriFormat = "$uriFormat/subscriptions/{0}"
    }

    $uriFormat = "$uriFormat/providers/$Provider/$($name)?api-version={1}"

    $ResourceType = $ResourceType.Split('::')[0]

    $payload = @{
        name = 'aaaaa'
        type = $ResourceType
    }

    $ignoreStatusCode = @(
        403,
        404
    )

    foreach ($apiVersionItem in $ApiVersion) {
        $uri = $uriFormat -f $SubscriptionId, $apiVersionItem

        $response = Invoke-AzRestMethod `
            -Uri $uri `
            -Method 'POST' `
            -Payload (
                $payload `
                | ConvertTo-Json `
                    -Compress
            )

        # $response = $httpClient.PostAsync(
        #     $uri,
        #     [System.Net.Http.StringContent]::new(
        #         (
        #             $body `
        #             | ConvertTo-Json `
        #                 -Compress
        #         ),
        #         [System.Text.Encoding]::UTF8, 'application/json'
        #     )
        # ).
        # GetAwaiter(). `
        # GetResult()

        if ($response.StatusCode -eq 200) {
            if ($response.Content) {
                $content = $response.Content `
                | ConvertFrom-Json `
                    -AsHashtable

                if ($content) {
                    if ($content.reason -ieq 'Invalid') {
                        Write-Host $content.message

                        return
                    }
                }
            }

            # [Hashtable] $body = $body
            $payload.name = '{NAME}'

            return [Ordered]@{
                Method = 'POST'
                Uri = $uriFormat -f '{0}', $apiVersionItem
                ApiVersion = $apiVersionItem
                Body = $payload
            }
        }
    }

    if ($response.StatusCode -notin $ignoreStatusCode) {
        Write-Host "$($ResourceType): $($response.StatusCode)"
        Write-Host "Uri: $($uri)"

        if ($response.Content) {
            Write-Host ($response.Content)
        }
    }
}

# function Invoke-Retry {
#     param (
#         [Parameter(
#             Mandatory = $true,
#             ValueFromPipeline = $true
#         )]
#         [ScriptBlock]
#         $InputObject,

#         [Int]
#         $RetryCount = 3,

#         [Int]
#         $Delay = 1000
#     )

#     for ($retryIndex = 0; $retryIndex -lt $RetryCount; $retryIndex++) {
#         $shouldProcess = $false
#         $errorOutput = $null

#         try {
#             $errorOutput = (
#                 $result = & $InputObject
#             ) 2>&1

#             if ($errorOutput.Exception) {
#                 $shouldProcess = $true
#             }
#         }
#         catch {
#             $errorOutput = $_
#             $shouldProcess = $true
#         }

#         if (-not $shouldProcess) {
#             return $result
#         }

#         if ($retryIndex -eq ($RetryCount - 1)) {
#             throw $errorOutput
#         }

#         Start-Sleep `
#             -Milliseconds $Delay
#     }
# }

New-Item `
    -Path $Destination `
    -ItemType 'Directory' `
    -ErrorAction 'SilentlyContinue' `
| Out-Null

$destinationPath = "$Destination/restApis.json"

$content = Initialize-Object `
    -Path $destinationPath

$subscriptionId = (Get-AzContext).Subscription.Id

$lastLine = $null
$isTableBody = $false
$provider = $false

$resourceTypeReader = Get-WebResponse `
    -Uri $Script:AzureUri.ResourceType `
    -AsCustomObject

$count = @(0, 0)

$baseId = 'default.restapis'

# $resourceTypeList = [System.Collections.Generic.List[String]]::new()
# $allResourceTypeList = [System.Collections.Generic.List[String]]::new()

try {
    Get-WebResponse `
        -Uri $Script:AzureUri.ResourceNameRule `
    | ForEach-Object {
        if ($_ -match ' *##.*') {
            $provider = @(
                (
                    (
                        (($_ -replace '#', $null).Trim() -split '\.') `
                        | Select-Object `
                            -Skip 1
                    ) -join '.'
                ),
                ($provider ?? @())[1]
            )

            $isTableBody = $false
        }

        if ($provider[0]) {
            if (
                (-not $provider[1]) `
                -or ($provider[1] -ile $provider[0])
            ) {
                while ($resourceTypeReader.StreamReader.Peek() -ge 0) {
                    if (-not $skipReadLine) {
                        $line = $resourceTypeReader.StreamReader.ReadLine()
                    }

                    $skipReadLine = $false
            
                    if ($line -imatch '(^ *## *microsoft\.)(.*)') {
                        $provider[1] = $Matches[2]

                        if ($provider[1] -gt $provider[0]) {
                            $skipReadLine = $true

                            break
                        }

                        $providerNamespace = @{}
                    }
                    elseif ($line -imatch '(^ *### *microsoft\.)(.*)') {
                        if ($provider[0] -ieq $provider[1]) {
                            $namespace = $Matches[2]
                            $providerNamespace.$namespace = @{
                                ApiVersion = [System.Collections.Generic.List[String]]::new()
                                Provider = "Microsoft.$($provider[0])"
                            }
                        }
                    }
                    elseif ($line -match '(\* *\*\*Link\*\*: *)\[(.*)\]') {
                        if ($provider[0] -ieq $provider[1]) {
                            $providerNamespaceItem = $providerNamespace.$namespace

                            if ($providerNamespaceItem) {
                                $providerNamespaceItem.ApiVersion.Add($Matches[2])
                            }
                        }
                    }
                }
            }

            if ($lastLine -imatch '^ *> *\| *---') {
                $isTableBody = $true
            }

            if ($isTableBody) {
                if (-not $_) {
                    $isTableBody = $false
                    $provider = @(
                        $null,
                        ($provider ?? @())[1]
                    )
                    $providerNamespace = @{}
                    $line = $resourceTypeReader.StreamReader.ReadLine()
                    $skipReadLine = $true
                }

                if ($_ -imatch '^ *> *\|') {
                    $cell = ($_ -split '\|')[1..4]
                    $namespace = @(
                        (("$($provider[0])/$($cell[0])" -replace ' |\*', $null) -replace '//', '/')
                    )

                    $count[0]++

                    # $allResourceTypeList.Add($resourceTypeNamespace[0])
                    # $resourceTypeNamespace

                    $namespace += ($namespace[0] -replace '-', $null)

                    foreach ($namespaceItem in $namespace) {
                        $providerNamespaceItem = $providerNamespace.$namespaceItem

                        if ($providerNamespaceItem) {
                            # $checkNameRequest = Get-CheckNameAvailabilityRequest `
                            #     -SubscriptionId $subscriptionId `
                            #     -Provider $providerNamespaceItem.Provider `
                            #     -ApiVersion $providerNamespaceItem.ApiVersion `
                            #     -ResourceType "Microsoft.$namespaceItem"

                            switch ($namespaceItem) {
                                ('Management/managementGroups') {
                                    $checkNameRequest = Get-CheckNameAvailabilityRequest `
                                        -Provider $providerNamespaceItem.Provider `
                                        -ApiVersion $providerNamespaceItem.ApiVersion `
                                        -ResourceType "Microsoft.$namespaceItem"
                                }
                                ('Media/mediaservices') {
                                    $checkNameRequest = Get-CheckNameAvailabilityRequest `
                                        -SubscriptionId $subscriptionId `
                                        -Provider $providerNamespaceItem.Provider `
                                        -ApiVersion $providerNamespaceItem.ApiVersion `
                                        -ResourceType 'mediaServices'
                                }
                                ('Search/searchServices') {
                                    $checkNameRequest = Get-CheckNameAvailabilityRequest `
                                        -SubscriptionId $subscriptionId `
                                        -Provider $providerNamespaceItem.Provider `
                                        -ApiVersion $providerNamespaceItem.ApiVersion `
                                        -ResourceType 'searchServices'
                                }
                                { $_.StartsWith('ServiceBus') } {
                                    $checkNameRequest = (
                                        ($_ -ieq 'ServiceBus/namespaces') `
                                        ? (
                                            Get-CheckNameAvailabilityRequest `
                                                -SubscriptionId $subscriptionId `
                                                -Provider $providerNamespaceItem.Provider `
                                                -ApiVersion $providerNamespaceItem.ApiVersion `
                                                -ResourceType "Microsoft.$namespaceItem"
                                        ) `
                                        : $null
                                    )

                                    $body = $checkNameRequest.Body

                                    if ($body) {
                                        $body.Remove('type')
                                    }
                                }
                                default {
                                    $checkNameRequest = Get-CheckNameAvailabilityRequest `
                                        -SubscriptionId $subscriptionId `
                                        -Provider $providerNamespaceItem.Provider `
                                        -ApiVersion $providerNamespaceItem.ApiVersion `
                                        -ResourceType "Microsoft.$namespaceItem"
                                }
                            }

                            if ($checkNameRequest) {
                                $content.$namespaceItem = [Ordered]@{
                                    '$id' = "$baseId.$($namespaceItem.Replace('.', $null).ToLower())"
                                    properties = @{
                                        requests = [Ordered]@{
                                            checkNameAvailability = $checkNameRequest
                                            exist = [Ordered]@{
                                                Method = 'GET'
                                                Uri = "https://management.azure.com/subscriptions/{0}/resourcegroups/{1}/providers/$($providerNamespaceItem.Provider)/{2}?api-version=$($providerNamespaceItem.ApiVersion[0])"
                                            }
                                        }
                                    }
                                }

                                # (
                                #     (
                                #         "`"$namespaceItem`": $(
                                #             @{
                                #                 properties = @{
                                #                     requests = [Ordered]@{
                                #                         checkNameAvailability = $checkNameRequest
                                #                         exist = [Ordered]@{
                                #                             Method = 'GET'
                                #                             Uri = "https://management.azure.com/subscriptions/{0}/resourcegroups/{1}/providers/$($providerNamespaceItem.Provider)/{2}?api-version=$($providerNamespaceItem.ApiVersion[0])"
                                #                         }
                                #                     }
                                #                 }
                                #             } `
                                #             | ConvertTo-Json `
                                #                 -Depth 100
                                #         )" -split '\r?\n'
                                #     ) `
                                #     | ForEach-Object {
                                #         "$(' ' * 2)$_"
                                # }
                                # ) -join "`n"
                            }

                            # $namespaceItem
                            # $providerNamespaceItem `
                            # | ConvertTo-Json `
                            #     -Depth 100

                            $count[1]++

                            break
                        }
                    }

                    if (-not $providerNamespaceItem) {
                        $namespace[0]
                    }

                    # while ($resourceTypeReader.StreamReader.Peek() -ge 0) {
                    #     # if ('ApiManagement/service/api-version-sets' -iin $resourceTypeNamespace) {
                    #     #     $v = 1
                    #     # }

                    #     # if ($resourceTypeItem.Namespace -iin $resourceTypeNamespace) {
                    #     #     $resourceTypeList.Add($resourceTypeNamespace[0])

                    #     #     $skipReadLine = $false
                    #     #     # $resourceTypeItem = $
                    #     #     $count[1]++

                    #     #     break
                    #     # }

                    #     if (-not $skipReadLine) {
                    #         $line = $resourceTypeReader.StreamReader.ReadLine()
                    #     }

                    #     $skipReadLine = $false
                
                    #     if ($line -imatch '(^ *## *microsoft\.)(.*)') {
                    #         $provider[1] = $Matches[2]
                    #         $providerNamespace = @{}
                    #     }
                    #     elseif ($line -imatch '(^ *### *microsoft\.)(.*)') {
                    #         if ($provider[0] -ieq $provider[1]) {
                    #             $namespace = $Matches[2]
                    #             $providerNamespace.$namespace = @{
                    #                 ApiVersion = [System.Collections.Generic.List[String]]::new()
                    #             }

                    #             # if (
                    #             #     ($namespace -gt $resourceTypeNamespace[0]) `
                    #             #     -or ($namespace -gt $resourceTypeNamespace[1])
                    #             # ) {
                    #             #     $skipReadLine = $true
                    #             #     # $resourceTypeItem = $null

                    #             #     break
                    #             # }
                        
                    #             # $resourceTypeItem = [Ordered]@{
                    #             #     Namespace = $namespace
                    #             #     ApiVersion = $null
                    #             # }

                    #             # if ($resourceTypeItem.Namespace -iin $resourceTypeNamespace) {
                    #             #     $resourceTypeList.Add($resourceTypeNamespace[0])
        
                    #             #     $skipReadLine = $false
                    #             #     # $resourceTypeItem = $
                    #             #     $count[1]++
        
                    #             #     break
                    #             # }
                    #         }
                    #     }
                    #     elseif ($line -match '(\* *\*\*Link\*\*: *)\[(.*)\]') {
                    #         # if ($resourceTypeItem) {
                    #         #     $resourceTypeItem.ApiVersion = $Matches[2]
                    #         # }

                    #         if ($provider[0] -ieq $provider[1]) {
                    #             $providerNamespaceItem = $providerNamespace.$namespace

                    #             if ($providerNamespaceItem) {
                    #                 $providerNamespaceItem.ApiVersion.Add($Matches[2])
                    #             }
                    #         }
                    #     }
                    # }
                }
            }
        }

        $lastLine = $_
    }

    $result = [Ordered]@{
        '$id' = $baseId
    }

    $content.GetEnumerator() `
    | ForEach-Object {
        $result.($_.Key) = $_.Value
    }

    New-Item `
        -Path $destinationPath `
        -ItemType 'File' `
        -Value (
            $result `
            | ConvertTo-Json `
                -Depth 100
        ) `
        -Force
    | Out-Null
}
finally {
    $resourceTypeReader.Dispose()
}

# $m = $allResourceTypeList `
# | Where-Object { $resourceTypeList -inotcontains $_ }

# $m

$count

# $m.Length

# $resourceTypeList

exit

$resourceType = [System.Collections.Generic.List[Ordered]]::new()

try {
    while ($resourceTypeReader.StreamReader.Peek() -ge 0) {
        $line = $resourceTypeReader.StreamReader.ReadLine()

        if ($line -match '(^ *### *)(.*)') {
            if ($resourceTypeItem) {
                $resourceType.Add($resourceTypeItem)
            }
    
            $resourceTypeItem = [Ordered]@{
                Namespace = $Matches[2].Split('.')[1]
                ApiVersion = $null
            }
        }
        elseif ($line -match '(\* *\*\*Link\*\*: *)\[(.*)\]') {
            $resourceTypeItem.ApiVersion = $Matches[2]
        }
    }
}
finally {
    $resourceTypeReader.Dispose()
}

# Get-WebResponse `
#     -Uri $Uri `
# | ForEach-Object {
#     if ($_ -match '(^ *### *)(.*)') {
#         if ($resourceTypeItem) {
#             $resourceType.Add($resourceTypeItem)
#         }

#         $resourceTypeItem = [Ordered]@{
#             Namespace = $Matches[2]
#             ApiVersion = $null
#         }
#     }
#     elseif ($_ -match '(\* *\*\*Link\*\*: *)\[(.*)\]') {
#         $resourceTypeItem.ApiVersion = $Matches[2]
#     }
# }

$resourceType.Add($resourceTypeItem)

$resourceType