#$permissions = @()
#write-output $permissions | ConvertTo-Json -Depth 10;


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
		DisplayName = "OperatorGroup $($group.groupName)";
		Identification = @{
			Id = $group.id;
			DisplayName = "OperatorGroup $($group.groupName)";
			Type = "OperatorGroup";
		}
	};
	Write-Output ($row | ConvertTo-Json -Depth 10)
}

<#
$permissiongroupsUrl = $url + "/permissiongroups/?page_size=100"
$responsepermissiongroupsJson = Invoke-WebRequest -uri $permissiongroupsUrl -Method Get -Headers $headers -UseBasicParsing
$responsepermissiongroups = $responsepermissiongroupsJson.Content | Out-String | ConvertFrom-Json

foreach($group in $responsepermissiongroups)
{
    #Write-Verbose -Verbose $group
	$row = @{
		DisplayName = "PermissionGroup $($group.name)";
		Identification = @{
			Id = $group.id;
			DisplayName = "PermissionGroup $($group.name)";
			Type = "PermissionGroup";
		}
	};
	Write-Output ($row | ConvertTo-Json -Depth 10)
}


$categoryfiltersUrl = $url + "/operators/filters/category/?page_size=100"
$responsecategoryfiltersJson = Invoke-WebRequest -uri $categoryfiltersUrl -Method Get -Headers $headers -UseBasicParsing
$responsecategoryfiltersgroups = $responsecategoryfiltersJson.Content | Out-String | ConvertFrom-Json

foreach($group in $responsecategoryfiltersgroups)
{
    #Write-Verbose -Verbose $group
	$row = @{
		DisplayName = "CategoryFilter $($group.name)";
		Identification = @{
			Id = $group.id;
			DisplayName = "CategoryFilter $($group.name)";
			Type = "CategoryFilter";
		}
	};
	Write-Output ($row | ConvertTo-Json -Depth 10)
}
#>

