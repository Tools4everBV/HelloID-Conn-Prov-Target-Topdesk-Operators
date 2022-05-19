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
# No mapping, since we only unarchive on enable
# $account = [PSCustomObject]@{}

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
            # Unarchive account
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
                        Action  = "EnableAccount"
                        Message = "Successfully unarchived account $($aRef.loginName) ($($aRef.id))";
                        IsError = $false;
                    }); 

            }
            else {
                $success = $true;
                $auditLogs.Add([PSCustomObject]@{
                        Action  = "EnableAccount"
                        Message = "Successfully unarchived account $($aRef.loginName) ($($aRef.id)) (already unarchived)";
                        IsError = $false;
                    });                 
            }
        }
    }
}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "EnableAccount"
            Message = "Error unarchiving account $($account.loginName): $($_)"
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