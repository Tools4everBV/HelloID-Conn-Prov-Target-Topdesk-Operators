#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-Import
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

try {
    Write-Information 'Starting target account import'

    $importFields = $($actionContext.ImportFields)
    
    # Remove all '.' and the value behind. For example branch instead of branch.name
    $importFields = $importFields -replace '\..*', ''

    # Add mandatory fields for HelloID to query and return
    if ('id' -notin $importFields) { $importFields += 'id' }
    if ('status' -notin $importFields) { $importFields += 'status' }
    if ('dynamicName' -notin $importFields) { $importFields += 'dynamicName' }
    if ('loginName' -notin $importFields) { $importFields += 'loginName' }

    # Example how to filter out users that are deleted by HelloID (Reconciliation)
    # if ('mainframeLoginName' -notin $importFields) { $importFields += 'mainframeLoginName' }

    # Convert to a ',' string
    $fields = $importFields -join ','
    Write-Information "Querying fields [$fields]"

    # Create basic authentication string
    $username = $actionContext.Configuration.username
    $apikey = $actionContext.Configuration.apikey
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${username}:${apikey}")
    $base64 = [System.Convert]::ToBase64String($bytes)

    # Set authentication headers
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "BASIC $base64")
    $headers.Add('Accept', 'application/json; charset=utf-8')

    $existingAccounts = @()
    $pageSize = 100

    # Get active operators
    $pageStart = 0
    do {
        $uri = "$($actionContext.Configuration.baseUrl)/tas/api/operators?start=$pageStart&page_size=$pageSize&query=archived==false&fields=$fields"

        $splatParams = @{
            Uri         = $uri
            Headers     = $headers
            Method      = 'GET'
            ContentType = 'application/json; charset=utf-8'
        }
    
        $partialResultUsers = Invoke-RestMethod @splatParams
        $existingAccounts += $partialResultUsers
        $pageStart = $pageStart + $pageSize

        Write-Information "Successfully queried [$($existingAccounts.count)] existing accounts"
        
    } while ($partialResultUsers.Count -eq $pageSize)

    # Get archived operators
    $pageStart = 0
    do {
        $uri = "$($actionContext.Configuration.baseUrl)/tas/api/operators?start=$pageStart&page_size=$pageSize&query=archived==true&fields=$fields"

        $splatParams = @{
            Uri         = $uri
            Headers     = $headers
            Method      = 'GET'
            ContentType = 'application/json; charset=utf-8'
        }
    
        $partialResultUsers = Invoke-RestMethod @splatParams
        $existingAccounts += $partialResultUsers
        $pageStart = $pageStart + $pageSize

        Write-Information "Successfully queried [$($existingAccounts.count)] existing account"
        
    } while ($partialResultUsers.Count -eq $pageSize)

    # Example how to filter out users that are deleted by HelloID (Reconciliation)
    # $existingAccounts = $existingAccounts | Where-Object {$_.mainframeLoginName -ne 'Deleted by HelloID'}

    # Map the imported data to the account field mappings
    foreach ($account in $existingAccounts) {
        $enabled = $false
        # Convert status to enable
        if ($account.status -eq 'operator') {
            $enabled = $true
        }

        # Make sure the DisplayName has a value
        if ([string]::IsNullOrEmpty($account.dynamicName)) {
            $dynamicName = $account.id
        }
        else{
            $dynamicName = $account.dynamicName
        }

        # Make sure the Username has a value
        if ([string]::IsNullOrEmpty($account.loginName)) {
            $loginName = $account.id
        }
        else {
            $loginName = $account.loginName
        }

        # Return the result
        Write-Output @{
            AccountReference = $account.id
            DisplayName      = $dynamicName
            UserName         = $loginName
            Enabled          = $enabled
            Data             = $account
        }
    }
    Write-Information 'Target account import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.ErrorDetails.Message)"
            Write-Error "Could not import account entitlements. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            Write-Error "Could not import account entitlements. Error: $($ex.Exception.Message)"
        }
    }
    else {
        Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import account entitlements. Error: $($ex.Exception.Message)"
    }
}