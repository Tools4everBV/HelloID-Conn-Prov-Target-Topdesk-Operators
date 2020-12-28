#Initialize default properties
$success = $False
$p = $person | ConvertFrom-Json
$config = $configuration | ConvertFrom-Json 
$auditMessage = " not created succesfully"

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username

$operatorUrl = $url + '/operators'
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }

#Connector settings
$createMissingDepartment = [System.Convert]::ToBoolean($config.persons.errorNoDepartmentTD)
$errorOnMissingDepartment = [System.Convert]::ToBoolean($config.persons.errorNoDepartmentHR)

#mapping
$username = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
$email = $p.Accounts.MicrosoftActiveDirectory.Mail

$account = @{
    surName = $p.Custom.TOPdeskSurName;
    firstName = $p.Name.NickName;
    firstInitials = $p.Name.Initials;
    gender = $p.Custom.TOPdeskGender;
    email = $email;
    exchangeAccount = $email;
    title = $p.PrimaryContract.Title.Name;
    department = @{ id = $p.PrimaryContract.Department.DisplayName };
    employeeNumber = $p.ExternalID;
    networkLoginName = $username;
    branch = @{ id = $p.PrimaryContract.Location.Name };
    loginName = $username;
    loginPermission = $True;
    #firstLineCallOperator = $True;
}

#correlation
$correlationField = 'employeeNumber'
$correlationValue = $p.ExternalID

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)) {
 try {
    $create = $True
    write-verbose -verbose "Correlate operator"
    $personCorrelationUrl = $operatorUrl + "/?page_size=2&query=$($correlationField)=='$($correlationValue)'"
    $responseCorrelationJson = Invoke-WebRequest -uri $personCorrelationUrl -Method Get -Headers $headers -UseBasicParsing
    $responseCorrelation = $responseCorrelationJson | ConvertFrom-Json

    if(-Not($null -eq $responseCorrelation) -and -Not($null -eq $responseCorrelation[0].id)) {
        $aRef = $responseCorrelation[0].id 
        $create = $False
        $success = $True
        $auditMessage = "Correlation found record $($correlationValue). Update succesful"
        write-verbose -verbose "Operator found in TOPdesk"
    }

    if($create){  
        write-verbose -verbose "Operator not found in TOPdesk"
        $lookupFailure = $False
        
        # get branch
        write-verbose -verbose "Branch lookup..."
        if ([string]::IsNullOrEmpty($account.branch.id)) {
            $auditMessage = $auditMessage + "; Branch is empty for person '$($p.ExternalId)'"
            $lookupFailure = $True
            write-verbose -verbose "Branch lookup failed"
        } else {
            $branchUrl = $url + "/branches?query=name=='$($account.branch.id)'"
            $responseBranchJson = Invoke-WebRequest -uri $branchUrl -Method Get -Headers $headers -UseBasicParsing
            $personBranch = $responseBranchJson.Content | Out-String | ConvertFrom-Json
        
            if ([string]::IsNullOrEmpty($personBranch.id) -eq $True) {
                $auditMessage = $auditMessage + "; Branch '$($account.branch.id)' not found!"
                $lookupFailure = $True
                write-verbose -verbose "Branch lookup failed"
            } else {
                $account.branch.id = $personBranch.id
                write-verbose -verbose "Branch lookup succesful"
            }
        }
        
        # get department
        write-verbose -verbose "Department lookup..."
        if ([string]::IsNullOrEmpty($account.department.id)) {
            if ($errorOnMissingDepartment) { 
                $lookupFailure = $true
            }
            write-verbose -verbose "Department lookup failed. HR Department is empty for person '$($p.ExternalId)'"
        } else {
            $departmentUrl = $url + "/departments"
            $responseDepartmentJson = Invoke-WebRequest -uri $departmentUrl -Method Get -Headers $headers -UseBasicParsing
            $responseDepartment = $responseDepartmentJson.Content | Out-String | ConvertFrom-Json
            $personDepartment = $responseDepartment | Where-object name -eq $account.department.id

            if ([string]::IsNullOrEmpty($personDepartment.id) -eq $True) {
                Write-Output -Verbose "Department '$($account.department.id)' not found"
                if ($createMissingDepartment) {
                    Write-Verbose -Verbose "Creating department '$($account.department.id)' in TOPdesk"
                    $bodyDepartment = @{ name=$account.department.id } | ConvertTo-Json -Depth 1
                    $responseDepartmentCreateJson = Invoke-WebRequest -uri $departmentUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyDepartment)) -UseBasicParsing
                    $responseDepartmentCreate = $responseDepartmentCreateJson.Content | Out-String | ConvertFrom-Json
                    Write-Verbose -Verbose "Created Department name '$($account.department.id)' with id '$($responseDepartmentCreate.id)'"
                    $account.department.id = $responseDepartmentCreate.id
                } else {
                    $auditMessage = $auditMessage + "; Department '$($account.department.id)' not found"
                    write-verbose -verbose "Department lookup failed"
                    $lookupFailure = $true
                }
            } else {
                $account.department.id = $personDepartment.id
                write-verbose -verbose "Department lookup succesful"
            }
        }
              
        if (!($lookupFailure)) {
            write-verbose -verbose "Creating account for '$($p.ExternalID)'"
            $bodyOperatorCreate = $account | ConvertTo-Json -Depth 10
            $responseOperatorCreate = Invoke-WebRequest -uri $operatorUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyOperatorCreate)) -UseBasicParsing
            $responseOperatorCreateJson = $responseOperatorCreate.Content | Out-String | ConvertFrom-Json
            if(![string]::IsNullOrEmpty($responseOperatorCreateJson.id)) {
                $aRef = $responseOperatorCreateJson.id
                $success = $True
                $auditMessage = "created succesfully"
            }  
        } else {
            $success = $False
        }
    }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not created succesfully: '$($_.Exception.Message)'" 
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
            $auditMessage = " not created succesfully: '$($_.ErrorDetails.Message)'"
        } else {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'" 
            $auditMessage = " not created succesfully: '$($_)'" 
        }        
        $success = $False
    }
}

#build up result
$result = [PSCustomObject]@{ 
	Success= $success;
    AccountReference=$aRef;
	AuditDetails=$auditMessage;
    Account=$account;
}

Write-Output $result | ConvertTo-Json -Depth 10