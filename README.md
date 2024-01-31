# HelloID-Conn-Prov-Target-Topdesk-Operators

| :warning: Warning |
| :---------------- |
| This readme is not updated. This will be done in combination with the import/export file for powershell V2 |

| :warning: Warning |
| :---------------- |
| This script is for the new powershell connector. Make sure to use the mapping and correlation keys like mentionded in this readme. For more information, please read our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) |

| :information_source: Information |
|:-|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |
<br />
<p align="center"> 
  <img src="https://www.tools4ever.nl/connector-logos/topdesk-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Topdesk-Operators](#helloid-conn-prov-target-topdesk-operators)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Permissions](#permissions)
      - [Filters](#filters)
  - [Setup the connector](#setup-the-connector)
    - [Remove attributes when correlating a Topdesk person](#remove-attributes-when-correlating-a-topdesk-person)
    - [Disable department or budgetholder](#disable-department-or-budgetholder)
    - [Extra fields](#extra-fields)
  - [Remarks](#remarks)
    - [Managing operator groups](#managing-operator-groups)
    - [Use Topdesk person as input](#use-topdesk-person-as-input)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

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

If you don't need the mapping of the department field or the budgetholder field in Topdesk, you can remove them from the field mapping. The create and update script will skip the lookup action. The branch lookup value is still mandatory.


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
