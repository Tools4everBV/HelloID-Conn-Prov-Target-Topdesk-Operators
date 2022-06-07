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
# $aRef = @{
#     loginName = "j.doe"
#     id = "a1b2345c-89dd-47a5-8de3-6de7df89g012"
# }
# $dryRun = $false

#correlation
$operatorCorrelationField = 'id'
$operatorCorrelationValue = $aRef.id

# Change mapping here
# Clear email, networkLoginName & loginName, if you need to clear other values, add these here
$account = [PSCustomObject]@{
    email            = $null
    networkLoginName = $null
    loginName        = $null
}

$operatorArchivingReason = "Persoon uit organisatie"

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

        # Define specific endpoint URI
        if ($baseUrl.EndsWith("/") -eq $false) {
            $baseUrl = $baseUrl + "/"
        }
        $operatorUri = $baseUrl + "tas/api/operators"

        # Search for account
        Write-Verbose "Searching for operator with $($operatorCorrelationField): $($operatorCorrelationValue)"
        $correlateUri = $operatorUri + "/?page_size=2&query=$($operatorCorrelationField)=='$($operatorCorrelationValue)'"
        $correlateResponse = Invoke-RestMethod -uri $correlateUri -Method Get -Headers $headers -UseBasicParsing
       
        if ($null -eq $correlateResponse.id) {
            throw "No operator found in TOPdesk with $($operatorCorrelationField): $($operatorCorrelationValue)"
        }
        elseif ($correlateResponse.id.Count -gt 1) {
            throw "Multiple operators found in TOPdesk with $($operatorCorrelationField): $($operatorCorrelationValue). Please correct this so the $($operatorCorrelationField) is unique."
        }
        elseif ($correlateResponse.id.Count -eq 1) {
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
                        Action  = "DeleteAccount"
                        Message = "Successfully unarchived account $($aRef.loginName) ($($aRef.id)) (needed to update account and clear fields)";
                        IsError = $false;
                    }); 

            }

            # Update account
            Write-Verbose "Clearing fields of operator $($aRef.loginName) ($($aRef.id))"

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
                    Action  = "DeleteAccount"
                    Message = "Successfully cleared fields of account $($aRef.loginName) ($($aRef.id))";
                    IsError = $false;
                }); 


            # Archive account (or re-archive if we had to unarchive to update)
            if ($updateResponse.status -eq "operator") {
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
                        Action  = "DeleteAccount"
                        Message = "Successfully archived account $($aRef.loginName) ($($aRef.id))";
                        IsError = $false;
                    });

            }
        }
    }
}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "DeleteAccount"
            Message = "Error clearing fields of account $($account.loginName): $($_)"
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
}

Write-Output $result | ConvertTo-Json -Depth 10
