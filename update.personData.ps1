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

#correlation
$personCorrelationField = 'employeeNumber'
$personCorrelationValue = $p.ExternalID
$operatorCorrelationField = 'id'
$operatorCorrelationValue = $aRef.id

# Get TOPdesk person, since we want to map the same data to the operators
try {
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

    # Search for account
    Write-Verbose "Searching for person with $($personCorrelationField): $($personCorrelationValue)"
    $personUri = $baseUrl + "tas/api/persons"
    $getPersonUri = $personUri + "/?page_size=2&query=$($personCorrelationField)=='$($personCorrelationValue)'"
    $getPersonResponse = Invoke-RestMethod -uri $getPersonUri -Method Get -Headers $headers -UseBasicParsing
    
    if ($null -eq $getPersonResponse.id) {
        throw "No person found in TOPdesk with $($personCorrelationField): $($personCorrelationValue)"
    }
    elseif ($getPersonResponse.id.Count -gt 1) {
        throw "Multiple persons found in TOPdesk with $($personCorrelationField): $($personCorrelationValue). Please correct this so the $($personCorrelationField) is unique."
    }
    elseif ($getPersonResponse.id.Count -eq 1) {
        Write-Information "Successfully found person $($getPersonResponse.tasLoginName) ($($getPersonResponse.id))"
    }
}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount"
            Message = "Error creating account $($account.Username): $($_)"
            IsError = $True
        });
    throw $_;
}

# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
# https://developers.topdesk.com/explorer/?page=supporting-files#/Persons/createPerson
# Use data from TOPdesk person (these are created from a direct sync between HR and TOPdesk)
$account = [PSCustomObject]@{
    surName          = $getPersonResponse.surName
    firstName        = $getPersonResponse.firstName
    firstInitials    = $getPersonResponse.firstInitials
    prefixes         = $getPersonResponse.prefixes
    title            = $getPersonResponse.title
    gender           = $getPersonResponse.gender

    telephone        = $getPersonResponse.telephone
    mobileNumber     = $getPersonResponse.mobileNumber
    faxNumber        = $getPersonResponse.faxNumber

    employeeNumber   = $getPersonResponse.employeeNumber
    email            = $getPersonResponse.email
    networkLoginName = $getPersonResponse.networkLoginName
    loginName        = $getPersonResponse.tasLoginName

    jobTitle         = $getPersonResponse.jobTitle
    department       = @{ id = $getPersonResponse.department.id }
    budgetHolder     = @{ id = $getPersonResponse.budgetHolder.id }
    branch           = @{ id = $getPersonResponse.branch.id }

    loginPermission  = $true
    exchangeAccount  = $getPersonResponse.email
}

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