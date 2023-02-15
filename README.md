# HelloID-Conn-Prov-Target-Topdesk-Operators

# HelloID-Conn-Prov-Target-Topdesk

| :warning: Warning |
|:-|
| This connector has been updated to a new version (V2), not officaly released. This version is not backward compatible, but a Tools4ever consultant or a partner can upgrade the connector with minor effort. If you have questions please ask them on our (new forum post needed for operator connector?) [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1266-helloid-conn-prov-target-topdesk). |

| :information_source: Information |
|:-|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://user-images.githubusercontent.com/69046642/169818554-fb19427a-5b47-43a4-9208-f412376e1cbb.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Prerequisites](#Prerequisites)
  + [Connection settings](#Connection-settings)
  + [Permissions](#Permissions)
- [Setup the connector](#Setup-The-Connector)
  + [Remove attributes when correlating a Topdesk person](#Remove-attributes-when-correlating-a-Topdesk-person)
  + [Disable department or budgetholder](#Disable-department-or-budgetholder)
  + [Extra fields](#Extra-fields)
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

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1266-helloid-conn-prov-target-topdesk)_

## HelloID docs

> The official HelloID documentation can be found at: https://docs.helloid.com/


| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |



## Introduction
_HelloID-Conn-Prov-Target-Topdesk-Operators is a _target_ connector. TOPdesk provides a set of REST API's that allow you to programmatically interact with it's data. The HelloID connector allows you to create and manage TOPdesk operators. Using entitlements it is possible to add operators to operator groups.
The HelloID connector consists of the template scripts shown in the following table.

| Action                          | Action(s) Performed                           | Comment   | 
| ------------------------------- | --------------------------------------------- | --------- |
| Create.ps1                      | Correlate or create TOPdesk operator          | This script uses the HR source data as input for the operator.<br> When no TOPdesk branch is found, the script will result in an error. So when using this script, __mapping the branch & having the TOPdesk branches match the source input is required__. |
| Create.personData.ps1           | Correlate or create TOPdesk operator          | This script uses the TOPdesk person data as input for the operator. When no TOPdesk person is found, the script will result in an error. So when using this script, a __TOPdesk person is required__. |
| Update.ps1                      | Update TOPdesk operator                       | This script uses the HR source data as input for the operator.<br> When no TOPdesk branch is found, the script will result in an error. So when using this script, __mapping the branch & having the TOPdesk branches match the source input is required__. |
| Update.personData.ps1           | Update TOPdesk operator                       | This script uses the TOPdesk person data as input for the operator. When no TOPdesk person is found, the script will result in an error. So when using this script, a __TOPdesk person is required__. |
| Enable.ps1                      | Unarchive TOPdesk operator                    |           |
| Disable.ps1                     | Archive TOPdesk operator                      | To archive a TOPdesk operator, the archiving reason is required. When no archiving reason is specified, the script will result in an error. So when using this script, an __archiving reason is required__.   |
| Delete.ps1                      | Clear loginnames and archive TOPdesk operator | The TOPdesk API does not support a delete, however, the loginnames are required to be unique in TOPdesk, therefore we clean these.<br> To archive a TOPdesk operator, the archiving reason is required. When no archiving reason is specified, the script will result in an error. So when using this script, an __archiving reason is required__.   |
| permissions.operatorGroups.ps1  | Query the operator groups in TOPdesk          |           |
| grant.operatorGroup.ps1         | Grant an operator group to an operator        |           |
| revoke.operatorGroup.ps1        | Grant an operator group to an operator        |           |


## Getting started
### Connection settings
The following settings are required to connect to the API.

| Setting               | Description                                                       | Mandatory   |
| --------------------- | ----------------------------------------------------------------- | ----------- |
| URL                   | The URL to the TOPdesk environment                                | Yes         |
| Username              | The username of the operator to connect to the API                | Yes         |
| Application password  | The application password for the operator to connect to the API.<br> For more information on how to create this, please see the [TOPdesk documentation](https://developers.topdesk.com/tutorial.html#show-collapse-usage-createAppPassword).    | Yes         |
| Operator archiving reason  | The default archiving reason, for example: Persoon uit organisatie   | Yes         |
| When an item can't be found in TOPdesk  | What to do when the mapping is provided (from source data) but no matching item in TOPdesk can be found. Choose to either: <ul><li>generate an error and stop processing</li><li>or do not set/update field in TOPdesk</li></ul>   | Yes         |
| When a department is empty because it's missing in the source data  | What to do when the department is mising in the mapping beause it is missing in source data. Choose to either: <ul><li>generate an error and stop processing</li><li>or do not set/update the department field in TOPdesk</li></ul> | Yes         |
| When a budgetholder is empty because it's missing in the source data  | What to do when the department is mising in the mapping beause it is missing in source data. Choose to either: <ul><li> generate an error and stop processing</li><li>or do not set/update the budgetholder field in TOPdesk</li></ul>  | Yes         |

### Prerequisites
- TOPdesk environment of at least version 7.11.005
- TOPdesk operator account with permissions as in the table below:

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

### Remarks
 - Currently, we only support managing operator groups (no permission groups etc.).

## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
