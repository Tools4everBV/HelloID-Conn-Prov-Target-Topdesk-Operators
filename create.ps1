#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Create
# PowerShell V2
#####################################################

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

    # Check if branch.name property exists in the account object set in the mapping
    if (-not($account.branch.PSObject.Properties.Name -contains 'name')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Requested to lookup branch, but [branch.name] is missing. This is a mapping issue."
                IsError = $true
            })
        return
    }
        
    if ([string]::IsNullOrEmpty($Account.branch.name)) {
        # As branch is always a required field,  no branch in lookup value = error
        $outputContext.AuditLogs.Add([PSCustomObject]@{
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
        $branch = $responseGet | Where-object name -eq $Account.branch.name
        # When branch is not found in Topdesk
        if ([string]::IsNullOrEmpty($branch.id)) {

            # As branch is a required field, if no branch is found, an error is logged
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Branch with name [$($Account.branch.name)] isn't found in Topdesk but it's a required field."
                    IsError = $true
                })
        }
        else {
            # Branch is found in Topdesk, set in Topdesk
            $Account.branch.PSObject.Properties.Remove('name')
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
  
    # When department.name is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.department.name)) {
        if ([System.Convert]::ToBoolean($LookupErrorHrDepartment)) {
            # True, no department in lookup value = throw error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "The lookup value for Department is empty and the connector is configured to stop when this happens."
                    IsError = $true
                })
        }
        else {
            # False, no department in lookup value = clear value
            Write-Verbose "Clearing department. (lookupErrorHrDepartment = False)"
            $Account.department.PSObject.Properties.Remove('name')
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
        $department = $responseGet | Where-object name -eq $Account.department.name

        # When department is not found in Topdesk
        if ([string]::IsNullOrEmpty($department.id)) {
            if ([System.Convert]::ToBoolean($LookupErrorTopdesk)) {
                # True, no department found = throw error
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Department [$($Account.department.name)] not found in Topdesk and the connector is configured to stop when this happens."
                        IsError = $true
                    })
            }
            else {
                # False, no department found = remove department field (leave empty on creation or keep current value on update)
                $Account.department.PSObject.Properties.Remove('name')
                $Account.PSObject.Properties.Remove('department')
                Write-Verbose "Not overwriting or setting department as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {
            # Department is found in Topdesk, set in Topdesk
            $Account.department.PSObject.Properties.Remove('name')
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

    # When budgetholder.name is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.budgetHolder.name)) {
        if ([System.Convert]::ToBoolean($lookupErrorHrBudgetHolder)) {
            # True, no budgetholder in lookup value = throw error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "The lookup value for budgetholder is empty and the connector is configured to stop when this happens."
                    IsError = $true
                })
        }
        else {
            # False, no budgetholder in lookup value = clear value
            Write-Verbose "Clearing budgetholder. (lookupErrorHrBudgetHolder = False)"
            $Account.budgetHolder.PSObject.Properties.Remove('name')
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
        $budgetHolder = $responseGet | Where-object name -eq $Account.budgetHolder.name

        # When budgetholder is not found in Topdesk
        if ([string]::IsNullOrEmpty($budgetHolder.id)) {
            if ([System.Convert]::ToBoolean($lookupErrorTopdesk)) {
                # True, no budgetholder found = throw error
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Budgetholder [$($Account.budgetHolder.name)] not found in Topdesk and the connector is configured to stop when this happens."
                        IsError = $true
                    })
            }
            else {
                # False, no budgetholder found = remove budgetholder field (leave empty on creation or keep current value on update)
                $Account.budgetHolder.PSObject.Properties.Remove('name')
                $Account.PSObject.Properties.Remove('budgetHolder')
                Write-Verbose "Not overwriting or setting budgetholder as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {
            # Budgetholder is found in Topdesk, set in Topdesk
            $Account.budgetHolder.PSObject.Properties.Remove('name')
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
                Message = "Multiple [$($responseGet.Count)] operators found with [$CorrelationField] [$($CorrelationValue)]. Login names: [$($responseGet.tasLoginName -join ', ')]"
                IsError = $true
            })
    }
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

    # Difference between GET and POST/PATCH operator for the field [initials] <--> [firstInitials] 
    # https://developers.topdesk.com/explorer/?page=supporting-files#/Operators/createOperator
    if ($account.PSObject.Properties.Name -Contains 'initials') {
        $account | Add-Member -MemberType NoteProperty -Name 'firstInitials' -Value $account.initials
        $account.PSObject.Properties.Remove('initials')
    } 

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

#region correlation
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
    }
    else {
        Throw "Configuration of correlation is mandatory."
    }
    #endregion correlation

    #region Calulate action
    if (-Not([string]::IsNullOrEmpty($TopdeskOperator))) {
        $action = 'Correlate'
    }    
    else {
        $action = 'Create' 
    }

    Write-Information "Check if current account can be found. Result: $action"
    #endregion Calulate action

    switch ($action) {
        'Create' {   
            #region lookup  
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

            if ($Account.department.PSObject.Properties.Name -Contains 'name') {
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
                write-verbose "Mapping of [department.name] is missing to lookup the department in Topdesk. Action skipped"
            }

            if ($Account.budgetHolder.PSObject.Properties.Name -Contains 'name') {
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
                write-verbose "Mapping of [budgetHolder.name] is missing to lookup the budgetHolder in Topdesk. Action skipped"
            }
        
            if ($outputContext.AuditLogs.isError -contains $true) {
                Throw "Error(s) occured while looking up required values"
            }
            #endregion lookup

            #region Write
            $splatParamsOperatorNew = @{
                Account = $account
                Headers = $authHeaders
                BaseUrl = $actionContext.Configuration.baseUrl
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $TopdeskOperator = New-TopdeskOperator @splatParamsOperatorNew

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully created"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun would create Topdesk operator. Account: $($account | Convertto-json)"
            }

            $outputContext.AccountReference = $TopdeskOperator.id
            $outputContext.Data = $TopdeskOperator
            #endregion Write
        }
        
        'Correlate' {
            #region correlate
            Write-Information "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully correlated on field [$($correlationField)] with value [$($correlationValue)]"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount"
                    Message = "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully correlated on field [$($correlationField)] with value [$($correlationValue)]"
                    IsError = $false
                })

            $outputContext.AccountReference = $TopdeskOperator.id
            $outputContext.AccountCorrelated = $true
            $outputContext.Data = $TopdeskOperator
            
            break
            #endregion correlate
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

    # Check if accountreference is set, if not set, set this with default value as this must contain a value
    if ([String]::IsNullOrEmpty($outputContext.AccountReference) -and $actionContext.DryRun -eq $true) {
        $outputContext.AccountReference = "DryRun: Currently not available"
    }
}
