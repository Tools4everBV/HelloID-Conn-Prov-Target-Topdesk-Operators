###################################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Permissions-Retrieve
#
# Version: 2.0.1
###################################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$take = 100
$skip = 0
$baseUrl = $config.baseUrl

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# region helperfunctions

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

# end region helperfunctions

try {

     # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    Write-Verbose "Searching for operator groups"
    $operatorGroups = [System.Collections.ArrayList]@();
    $paged = $true;
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
            [void]$operatorGroups.AddRange($operatorGroupsResponse);
        }
        else {
            [void]$operatorGroups.Add($operatorGroupsResponse);
        }
    }
}
catch {
    throw $_;
}

foreach ($group in $operatorGroups) {
    $returnObject = @{
        DisplayName    = "OperatorGroup - $($group.groupName)";
        Identification = @{
            Id   = $group.id
            Name = $group.groupName
            Type = "OperatorGroup"
        }
    };

    Write-Output $returnObject | ConvertTo-Json -Depth 10
}