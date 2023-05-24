$c = $configuration | ConvertFrom-Json

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# TOPdesk system data
$baseUrl = $c.baseUrl
$username = $c.username
$apiKey = $c.apikey

$take = 100;   
$skip = 0;
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

    Write-Verbose "Searching for operator filters"
    $operatorFilters = [System.Collections.ArrayList]@();
    $paged = $true;
    while ($paged) {
        # Define specific endpoint URI
        $operatorFiltersUri = $baseUrl + "tas/api/operators/filters/operator/?start=$skip&page_size=$take"
        $operatorFiltersResponse = Invoke-RestMethod -uri $operatorFiltersUri -Method Get -Headers $headers -UseBasicParsing

        # Set $paged to false (to end loop) when response is less than take, indicating there are no more records to query
        if ($operatorFiltersResponse.id.count -lt $take) {
            $paged = $false;
        }
        # Else: Up skip with take to skip the already queried records
        else {
            $skip = $skip + $take;
        }

        if ($operatorFiltersResponse -is [array]) {
            [void]$operatorFilters.AddRange($operatorFiltersResponse);
        }
        else {
            [void]$operatorFilters.Add($operatorFiltersResponse);
        }
    }
}
catch {
    throw $_;
}

foreach ($filter in $operatorFilters) {
    $returnObject = @{
        DisplayName    = "Operator Filter - $($filter.name)";
        Identification = @{
            Id   = $filter.id
            Name = $filter.name
            Type = "OperatorFilter"
        }
    };

    Write-Output $returnObject | ConvertTo-Json -Depth 10
}