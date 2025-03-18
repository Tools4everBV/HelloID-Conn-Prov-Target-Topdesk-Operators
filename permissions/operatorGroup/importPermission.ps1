#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Operators-importPermission-Group
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

    $existingPermissions = @()
    $pageSize = 100
    $pageStart = 0
   
    do {
        $uri = "$($actionContext.Configuration.baseUrl)/tas/api/operatorgroups?start=$pageStart&page_size=$pageSize&fields=id,groupName"

        $splatGetGroups = @{
            Uri         = $uri
            Headers     = $headers
            Method      = 'GET'
            ContentType = 'application/json; charset=utf-8'
        }
    
        $partialResultGroups = Invoke-RestMethod @splatGetGroups
        $existingPermissions += $partialResultGroups
        $pageStart = $pageStart + $pageSize

        Write-Information "Successfully queried [$($existingPermissions.count)] existing permissions"
        
    } while ($partialResultUsers.Count -eq $pageSize)

    Write-Information 'Starting getting account memberships of each permission'

    foreach ($permission in $existingPermissions) {       
        $splatGetGroupMembers = @{
            Uri         = "$($actionContext.Configuration.baseUrl)/tas/api/operatorgroups/id/$($permission.id)/operators"
            Headers     = $headers
            Method      = 'GET'
            ContentType = 'application/json; charset=utf-8'
        }
            
        [array]$groupMembers = (Invoke-RestMethod @splatGetGroupMembers).id

        if ($groupMembers.count -gt 0) {
            Write-Output @(
                @{
                    AccountReferences   = $groupMembers
                    PermissionReference = @{
                        Reference = $permission.id
                    }
                    Description         = "Operator group $($permission.groupName)"
                    DisplayName         = $permission.groupName
                }
            )

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