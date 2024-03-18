###################################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Permissions-Groups
#
# Version: 3.0.0 | new-powershell-connector
#####################################################

# Initialize default values
$take = 100
$skip = 0
$baseUrl = $actionContext.Configuration.baseUrl

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
#endregion functions

try {

    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders

    Write-Verbose "Searching for operator groups"
    $operatorGroups = [System.Collections.ArrayList]@()
    $paged = $true
    while ($paged) {

        # Get operatorgroups
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/operatorgroups/?start=$skip&page_size=$take"
            Method  = 'GET'
            Headers = $authHeaders
        }
        $operatorGroupsResponse = Invoke-TopdeskRestMethod @splatParams

        # Set $paged to false (to end loop) when response is less than take, indicating there are no more records to query
        if ($operatorGroupsResponse.id.count -lt $take) {
            $paged = $false;
        }
        # Else: Up skip with take to skip the already queried records
        else {
            $skip = $skip + $take;
        }

        if ($operatorGroupsResponse -is [array]) {
            [void]$operatorGroups.AddRange($operatorGroupsResponse)
        }
        else {
            [void]$operatorGroups.Add($operatorGroupsResponse)
        }
    }
}
catch {
    throw $_
}

foreach ($group in $operatorGroups) {
    $outputContext.Permissions.Add(
        @{
            displayName    = "OperatorGroup - $($group.groupName)";
            identification = @{
                Id   = $group.id
                Name = $group.groupName
                Type = "OperatorGroup"
            }
        }
    )
}