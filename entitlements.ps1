$config = $configuration | ConvertFrom-Json 

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username

$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }

$operatorgroupsUrl = $url + "/operatorgroups/?page_size=100"
$responseoperatorgroupsJson = Invoke-WebRequest -uri $operatorgroupsUrl -Method Get -Headers $headers -UseBasicParsing
$responseoperatorgroups = $responseoperatorgroupsJson.Content | Out-String | ConvertFrom-Json

foreach($group in $responseoperatorgroups)
{
	$row = @{
		DisplayName = $group.groupName;
		Identification = @{
			Id = $group.id;
			DisplayName = $group.groupName;
			Type = "OperatorGroup";
		}
	};
	Write-Output ($row | ConvertTo-Json -Depth 10)
}
