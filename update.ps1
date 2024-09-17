#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Update
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
function ConvertTo-TopDeskFlatObject {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object,
        [string] $Prefix = ""
    )
 
    $result = [ordered]@{}
 
    foreach ($property in $Object.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix`_$($property.Name)" } else { $property.Name }
 
        if ($null -ne $property.Value) {
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

    $account = $actionContext.Data
    # Remove ID field because only used for export data
    if ($account.PSObject.Properties.Name -Contains 'id') {
        $account.PSObject.Properties.Remove('id')
    }

    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders
    
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

    # get operator
    $splatParamsOperator = @{
        AccountReference = $actionContext.References.Account
        Headers          = $authHeaders
        BaseUrl          = $actionContext.Configuration.baseUrl
    }
    $TopdeskOperator = Get-TopdeskOperator @splatParamsOperator        

    $outputContext.PreviousData = $TopdeskOperator

    if ($outputContext.AuditLogs.isError -contains - $true) {
        Throw "Error(s) occured while looking up required values"
    }
    #endregion lookup

    #region remove value for update
    if (-not($actionContext.AccountCorrelated -eq $true)) {
        # Example to only set certain attributes when create-correlate. If you don't want to update certain values, you need to remove them here.    
        # $account.PSObject.Properties.Remove('email')
        # $account.PSObject.Properties.Remove('networkLoginName')
        # $account.PSObject.Properties.Remove('loginName')
        # $account.PSObject.Properties.Remove('exchangeAccount')
    }
    #endregion remove value for update

    #region Calulate action
    if (-Not([string]::IsNullOrEmpty($TopdeskOperator))) {
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
            $accountOldProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "<=" }
            $accountNewProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "=>" }
        }

        if ($accountNewProperties) {
            $action = 'Update'
            Write-Information "Account property(s) required to update: $($accountNewProperties.Name -join ', ')"
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
        'Update' {
            $accountChangedPropertiesObject = [PSCustomObject]@{
                OldValues = @{}
                NewValues = @{}
            }
        
            foreach ($accountOldProperty in ($accountOldProperties | Where-Object { $_.Name -in $accountNewProperties.Name })) {
                $accountChangedPropertiesObject.OldValues.$($accountOldProperty.Name) = $accountOldProperty.Value
            }
        
            foreach ($accountNewProperty in $accountNewProperties) {
                $accountChangedPropertiesObject.NewValues.$($accountNewProperty.Name) = $accountNewProperty.Value
            }

            # Unarchive operator if required
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
                Write-Warning "DryRun would update account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))]. Old values: $($accountChangedPropertiesObject.oldValues | ConvertTo-Json). New values: $($accountChangedPropertiesObject.newValues | ConvertTo-Json)"
            }

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

                if (-Not($actionContext.DryRun -eq $true)) {
                    Set-TopdeskOperatorArchiveStatus @splatParamsOperatorArchive
                }
                else {
                    Write-Warning "DryRun would re-archive account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] after update"
                }
            }

            $outputContext.AccountReference = $TopdeskOperator.id
            $outputContext.Data = $TopdeskOperatorUpdated

            if (-Not($actionContext.DryRun -eq $true)) {
                Write-Information "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully updated. Old values: $($accountChangedPropertiesObject.oldValues | ConvertTo-Json). New values: $($accountChangedPropertiesObject.newValues | ConvertTo-Json)"

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully updated. Old values: $($accountChangedPropertiesObject.oldValues | ConvertTo-Json). New values: $($accountChangedPropertiesObject.newValues | ConvertTo-Json)"
                        IsError = $false
                    })
            }
        }
        
        'NoChanges' {        
            $outputContext.AccountReference = $TopdeskOperator.id
            $outputContext.Data = $TopdeskOperator
            $outputContext.PreviousData = $TopdeskOperator

            Write-Information "Account with id [$($TopdeskOperator.id)] successfully checked. No changes required"

            # AuditLog is skipped because $outputContext.Data & $outputContext.PreviousData are the same. If auditlog is required please change this variables above
            # $outputContext.AuditLogs.Add([PSCustomObject]@{
            #         Message = "Account with id [$($TopdeskOperator.id)] and dynamicName [($($TopdeskOperator.dynamicName))] successfully checked. No changes required"
            #         IsError = $false
            #     })

            break
        }

        'NotFound' {                
            Write-Information "Account with id [$($actionContext.References.Account)] is not found. If the person is deleted, you might need to regrant the entitlement."

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Account with id [$($actionContext.References.Account)] is not found. If the person is deleted, you might need to regrant the entitlement."
                    IsError = $true
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
