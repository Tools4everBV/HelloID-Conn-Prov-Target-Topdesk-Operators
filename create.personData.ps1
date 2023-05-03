#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Create.personData
#
# Version: 2.0
#####################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Update a corrolated Operator
$updateOnCorrelate = $false

# Correlation
$correlationAttributePerson = 'employeeNumber'
$Topdeskperson = [PSCustomObject]@{
    employeeNumber = $p.ExternalID
}

$correlationAttributeOperator = 'employeeNumber'
$TopdeskOperator = [PSCustomObject]@{
    employeeNumber = $p.ExternalID
}


# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
# https://developers.Topdesk.com/explorer/?page=supporting-files#/Persons/createPerson
# Use data from TOPdesk person (these are created from a direct sync between HR and TOPdesk)

function Set-OpperatorAccount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $TopdeskPerson
    )

    $account = [PSCustomObject]@{
        surName          = $TopdeskPerson.surName
        firstName        = $TopdeskPerson.firstName
        firstInitials    = $TopdeskPerson.firstInitials
        prefixes         = $TopdeskPerson.prefixes
        title            = $TopdeskPerson.title
        gender           = $TopdeskPerson.gender

        telephone        = $TopdeskPerson.telephone
        mobileNumber     = $TopdeskPerson.mobileNumber
        faxNumber        = $TopdeskPerson.faxNumber

        employeeNumber   = $TopdeskPerson.employeeNumber
        email            = $TopdeskPerson.email
        networkLoginName = $TopdeskPerson.networkLoginName
        loginName        = $TopdeskPerson.tasLoginName

        jobTitle         = $TopdeskPerson.jobTitle
        department       = @{ id = $TopdeskPerson.department.id }
        budgetHolder     = @{ id = $TopdeskPerson.budgetHolder.id }
        branch           = @{ id = $TopdeskPerson.branch.id }

        loginPermission  = $true
        exchangeAccount  = $TopdeskPerson.email
    }
    Write-Output $account
}

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
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-TopdeskPersonByCorrelationAttribute {
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
        [String]
        $CorrelationAttribute,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PersonType,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if the correlation attribute exists in the account object set in the mapping
    if (-not([bool]$account.PSObject.Properties[$CorrelationAttribute])) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is missing in the account mapping. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Check if the correlationAttribute is not empty
    if ([string]::IsNullOrEmpty($account.$CorrelationAttribute)) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is empty. This is likely a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Lookup value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/persons?page_size=2&query=$($correlationAttribute)=='$($account.$CorrelationAttribute)'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet.id)) {
        # no results found
        $errorMessage = "No $($PersonType)s found with [$CorrelationAttribute] [$($account.$CorrelationAttribute)]."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } elseif ($responseGet.Count -eq 1) {
        # one record found, correlate, return user
        Write-Information "Successfully found person $($responseGet.tasLoginName) ($($responseGet.id))"
        write-output $responseGet
    } else {
        # Multiple records found, correlation
        $errorMessage = "Multiple [$($responseGet.Count)] $($PersonType)s found with [$CorrelationAttribute] [$($account.$CorrelationAttribute)]. Login names: [$($responseGet.tasLoginName -join ', ')]"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    }
}

function Get-TopdeskOperatorByCorrelationAttribute {
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
        [String]
        $CorrelationAttribute,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if the correlation attribute exists in the account object set in the mapping
    if (-not([bool]$account.PSObject.Properties[$CorrelationAttribute])) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is missing in the account mapping. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Check if the correlationAttribute is not empty
    if ([string]::IsNullOrEmpty($account.$CorrelationAttribute)) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is empty. This is likely a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Lookup value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/operators?page_size=2&query=$($correlationAttribute)=='$($account.$CorrelationAttribute)'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet.id)) {
        # no results found
        Write-Output $null
    } elseif ($responseGet.Count -eq 1) {
        # one record found, correlate, return user
        write-output $responseGet
    } else {
        # Multiple records found, correlation
        $errorMessage = "Multiple [$($responseGet.Count)] operators found with [$CorrelationAttribute] [$($account.$CorrelationAttribute)]. Login names: [$($responseGet.tasLoginName -join ', ')]"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
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
    $TopdeskOperator = Invoke-TopdeskRestMethod @splatParams
    write-output $TopdeskOperator
}
function New-TopdeskOperator {
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
        $Account
    )

    Write-Verbose "Creating operator"

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/operators"
        Method  = 'POST'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $TopdeskOperator = Invoke-TopdeskRestMethod @splatParams
    Write-Output $TopdeskOperator
}

#endregion helperfunctions

#region lookup
try {
    $action = 'Process'

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    # get person
    $splatParamsPerson = @{
        Account                   = $Topdeskperson
        AuditLogs                 = [ref]$auditLogs
        CorrelationAttribute      = $correlationAttributePerson
        Headers                   = $authHeaders
        BaseUrl                   = $config.baseUrl
        PersonType                = 'person'
    }
    $TopdeskPerson = Get-TopdeskPersonByCorrelationAttribute @splatParamsPerson
    
    # get operator
    $splatParamsOperator = @{
        Account                   = $TopdeskOperator
        AuditLogs                 = [ref]$auditLogs
        CorrelationAttribute      = $correlationAttributeOperator
        Headers                   = $authHeaders
        BaseUrl                   = $config.baseUrl
    }
    $TopdeskOperator = Get-TopdeskOperatorByCorrelationAttribute @splatParamsOperator

    if ($auditLogs.isError -contains -$true) {
        Throw "Error(s) occured while looking up required values"
    }

#endregion lookup

    # Verify if a user must be created or correlated
    if ([string]::IsNullOrEmpty($TopdeskOperator)) {
        $action = 'Create'
        $actionType = 'created'
    } else {
        $action = 'Correlate'
        $actionType = 'correlated'       
    }

    # map Topdesk person with Topdesk Opperator
    $splatParamsOperatorAccount = @{
        TopdeskPerson             = $TopdeskPerson
    }
    $account = Set-OpperatorAccount @splatParamsOperatorAccount  

    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action Topdesk operator for: [$($p.DisplayName)], will be executed during enforcement"
        })
    }

#region Write

        # Process
        if (-not($dryRun -eq $true)){
            switch ($action) {
                'Create' {
                    Write-Verbose "Creating Topdesk operator for: [$($p.DisplayName)]"
                    $splatParamsOperatorNew = @{
                        Account         = $account
                        Headers         = $authHeaders
                        BaseUrl         = $config.baseUrl
                    }
                    $TopdeskOperator = New-TopdeskOperator @splatParamsOperatorNew

                } 'Correlate'{
                    if ($updateOnCorrelate -eq $true) {
                    
                        Write-Verbose "Correlating and updating Topdesk operator for: [$($p.DisplayName)]"

                        # Unarchive operator if required
                        if ($TopdeskOperator.status -eq 'operatorArchived') {

                            # Unarchive person
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
                        $TopdeskOperator = Set-TopdeskOperator @splatParamsOperatorUpdate
                    }
                }
            }
            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = "Account with id [$($TopdeskOperator.id)] successfully $($actionType)"
                IsError = $false
            })
        }

} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not $action operator. Error: $($ex.ErrorDetails.Message)"
        } else {
            $errorMessage = "Could not $action operator. Error: $($ex.Exception.Message)"
        }
    } else {
        $errorMessage = "Could not $action operator. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    # Only log when there are no lookup values, as these generate their own audit message
    if (-Not($ex.Exception.Message -eq 'Error(s) occured while looking up required values')) {
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    }
# End
} finally {
   $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $TopdeskOperator.id
        Auditlogs        = $auditLogs
        Account          = $account
        ExportData = [PSCustomObject]@{
            Id                  = $TopdeskOperator.id
            employeeNumber      = $TopdeskOperator.employeeNumber
            networkLoginName    = $TopdeskOperator.networkLoginName
        }
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
#endregion Write