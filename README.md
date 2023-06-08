# HelloID-Conn-Prov-Target-Topdesk-Operators

| :warning: Warning |
|:-|
| This connector has been updated to a new version (V2), not officaly released. This version is not backward compatible, but a Tools4ever consultant or a partner can upgrade the connector with minor effort. If you have questions please ask them on our (new forum post needed for operator connector?) [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1266-helloid-conn-prov-target-topdesk). |

| :information_source: Information |
|:-|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |
<br />
<p align="center"> 
  <img src="https://www.tools4ever.nl/connector-logos/topdesk-logo.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Prerequisites](#Prerequisites)
  + [Connection settings](#Connection-settings)
  + [Permissions](#Permissions)
  + [Filters](#Filters)
- [Setup the connector](#Setup-The-Connector)
  + [Remove attributes when correlating a Topdesk person](#Remove-attributes-when-correlating-a-Topdesk-person)
  + [Disable department or budgetholder](#Disable-department-or-budgetholder)
  + [Extra fields](#Extra-fields)
- [Remarks](#Remarks)
  + [Managing operator groups](#Managing-operator-groups)
  + [Use Topdesk person as input](#Use-Topdesk-person-as-input)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-Topdesk-Operator_ is a _target_ connector. Topdesk provides a set of REST APIs that allow you to programmatically interact with its data. The [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/) provides details of API commands that are used.

## Getting started
### Prerequisites

  - Archiving reason that is configured in Topdesk
  - Credentials with the rights as described in permissions

### Connection settings

The following settings are required to connect to the API.

| Setting |Description | Mandatory 
| - | - | - 
| BaseUrl | The URL to the API | Yes 
| UserName| The UserName to connect to the API | Yes 
| Password | The Password to connect to the API | Yes 
| Archiving reason | Fill in an archiving reason that is configured in Topdesk | Yes 
| Toggle debug logging | Creates extra logging for debug purposes | Yes
| When no item is found in Topdesk | Stop processing and generate an error or keep the current value and continue. For example, when no budgetholder or department is found in Topdesk. | Yes
| When no department in source data | Stop processing and generate an error or clear the department field in Topdesk | Yes
| When no budgetholder in source data | Stop processing and generate an error or clear the budgetholder field in Topdesk |  Yes

### Permissions
[HelloID-Conn-Prov-Target-Topdesk](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Topdesk).

TOPdesk operator account with permissions as in the table below:

| Permission                | Read  | Write | Create    | Delete    | Archive   |
| ------------------------- | ----- | ----- | --------- | --------- | --------- |
| __Supporting Files__      |
| Persons                   | __X__ |       |           |           |           |
| Operators                 | __X__ | __X__ | __X__     |           | __X__     |
| Operator groups           | __X__ | __X__ | __X__     |           |           |
| Permission groups         | __X__ |       |           |           |           |
| Login data                |       | __X__ |           |           |           |
| __API access__            |
| REST API                  | __X__ |       |           |           |           |
| Use application passwords |       | __X__ |           |           |           |

#### Filters
| :information_source: Information |
|:-|
It is possible to set filters in Topdesk. If you don't get a result from Topdesk when expecting one it is probably because filters are used. For example, searching for a branch that can't be found by the API user but is visible in Topdesk. |

## Setup the connector

### Remove attributes when correlating a Topdesk person
There is an example of only set certain attributes when creating a person, but skipping them when updating the script.

```powershell
  if ([string]::IsNullOrEmpty($TopdeskOperator)) {
      $action = 'Create'
      $actionType = 'created'
  } else {
      $action = 'Correlate'
      $actionType = 'correlated'
      
      # Example to only set certain attributes when creating a person, but skip them when updating
      # $account.PSObject.Properties.Remove('loginPermission')

  }
```

### Disable department or budgetholder

The fields department and budgetholder are both non-required lookup fields in Topdesk. This means you first need to look up the field and then use the returned GUID (ID) to set the Topdesk person. 

For example:


```JSON
"id": "90ee5493-027d-4cda-8b41-8325130040c3",
"name": "EnYoi Holding B.V.",
"externalLinks": []
```

If you don't need the mapping of the department field or the budgetholder field in Topdesk, it's necessary to comment out both mapping and the call function in the script.

Example for the department field:

Mapping:

```powershell
# department          = @{ lookupValue = $p.PrimaryContract.Department.DisplayName }
```

Call function:

```powershell
# Resolve department id
# $splatParamsDepartment = @{
#     Account                   = [ref]$account
#     AuditLogs                 = [ref]$auditLogs
#     Headers                   = $authHeaders
#     BaseUrl                   = $config.baseUrl
#     LookupErrorHrDepartment   = $config.lookupErrorHrDepartment
#     LookupErrorTopdesk        = $config.lookupErrorTopdesk
# }
# Get-TopdeskDepartment @splatParamsDepartment
```

### Extra fields
You can add extra fields by adding them to the account mapping. For all possible options please check the [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/).

Example for mobileNumber:

```powershell
# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
# https://developers.topdesk.com/explorer/?page=supporting-files#/Operators/createOperator
$account = [PSCustomObject]@{
    # other mapping fields are here
    mobileNumber        = $p.Contact.Business.Phone.Mobile
}
```
## Remarks
### Managing operator groups
Currently, we only support managing operator groups (no permission groups etc.).

### Use Topdesk person as input
Use create.personData.ps1 and update.personData.ps1 if you want to use a Topdesk person as input to create or update Topdesk operators.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1266-helloid-conn-prov-target-topdesk)_

## HelloID docs

> The official HelloID documentation can be found at: https://docs.helloid.com/
