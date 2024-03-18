#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Create
#
# Version: 3.0.0 | new-powershell-connector
#####################################################

# Set to true at start, because only when an error occurs it is set to false
$outputContext.Success = $true

# AccountReference must have a value for dryRun
$outputContext.AccountReference = "Unknown"

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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

function Get-TopdeskBranch {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account
    )

    # Check if branch.lookupValue property exists in the account object set in the mapping
    if (-not($account.branch.PSObject.Properties.Name -contains 'lookupValue')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount"
                Message = "Requested to lookup branch, but [branch.lookupValue] is missing. This is a mapping issue."
                IsError = $true
            })
        return
    }
        
    if ([string]::IsNullOrEmpty($Account.branch.lookupValue)) {
        # As branch is always a required field,  no branch in lookup value = error
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount"
                Message = "The lookup value for Branch is empty but it's a required field."
                IsError = $true
            })
    }
    else {
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
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "Branch with name [$($Account.branch.lookupValue)] isn't found in Topdesk but it's a required field."
                    IsError = $true
                })
        }
        else {
            # Branch is found in Topdesk, set in Topdesk
            $Account.branch.PSObject.Properties.Remove('lookupValue')
            $Account.branch | Add-Member -MemberType NoteProperty -Name 'id' -Value $branch.id
        }
    }
}
function Get-TopdeskDepartment {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        $LookupErrorHrDepartment,

        [ValidateNotNullOrEmpty()]
        $LookupErrorTopdesk,

        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account
    )
  
    # When department.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.department.lookupValue)) {
        if ([System.Convert]::ToBoolean($LookupErrorHrDepartment)) {
            # True, no department in lookup value = throw error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "The lookup value for Department is empty and the connector is configured to stop when this happens."
                    IsError = $true
                })
        }
        else {
            # False, no department in lookup value = clear value
            Write-Verbose "Clearing department. (lookupErrorHrDepartment = False)"
            $Account.department.PSObject.Properties.Remove('lookupValue')
            $Account.department | Add-Member -NotePropertyName id -NotePropertyValue $null
        }
    }
    else {
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
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CreateAccount"
                        Message = "Department [$($Account.department.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                        IsError = $true
                    })
            }
            else {
                # False, no department found = remove department field (leave empty on creation or keep current value on update)
                $Account.department.PSObject.Properties.Remove('lookupValue')
                $Account.PSObject.Properties.Remove('department')
                Write-Verbose "Not overwriting or setting department as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {
            # Department is found in Topdesk, set in Topdesk
            $Account.department.PSObject.Properties.Remove('lookupValue')
            $Account.department | Add-Member -MemberType NoteProperty -Name 'id' -Value $department.id
            # $Account.department.Add('id', $department.id)
        }
    }
}

function Get-TopdeskBudgetHolder {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        $LookupErrorHrBudgetHolder,

        [ValidateNotNullOrEmpty()]
        $LookupErrorTopdesk,

        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account
    )

    # When budgetholder.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.budgetHolder.lookupValue)) {
        if ([System.Convert]::ToBoolean($lookupErrorHrBudgetHolder)) {
            # True, no budgetholder in lookup value = throw error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "The lookup value for budgetholder is empty and the connector is configured to stop when this happens."
                    IsError = $true
                })
        }
        else {
            # False, no budgetholder in lookup value = clear value
            Write-Verbose "Clearing budgetholder. (lookupErrorHrBudgetHolder = False)"
            $Account.budgetHolder.PSObject.Properties.Remove('lookupValue')
            $Account.budgetHolder | Add-Member -NotePropertyName id -NotePropertyValue $null
        }
    }
    else {

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
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CreateAccount"
                        Message = "Budgetholder [$($Account.budgetHolder.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                        IsError = $true
                    })
            }
            else {
                # False, no budgetholder found = remove budgetholder field (leave empty on creation or keep current value on update)
                $Account.budgetHolder.PSObject.Properties.Remove('lookupValue')
                $Account.PSObject.Properties.Remove('budgetHolder')
                Write-Verbose "Not overwriting or setting budgetholder as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {
            # Budgetholder is found in Topdesk, set in Topdesk
            $Account.budgetHolder.PSObject.Properties.Remove('lookupValue')
            $Account.budgetHolder | Add-Member -MemberType NoteProperty -Name 'id' -Value $budgetHolder.id
        }
    }
}

function Get-TopdeskOperatorByCorrelationAttribute {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        $CorrelationValue,

        [ValidateNotNullOrEmpty()]
        [String]
        $CorrelationField
    )

    # Lookup value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/operators?page_size=2&query=$($CorrelationField)=='$($CorrelationValue)'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet.id)) {
        # no results found
        Write-Output $null
    }
    elseif ($responseGet.Count -eq 1) {
        # one record found, correlate, return operator
        write-output $responseGet
    }
    else {
        # Multiple records found, correlation
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount"
                Message = "Multiple [$($responseGet.Count)] operators found with [$CorrelationAttribute] [$($account.$CorrelationAttribute)]. Login names: [$($responseGet.tasLoginName -join ', ')]"
                IsError = $true
            })
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
                    Action  = "CreateAccount"
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
                    Action  = "CreateAccount"
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
    $TopdeskOperator = Invoke-TopdeskRestMethod @splatParams
}
function New-TopdeskOperator {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

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
#endregion functions

#region lookup
try {
    $action = 'Process'

    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders

    # Check if we should try to correlate the account
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($correlationField)) {
            Write-Warning "Correlation is enabled but not configured correctly."
            Throw "Correlation is enabled but not configured correctly."
        }

        if ([string]::IsNullOrEmpty($correlationValue)) {
            Write-Warning "The correlation value for [$correlationField] is empty. This is likely a scripting issue."
            Throw "The correlation value for [$correlationField] is empty. This is likely a scripting issue."
        }

        # get person
        $splatParamsOperator = @{
            correlationValue = $correlationValue
            correlationField = $correlationField
            Headers          = $authHeaders
            BaseUrl          = $actionContext.Configuration.baseUrl
        }
        $TopdeskOperator = Get-TopdeskOperatorByCorrelationAttribute @splatParamsOperator

        if (!([string]::IsNullOrEmpty($TopdeskOperator))) {
            if (-Not($actionContext.DryRun -eq $true)) {
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CorrelateAccount"
                        Message = "Correlated account with id [$($TopdeskOperator.id)] on field $($correlationField) with value $($correlationValue)"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would correlate account [$($personContext.Person.DisplayName)] on field [$($correlationField)] with value [$($correlationValue)]"
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CorrelateAccount"
                        Message = "DryRun: Would correlate account [$($personContext.Person.DisplayName)] on field [$($correlationField)] with value [$($correlationValue)]"
                        IsError = $false
                    })
            }
            $outputContext.AccountReference = $TopdeskOperator.id
            $outputContext.AccountCorrelated = $true
        }
    }
    else {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CorrelateAccount"
                Message = "Configuration of correlation is madatory."
                IsError = $true
            })
        Throw "Configuration of correlation is madatory."
    }

    if (!$outputContext.AccountCorrelated) {    
        $account = $actionContext.Data
        # Remove ID field because only used for export data
        if ($account.PSObject.Properties.Name -Contains 'id') {
            $account.PSObject.Properties.Remove('id')
        }

        # Resolve branch id
        $splatParamsBranch = @{
            Account = [ref]$account
            Headers = $authHeaders
            BaseUrl = $actionContext.Configuration.baseUrl
        }
        Get-TopdeskBranch @splatParamsBranch

        if ($Account.department.PSObject.Properties.Name -Contains 'lookupValue') {
            # Resolve department id
            $splatParamsDepartment = @{
                Account                 = [ref]$account
                Headers                 = $authHeaders
                BaseUrl                 = $actionContext.Configuration.baseUrl
                LookupErrorHrDepartment = $actionContext.Configuration.lookupErrorHrDepartment
                LookupErrorTopdesk      = $actionContext.Configuration.lookupErrorTopdesk
            }
            Get-TopdeskDepartment @splatParamsDepartment  
        }
        else {
            write-verbose "Mapping of [department.lookupValue] is missing to lookup the department in Topdesk. Action skipped"
        }

        if ($Account.budgetHolder.PSObject.Properties.Name -Contains 'lookupValue') {
            # Resolve budgetholder id
            $splatParamsBudgetHolder = @{
                Account                   = [ref]$account
                Headers                   = $authHeaders
                BaseUrl                   = $actionContext.Configuration.baseUrl
                lookupErrorHrBudgetHolder = $actionContext.Configuration.lookupErrorHrBudgetHolder
                lookupErrorTopdesk        = $actionContext.Configuration.lookupErrorTopdesk
            }
            Get-TopdeskBudgetholder @splatParamsBudgetHolder
        }
        else {
            write-verbose "Mapping of [budgetHolder.lookupValue] is missing to lookup the budgetHolder in Topdesk. Action skipped"
        }
        
        if ($outputContext.AuditLogs.isError -contains $true) {
            Throw "Error(s) occured while looking up required values"
        }
        #endregion lookup

        #region Write
        $action = 'Create'
        if (-Not($actionContext.DryRun -eq $true)) {
            Write-Verbose "Creating Topdesk operator for: [$($personContext.Person.DisplayName)]"
            $splatParamsOperatorNew = @{
                Account = $account
                Headers = $authHeaders
                BaseUrl = $actionContext.Configuration.baseUrl
            }
            $TopdeskOperator = New-TopdeskOperator @splatParamsOperatorNew
            $outputContext.AccountReference = $TopdeskOperator.id
            $outputContext.Data = $TopdeskOperator
               
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "Account with id [$($TopdeskOperator.id)] successfully created"
                    IsError = $false
                })
        }
        else {
            Write-Warning "DryRun: Would create account [$($personContext.Person.DisplayName)]"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "DryRun: Would create account [$($personContext.Person.DisplayName)]"
                    IsError = $false
                })
        }
    }
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
                Action  = "CreateAccount"
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
#endregion Write