
# HelloID-Conn-Prov-Target-TOPdesk-Operators

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
    <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Topdesk-Operators/blob/main/Logo.png?raw=true">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-TOPdesk-Operators](#helloid-conn-prov-target-topdesk-operators)
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
    - [Remove attributes when updating a TOPdesk operator instead of corelating](#remove-attributes-when-updating-a-topdesk-operator-instead-of-corelating)
    - [Disable department or budgetholder](#disable-department-or-budgetholder)
    - [Managing tasks permissions](#managing-tasks-permissions)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

Supported features:
| Feature                             | Supported | Actions                                                                     | Remarks |
| ----------------------------------- | --------- | --------------------------------------------------------------------------- | ------- |
| **Account Lifecycle**               | ✅         | Create, Update, Enable, Disable, Delete (disable with option to clear data) |         |
| **Permissions**                     | ✅         | Operator groups, operator filters, category filters and tasks               |         |
| **Resources**                       | ❌         | -                                                                           |         |
| **Entitlement Import: Accounts**    | ✅         | -                                                                           |         |
| **Entitlement Import: Permissions** | ❌         | -                                                                           |         |

_HelloID-Conn-Prov-Target-TOPdesk-Operator_ is a _target_ connector. TOPdesk provides a set of REST APIs that allow you to programmatically interact with its data. The [TOPdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/) provides details of API commands that are used.

| Endpoint                   | Description                                                  |
| -------------------------- | ------------------------------------------------------------ |
| /tas/api/operators         | `GET / POST / PATCH` actions to read and write the operators |
| /tas/api/branches          | `GET` braches to use in `PUT / PATCH` to operators           |
| /tas/api/departments       | `GET` departments to use in `PUT / PATCH` to operators       |
| /tas/api/budgetholders     | `GET` budgetholders to use in `PUT / PATCH` to operators     |
| /tas/api/archiving-reasons | `GET` archiving-reasons to archive operators                 |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _HelloID-Conn-Prov-Target-TOPdesk-Operators_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | `PersonContext.Person.ExternalId` |
    | Account correlation field | `employeeNumber`                  |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the [_fieldMapping.json_](./fieldMapping.json) file.

> [!TIP]
> You can add extra fields by adding them to the account mapping. For all possible options please check the [TOPdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/)

> [!NOTE]
> Starting November 2025, it will be mandatory to link a TOPdesk person to a TOPdesk operator.  
> This is done by setting the `linkedPerson.id` field with the TOPdesk Person ID.  
> You can achieve this by making the TOPdesk Operator target dependent on the TOPdesk Person target, and assigning the Person’s TOPdesk account ID to the `linkedPerson.id` field.  
> By default, this mapping is included in the `fieldMapping.json` file.  
> For more information, please refer to the [official documentation](https://docs.topdesk.com/en/step-2--api-changes.html).

### Connection settings

The following settings are required to connect to the API.

| Setting                             | Description                                                                                                             | Mandatory |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | --------- |
| BaseUrl                             | The URL to the API                                                                                                      | Yes       |
| UserName                            | The UserName to connect to the API                                                                                      | Yes       |
| Password                            | The Password to connect to the API                                                                                      | Yes       |
| Archiving reason                    | Fill in an archiving reason that is configured in TOPdesk                                                               | Yes       |
| When no item is found in TOPdesk    | Stop processing and generate an error or keep the current value and continue if budgetHolder or Department is not found | Yes       |
| When no department in source data   | Stop processing and generate an error or clear the department field in TOPdesk                                          | Yes       |
| When no budgetholder in source data | Stop processing and generate an error or clear the budgetholder field in TOPdesk                                        | Yes       |

### Prerequisites
a archiving reason that is configured in TOPdesk
Credentials with the rights listed below. 

| Permission                | Read  | Write | Create | Delete | Archive |
| ------------------------- | ----- | ----- | ------ | ------ | ------- |
| __Supporting Files__      |
| Persons                   | __X__ |       |        |        |         |
| Operators                 | __X__ | __X__ | __X__  |        | __X__   |
| Operator groups           | __X__ | __X__ | __X__  |        |         |
| Permission groups         | __X__ | __X__ |        |        |         |
| Filters                   | __X__ | __X__ |        |        |         |
| Login data                |       | __X__ |        |        |         |
| __API access__            |
| REST API                  | __X__ |       |        |        |         |
| Use application passwords |       | __X__ |        |        |         |

> [!NOTE]
> It is possible to set filters in TOPdesk. If you don't get a result from TOPdesk when expecting one it is probably because filters are used. For example, searching for a branch that can't be found by the API user but is visible in TOPdesk.


### Remarks

## Setup the connector

### Remove attributes when updating a TOPdesk operator instead of corelating
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

The fields _department_ and _budgetholder_ are both non-required lookup fields in TOPdesk. This means you first need to look up the field and then use the returned GUID (ID) to set the TOPdesk operator. 

For example:


```JSON
"id": "90ee5493-027d-4cda-8b41-8325130040c3",
"name": "EnYoi Holding B.V.",
"externalLinks": []
```

If you don't need the mapping of the department field or the budgetholder field in TOPdesk, you can remove `department.lookupValue` or `budgetHolder.lookupValue` from the field mapping. The create and update script will skip the lookup action. 

> [!IMPORTANT]
> The branch lookup value `branch.lookupValue` is still mandatory.

### Managing tasks permissions
> [!IMPORTANT]
> When managing tasks as permissions, we recommend you set concurrent actions to 1 to prevent timing issues. This is necessary because you can't update a task on an archived operator. When revoking the account access and the task permission at the same moment the operator could be left in the wrong state. This is not possible when concurrent actions are set to 1.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1266-helloid-conn-prov-target-topdesk)._

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

