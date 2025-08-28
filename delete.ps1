#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Delete
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function ConvertTo-TopDeskFlatObject {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object,
        [string] $Prefix = ""
    )
 
    $result = [ordered]@{}
 
    foreach ($property in $Object.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix`_$($property.Name)" } else { $property.Name }
 
        if ($property.Value -is [pscustomobject]) {
            $flattenedSubObject = ConvertTo-TopDeskFlatObject -Object $property.Value -Prefix $name
            foreach ($subProperty in $flattenedSubObject.PSObject.Properties) {
                $result[$subProperty.Name] = [string]$subProperty.Value
            }
        }
        else {
            $result[$name] = [string]$property.Value
        }
    }
 
    [PSCustomObject]$result
}

function Set-AuthorizationHeaders {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Username,

        [ValidateNotNullOrEmpty()]
        [string]
        $ApiKey
    )
    # Create basic authentication string
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${Username}:${Apikey}")
    $base64 = [System.Convert]::ToBase64String($bytes)

    # Set authentication headers
    $authHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
    $authHeaders.Add("Authorization", "BASIC $base64")
    $authHeaders.Add('Accept', 'application/json; charset=utf-8')

    Write-Output $authHeaders
}

function Invoke-TopdeskRestMethod {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json; charset=utf-8',

        [System.Collections.IDictionary]
        $Headers
    )
    process {
        try {
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }

            if ($Body) {
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        }
        catch {
            Throw $_
        }
    }
}

function Get-TopdeskOperator {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [String]
        $AccountReference
    )

    # Check if the account reference is empty, if so, generate audit message
    if ([string]::IsNullOrEmpty($AccountReference)) {

        # Throw an error when account reference is empty
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "The account reference is empty. This is a scripting issue."
                IsError = $true
            })
        return
    }

    # Lookup value is filled in, lookup operator in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/operators/id/$AccountReference"
        Method  = 'GET'
        Headers = $Headers
    }
    try {
        $operator = Invoke-TopdeskRestMethod @splatParams
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            $operator = $null
        }
        else {
            throw
        }
    }
    Write-Output $operator
}

function Set-TopdeskOperatorArchiveStatus {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        [Ref]$TopdeskOperator,

        [ValidateNotNullOrEmpty()]
        [Bool]
        $Archive,

        [String]
        $ArchivingReason
    )

    # Set ArchiveStatus variables based on archive parameter
    if ($Archive -eq $true) {

        # When the 'archiving reason' setting is not configured in the target connector configuration
        if ([string]::IsNullOrEmpty($ArchivingReason)) {
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Configuration setting 'Archiving Reason' is empty. This is a configuration error."
                    IsError = $true
                })
            Throw "Error(s) occured while looking up required values"
        }

        $splatParams = @{
            Uri     = "$baseUrl/tas/api/archiving-reasons"
            Method  = 'GET'
            Headers = $Headers
        }

        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $archivingReasonObject = $responseGet | Where-object name -eq $ArchivingReason

        # When the configured archiving reason is not found in Topdesk
        if ([string]::IsNullOrEmpty($archivingReasonObject.id)) {
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Archiving reason [$ArchivingReason] not found in Topdesk"
                    IsError = $true
                })
            Throw "Error(s) occured while looking up required values"
        }
        $archiveStatus = 'operatorArchived'
        $archiveUri = 'archive'
        $body = @{ id = $archivingReasonObject.id }
    }
    else {
        $archiveStatus = 'operator'
        $archiveUri = 'unarchive'
        $body = $null
    }
    # Check the current status of the Person and compare it with the status in archiveStatus
    if ($archiveStatus -ne $TopdeskOperator.status) {
        # Archive / unarchive person
        Write-Information "[$archiveUri] person with id [$($TopdeskOperator.id)]"
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/operators/id/$($TopdeskOperator.id)/$archiveUri"
            Method  = 'PATCH'
            Headers = $Headers
            Body    = $body | ConvertTo-Json
        }
        $null = Invoke-TopdeskRestMethod @splatParams
        $TopdeskOperator.status = $archiveStatus
    }
}

function Set-TopdeskOperator {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        $Account,

        [ValidateNotNullOrEmpty()]
        [Object]
        $TopdeskOperator
    )

    Write-Information "Updating operator"

    # Difference between GET and POST/PATCH operator for the field [initials] <--> [firstInitials] 
    # https://developers.topdesk.com/explorer/?page=supporting-files#/Operators/createOperator
    if ($account.PSObject.Properties.Name -Contains 'initials') {
        $account | Add-Member -MemberType NoteProperty -Name 'firstInitials' -Value $account.initials
        $account.PSObject.Properties.Remove('initials')
    } 

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/operators/id/$($TopdeskOperator.id)"
        Method  = 'PATCH'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $TopdeskOperatorUpdated = Invoke-TopdeskRestMethod @splatParams
    Return $TopdeskOperatorUpdated
}
#endregion functions

#region lookup
try {
    $action = 'Process'

    if ($actionContext.Origin -eq 'reconciliation') {
        $data = [pscustomobject]@{ 
            email            = ''
            networkLoginName = ''
            tasLoginName     = ''
            # mainframeLoginName = 'Deleted by HelloID'
        }
        $actionContext | Add-Member -MemberType NoteProperty -Name 'data' -Value $data -Force

        # Additional endpoint Reconciliation
    }

    $account = $actionContext.Data

    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders

    # get operator
    $splatParamsOperator = @{
        AccountReference = $actionContext.References.Account
        Headers          = $authHeaders
        BaseUrl          = $actionContext.Configuration.baseUrl
    }
    $TopdeskOperator = Get-TopdeskOperator @splatParamsOperator 

    $outputContext.PreviousData = $TopdeskOperator
    #endregion lookup

    #region Calulate action
    if (-Not([string]::IsNullOrEmpty($TopdeskOperator))) {
        # Only compare object if a account object exists
        if (-Not([string]::IsNullOrEmpty($account))) {
            # Flatten the JSON object
            $accountDifferenceObject = ConvertTo-TopDeskFlatObject -Object $account
            $accountReferenceObject = ConvertTo-TopDeskFlatObject -Object $TopdeskOperator
            # Define properties to compare for update
            $accountPropertiesToCompare = $accountDifferenceObject.PsObject.Properties.Name

            $accountSplatCompareProperties = @{
                ReferenceObject  = $accountReferenceObject.PSObject.Properties | Where-Object { $_.Name -in $accountPropertiesToCompare }
                DifferenceObject = $accountDifferenceObject.PSObject.Properties | Where-Object { $_.Name -in $accountPropertiesToCompare }
            }
            if ($null -ne $accountSplatCompareProperties.ReferenceObject -and $null -ne $accountSplatCompareProperties.DifferenceObject) {
                $accountPropertiesChanged = Compare-Object @accountSplatCompareProperties -PassThru
                $accountNewProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "=>" }
            }
        }
        if ($accountNewProperties) {
            $action = 'UpdateAndDisable'
            Write-Information "Account property(s) required to update: $($accountNewProperties.Name -join ', ')"
        }
        elseif ($TopdeskOperator.status -eq 'operator') {
            $action = 'Disable'
        }   
        else {
            $action = 'NoChanges'
        }
    }
    else {
        $action = 'NotFound' 
    }        

    Write-Information "Compared current account to mapped properties. Result: $action"
    #endregion Calulate action

    #region Write
    switch ($action) {
        'UpdateAndDisable' {
            # Unarchive operator if required
            if ($TopdeskOperator.status -eq 'operatorArchived') {

                # Unarchive operator
                $splatParamsOperatorUnarchive = @{
                    TopdeskOperator = [ref]$TopdeskOperator
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $false
                    ArchivingReason = $actionContext.Configuration.operatorArchivingReason
                }

                if (-Not($actionContext.DryRun -eq $true)) {
                    Set-TopdeskOperatorArchiveStatus @splatParamsOperatorUnarchive
                }
                else {
                    Write-Warning "DryRun would unarchive account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] for update"
                }
            }

            # Update TOPdesk operator
            $splatParamsOperatorUpdate = @{
                TopdeskOperator = $TopdeskOperator
                Account         = $account
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $TopdeskOperatorUpdated = Set-TopdeskOperator @splatParamsOperatorUpdate
            }
            else {
                Write-Warning "DryRun would update account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))]"
            }
    
            # Always archive operator in the delete process
            # Archive operator
            $splatParamsOperatorArchive = @{
                TopdeskOperator = [ref]$TopdeskOperator
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $true
                ArchivingReason = $actionContext.Configuration.operatorArchivingReason
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                Set-TopdeskOperatorArchiveStatus @splatParamsOperatorArchive
            }
            else {
                Write-Warning "DryRun would archive account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))]"
            }
    
            $outputContext.Data = $TopdeskOperatorUpdated

            if (-Not($actionContext.DryRun -eq $true)) {
                Write-Information "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully updated and archived"

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully updated and archived"
                        IsError = $false
                    })
            }

            break
        }
    
        'Disable' {
            # Archive operator
            $splatParamsOperatorArchive = @{
                TopdeskOperator = [ref]$TopdeskOperator
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $true
                ArchivingReason = $actionContext.Configuration.operatorArchivingReason
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                Set-TopdeskOperatorArchiveStatus @splatParamsOperatorArchive

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully disabled"
                        IsError = $false
                    })
            }
            else {
                # Add an auditMessage showing what will happen during enforcement
                Write-Warning "DryRun: Would disable account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))]"
            }

            $outputContext.Data = $TopdeskOperator
        }
    
        'NoChanges' {
            Write-Information "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] already disabled"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] already disabled"
                    IsError = $false
                }) 
            break
        }
    
        'NotFound' {        
            Write-Information "Account with id [$($actionContext.References.Account)] successfully archived (skiped not found)"
            
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Account with id [$($actionContext.References.Account)] successfully archived (skiped not found)"
                    IsError = $false
                })

            break
        }
    }
    #endregion Write 
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not $action operator. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            $errorMessage = "Could not $action operator. Error: $($ex.Exception.Message)"
        }
    }
    else {
        $errorMessage = "Could not $action operator. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    # Only log when there are no lookup values, as these generate their own audit message
    if (-Not($ex.Exception.Message -eq 'Error(s) occured while looking up required values')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
    else {
        $outputContext.Success = $true
    }
}