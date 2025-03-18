#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-ImportPermission-OperatorFilters
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

try {      
    Write-Information 'Starting target account permission import'

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
        $uri = "$($actionContext.Configuration.baseUrl)/tas/api/operators?start=$pageStart&page_size=$pageSize&query=archived==false&fields=id"

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
        $uri = "$($actionContext.Configuration.baseUrl)/tas/api/operators?start=$pageStart&page_size=$pageSize&query=archived==true&fields=id"

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


    Write-Information 'Starting getting permission memberships of each account'

    foreach ($account in $existingAccounts) {
        $splatGetGroupMembers = @{
            Uri         = "$($actionContext.Configuration.baseUrl)/tas/api/operators/id/$($account.id)/filters/operator"
            Headers     = $headers
            Method      = 'GET'
            ContentType = 'application/json; charset=utf-8'
        }
        
        [array]$existingPermissions = Invoke-RestMethod @splatGetGroupMembers

        if (-not([string]::IsNullOrEmpty($existingPermissions))) {
            foreach ($permission in $existingPermissions) {
                Write-Output @(
                    @{
                        AccountReferences   = @( 
                            $account.id
                        )
                        PermissionReference = @{
                            Reference = $permission.id
                        }
                        Description         = "Operator filter $($permission.name)"
                        DisplayName         = $permission.name
                    }
                )
            }
        }
    }

    Write-Information 'Target account permission import completed'
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