###################################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-RevokePermission-Task
#
# Version: 3.0.0 | new-powershell-connector
#####################################################

$pRef = $actionContext.References.Permission
$aRef = $actionContext.References.Account
$baseUrl = $actionContext.Configuration.baseUrl

# Set to true at start, because only when an error occurs it is set to false
$outputContext.Success = $true

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
$account = [PSCustomObject]@{
    $($pRef.Reference) = $false
}

#region functions
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
    $authHeaders.Add("Accept", 'application/json')

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
                Action  = "RevokePermission"
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
    $operator = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($operator)) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{ 
                Action  = "RevokePermission"
                Message = "Operator with reference [$AccountReference)] is not found. If the operator is deleted, you might need to regrant the entitlement."
                IsError = $true
            })
    }
    else {
        Write-Output $operator
    }
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
                    Action  = "RevokePermission"
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
                    Action  = "RevokePermission"
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
        Write-Verbose "[$archiveUri] person with id [$($TopdeskOperator.id)]"
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

    Write-Verbose "Updating operator"
    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/operators/id/$($TopdeskOperator.id)"
        Method  = 'PATCH'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $null = Invoke-TopdeskRestMethod @splatParams
}
#endregion functions

#region lookup
try {

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
   
    if ($outputContext.AuditLogs.isError -contains - $true) {
        Throw "Error(s) occured while looking up required values"
    }
    #endregion lookup 
    
    #region write 
    if (-Not($actionContext.DryRun -eq $true)) {          
        if ($TopdeskOperator.status -eq 'operatorArchived') {

            # Unarchive operator
            $shouldArchive = $true
            $splatParamsOperatorUnarchive = @{
                TopdeskOperator = [ref]$TopdeskOperator
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $false
                ArchivingReason = $actionContext.Configuration.operatorArchivingReason
            }
            Set-TopdeskOperatorArchiveStatus @splatParamsOperatorUnarchive
        }

        Write-Verbose "Revoking task permission $($pRef.Reference) from ($($aRef))"
        # Update TOPdesk operator
        $splatParamsOperatorUpdate = @{
            TopdeskOperator = $TopdeskOperator
            Account         = $account
            Headers         = $authHeaders
            BaseUrl         = $actionContext.Configuration.baseUrl
        }
        Set-TopdeskOperator @splatParamsOperatorUpdate
        
        # As the update process could be started for an inactive HelloID operator, the user return should be archived state
        if ($shouldArchive) {

            # Archive operator
            $splatParamsOperatorArchive = @{
                TopdeskOperator = [ref]$TopdeskOperator
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $true
                ArchivingReason = $actionContext.Configuration.operatorArchivingReason
            }
            Set-TopdeskOperatorArchiveStatus @splatParamsOperatorArchive
        }

        Write-Verbose "Successfully revoked task permission $($pRef.Reference) from ($($aRef))"

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "RevokePermission"
                Message = "Successfully revoked task permission $($pRef.Reference) from ($($actionContext.References.Account))"
                IsError = $false
            })
    }
    else {
        # Add an auditMessage showing what will happen during enforcement
        Write-Warning "DryRun: Would revoke task permission $($pRef.Reference) from [$($personContext.Person.DisplayName)]"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "RevokePermission"
                Message = "DryRun: Would revoke task permission $($pRef.Reference) from [$($personContext.Person.DisplayName)]"
                IsError = $false
            })
    } 

}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not revoke task permission: $($ex.ErrorDetails.Message)"
        }
        else {
            $errorMessage = "Could not revoke task permission Error: $($ex.Exception.Message)"
        }
    }
    else {
        $errorMessage = "Could not revoke task permission. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    # Only log when there are no lookup values, as these generate their own audit message
    if (-Not($ex.Exception.Message -eq 'Error(s) occured while looking up required values')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "RevokePermission"
                Message = $errorMessage
                IsError = $true
            })
    }
}
finally {
    # Check if auditLogs contains errors, if errors are found, set success to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}
#endregion write