#region Initialize default properties
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;

# The permissionReference object contains the Identification object provided in the retrieve permissions call
$pRef = $permissionReference | ConvertFrom-Json;

$success = $True
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Troubleshooting
# $aRef = @{
#     loginName = "j.doe"
#     id = "a1b2345c-89dd-47a5-8de3-6de7df89g012"
# }
# $dryRun = $false

# TOPdesk system data
$baseUrl = $c.baseUrl
$username = $c.username
$apiKey = $c.apikey

try {
    if ($dryRun -eq $false) {
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

        Write-Verbose "Granting permission $($pRef.Name) ($($pRef.id)) to $($aRef.loginName) ($($aRef.id))"
        $body = ConvertTo-Json -InputObject @(@{ id = $($pRef.id) }) -Depth 10
        $operatorGroupMembershipUri = $baseUrl + "tas/api/operators/id/$($aRef.id)/operatorgroups"
        $addOperatorGroupMembershipResponse = Invoke-RestMethod -Method Post -Uri $operatorGroupMembershipUri -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -ContentType "application/json" -Verbose:$false
        Write-Verbose "Successfully granted Permission $($pRef.Name) ($($pRef.id)) to $($aRef.loginName) ($($aRef.id))"

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Action  = "GrantPermission"
                Message = "Successfully granted Permission $($pRef.Name) ($($pRef.id)) to $($aRef.loginName) ($($aRef.id))"
                IsError = $false
            })
    }

}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "GrantPermission"
            Message = "Failed to grant permission $($pRef.Name) ($($pRef.id)) to $($aRef.loginName) ($($aRef.id)):  $_"
            IsError = $True
        });
    $success = $false
    Write-Warning $_;
}

#build up result
$result = [PSCustomObject]@{ 
    Success   = $success
    AuditLogs = $auditLogs
    # Account   = [PSCustomObject]@{ }
};

Write-Output $result | ConvertTo-Json -Depth 10;