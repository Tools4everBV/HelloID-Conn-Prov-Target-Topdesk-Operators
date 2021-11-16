#Initialize default properties
$success = $False
#Write-Verbose -Verbose $person
$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$pRef = $permissionReference | ConvertFrom-json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$config = $configuration | ConvertFrom-Json 
$auditMessage = " not created succesfully";

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

if (-Not($dryRun -eq $True)) {
    
	try {
		$contentType = "application/json"
		$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
		$base64 = [System.Convert]::ToBase64String($bytes)
		$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }
	   
        if($pRef.Type -eq "OperatorGroup")
        {
            $uriOperatorgroupMembership  = $url + "/operators/id/$aref/operatorgroups"
            $item = @{
                id = $($pref.id)
            } 
            
            $requestObject = @($item)        
            
            $request = ConvertTo-Json -InputObject $requestObject -Depth 10

            $response = Invoke-WebRequest -Uri $uriOperatorgroupMembership -Method POST -ContentType $contentType -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($request)) -UseBasicParsing
        }

        if($pRef.Type -eq "PermissionGroup")
        {
            Write-Error "Not yet implemented"
        }

        if($pRef.Type -eq "CategoryFilter")
        {
            Write-Error "Not yet implemented"
        }
		
		Write-Verbose -Verbose "Successfully added operator to $($pRef.Type)"
		
		$success = $True;
		$auditMessage = "Successfully added operator to operatorgroup"
	}
	catch {
		write-verbose -verbose $_
		$result = $_.Exception.Response.GetResponseStream()
		$reader = New-Object System.IO.StreamReader($result)
		$reader.BaseStream.Position = 0
		$reader.DiscardBufferedData()
		$errResponse = $reader.ReadToEnd();
		$auditMessage = "${errResponse}";
	}
}

#build up result
$result = [PSCustomObject]@{ 
	Success= $success;
    AccountReference= $aRef;
	AuditDetails=$auditMessage;
    Account= $account;
};

Write-Output $result | ConvertTo-Json -Depth 10;