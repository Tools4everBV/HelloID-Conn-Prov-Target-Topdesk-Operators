###################################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Permissions-Grant
#
# Version: 2.0
###################################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()
$success = $True
$baseUrl = $config.baseUrl

# The permissionReference object contains the Identification object provided in the retrieve permissions call
$pRef = $permissionReference | ConvertFrom-Json;

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# region helperfunctions

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
            $PSCmdlet.ThrowTerminatingError($_)
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

# end region helperfunctions

try {
    if ($dryRun -eq $false) {
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

        if ($TopdeskOperator.status -eq 'operatorArchived') {

            # Unarchive operator
            $shouldArchive  = $true
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

        Write-Verbose -verbose "Granting permission $($pRef.Name) ($($pRef.id)) to ($($aRef))"
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/operators/id/$($aRef)/operatorgroups"
            Method  = 'Post'
            Headers = $authHeaders
            Body    = ConvertTo-Json -InputObject @(@{ id = $($pRef.id) }) -Depth 10
        }
        $null = Invoke-TopdeskRestMethod @splatParams
        
        # As the update process could be started for an inactive HelloID operator, the user return should be archived state
        if ($shouldArchive) {

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

        Write-Verbose "Successfully granted Permission $($pRef.Name) ($($pRef.id)) to ($($aRef))"


        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Action  = "GrantPermission"
                Message = "Successfully granted Permission $($pRef.Name) ($($pRef.id)) to ($($aRef))"
                IsError = $false
            })
    }

}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "GrantPermission"
            Message = "Failed to grant permission $($pRef.Name) ($($pRef.id)) to $($aRef.loginName) ($($aRef.id)):  $_"
            IsError = $True
        });
    $success = $false
    Write-Warning $_;
}

#build up result
$result = [PSCustomObject]@{ 
    Success   = $success
    AuditLogs = $auditLogs
    # Account   = [PSCustomObject]@{ }
};

Write-Output $result | ConvertTo-Json -Depth 10;