#Initialize default properties
$success = $False
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$config = $configuration | ConvertFrom-Json 
$auditMessage = " not deleted succesfully"

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username

$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }

$operatorArchivingReason = @{
    id = "Persoon uit organisatie";
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)){
    try {
        $lookupFailure = $False

        write-verbose -verbose "Archiving reason lookup..."
        if ([string]::IsNullOrEmpty($operatorArchivingReason.id)) {
            $auditMessage = $auditMessage + "; Archiving reason is not set'"
            $lookupFailure = $True
            write-verbose -verbose "Archiving reason lookup failed"
        } else {
            $archivingReasonUrl = $url + "/archiving-reasons"
            $responseArchivingReasonJson = Invoke-WebRequest -uri $archivingReasonUrl -Method Get -Headers $headers -UseBasicParsing
            $responseArchivingReason = $responseArchivingReasonJson.Content | Out-String | ConvertFrom-Json
            $archivingReason = $responseArchivingReason | Where-object name -eq $operatorArchivingReason.id

            if ([string]::IsNullOrEmpty($archivingReason.id) -eq $True) {
                Write-Output -Verbose "Archiving Reason '$($operatorArchivingReason.id)' not found"
                $auditMessage = $auditMessage + "; Archiving Reason '$($operatorArchivingReason.id)' not found"
                $lookupFailure = $True
                write-verbose -verbose "Archiving Reason lookup failed"
            } else {
                $operatorArchivingReason.id = $archivingReason.id
                write-verbose -verbose "Archiving Reason lookup succesful"
            }
        }

        write-verbose -verbose "Operator lookup..."
        $operatorUrl = $url + "/operators/id/${aRef}"
        $responseOperatorJson = Invoke-WebRequest -uri $operatorUrl -Method Get -Headers $headers -UseBasicParsing -Verbose
        $responseOperator = $responseOperatorJson.Content | Out-String | ConvertFrom-Json

        if([string]::IsNullOrEmpty($responseoperator.id)) {
            $auditMessage = $auditMessage + "; Operator is not found in TOPdesk'"
            $lookupFailure = $true
            write-verbose -verbose "Operator not found in TOPdesk"
        } else {
            write-verbose -verbose "Operator lookup succesful"
        }
           
        if (!($lookupFailure)) {
            if ($responseoperator.status -eq "operator") {
                write-verbose -verbose "Archiving account for '$($p.ExternalID)...'"
                $bodyOperatorArchive = $operatorArchivingReason | ConvertTo-Json -Depth 10
                $archiveUrl = $url + "/operators/id/${aRef}/archive"
                $null = Invoke-WebRequest -uri $archiveUrl -Method PATCH -Body ([Text.Encoding]::UTF8.GetBytes($bodyOperatorArchive)) -Headers $headers -UseBasicParsing
             write-verbose -verbose "Operator Archived"
                $auditMessage = "disabled succesfully";
            } else {
                write-verbose -verbose "Operator is already archived. Nothing to do"
            }
            $success = $True
            $auditMessage = "deleted succesfully"
        }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not deleted succesfully: '$($_.Exception.Message)'" 
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
            $auditMessage = " not deleted succesfully: '$($_.ErrorDetails.Message)'"
        } else {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
            $auditMessage = " not deleted succesfully: '$($_)'"
        }        
        $success = $False
    }
}

#build up result
$result = [PSCustomObject]@{ 
	Success = $success;
	AuditDetails = $auditMessage;
}

Write-Output $result | ConvertTo-Json -Depth 10