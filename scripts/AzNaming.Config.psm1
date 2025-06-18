$Script:AzureUri = @{
    RegionList = 'https://raw.githubusercontent.com/MicrosoftDocs/azure-docs/refs/heads/main/articles/reliability/regions-list.md'
    ResourceNameRule = 'https://raw.githubusercontent.com/MicrosoftDocs/azure-docs/refs/heads/main/articles/azure-resource-manager/management/resource-name-rules.md'
    ResourceType = 'https://raw.githubusercontent.com/Azure/bicep-types-az/a1f912858bde4b99de09da237394f87d9ecaac48/generated/index.md'
}

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
        return Get-Content `
            -Path $Path `
            -Raw `
        | ConvertFrom-Json `
            -AsHashtable
    }
    
    return [Ordered]@{}
}

function Build-ComponentConfig {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $ConfigPath,

        [String]
        $Name,

        [Parameter(Mandatory = $true)]
        [String]
        $Destination,

        [ValidateSet(
            'instance',
            'dictionary',
            'childDictionary',
            'freeText',
            'unique'
        )]
        [String]
        $Type = 'freeText',

        [ScriptBlock]
        $Process
    )

    function Invoke-Item {
        param (
            [Parameter(ValueFromPipeline = $true)]
            [Object]
            $InputObject,

            [ScriptBlock]
            $Process
        )

        process {
            & $Process
        }
    }

    if (-not $Name) {
        $Name = Split-Path `
            -Path $ConfigPath `
            -LeafBase
    }

    New-Item `
        -Path $Destination `
        -ItemType 'Directory' `
        -ErrorAction 'SilentlyContinue' `
    | Out-Null

    $fileName = Split-Path `
        -Path $ConfigPath `
        -LeafBase

    $result = @{
        $Name = [Ordered]@{
            '$id' = "default.components.$Name".ToLower()
            type = 'dictionary'
        }
    }
    $properties = [Ordered]@{}

    switch ($Type) {
        ('dictionary') {
            $source = [Ordered]@{}

            (
                Get-Content `
                    -Path $ConfigPath `
                    -Raw
                | ConvertFrom-Json `
                    -AsHashtable
            ).GetEnumerator() `
            | ForEach-Object {
                $keyValue = $_

                if (-not ('<TODO>' -iin $keyValue.Value.Values)) {
                    $item = $keyValue `
                    | Invoke-Item `
                        -Process $Process

                    $item `
                    | ForEach-Object {
                        if ($_.Key -and $_.Value) {
                            $source.($_.Key) = $_.Value
                        }
                        else {
                            $source.($keyValue.Key) = $_
                        }
                    }
                }
            }

            $properties.source = $source
        }
    }

    $result.$Name.properties = $properties

    New-Item `
        -Path "$Destination/$fileName.json" `
        -ItemType 'File' `
        -Value (
            $result `
            | ConvertTo-Json `
                -Depth 100
        ) `
        -Force
    | Out-Null
}

function Build-Config {
    $sourcePath = "$PSScriptRoot/../src"
    $configBasePath = "$PSScriptRoot/../config"
    $configComponentPath = "$configBasePath/components"

    $sourceFile = Build-ResourceTypeSource `
        -Destination $sourcePath `
        -PassThru

    Build-ComponentConfig `
        -ConfigPath $sourceFile.FullName `
        -Name 'RESOURCE_TYPE' `
        -Destination $configComponentPath `
        -Type 'dictionary' `
        -Process {
            @{
                Key = $_.Key
                Value = $_.Value.abbreviation
            }
            @{
                Key = $_.Value.abbreviation
                Value = $_.Value.abbreviation
            }
        }

    Build-TemplateConfig `
        -SourcePath $sourceFile.FullName `
        -DefaultTemplate (
            [Ordered]@{
                '$id' = 'default.templates.default'
                properties = [Ordered]@{
                    name = 'default'
                    shortName = 'default'
                    template = '{RESOURCE_TYPE}[{-}]{WORKLOAD}[{-}]{ENVIRONMENT}[{-}]{REGION}[{-}{INSTANCE}]'
                    lengthMax = 1024
                    lengthMin = 1
                    casing = 'none'
                    values = @{
                        SEPARATOR = '-'
                    }
                    validText = [String]::Empty
                    invalidText = [String]::Empty
                    invalidCharacters = [String]::Empty
                    invalidCharactersStart = [String]::Empty
                    invalidCharactersEnd = [String]::Empty
                    invalidCharactersConsecutive = [String]::Empty
                    regex = [String]::Empty
                    staticValue = [String]::Empty
                }
            }
        ) `
        -ComponentKey 'RESOURCE_TYPE' `
        -Destination $configBasePath

    $sourceFile = Build-LocationSource `
        -Destination $sourcePath `
        -PassThru

    Build-ComponentConfig `
        -ConfigPath $sourceFile.FullName `
        -Name 'LOCATION' `
        -Destination $configComponentPath `
        -Type 'dictionary' `
        -Process {
            @{
                Key = $_.Key
                Value = $_.Value.abbreviation
            }
            @{
                Key = $_.Value.abbreviation
                Value = $_.Value.abbreviation
            }
        }

    # Build-RestApiConfig `
    #     -Destination $configBasePath
}

# function Build-RestApiConfig {
#     param (
#         [Parameter(Mandatory = $true)]
#         [String]
#         $Destination,

#         [String]
#         $ConfigDirectory = "$PSScriptRoot/../../../../config"
#     )

#     function Get-Request {
#         param (
#             [Parameter(
#                 Mandatory = $true,
#                 ValueFromPipeline = $true
#             )]
#             [String]
#             $InputObject,

#             [String]
#             $SubscriptionId,

#             [Parameter(Mandatory = $true)]
#             [String[]]
#             $ApiVersion,

#             [Parameter(Mandatory = $true)]
#             [String]
#             $ResourceType
#         )

#         if (-not $SubscriptionId) {
#             $SubscriptionId = (Get-AzContext).Subscription.Id
#         }

#         $ResourceType = $ResourceType.Split('::')[0]

#         $body = @{
#             name = 'aaaaa'
#             type = $ResourceType
#         }

#         foreach ($apiVersionItem in $ApiVersion) {
#             $uri = $InputObject -f $SubscriptionId, $apiVersionItem

#             $response = $httpClient.PostAsync(
#                 $uri,
#                 [System.Net.Http.StringContent]::new(
#                     (
#                         $body `
#                         | ConvertTo-Json `
#                             -Compress
#                     ),
#                     [System.Text.Encoding]::UTF8, 'application/json'
#                 )
#             ).
#             GetAwaiter(). `
#             GetResult()

#             if ($response.IsSuccessStatusCode) {
#                 if ($response.Content) {
#                     $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() `
#                     | ConvertFrom-Json `
#                         -AsHashtable

#                     if ($content) {
#                         if ($content.reason -ieq 'Invalid') {
#                             Write-Host $content.message

#                             return
#                         }
#                     }
#                 }

#                 [Hashtable] $body = $body
#                 $body.name = '{NAME}'

#                 return @{
#                     Uri = $InputObject -f '{0}', $apiVersionItem
#                     ApiVersion = $apiVersionItem
#                     Body = $body
#                 }
#             }
#         }

#         if ($response.StatusCode -ine 'NotFound') {
#             Write-Host "$($ResourceType): $($response.StatusCode)"

#             if ($response.Content) {
#                 Write-Host ($response.Content.ReadAsStringAsync().Result)
#             }
#         }
#     }

#     $action = 'checkNameAvailability'
#     $provider = @{}

#     $httpClient = [System.Net.Http.HttpClient]::new()
#     $httpClient.DefaultRequestHeaders.Accept.Add([System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new("application/json"))
#     $httpClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new(
#         "Bearer",
#         [Azure.Identity.DefaultAzureCredential]::new().GetToken([Azure.Core.TokenRequestContext]::new(@("https://management.azure.com/.default"))).Token
#     )

#     Get-AzResourceProvider `
#     | Where-Object { $_.ResourceTypes.ResourceTypeName -ieq $action } `
#     | ForEach-Object {
#         $provider.($_.ProviderNamespace) = @{
#             ApiVersion = $_.ResourceTypes.ApiVersions `
#                 | Select-Object `
#                     -Unique `
#                 | Sort-Object `
#                     -Descending
#         }
#     }

#     $baseId = 'default.restApis'
#     $content = [Ordered]@{
#         '$id' = $baseId
#     }
#     $subscriptionId = (Get-AzContext).Subscription.Id

#     (
#         Get-Content `
#             -Path "$ConfigDirectory/resourceTypes.json" `
#             -Raw `
#         | ConvertFrom-Json `
#             -AsHashtable
#     ).GetEnumerator() `
#     | ForEach-Object {
#         $providerNamespace = $_.Value.namespace.Split('/')[0]
#         $providerItem = $provider[$providerNamespace]

#         if ($providerItem) {
#             $checkNameBaseUri = "https://management.azure.com/subscriptions/{0}/providers/"
#             $namespace = $_.Value.namespace

#             switch ($_.Key) {
#                 ('Management/managementGroups') {
#                     $checkNameRequest = "https://management.azure.com/providers/$($providerNamespace)/$($action)?api-version={1}" `
#                     | Get-Request `
#                         -SubscriptionId $subscriptionId `
#                         -ApiVersion $providerItem.ApiVersion `
#                         -ResourceType $namespace
#                 }
#                 ('Media/mediaservices') {
#                     $checkNameRequest = "$($checkNameBaseUri)$($providerNamespace)/$($action)?api-version={1}" `
#                     | Get-Request `
#                         -SubscriptionId $subscriptionId `
#                         -ApiVersion $providerItem.ApiVersion `
#                         -ResourceType 'mediaServices'
#                 }
#                 ('Search/searchServices') {
#                     $checkNameRequest = "$($checkNameBaseUri)$($providerNamespace)/$($action)?api-version={1}" `
#                     | Get-Request `
#                         -SubscriptionId $subscriptionId `
#                         -ApiVersion $providerItem.ApiVersion `
#                         -ResourceType 'searchServices'
#                 }
#                 { $_.StartsWith('ServiceBus') } {
#                     $checkNameRequest = (
#                         ($_ -ieq 'ServiceBus/namespaces') `
#                         ? (
#                             "$($checkNameBaseUri)$($providerNamespace)/$($action)?api-version={1}" `
#                             | Get-Request `
#                                 -SubscriptionId $subscriptionId `
#                                 -ApiVersion $providerItem.ApiVersion `
#                                 -ResourceType $namespace
#                         ) `
#                         : $null
#                     )

#                     $body = $checkNameRequest.Body

#                     if ($body) {
#                         $body.Remove('type')
#                     }
#                 }
#                 default {
#                     $checkNameRequest = "$($checkNameBaseUri)$($providerNamespace)/$($action)?api-version={1}" `
#                     | Get-Request `
#                         -SubscriptionId $subscriptionId `
#                         -ApiVersion $providerItem.ApiVersion `
#                         -ResourceType $namespace
#                 }
#             }

#             if ($checkNameRequest) {
#                 $content.($_.Key) = [Ordered]@{
#                     '$id' = "$baseId.$($_.Key)".ToLower()
#                     properties = [Ordered]@{
#                         apiVersion = $checkNameRequest.ApiVersion
#                         requests = [Ordered]@{
#                             checkName = [Ordered]@{
#                                 uri = $checkNameRequest.Uri
#                                 body = $checkNameRequest.Body
#                             }
#                             exist = [Ordered]@{
#                                 uri = "https://management.azure.com/subscriptions/{0}/resourcegroups/{1}/providers/$($_.Value.namespace)/{2}?api-version=$($checkNameRequest.ApiVersion)"
#                             }
#                         }
#                     }
#                 }
#             }
#             else {
#                 Write-Host $providerNamespace
#                 Write-Host $namespace
#                 Write-Host '---'
#             }
#         }
#     }

#     New-Item `
#         -Path $Destination `
#         -ItemType 'Directory' `
#         -ErrorAction 'SilentlyContinue' `
#     | Out-Null

#     $destinationPath = "$Destination/restApis.json"

#     Remove-Item `
#         -Path $destinationPath `
#         -ErrorAction 'SilentlyContinue' `
#         -Force

#     New-Item `
#         -Path $destinationPath `
#         -ItemType 'File' `
#         -ErrorAction 'SilentlyContinue' `
#     | Out-Null

#     Set-Content `
#         -Path $destinationPath `
#         -Value (
#             $content `
#             | ConvertTo-Json `
#                 -Depth 100
#         )
# }

function Build-TemplateConfig {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $SourcePath,

        [System.Collections.Specialized.OrderedDictionary]
        $DefaultTemplate,

        [String]
        $ComponentKey,

        [Parameter(Mandatory = $true)]
        [String]
        $Destination,

        [ScriptBlock]
        $Process
    )

    # function Invoke-Item {
    #     param (
    #         [Parameter(ValueFromPipeline = $true)]
    #         [Object]
    #         $InputObject,

    #         [ScriptBlock]
    #         $Process
    #     )

    #     process {
    #         & $Process
    #     }
    # }

    # function Initialize-Object {
    #     param (
    #         [String]
    #         $Path
    #     )

    #     if (
    #         ($Path) `
    #         -and (
    #             Test-Path `
    #                 -Path $Path `
    #                 -PathType 'Leaf'
    #         )
    #     ) {
    #         return Get-Content `
    #             -Path $Path `
    #             -Raw `
    #         | ConvertFrom-Json `
    #             -AsHashtable
    #     }
        
    #     return [Ordered]@{}
    # }

    New-Item `
        -Path $Destination `
        -ItemType 'Directory' `
        -ErrorAction 'SilentlyContinue' `
    | Out-Null

    $destinationPath = "$Destination/templates.json"

    $content = Initialize-Object `
        -Path $destinationPath

    $aliasDestinationPath = "$Destination/aliases.templates.json"

    $alias = Initialize-Object `
        -Path $aliasDestinationPath

    $baseId = 'default.templates'

    if (
        ($DefaultTemplate) `
        -and ($DefaultTemplate.Keys)
    ) {
        $content.default = $DefaultTemplate
    }

    (
        Get-Content `
            -Path $SourcePath `
            -Raw
        | ConvertFrom-Json `
            -AsHashtable
    ).GetEnumerator() `
    | ForEach-Object {
        if (-not ('<TODO>' -iin $_.Value.Values)) {
            $id = "$baseId.$($_.Key.Replace('.', $null).ToLower())"
            $lengthMax = [Nullable[Int]]$_.Value.lengthMax
            $lengthMax = (($lengthMax -eq 0) ? $null : $lengthMax)
            $lengthMin = [Nullable[Int]]$_.Value.lengthMin
            $lengthMin = (($lengthMin -eq 0) ? $null : $lengthMin)
            $values = [Ordered]@{}

            $value = [Ordered]@{
                '$id' = $id
            }
            $properties = [Ordered]@{
                name = $_.Key
                shortName = $_.Value.abbreviation
                lengthMax = $lengthMax
                lengthMin = $lengthMin
                casing = 'none'
                validText = ($_.Value.validText ?? [String]::Empty).Replace('  ', ' ')
                invalidText = ($_.Value.invalidText ?? [String]::Empty).Replace('  ', ' ')
                invalidCharacters = $_.Value.invalidCharacters
                invalidCharactersStart = $_.Value.invalidCharactersStart
                invalidCharactersEnd = $_.Value.invalidCharactersEnd
                invalidCharactersConsecutive = $_.Value.invalidCharactersConsecutive
                regex = $_.Value.regex
                staticValue = $_.Value.staticValue
            }

            if (($_.Value.validText -match '^Lowercase ')) {
                $properties.casing = 'lower'
            }

            if ($_.Value.staticValue) {
                $properties.template = $_.Value.staticValue
                $properties.regex = $_.Value.staticValue
            }

            if (
                (-not $_.Value.staticValue) `
                -and (-not ("$('a-' * ([Math]::Floor($_.Value.lengthMin / 2)))a" -match $_.Value.regex))
            ) {
                $values.SEPARATOR = $null
            }

            if ($_.Value.validText -ilike 'Alphanumerics and underscores*') {
                $values.SEPARATOR = '_'
            }

            if ($values.Keys.Count -gt 0) {
                $properties.values = $values
            }

            $value.properties = $properties

            $content.($_.Key) = $value
            # $content.($_.Value.abbreviation) = @{
            #     '$ref' = "#$id"
            # }
            if (-not ($_.Value.abbreviation -imatch '.*<.*>.*')) {
                $alias.($_.Value.abbreviation) = $_.Key
            }
        }
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

    $result = [Ordered]@{}

    $alias.GetEnumerator() `
    | Sort-Object `
        -Property 'Key' `
    | ForEach-Object {
        $result.($_.Key) = $_.Value
    }

    New-Item `
        -Path $aliasDestinationPath `
        -ItemType 'File' `
        -Value (
            $result `
            | ConvertTo-Json `
                -Depth 100
        ) `
        -Force
    | Out-Null

    $destinationPath = "$Destination/templateComponentKey.json"

    if (
        Test-Path `
            -Path $destinationPath `
            -PathType 'Leaf'
    ) {
        $content = Get-Content `
            -Path $destinationPath `
            -Raw `
        | ConvertFrom-Json `
            -AsHashtable
    }
    else {
        $content = [Ordered]@{}
    }

    $ComponentKey = $ComponentKey ?? $content.templateComponentKey

    if ($ComponentKey) {
        New-Item `
            -Path "$Destination/templateComponentKey.json" `
            -ItemType 'File' `
            -Value (
                @{
                    templateComponentKey = $ComponentKey
                } `
                | ConvertTo-Json `
                    -Depth 100
            ) `
            -Force
        | Out-Null
    }
}

function Build-LocationSource {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $Destination,

        [Switch]
        $PassThru
    )

    New-Item `
        -Path $Destination `
        -ItemType 'Directory' `
        -ErrorAction 'SilentlyContinue' `
    | Out-Null

    $destinationPath = "$Destination/locations.json"

    if (
        Test-Path `
            -Path $destinationPath `
            -PathType 'Leaf'
    ) {
        $content = Get-Content `
            -Path $destinationPath `
            -Raw `
        | ConvertFrom-Json `
            -AsHashtable
    }
    else {
        $content = @{}
    }

    $lastLine = $null
    $isRegionList = $false
    $isTableBody = $false

    Get-WebResponse `
        -Uri $Script:AzureUri.RegionList `
    | ForEach-Object {
        if ($_ -match '## Azure regions list') {
            $isRegionList = $true
        }

        if ($isRegionList) {
            if ($lastLine -imatch '^\|---') {
                $isTableBody = $true
            }

            if ($isTableBody) {
                if ($_ -imatch '^\|') {
                    $name = (($_ -split '\|')[1]).Trim()

                    if ($name -inotmatch '^:::.*') {
                        $name = $name -replace ' ', $null

                        if (-not $content.ContainsKey($name)) {
                            $content.$name = @{
                                abbreviation = '<TODO>'
                            }
                        }
                    }
                }
            }
        }

        $lastLine = $_
    }

    $result = [Ordered]@{}

    $content.GetEnumerator() `
    | Sort-Object `
        -Property 'Key' `
    | ForEach-Object {
        $result.($_.Key) = $_.Value
    }

    $output = New-Item `
        -Path $destinationPath `
        -ItemType 'File' `
        -Value (
            $result
            | ConvertTo-Json `
                -Depth 100
        ) `
        -Force

    if ($PassThru) {
        return $output
    }
}

function Build-ResourceTypeSource {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $Destination,

        [Switch]
        $PassThru
    )

    New-Item `
        -Path $Destination `
        -ItemType 'Directory' `
        -ErrorAction 'SilentlyContinue' `
    | Out-Null

    $destinationPath = "$Destination/resourceTypes.json"

    $content = Initialize-Object `
        -Path $destinationPath

    # if (
    #     Test-Path `
    #         -Path $destinationPath `
    #         -PathType 'Leaf'
    # ) {
    #     $content = Get-Content `
    #         -Path $destinationPath `
    #         -Raw `
    #     | ConvertFrom-Json `
    #         -AsHashtable
    # }
    # else {
    #     $content = @{}
    # }

    $response = Invoke-WebRequest `
        -Uri 'https://raw.githubusercontent.com/MicrosoftDocs/azure-docs/refs/heads/main/articles/azure-resource-manager/management/resource-name-rules.md'

    $lastLine = $null
    $isTableBody = $false
    $provider = $false

    foreach ($line in ($response.Content -split '\r?\n')) {
        if ($line -match ' *##.*') {
            $provider = (
                (($line -replace '#', $null).Trim() -split '\.') `
                | Select-Object `
                    -Skip 1
            ) -join '.'

            $isTableBody = $false
        }

        if ($provider) {
            if ($lastLine -imatch '^ *> *\| *---') {
                $isTableBody = $true
            }

            if ($isTableBody) {
                if (-not $line) {
                    $isTableBody = $false
                    $provider = $null
                }

                if ($line -imatch '^ *> *\|') {
                    $cell = ($line -split '\|')[1..4]
                    $resourceType = "$provider/$($cell[0])" -replace ' ', $null

                    if (-not
                        (
                            $content.Keys `
                            | Where-Object { $_ -ilike "$resourceType*" }
                        )
                    ) {
                        switch ($resourceType) {
                            ('Authorization/policyAssignments') {}
                            ('Authorization/policyDefinitions') {}
                            default {
                                $content.$resourceType = [Ordered]@{
                                    '$metadata' = @{
                                        scope = $cell[1].Trim()
                                        length = $cell[2].Trim()
                                        validText = $cell[3].Trim()
                                    }
                                    abbreviation = '<TODO>'
                                    namespace = "Microsoft.$provider"
                                    scope = '<TODO>'
                                    lengthMin = '<TODO>'
                                    lengthMax = '<TODO>'
                                    validText = '<TODO>'
                                    invalidText = '<TODO>'
                                    invalidCharacters = '<TODO>'
                                    invalidCharactersStart = '<TODO>'
                                    invalidCharactersEnd = '<TODO>'
                                    invalidCharactersConsecutive = '<TODO>'
                                    regex = '<TODO>'
                                    staticValue = '<TODO>'
                                }
                            }
                        }
                    }                    
                }
            }
        }

        $lastLine = $line
    }

    # az account list-locations `
    #     --query '[?type == ''Region'' && metadata.regionType == ''Physical''].name' `
    # | ConvertFrom-Json `
    #     -AsHashtable
    # | ForEach-Object {
    #     if (-not $content.ContainsKey($_)) {
    #         $content.$_ = @{
    #             abbreviation = '<TODO>'
    #         }
    #     }
    # }

    $result = [Ordered]@{}

    $content.GetEnumerator() `
    | Sort-Object `
        -Property 'Key' `
    | ForEach-Object {
        $result.($_.Key) = $_.Value
    }

    $response = Invoke-WebRequest `
        -Uri 'https://raw.githubusercontent.com/MicrosoftDocs/cloud-adoption-framework/refs/heads/main/docs/ready/azure-best-practices/resource-abbreviations.md'

    $lastLine = $null
    $isTableBody = $false
    $provider = $null

    foreach ($line in ($response.Content -split '\r?\n')) {
        if ($line -match ' *##.*') {
            $provider = ($line -replace '#', $null).Trim()

            $isTableBody = $false
        }

        if ($provider) {
            if ($lastLine -imatch '^ *\| *--') {
                $isTableBody = $true
            }

            if ($isTableBody) {
                if (-not $line) {
                    $isTableBody = $false
                    $provider = $null
                }

                if ($line -imatch '^ *\|') {
                    $cell = ($line -split '\|')[1..3]
                    $resourceType = (($cell[1] -split '\.')[1]).Trim().Trim('`')
                    $abbreviation = $cell[2].Trim().Trim('`')
                    $value = $result.$resourceType

                    if ($value) {
                        $value.abbreviation = $abbreviation
                        # $content.$resourceType = $value
                    }
                }
            }
        }

        $lastLine = $line
    }

    $output = New-Item `
        -Path $destinationPath `
        -ItemType 'File' `
        -Value (
            $result
            | ConvertTo-Json `
                -Depth 100
        ) `
        -Force

    if ($PassThru) {
        return $output
    }
}

# function Get-WebResponse {
#     param (
#         [Parameter(Mandatory = $true)]
#         [String]
#         $Uri
#     )

#     try {
#         $webrequest = [System.Net.HttpWebRequest]::Create($Uri)
#         $response = $webrequest.GetResponse()
#         $responseStream = $response.GetResponseStream()
#         $streamReader = [System.IO.StreamReader]::new($responseStream)
    
#         while ($streamReader.Peek() -ge 0)
#         {
#             $streamReader.ReadLine()
#         }
#     }
#     finally {
#         @(
#             $response,
#             $responseStream,
#             $streamReader
#         ) `
#         | ForEach-Object {
#             if ($_ -is [System.IDisposable]) {
#                 $_.Dispose()
#             }
#         }
#     }
# }

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

function Build-RestApiConfig {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $Destination,

        [String]
        $SubscriptionId
    )

    New-Item `
        -Path $Destination `
        -ItemType 'Directory' `
        -ErrorAction 'SilentlyContinue' `
    | Out-Null

    $destinationPath = "$Destination/restApis.json"

    $content = Initialize-Object `
        -Path $destinationPath

    if (-not $SubscriptionId) {
        $SubscriptionId = (Get-AzContext).Subscription.Id
    }

    $lastLine = $null
    $isTableBody = $false
    $provider = $false

    $resourceTypeReader = Get-WebResponse `
        -Uri $Script:AzureUri.ResourceType `
        -AsCustomObject

    $baseId = 'default.restapis'

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

                        $namespace += ($namespace[0] -replace '-', $null)

                        foreach ($namespaceItem in $namespace) {
                            $providerNamespaceItem = $providerNamespace.$namespaceItem

                            if ($providerNamespaceItem) {
                                switch ($namespaceItem) {
                                    ('Management/managementGroups') {
                                        $checkNameRequest = Get-CheckNameAvailabilityRequest `
                                            -Provider $providerNamespaceItem.Provider `
                                            -ApiVersion $providerNamespaceItem.ApiVersion `
                                            -ResourceType "Microsoft.$namespaceItem"
                                    }
                                    ('Media/mediaservices') {
                                        $checkNameRequest = Get-CheckNameAvailabilityRequest `
                                            -SubscriptionId $SubscriptionId `
                                            -Provider $providerNamespaceItem.Provider `
                                            -ApiVersion $providerNamespaceItem.ApiVersion `
                                            -ResourceType 'mediaServices'
                                    }
                                    ('Search/searchServices') {
                                        $checkNameRequest = Get-CheckNameAvailabilityRequest `
                                            -SubscriptionId $SubscriptionId `
                                            -Provider $providerNamespaceItem.Provider `
                                            -ApiVersion $providerNamespaceItem.ApiVersion `
                                            -ResourceType 'searchServices'
                                    }
                                    { $_.StartsWith('ServiceBus') } {
                                        $checkNameRequest = (
                                            ($_ -ieq 'ServiceBus/namespaces') `
                                            ? (
                                                Get-CheckNameAvailabilityRequest `
                                                    -SubscriptionId $SubscriptionId `
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
                                            -SubscriptionId $SubscriptionId `
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
                                                    ApiVersion = $providerNamespaceItem.ApiVersion[0]
                                                }
                                            }
                                        }
                                    }
                                }

                                break
                            }
                        }

                        if (-not $providerNamespaceItem) {
                            $namespace[0]
                        }
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
}

# function Initialize-ResourceTypeConfig {
#     param (
#         [Parameter(Mandatory = $true)]
#         [String]
#         $Destination,

#         [Switch]
#         $PassThru
#     )

#     $parenthesesToKeep = @(
#         'data',
#         'external',
#         'internal',
#         'os',
#         'training'
#     )

#     function Get-Key {
#         param (
#             [Parameter(
#                 Mandatory = $true,
#                 ValueFromPipeline = $true
#             )]
#             [String]
#             $InputObject
#         )

#         if ($InputObject -match '\(([^\)]+)\)') {
#             $Matches `
#             | ForEach-Object {
#                 if ($_[1] -iin $parenthesesToKeep) {
#                     $InputObject = $InputObject.Replace($_[0], $_[1])
#                 }

#                 $InputObject =  $InputObject.Replace($_[0], ($_[1] -iin $parenthesesToKeep) ? $_[1] : $null)
#             }
#         }

#         if ($InputObject.TrimStart(' ').StartsWith('Azure Cosmos DB', [StringComparison]::InvariantCultureIgnoreCase)) {
#             $InputObject = $InputObject. `
#             Replace(' for ', ' '). `
#             Replace(' account', ' ')
#         }

#         return ($InputObject.Trim() -replace '.name$', $null). `
#         Split(' -'.ToCharArray(), [System.StringSplitOptions]::RemoveEmptyEntries) `
#         -join ''

#         # return (
#         #     ($InputObject.Trim() -replace '.name$', $null) `
#         #     | Set-Casing `
#         #         -Casing 'PascalCase'
#         # ). `
#         # Split(' -'.ToCharArray(), [System.StringSplitOptions]::RemoveEmptyEntries) `
#         # -join ''
#     }

#     New-Item `
#         -Path $Destination `
#         -ItemType 'Directory' `
#         -ErrorAction 'SilentlyContinue'
#     | Out-Null

#     $response = Invoke-WebRequest `
#         -Uri 'https://raw.githubusercontent.com/mspnp/AzureNamingTool/refs/heads/main/src/repository/resourcetypes.json'

#     $destinationPath = "$Destination/resourceTypes.json"

#     if (
#         Test-Path `
#             -Path $destinationPath `
#             -PathType 'Leaf'
#     ) {
#         $content = Get-Content `
#             -Path $destinationPath `
#             -Raw `
#         | ConvertFrom-Json `
#             -AsHashtable
#     }
#     else {
#         $content = @{}
#     }

#     $response.Content `
#     | ConvertFrom-Json `
#     | ForEach-Object {
#         $abbreviation = $_.ShortName
#         $kind = (($_.property) ? ($_.property.Split(' -'.ToCharArray()) -join '') : $null)

#         if ($kind) {
#             switch ($_.resource) {
#                 ('compute/virtualMachines') {
#                     switch ($kind) {
#                         ('windows') {
#                             $abbreviation = "vmw";
#                         }
#                         ('linux') {
#                             $abbreviation = "vml";
#                         }
#                     }
#                 }
#                 ('compute/virtualMachineScaleSets') {
#                     switch ($kind) {
#                         ('windows') {
#                             $abbreviation = "vmssw";
#                         }
#                         ('linux') {
#                             $abbreviation = "vmssl";
#                         }
#                     }
#                 }
#                 ('devTestLab/labs/virtualmachines') {
#                     switch ($kind) {
#                         ('windows') {
#                             $abbreviation = "dvmw";
#                         }
#                         ('linux') {
#                             $abbreviation = "dvml";
#                         }
#                     }
#                 }
#                 ('HDInsight/clusters') {
#                     $kind = $kind -replace 'Cluster$', $null

#                     switch ($kind) {
#                         ('MLServices') {
#                             # $kind = 'mlServices'
#                             $abbreviation = 'mls'
#                         }
#                         ('spark') {
#                             $abbreviation = 'spark'
#                         }
#                         ('storm') {
#                             $abbreviation = 'storm'
#                         }
#                     }
#                 }
#                 ('Sql/servers') {
#                     switch ($kind) {
#                         ('azureSQLDatabaseServer') {
#                             $kind = 'database'
#                         }
#                         ('azureSQLDataWarehouse') {
#                             $kind = 'dataWarehouse'
#                         }
#                     }
#                 }
#                 # ('Storage/storageAccounts') {
#                 #     if ($kind -ieq 'VMStorageAccount') {
#                 #         $kind = 'vmStorageAccount'
#                 #     }
#                 # }
#                 ('Synapse/workspaces/sqlPools') {
#                     $kind = $kind -replace 'Pool$', $null
#                     $kind = $kind -replace '^azureSynapseAnalytics', $null

#                     # switch ($kind) {
#                     #     ('SQLDedicated') {
#                     #         $kind = 'sqlDedicated'
#                     #     }
#                     # }
#                 }
#             }

#             $kind = $kind.Trim()

#             # $kind = $kind.Trim() `
#             # | Set-Casing -Casing 'CamelCase'
#         }

#         $key = "$($_.resource)$((($kind) ? "::$kind" : $null))"

#         if (
#             $key `
#             -and (-not $key.StartsWith('::'))
#         ) {
#             $content.$key = [Ordered]@{
#                 abbreviation = $abbreviation
#                 namespace = "Microsoft.$($_.resource)"
#                 scope = $_.scope
#                 lengthMin = $_.lengthMin
#                 lengthMax = $_.lengthMax
#                 validText = $_.validText
#                 invalidText = $_.invalidText
#                 invalidCharacters = $_.invalidCharacters
#                 invalidCharactersStart = $_.invalidCharactersStart
#                 invalidCharactersEnd = $_.invalidCharactersEnd
#                 invalidCharactersConsecutive = $_.invalidCharactersConsecutive
#                 regex = $_.regx
#                 staticValue = $_.staticValues
#             }
#         }
#     }

#     $content.'App/jobs' = [Ordered]@{
#         abbreviation = 'caj'
#         namespace = "Microsoft.App/jobs"
#         scope = "resource group"
#         lengthMin = 2
#         lengthMax = 32
#         validText = "Lowercase letters, numbers, and hyphens. Start with letter, and end with alphanumeric"
#         invalidText = [String]::Empty
#         invalidCharacters = [String]::Empty
#         invalidCharactersStart = [String]::Empty
#         invalidCharactersEnd = [String]::Empty
#         invalidCharactersConsecutive = [String]::Empty
#         regex = "^(?:[a-z]|[a-z][a-z0-9-]{1,30}[a-z0-9])$"
#         staticValue = [String]::Empty
#     }

#     $content.'Network/privateLinkServices' = [Ordered]@{
#         abbreviation = 'pl'
#         namespace = "Microsoft.Network/privateLinkServices"
#         scope = "resource group"
#         lengthMin = 2
#         lengthMax = 64
#         validText = "Alphanumerics, underscores, periods, and hyphens. Start with alphanumeric. End alphanumeric or underscore."
#         invalidText = [String]::Empty
#         invalidCharacters = [String]::Empty
#         invalidCharactersStart = [String]::Empty
#         invalidCharactersEnd = [String]::Empty
#         invalidCharactersConsecutive = [String]::Empty
#         regex = "^(?:[a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9_\\.-]{0,78}[a-zA-Z0-9_])$"
#         staticValue = [String]::Empty
#     }

#     $content.'Network/privateEndpoints' = [Ordered]@{
#         abbreviation = 'pep'
#         namespace = "Microsoft.Network/privateEndpoints"
#         scope = "resource group"
#         lengthMin = 2
#         lengthMax = 64
#         validText = "Alphanumerics, underscores, periods, and hyphens. Start with alphanumeric. End alphanumeric or underscore."
#         invalidText = [String]::Empty
#         invalidCharacters = [String]::Empty
#         invalidCharactersStart = [String]::Empty
#         invalidCharactersEnd = [String]::Empty
#         invalidCharactersConsecutive = [String]::Empty
#         regex = "^(?:[a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9_\\.-]{0,78}[a-zA-Z0-9_])$"
#         staticValue = [String]::Empty
#     }

#     $result = [Ordered]@{}

#     $content.GetEnumerator() `
#     | Sort-Object `
#         -Property 'Key' `
#     | ForEach-Object {
#         $result.($_.Key) = $_.Value
#     }

#     $output = New-Item `
#         -Path $destinationPath `
#         -ItemType 'File' `
#         -Value (
#             $result
#             | ConvertTo-Json `
#                 -Depth 100
#         ) `
#         -Force

#     if ($PassThru) {
#         return $output
#     }
# }