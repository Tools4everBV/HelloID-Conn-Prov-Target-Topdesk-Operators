
# HelloID-Conn-Prov-Target-Topdesk-Operators

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
    <img src="./Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Topdesk-Operators](#helloid-conn-prov-target-topdesk-operators)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
  - [Setup the connector](#setup-the-connector)
    - [Remove attributes when updating a Topdesk operator instead of corelating](#remove-attributes-when-updating-a-topdesk-operator-instead-of-corelating)
    - [Disable department or budgetholder](#disable-department-or-budgetholder)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Topdesk-Operator_ is a _target_ connector. Topdesk provides a set of REST APIs that allow you to programmatically interact with its data. The [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/) provides details of API commands that are used.

| Endpoint                   | Description                                                  |
| -------------------------- | ------------------------------------------------------------ |
| /tas/api/operators         | `GET / POST / PATCH` actions to read and write the operators |
| /tas/api/branches          | `GET` braches to use in `PUT / PATCH` to operators           |
| /tas/api/departments       | `GET` departments to use in `PUT / PATCH` to operators       |
| /tas/api/budgetholders     | `GET` budgetholders to use in `PUT / PATCH` to operators     |
| /tas/api/archiving-reasons | `GET` archiving-reasons to archive operators                 |

The following lifecycle actions are available:

| Action                         | Description                                                                |
| ------------------------------ | -------------------------------------------------------------------------- |
| create.ps1                     | PowerShell _create_ or _correlate_ lifecycle action                        |
| delete.ps1                     | PowerShell _delete_ lifecycle action (empty configured values and archive) |
| disable.ps1                    | PowerShell _disable_ lifecycle action                                      |
| enable.ps1                     | PowerShell _enable_ lifecycle action                                       |
| update.ps1                     | PowerShell _update_ lifecycle action                                       |
| grant.operatorGroup.ps1        | PowerShell _grant_ operator group lifecycle action                         |
| revoke.operatorGroup.ps1       | PowerShell _revoke_ operator group lifecycle action                        |
| permissions.operatorGroups.ps1 | PowerShell _permissions_ get operator groups lifecycle action              |
| grant.categoryFilter.ps1       | PowerShell _grant_ category filters lifecycle action                       |
| revoke.categoryFilter.ps1      | PowerShell _revoke_ category filters lifecycle action                      |
| permissions.categoryFilter.ps1 | PowerShell _permissions_ get category filters lifecycle action             |
| grant.operatorFilter.ps1       | PowerShell _grant_ operator filters lifecycle action                       |
| revoke.operatorFilter.ps1      | PowerShell _revoke_ operator filters lifecycle action                      |
| permissions.operatorFilter.ps1 | PowerShell _permissions_ get operator filters lifecycle action             |
| grant.task.ps1                 | PowerShell _grant_ task lifecycle action                                   |
| revoke.task.ps1                | PowerShell _revoke_ task lifecycle action                                  |
| permissions.task.ps1           | PowerShell _permissions_ with static list of tasks                         |
| configuration.json             | Default _configuration.json_                                               |
| fieldMapping.json              | Default _fieldMapping.json_                                                |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _HelloID-Conn-Prov-Target-Topdesk-Operators_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value            |
    | ------------------------- | ---------------- |
    | Enable correlation        | `True`           |
    | Person correlation field  | ``               |
    | Account correlation field | `employeeNumber` |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the [_fieldMapping.json_](./fieldMapping.json) file.

> [!TIP]
> You can add extra fields by adding them to the account mapping. For all possible options please check the [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/)


### Connection settings

The following settings are required to connect to the API.

| Setting                             | Description                                                                                                             | Mandatory |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | --------- |
| BaseUrl                             | The URL to the API                                                                                                      | Yes       |
| UserName                            | The UserName to connect to the API                                                                                      | Yes       |
| Password                            | The Password to connect to the API                                                                                      | Yes       |
| Archiving reason                    | Fill in an archiving reason that is configured in Topdesk                                                               | Yes       |
| When no item is found in Topdesk    | Stop processing and generate an error or keep the current value and continue if budgetHolder or Department is not found | Yes       |
| When no department in source data   | Stop processing and generate an error or clear the department field in Topdesk                                          | Yes       |
| When no budgetholder in source data | Stop processing and generate an error or clear the budgetholder field in Topdesk                                        | Yes       |
| Toggle debug logging                | Creates extra logging for debug purposes                                                                                |

### Prerequisites
a archiving reason that is configured in Topdesk
Credentials with the rights listed below. 

| Permission                | Read  | Write | Create | Delete | Archive |
| ------------------------- | ----- | ----- | ------ | ------ | ------- |
| __Supporting Files__      |
| Persons                   | __X__ |       |        |        |         |
| Operators                 | __X__ | __X__ | __X__  |        | __X__   |
| Operator groups           | __X__ | __X__ | __X__  |        |         |
| Permission groups         | __X__ |       |        |        |         |
| Filters                   | __X__ | __X__ |        |        |         |
| Login data                |       | __X__ |        |        |         |
| __API access__            |
| REST API                  | __X__ |       |        |        |         |
| Use application passwords |       | __X__ |        |        |         |

> [!NOTE]
> It is possible to set filters in Topdesk. If you don't get a result from Topdesk when expecting one it is probably because filters are used. For example, searching for a branch that can't be found by the API user but is visible in Topdesk.


### Remarks

## Setup the connector

### Remove attributes when updating a Topdesk operator instead of corelating
In the `update.ps1` script. There is an example of only set certain attributes when corelating a operator, but skipping them when updating them.

```powershell
    if (-not($actionContext.AccountCorrelated -eq $true)) {
        # Example to only set certain attributes when create-correlate. If you don't want to update certain values, you need to remove them here.    
        # $account.PSObject.Properties.Remove('email')
        # $account.PSObject.Properties.Remove('networkLoginName')
        # $account.PSObject.Properties.Remove('loginName')
        # $account.PSObject.Properties.Remove('exchangeAccount')
    }
```

### Disable department or budgetholder

The fields _department_ and _budgetholder_ are both non-required lookup fields in Topdesk. This means you first need to look up the field and then use the returned GUID (ID) to set the Topdesk operator. 

For example:


```JSON
"id": "90ee5493-027d-4cda-8b41-8325130040c3",
"name": "EnYoi Holding B.V.",
"externalLinks": []
```

If you don't need the mapping of the department field or the budgetholder field in Topdesk, you can remove `department.lookupValue` or `budgetHolder.lookupValue` from the field mapping. The create and update script will skip the lookup action. 

> [!IMPORTANT]
> The branch lookup value `branch.lookupValue` is still mandatory.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1266-helloid-conn-prov-target-topdesk)._

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

