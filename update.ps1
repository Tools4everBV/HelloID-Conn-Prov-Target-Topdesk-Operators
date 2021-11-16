#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$config = $configuration | ConvertFrom-Json 
$auditMessage = " not updated succesfully";

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username

$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }

#Connector settings
$createMissingDepartment = [System.Convert]::ToBoolean($config.persons.errorNoDepartmentTD)
$errorOnMissingDepartment = [System.Convert]::ToBoolean($config.persons.errorNoDepartmentHR)

#mapping
$username = $p.Accounts.MicrosoftActiveDirectory.SamAccountName;
$email = $p.Accounts.MicrosoftActiveDirectory.Mail;
$surname = ""

$prefix = ""
if(-Not([string]::IsNullOrEmpty($p.Name.FamilyNamePrefix)))
{
    $prefix = $p.Name.FamilyNamePrefix + " "
}

$partnerprefix = ""
if(-Not([string]::IsNullOrEmpty($p.Name.FamilyNamePartnerPrefix)))
{
    $partnerprefix = $p.Name.FamilyNamePartnerPrefix + " "
}

switch($p.Name.Convention)
{
    "B" {$surname += $prefix + $p.Name.FamilyName}
    "P" {$surname += $partnerprefix + $p.Name.FamilyNamePartner}
    "BP" {$surname += $prefix + $p.Name.FamilyName + " - " + $partnerprefix + $p.Name.FamilyNamePartner}
    "PB" {$surname += $partnerprefix + $p.Name.FamilyNamePartner + " - " + $prefix + $p.Name.FamilyName}
    default {$surname += $prefix + $p.Name.FamilyName}
}


switch($p.details.Gender)
{
    "M" {$gender = "MALE"}
    "V" {$gender = "FEMALE"}
    default {$gender = ""}
}

$account = @{
    surName = $surname;
    firstName = $p.Name.NickName; 
    firstInitials = $p.Name.Initials;
    gender = $gender;
    email = $email; 
    exchangeAccount = $email;
    jobTitle = $p.PrimaryContract.Title.Name;  
    department = @{ id = $p.PrimaryContract.Department.DisplayName };
    employeeNumber = $p.ExternalID;
    networkLoginName = $username;
    branch = @{ id = "Fixed Branch" };
    loginName = $username;
    loginPermission = $True;
    secondLineCallOperator = $True;
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)){
    try {
        $lookupFailure = $False

        # get person by ID
        write-verbose -verbose "Person lookup..."
        $PersonUrl = $url + "/operators/id/${aRef}"
        $responsePersonJson = Invoke-WebRequest -uri $PersonUrl -Method Get -Headers $headers -UseBasicParsing
        $responsePerson = $responsePersonJson.Content | Out-String | ConvertFrom-Json

        if([string]::IsNullOrEmpty($responsePerson.id)) {
            # add audit message
            $lookupFailure = $true
            write-verbose -verbose "Person not found in TOPdesk"
        } else {
            write-verbose -verbose "Person lookup succesful"
        
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
                $auditMessage = $auditMessage + "; Department is empty for person '$($p.ExternalId)'"
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
                        Write-Verbose -Verbose "Creating department '$($Account.department.id)' in TOPdesk"
                        $bodyDepartment = @{ name=$account.department.id } | ConvertTo-Json -Depth 1
                        $responseDepartmentCreateJson = Invoke-WebRequest -uri $departmentUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyDepartment)) -UseBasicParsing
                        $responseDepartmentCreate = $responseDepartmentCreateJson.Content | Out-String | ConvertFrom-Json
                        Write-Verbose -Verbose "Created department name '$($account.department.id)' with id '$($responseDepartmentCreate.id)'"
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
                if ($person.status -eq "personArchived") {
                    write-verbose -verbose "Unarchiving account for '$($p.ExternalID)...'"
                    $unarchiveUrl = $PersonUrl + "/unarchive"
                    $null = Invoke-WebRequest -uri $unarchiveUrl -Method PATCH -Headers $headers -UseBasicParsing
                    write-verbose -verbose "Account unarchived"
                }
            
                write-verbose -verbose "Updating account for '$($p.ExternalID)...'"
                $bodyPersonUpdate = $account | ConvertTo-Json -Depth 10
                $null = Invoke-WebRequest -uri $personUrl -Method PATCH -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyPersonUpdate)) -UseBasicParsing
                $success = $True
                $auditMessage = "update succesful"
                write-verbose -verbose "Account updated for '$($p.ExternalID)'"
            } else {
                $success = $False;
            }
        }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not updated succesfully: '$($_.Exception.Message)'" 
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
            $auditMessage = " not updated succesfully: '$($_.ErrorDetails.Message)'"
        } else {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'" 
            $auditMessage = " not updated succesfully: '$($_)'" 
        }        
        $success = $False
    }
}

#build up result
$result = [PSCustomObject]@{ 
	Success = $success;
    #AccountReference = $aRef;
	AuditDetails = $auditMessage;
};

Write-Output $result | ConvertTo-Json -Depth 10