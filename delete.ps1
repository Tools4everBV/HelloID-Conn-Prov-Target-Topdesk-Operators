#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Delete
#
# Version: 2.0.1
#####################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()
$aRef = $AccountReference | ConvertFrom-Json

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region mapping
# Clear email, networkLoginName & loginName, if you need to clear other values, add these here
$account = [PSCustomObject]@{
    email            = $null
    networkLoginName = $null
    loginName        = $null
}
#endregion mapping

#region helperfunctions
function Set-AuthorizationHeaders {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Username,

        [Parameter(Mandatory)]
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
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json; charset=utf-8',

        [Parameter(Mandatory)]
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
        } catch {
            throw $_
        }
    }
}

function Get-TopdeskOperator {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [String]
        $AccountReference,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if the account reference is empty, if so, generate audit message
    if ([string]::IsNullOrEmpty($AccountReference)) {

        # Throw an error when account reference is empty
        $errorMessage = "The account reference is empty. This is a scripting issue."
        $AuditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
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
        $errorMessage = "Operator with reference [$AccountReference)] is not found. If the operator is deleted, you might need to regrant the entitlement."
        $AuditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } else {
        Write-Output $operator
    }
}

function Set-TopdeskOperatorArchiveStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        [Ref]$TopdeskOperator,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Bool]
        $Archive,

        [Parameter()]
        [String]
        $ArchivingReason,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Set ArchiveStatus variables based on archive parameter
    if ($Archive -eq $true) {

         #When the 'archiving reason' setting is not configured in the target connector configuration
        if ([string]::IsNullOrEmpty($ArchivingReason)) {
            $errorMessage = "Configuration setting 'Archiving Reason' is empty. This is a configuration error."
            $AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
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

        #When the configured archiving reason is not found in Topdesk
        if ([string]::IsNullOrEmpty($archivingReasonObject.id)) {
            $errorMessage = "Archiving reason [$ArchivingReason] not found in Topdesk"
            $AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
            Throw "Error(s) occured while looking up required values"
        }

        $archiveStatus = 'operatorArchived'
        $archiveUri = 'archive'
        $body = @{ id = $archivingReasonObject.id }
    } else {
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
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $Account,

        [Parameter(Mandatory)]
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
#endregion helperfunctions

#region lookup
try {
    $action = 'Process'

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    # get operator
    $splatParamsOperator = @{
        AccountReference          = $aRef
        AuditLogs                 = [ref]$auditLogs
        Headers                   = $authHeaders
        BaseUrl                   = $config.baseUrl
    }
    $TopdeskOperator = Get-TopdeskOperator @splatParamsOperator 

    if ($auditLogs.isError -contains -$true) {
        Throw "Error(s) occured while looking up required values"
    }  
#endregion lookup

#region Write

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
            Message = "Archiving TOPdesk person for: [$($p.DisplayName)], will be executed during enforcement"
        })
    }
    
    $action = 'Archive'

    # Process
    if (-not($dryRun -eq $true)){
        Write-Verbose "Archiving Topdesk operator for: [$($p.DisplayName)]"

        # Unarchive operator if required
        if ($TopdeskOperator.status -eq 'operatorArchived') {

            # Unarchive operator
            $splatParamsOperatorUnarchive = @{
                TopdeskOperator = [ref]$TopdeskOperator
                Headers         = $authHeaders
                BaseUrl         = $config.baseUrl
                Archive         = $false
                ArchivingReason = $config.operatorArchivingReason
                AuditLogs       = [ref]$auditLogs
            }
            Set-TopdeskOperatorArchiveStatus @splatParamsOperatorUnarchive
        }

        # Update TOPdesk operator
        $splatParamsOperatorUpdate = @{
            TopdeskOperator = $TopdeskOperator
            Account         = $account
            Headers         = $authHeaders
            BaseUrl         = $config.baseUrl
        }
        Set-TopdeskOperator @splatParamsOperatorUpdate

        # Always archive operator in the delete process
        if ($TopdeskOperator.status -ne 'operatorArchived') {

            # Archive operator
            $splatParamsOperatorArchive = @{
                TopdeskOperator = [ref]$TopdeskOperator
                Headers         = $authHeaders
                BaseUrl         = $config.baseUrl
                Archive         = $true
                ArchivingReason = $config.operatorArchivingReason
                AuditLogs       = [ref]$auditLogs
            }
            Set-TopdeskOperatorArchiveStatus @splatParamsOperatorArchive
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "Archive operator was successful."
            IsError = $false
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    Write-Verbose ($ex | ConvertTo-Json)
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not $action operator. Error: $($ex.ErrorDetails.Message)"
        } else {
            #$errorObj = Resolve-HTTPError -ErrorObject $ex
            $errorMessage = "Could not $action operator. Error: $($ex.Exception.Message)"
        }
    } else {
        $errorMessage = "Could not archive operator. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
#endregion Write