$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "Continue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# TOPdesk system data
$baseUrl = $c.baseUrl
$username = $c.username
$apiKey = $c.apikey
$operatorArchivingReason = $c.operatorArchivingReason

# Troubleshooting
# $p.ExternalID = '12345678'
# $dryRun = $false

#correlation
$personCorrelationField = 'employeeNumber'
$personCorrelationValue = $p.ExternalID
$operatorCorrelationField = 'employeeNumber'
$operatorCorrelationValue = $p.ExternalID

$updateOnCorrelate = $false

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

# Create or Correlate user
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
        $correlateUri = $operatorUri + "/?page_size=2&query=$($operatorCorrelationField)=='$($operatorCorrelationValue)'"
        $correlateResponse = Invoke-RestMethod -uri $correlateUri -Method Get -Headers $headers -UseBasicParsing
    
        if ($correlateResponse.id.Count -gt 1) {
            throw "Multiple operators found in TOPdesk with $($operatorCorrelationField): $($operatorCorrelationValue). Please correct this so the $($operatorCorrelationField) is unique."
        }
        elseif ($correlateResponse.id.Count -eq 1) {
            # Correlate account
            $aRef = @{
                loginName = $correlateResponse.loginName
                id        = $correlateResponse.id
            }

            $success = $true;
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "Successfully correlated to account $($aRef.loginName) ($($aRef.id))";
                    IsError = $false;
                });

            # Update account if so configured
            if ($updateOnCorrelate -eq $true) {
                # register the original status of the operator, so we know what to do after the update
                $originalStatus = $correlateResponse.status

                # Search for archiving reason
                if ([string]::IsNullOrEmpty($operatorArchivingReason)) {
                    throw "No archiving reason configured. Please configure an archiving reason."
                }

                Write-Verbose "Searching for archiving reason: $($operatorArchivingReason)"
                $archivingReasonUri = $baseUrl + "tas/api/archiving-reasons"
                $archivingReasonResponse = Invoke-RestMethod -uri $archivingReasonUri -Method Get -Headers $headers -UseBasicParsing
                $archivingReason = $archivingReasonResponse | Where-object { $_.name -eq $operatorArchivingReason }

                if ([string]::IsNullOrEmpty($archivingReason.id) -eq $True) {
                    Write-Information "Found archiving reasons: $($archivingReasonResponse.name -Join ';')"
                    throw "Archiving Reason '$($operatorArchivingReason)' not found. Please configure a valid archiving reason."
                }
                else {
                    Write-Verbose "Successfully found archiving reason $($archivingReason.name) ($($archivingReason.id))"
                }

                # Unarchive account (needed to update account)
                if ($correlateResponse.status -eq "operatorArchived") {
                    Write-Verbose "Unarchiving operator $($aRef.loginName) ($($aRef.id))"
                    $unarchiveUri = $operatorUri + "/id/$($aRef.id)/unarchive"
                    $updateResponse = Invoke-RestMethod -Method Patch -Uri $unarchiveUri -Headers $headers -Verbose:$false

                    # Make sure to always have the latest data in $aRef (eventhough this shouldn't change)
                    $aRef = @{
                        loginName = $updateResponse.loginName
                        id        = $updateResponse.id
                    }

                    $success = $true;
                    $auditLogs.Add([PSCustomObject]@{
                            Action  = "CreateAccount"
                            Message = "Successfully unarchived account $($aRef.loginName) ($($aRef.id)) (needed to update account)";
                            IsError = $false;
                        }); 

                }

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
                        Action  = "CreateAccount"
                        Message = "Successfully updated account $($aRef.loginName) ($($aRef.id))";
                        IsError = $false;
                    }); 

                # Archive account (or re-archive if we had to unarchive to update)
                if ($originalStatus -eq "operatorArchived" -and $updateResponse.status -eq "operator") {
                    Write-Verbose "Archiving operator $($aRef.loginName) ($($aRef.id))"
                    $body = @{ id = $archivingReason.id } | ConvertTo-Json -Depth 10
                    $archiveUri = $operatorUri + "/id/$($aRef.id)/archive"
                    $updateResponse = Invoke-RestMethod -Method Patch -Uri $archiveUri -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -ContentType "application/json" -Verbose:$false

                    # Make sure to always have the latest data in $aRef (eventhough this shouldn't change)
                    $aRef = @{
                        loginName = $updateResponse.loginName
                        id        = $updateResponse.id
                    }

                    $success = $true;
                    $auditLogs.Add([PSCustomObject]@{
                            Action  = "CreateAccount"
                            Message = "Successfully archived account $($aRef.loginName) ($($aRef.id))";
                            IsError = $false;
                        });

                }
            }
        }
        elseif ($null -eq $correlateResponse.id) {
            # Create account
            Write-Verbose "Creating account with loginName: $($account.loginName)"
            $body = $account | ConvertTo-Json -Depth 10
            $createUri = $operatorUri
            $createResponse = Invoke-RestMethod -Method Post -Uri $createUri -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -ContentType "application/json" -Verbose:$false

            # Make sure to always have the latest data in $aRef (eventhough this shouldn't change)
            $aRef = @{
                loginName = $createResponse.loginName
                id        = $createResponse.id
            }

            $success = $true;
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount"
                    Message = "Successfully created account $($aRef.loginName) ($($aRef.id))";
                    IsError = $false;
                }); 
        }
    }
}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount"
            Message = "Error creating account $($account.loginName): $($_)"
            IsError = $True
        });
    Write-Warning $_
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