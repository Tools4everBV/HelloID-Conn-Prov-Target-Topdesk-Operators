$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json;
$success = $false
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# TOPdesk system data
$baseUrl = $c.baseUrl
$username = $c.username
$apiKey = $c.apikey

# Troubleshooting
# $p.ExternalID = '12345678'
# $aRef = @{
#     loginName = "j.doe"
#     id = "a1b2345c-89dd-47a5-8de3-6de7df89g012"
# }
# $dryRun = $false

#region mapping

# Last name generation based on name convention code
#  B  "<birth name prefix> <birth name>"
#  P  "<partner name prefix> <partner name>"
#  BP "<birth name prefix> <birth name> - <partner name prefix> <partner name>"
#  PB "<partner name prefix> <partner name> - <birth name prefix> <birth name>"
function New-TopdeskSurname {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]
        $person
    )

    if ([string]::IsNullOrEmpty($person.Name.FamilyNamePrefix)) {
        $prefix = ""
    }
    else {
        $prefix = $person.Name.FamilyNamePrefix + " "
    }

    if ([string]::IsNullOrEmpty($person.Name.FamilyNamePartnerPrefix)) {
        $partnerPrefix = ""
    }
    else {
        $partnerPrefix = $person.Name.FamilyNamePartnerPrefix + " "
    }

    $TopdeskSurname = switch ($person.Name.Convention) {
        "B" { $person.Name.FamilyName }
        "BP" { $person.Name.FamilyName + " - " + $partnerprefix + $person.Name.FamilyNamePartner }
        "P" { $person.Name.FamilyNamePartner }
        "PB" { $person.Name.FamilyNamePartner + " - " + $prefix + $person.Name.FamilyName }
        default { $prefix + $person.Name.FamilyName }
    }

    $TopdeskPrefix = switch ($person.Name.Convention) {
        "B" { $prefix }
        "BP" { $prefix }
        "P" { $partnerPrefix }
        "PB" { $partnerPrefix }
        default { $prefix }
    }

    $output = [PSCustomObject]@{
        prefixes = $TopdeskPrefix
        surname  = $TopdeskSurname
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

#correlation
$operatorCorrelationField = 'id'
$operatorCorrelationValue = $aRef.id

# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
# https://developers.topdesk.com/explorer/?page=supporting-files#/Persons/createPerson
$account = [PSCustomObject]@{
    surName          = (New-TopdeskSurname -Person $p).surname       # Generate surname according to the naming convention code.
    firstName        = $p.Name.NickName
    firstInitials    = $p.Name.Initials
    prefixes         = (New-TopdeskSurname -Person $p).prefixes     # Generate prefixes according to the naming convention code.
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
    department       = @{ lookupValue = $p.PrimaryContract.Department.DisplayName }
    budgetholder     = @{ lookupValue = $p.PrimaryContract.CostCenter.Name }
    branch           = @{ lookupValue = $p.PrimaryContract.Location.Name } # or  'Fixed branch'
}

#endregion mapping

#region helperfunctions

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
    if (-not($account.department.Keys -Contains 'lookupValue')) {
        $errorMessage = "Requested to lookup department, but department.lookupValue is not set. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # When department.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($account.department.lookupValue)) {
        if ([System.Convert]::ToBoolean($LookupErrorHrDepartment)) {
            # True, no department in lookup value = throw error
            $errorMessage = "The lookup value for Department is empty and the connector is configured to stop when this happens."
            $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
        else {
            # False, no department in lookup value = clear value
            Write-Verbose "Clearing department. (lookupErrorHrdDepartment = False)"
            $account.department.PSObject.Properties.Remove('lookupValue')
            $account.department | Add-Member -NotePropertyName id -NotePropertyValue $null
        }
    }
    else {
        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/departments"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-RestMethod @splatParams
        $department = $responseGet | Where-object name -eq $account.department.lookupValue

        # When department is not found in Topdesk
        if ([string]::IsNullOrEmpty($department.id)) {
            if ([System.Convert]::ToBoolean($LookupErrorTopdesk)) {

                # True, no department found = throw error
                $errorMessage = "Department [$($account.department.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                $auditLogs.Add([PSCustomObject]@{
                        Message = $errorMessage
                        IsError = $true
                    })
            }
            else {

                # False, no department found = remove department field (leave empty on creation or keep current value on update)
                $Account.department.Remove('lookupValue')
                $Account.PSObject.Properties.Remove('department')
                Write-Verbose "Not overwriting or setting department as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {

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
    if (-not($account.budgetholder.Keys -Contains 'lookupValue')) {
        $errorMessage = "Requested to lookup Budgetholder, but budgetholder.lookupValue is missing. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # When budgetholder.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($account.budgetholder.lookupValue)) {
        if ([System.Convert]::ToBoolean($lookupErrorHrBudgetHolder)) {

            # True, no budgetholder in lookup value = throw error
            $errorMessage = "The lookup value for Budgetholder is empty and the connector is configured to stop when this happens."
            $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
        else {

            # False, no budgetholder in lookup value = clear value
            $account.budgetHolder.PSObject.Properties.Remove('lookupValue')
            $account.budgetHolder | Add-Member -NotePropertyName id -NotePropertyValue $null
            Write-Verbose "Clearing budgetholder. (lookupErrorHrBudgetHolder = False)"
        }
    }
    else {

        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/budgetholders"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-RestMethod @splatParams
        $budgetHolder = $responseGet | Where-object name -eq $account.budgetHolder.lookupValue

        # When budgetholder is not found in Topdesk
        if ([string]::IsNullOrEmpty($budgetHolder.id)) {
            if ([System.Convert]::ToBoolean($lookupErrorTopdesk)) {
                # True, no budgetholder found = throw error
                $errorMessage = "Budgetholder [$($account.budgetHolder.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                $auditLogs.Add([PSCustomObject]@{
                        Message = $errorMessage
                        IsError = $true
                    })
            }
            else {

                # False, no budgetholder found = remove budgetholder field (leave empty on creation or keep current value on update)
                $Account.budgetHolder.Remove('lookupValue')
                $account.PSObject.Properties.Remove('budgetHolder')
                Write-Verbose "Not overwriting or setting Budgetholder as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {

            # Budgetholder is found in Topdesk, set in Topdesk
            $Account.budgetHolder.Remove('lookupValue')
            $Account.PSObject.Properties.Remove('budgetHolder')
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
    }
    else {
        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/branches"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-RestMethod @splatParams
        $branch = $responseGet | Where-object name -eq $Account.branch.lookupValue

        # When branch is not found in Topdesk
        if ([string]::IsNullOrEmpty($branch.id)) {

            # As branch is a required field, if no branch is found, an error is logged
            $errorMessage = "Branch with name [$($Account.branch.lookupValue)] isn't found in Topdesk but it's a required field."
            $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
        else {

            # Branch is found in Topdesk, set in Topdesk
            $Account.branch.Remove('lookupValue')
            $Account.branch.Add('id', $branch.id)
        }
    }
}

#endregion helperfunctions

# Update user
try {
    if (-Not($dryRun -eq $True)) {
        # Create basic authentication string
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("${username}:${apikey}")
        $base64 = [System.Convert]::ToBase64String($bytes)

        # Set authentication headers
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "BASIC $base64")
        $headers.Add("Accept", 'application/json')

        # Make sure baseUrl ends with '/'
        if ($baseUrl.EndsWith("/") -eq $false) {
            $baseUrl = $baseUrl + "/"
        }

        # Resolve branch id
        $splatParamsBranch = @{
            Account   = [ref]$account
            AuditLogs = [ref]$auditLogs
            Headers   = $headers
            baseUrl   = $c.baseUrl
        }
        Get-TopdeskBranch @splatParamsBranch

        # Resolve department id
        $splatParamsDepartment = @{
            Account                 = [ref]$account
            AuditLogs               = [ref]$auditLogs
            Headers                 = $headers
            baseUrl                 = $c.baseUrl
            lookupErrorHrDepartment = $c.lookupErrorHrDepartment
            lookupErrorTopdesk      = $c.lookupErrorTopdesk
        }
        Get-TopdeskDepartment @splatParamsDepartment

        # Resolve budgetholder id
        $splatParamsBudgetholder = @{
            Account                   = [ref]$account
            AuditLogs                 = [ref]$auditLogs
            Headers                   = $headers
            baseUrl                   = $c.baseUrl
            lookupErrorHrBudgetholder = $c.lookupErrorHrBudgetholder
            lookupErrorTopdesk        = $c.lookupErrorTopdesk
        }
        Get-TopdeskBudgetholder @splatParamsBudgetholder

        # Search for account
        Write-Verbose "Searching for operator with $($operatorCorrelationField): $($operatorCorrelationValue)"
        $operatorUri = $baseUrl + "tas/api/operators"
        $correlateUri = $operatorUri + "/?page_size=2&query=$($operatorCorrelationField)=='$($operatorCorrelationValue)';archived==false"
        $correlateResponse = Invoke-RestMethod -uri $correlateUri -Method Get -Headers $headers -UseBasicParsing
       
        if ($null -eq $correlateResponse.id) {
            throw "No operator found in TOPdesk with $($operatorCorrelationField): $($operatorCorrelationValue)"
        }
        elseif ($correlateResponse.id.Count -gt 1) {
            throw "Multiple operators found in TOPdesk with $($operatorCorrelationField): $($operatorCorrelationValue). Please correct this so the $($operatorCorrelationField) is unique."
        }
        elseif ($correlateResponse.id.Count -eq 1) {
            # Update account
            Write-Verbose "Updating operator $($aRef.loginName) ($($aRef.id))"

            $body = $account | ConvertTo-Json -Depth 10
            $updateUri = $operatorUri + "/id/$($aRef.id)"
            $updateResponse = Invoke-RestMethod -Method Patch -Uri $updateUri -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -ContentType "application/json" -Verbose:$false

            # Make sure to always have the latest data in $aRef (eventhough this shouldn't change)
            $aRef = @{
                loginName = $updateResponse.loginName
                id        = $updateResponse.id
            }
            
            $success = $true;
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "UpdateAccount"
                    Message = "Successfully updated account $($aRef.loginName) ($($aRef.id))";
                    IsError = $false;
                }); 
        }
    }
}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount"
            Message = "Error updating account $($account.loginName): $($_)"
            IsError = $True
        });
    Write-Warning $_;
}

# Send results
$result = [PSCustomObject]@{
    Success          = $success
    AccountReference = $aRef
    AuditLogs        = $auditLogs
    Account          = $account

    # Optionally return data for use in other systems
    ExportData       = [PSCustomObject]@{
        loginName = $aRef.loginName;
        id        = $aRef.id;
    };
}

Write-Output $result | ConvertTo-Json -Depth 10