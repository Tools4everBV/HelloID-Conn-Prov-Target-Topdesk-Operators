#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Update
#
# Version: 2.0
#####################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#region mapping
# Last name generation based on name convention code
#  B  "<birth name prefix> <birth name>"
#  P  "<partner name prefix> <partner name>"
#  BP "<birth name prefix> <birth name> - <partner name prefix> <partner name>"
#  PB "<partner name prefix> <partner name> - <birth name prefix> <birth name>"
function New-TopdeskName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]
        $person
    )

    if([string]::IsNullOrEmpty($person.Name.Initials)) {
        $initials = $person.Name.Initials
    } else {
        $initials = $person.Name.Initials[0..9] -join ""        # Max 10 chars
    }

    if([string]::IsNullOrEmpty($person.Name.FamilyNamePrefix)) {
        $prefix = ""
    } else {
        $prefix = $person.Name.FamilyNamePrefix + " "
    }

    if([string]::IsNullOrEmpty($person.Name.FamilyNamePartnerPrefix)) {
        $partnerPrefix = ""
    } else {
        $partnerPrefix = $person.Name.FamilyNamePartnerPrefix + " "
    }

    $TopdeskSurname = switch($person.Name.Convention) {
                    "B"  { $person.Name.FamilyName }
                    "BP" { $person.Name.FamilyName + " - " + $partnerprefix + $person.Name.FamilyNamePartner }
                    "P"  { $person.Name.FamilyNamePartner }
                    "PB" { $person.Name.FamilyNamePartner + " - " + $prefix + $person.Name.FamilyName }
                    default { $prefix + $person.Name.FamilyName }
    }

    $TopdeskPrefix = switch($person.Name.Convention) {
                    "B"  { $prefix }
                    "BP" { $prefix }
                    "P"  { $partnerPrefix }
                    "PB" { $partnerPrefix }
                    default { $prefix }
    }

    $output = [PSCustomObject]@{
        prefixes    = $TopdeskPrefix
        surname     = $TopdeskSurname
        initials    = $Initials
    }
    Write-Output $output
}

function New-TopdeskGender {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]
        $person
    )

    switch ($person.details.Gender) {
        "M" { $gender = "MALE" }
        "V" { $gender = "FEMALE" }
        default { $gender = 'UNDEFINED' }
    }

    Write-Output $gender
}

# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
# https://developers.topdesk.com/explorer/?page=supporting-files#/Operators/createOperator
$account = [PSCustomObject]@{
    surName          = (New-TopdeskName -Person $p).surname      # Generate surname according to the naming convention code.
    prefixes         = (New-TopdeskName -Person $p).prefixes
    firstName        = $p.Name.NickName
    firstInitials    = (New-TopdeskName -Person $p).initials     # Generate initials max 10 char
    # title            = $p.Custom.title
    gender           = New-TopdeskGender -Person $p

    telephone        = $p.Contact.Business.Phone.Fixed
    mobileNumber     = $p.Contact.Business.Phone.Mobile
    # faxNumber        = $p.Custom.faxnumber

    employeeNumber   = $p.ExternalId
    email            = $p.Accounts.MicrosoftActiveDirectory.Mail
    networkLoginName = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
    loginName        = $p.Accounts.MicrosoftActiveDirectory.userPrincipalName

    jobTitle         = $p.PrimaryContract.Title.Name
    branch           = @{ lookupValue = $p.PrimaryContract.Location.Name } # or  'Fixed branch'
    department       = @{ lookupValue = $p.PrimaryContract.Department.DisplayName }
    budgetHolder     = @{ lookupValue = $p.PrimaryContract.CostCenter.Name }
    
    loginPermission  = $true
    exchangeAccount  = $p.Accounts.MicrosoftActiveDirectory.Mail
}

Write-Verbose ($account | ConvertTo-Json) # Debug output

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
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-TopdeskBranch {
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
        [ref]$Account,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if branch.lookupValue property exists in the account object set in the mapping
    if (-not($account.branch.Keys -Contains 'lookupValue')) {
        $errorMessage = "Requested to lookup branch, but branch.lookupValue is missing. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # When branch.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.branch.lookupValue)) {
           # As branch is always a required field,  no branch in lookup value = error
            $errorMessage = "The lookup value for Branch is empty but it's a required field."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    } else {
        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/branches"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $branch = $responseGet | Where-object name -eq $Account.branch.lookupValue

        # When branch is not found in Topdesk
        if ([string]::IsNullOrEmpty($branch.id)) {

            # As branch is a required field, if no branch is found, an error is logged
            $errorMessage = "Branch with name [$($Account.branch.lookupValue)] isn't found in Topdesk but it's a required field."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {

            # Branch is found in Topdesk, set in Topdesk
            $Account.branch.Remove('lookupValue')
            $Account.branch.Add('id', $branch.id)
        }
    }
}
function Get-TopdeskDepartment {
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
        $LookupErrorHrDepartment,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $LookupErrorTopdesk,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if department.lookupValue property exists in the account object set in the mapping
    if (-not($Account.department.Keys -Contains 'lookupValue')) {
        $errorMessage = "Requested to lookup department, but department.lookupValue is not set. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # When department.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.department.lookupValue)) {
        if ([System.Convert]::ToBoolean($LookupErrorHrDepartment)) {
            # True, no department in lookup value = throw error
            $errorMessage = "The lookup value for Department is empty and the connector is configured to stop when this happens."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {
            # False, no department in lookup value = clear value
            Write-Verbose "Clearing department. (lookupErrorHrDepartment = False)"
            $Account.department.PSObject.Properties.Remove('lookupValue')
            $Account.department | Add-Member -NotePropertyName id -NotePropertyValue $null
        }
    } else {
        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/departments"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $department = $responseGet | Where-object name -eq $Account.department.lookupValue

        # When department is not found in Topdesk
        if ([string]::IsNullOrEmpty($department.id)) {
            if ([System.Convert]::ToBoolean($LookupErrorTopdesk)) {

                # True, no department found = throw error
                $errorMessage = "Department [$($Account.department.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
            } else {

                # False, no department found = remove department field (leave empty on creation or keep current value on update)
                $Account.department.Remove('lookupValue')
                $Account.PSObject.Properties.Remove('department')
                Write-Verbose "Not overwriting or setting department as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        } else {

            # Department is found in Topdesk, set in Topdesk
            $Account.department.Remove('lookupValue')
            $Account.department.Add('id', $department.id)
        }
    }
}

function Get-TopdeskBudgetHolder {
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
        $LookupErrorHrBudgetHolder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $LookupErrorTopdesk,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if budgetholder.lookupValue property exists in the account object set in the mapping
    if (-not($Account.budgetHolder.Keys -Contains 'lookupValue')) {
        $errorMessage = "Requested to lookup budgetholder, but budgetholder.lookupValue is missing. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # When budgetholder.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.budgetHolder.lookupValue)) {
        if ([System.Convert]::ToBoolean($lookupErrorHrBudgetHolder)) {

            # True, no budgetholder in lookup value = throw error
            $errorMessage = "The lookup value for budgetholder is empty and the connector is configured to stop when this happens."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {

            # False, no budgetholder in lookup value = clear value
            $Account.budgetHolder.PSObject.Properties.Remove('lookupValue')
            $Account.budgetHolder | Add-Member -NotePropertyName id -NotePropertyValue $null
            Write-Verbose "Clearing budgetholder. (lookupErrorHrBudgetHolder = False)"
        }
    } else {

        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/budgetholders"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $budgetHolder = $responseGet | Where-object name -eq $Account.budgetHolder.lookupValue

        # When budgetholder is not found in Topdesk
        if ([string]::IsNullOrEmpty($budgetHolder.id)) {
            if ([System.Convert]::ToBoolean($lookupErrorTopdesk)) {
                # True, no budgetholder found = throw error
                $errorMessage = "Budgetholder [$($Account.budgetHolder.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
            } else {

                # False, no budgetholder found = remove budgetholder field (leave empty on creation or keep current value on update)
                $Account.budgetHolder.Remove('lookupValue')
                $Account.PSObject.Properties.Remove('budgetHolder')
                Write-Verbose "Not overwriting or setting budgetholder as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        } else {

            # Budgetholder is found in Topdesk, set in Topdesk
            $Account.budgetHolder.Remove('lookupValue')
            $Account.budgetHolder.Add('id', $budgetHolder.id)
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
    $TopdeskOperator = Invoke-TopdeskRestMethod @splatParams
}

#endregion helperfunctions

# Create or Correlate user
try {
        $action = 'Process'

        # Setup authentication headers
        $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

        # Resolve branch id
        $splatParamsBranch = @{
            Account   = [ref]$account
            AuditLogs = [ref]$auditLogs
            Headers   = $authHeaders
            baseUrl   = $config.baseUrl
        }
        Get-TopdeskBranch @splatParamsBranch

        # Resolve department id
        $splatParamsDepartment = @{
            Account                 = [ref]$account
            AuditLogs               = [ref]$auditLogs
            Headers                 = $authHeaders
            baseUrl                 = $config.baseUrl
            lookupErrorHrDepartment = $config.lookupErrorHrDepartment
            lookupErrorTopdesk      = $config.lookupErrorTopdesk
        }
        Get-TopdeskDepartment @splatParamsDepartment

        # Resolve budgetholder id
        $splatParamsBudgetholder = @{
            Account                   = [ref]$account
            AuditLogs                 = [ref]$auditLogs
            Headers                   = $authHeaders
            baseUrl                   = $config.baseUrl
            lookupErrorHrBudgetholder = $config.lookupErrorHrBudgetholder
            lookupErrorTopdesk        = $config.lookupErrorTopdesk
        }
        Get-TopdeskBudgetholder @splatParamsBudgetholder

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

        if ($dryRun -eq $true) {
            $auditLogs.Add([PSCustomObject]@{
                Message = "$action Topdesk operator for: [$($p.DisplayName)], will be executed during enforcement"
            })
        }
 
        # region write
        $action = 'Update'

        # Process
        if (-not($dryRun -eq $true)){
            Write-Verbose "Updating Topdesk operator for: [$($p.DisplayName)]"
 
            # Unarchive operator if required
            if ($TopdeskOperator.status -eq 'operatorArchived') {

                # Unarchive operator
                $shouldArchive  = $true
                $splatParamsOperatorUnarchive = @{
                    TopdeskOperator = [ref]$TopdeskOperator
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                    Archive         = $false
                    ArchivingReason = $config.operatorArchivingReason
                    AuditLogs        = [ref]$auditLogs
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

            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = "Account with id [$($TopdeskOperator.id)] successfully updated"
                IsError = $false
            })
        }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        #write-verbose ($ex | ConvertTo-Json)

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not $action operator. Error: $($ex.ErrorDetails.Message)"
        } else {
            #$errorObj = Resolve-HTTPError -ErrorObject $ex
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