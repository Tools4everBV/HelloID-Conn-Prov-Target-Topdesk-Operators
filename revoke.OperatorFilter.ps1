###################################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Permissions-Revoke
#
# Version: 2.0.1
###################################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()
$success = $True
$baseUrl = $config.baseUrl

# The permissionReference object contains the Identification object provided in the retrieve permissions call
$pRef = $permissionReference | ConvertFrom-Json;
$aRef = $aRef.ID

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

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
            throw $_
        }
    }
}

try {
    if ($dryRun -eq $false) {
        # Setup authentication headers
        $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

        Write-Verbose -verbose "Revoking filter $($pRef.Name) ($($pRef.id)) from ($($aRef))"
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/operators/id/$($aRef)/filters/operator"
            #Method  = 'Post'
            Method  = 'Delete'
            Headers = $authHeaders
            Body    = ConvertTo-Json -InputObject @(@{ id = $($pRef.id) }) -Depth 10
        }
       $null = Invoke-TopdeskRestMethod @splatParams
        
        Write-Verbose "Successfully revoked Filter $($pRef.Name) ($($pRef.id)) from ($($aRef))"

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Action  = "RevokePermission"
                Message = "Successfully revoked Filter $($pRef.Name) ($($pRef.id)) from ($($aRef))"
                IsError = $false
            })
    }
}
catch {
    $auditLogs.Add([PSCustomObject]@{
            Action  = "RevokePermission"
            Message = "Failed to revoke Filter $($pRef.Name) ($($pRef.id)) from $($aRef.loginName) ($($aRef.id)):  $_"
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