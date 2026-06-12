
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
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Remove attributes when updating a TOPdesk operator instead of correlating](#remove-attributes-when-updating-a-topdesk-operator-instead-of-correlating)
    - [Disable department or budgetholder](#disable-department-or-budgetholder)
    - [Managing tasks permissions](#managing-tasks-permissions)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-TOPdesk-Operators_ is a _target_ connector. TOPdesk provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                                                          | Remarks                                                                                                                                  |
| ----------------------------------------- | --------- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete (disable with option to clear data)      |                                                                                                                                          |
| **Permissions**                           | ✅         | Operator groups, permission groups, operator filters, category filters and tasks |                                                                                                                                          |
| **Resources**                             | ❌         | -                                                                                |                                                                                                                                          |
| **Entitlement Import: Accounts**          | ✅         | -                                                                                |                                                                                                                                          |
| **Entitlement Import: Permissions**       | ✅         | -                                                                                |                                                                                                                                          |
| **Governance Reconciliation Resolutions** | ✅         | Revoke, Disable, Delete                                                          | Delete is treated as a disable action with the option to update values. Please adjust the configuration accordingly in the delete script |

> [!NOTE]
> By default all archived operators are also retrieved by the import script(s). To prevent this we provide a example solution to filter by a property. For example `mainframeLoginName = 'Deleted by HelloID'`.

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```txt
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Topdesk-Operators/refs/heads/main/Icon.png
```

### Requirements

- An archiving reason that is configured in TOPdesk.
- Credentials with the rights listed below.

| Permission                | Read  | Write | Create | Delete | Archive |
| ------------------------- | ----- | ----- | ------ | ------ | ------- |
| __Supporting Files__      |       |       |        |        |         |
| Persons                   | __X__ |       |        |        |         |
| Operators                 | __X__ | __X__ | __X__  |        | __X__   |
| Operator groups           | __X__ | __X__ | __X__  |        |         |
| Permission groups         | __X__ | __X__ |        |        |         |
| Filters                   | __X__ | __X__ |        |        |         |
| Login data                |       | __X__ |        |        |         |
| __API access__            |       |       |        |        |         |
| REST API                  | __X__ |       |        |        |         |
| Use application passwords |       | __X__ |        |        |         |

> [!NOTE]
> It is possible to set filters in TOPdesk. If you don't get a result from TOPdesk when expecting one it is probably because filters are used. For example, searching for a branch that can't be found by the API user but is visible in TOPdesk.

### Connection settings

The following settings are required to connect to the API.

| Setting                             | Description                                                                                                              | Mandatory |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | --------- |
| BaseUrl                             | The URL to the API                                                                                                       | Yes       |
| UserName                            | The UserName to connect to the API                                                                                       | Yes       |
| Password                            | The Password to connect to the API                                                                                       | Yes       |
| Archiving reason                    | Fill in an archiving reason that is configured in TOPdesk                                                                | Yes       |
| When no item is found in TOPdesk    | Stop processing and generate an error, or keep the current value and continue if budgetHolder or Department is not found | Yes       |
| When no department in source data   | Stop processing and generate an error, or clear the department field in TOPdesk                                          | Yes       |
| When no budgetholder in source data | Stop processing and generate an error, or clear the budgetholder field in TOPdesk                                        | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _HelloID-Conn-Prov-Target-TOPdesk-Operators_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `employeeNumber`                  |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the [fieldMapping.json](./fieldMapping.json) file.

> [!TIP]
> You can add extra fields by adding them to the account mapping. For all possible options please check the [TOPdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/).

> [!NOTE]
> Starting November 2025, it will be mandatory to link a TOPdesk person to a TOPdesk operator.  
> This is done by setting the `linkedPerson.id` field with the TOPdesk Person ID.  
> You can achieve this by making the TOPdesk Operator target dependent on the TOPdesk Person target, and assigning the Person's TOPdesk account ID to the `linkedPerson.id` field.  
> By default, this mapping is included in the `fieldMapping.json` file.  
> For more information, please refer to the [official documentation](https://docs.topdesk.com/en/step-2--api-changes.html).

### Account Reference

The account reference is populated with the `id` property from TOPdesk operators.

## Remarks

### Remove attributes when updating a TOPdesk operator instead of correlating

In the `update.ps1` script there is an example to set certain attributes only during create/correlate and skip them during updates.

```powershell
if (-not($actionContext.AccountCorrelated -eq $true)) {
    # Example to only set certain attributes when create-correlate.
    # If you don't want to update certain values, remove them here.
    # $account.PSObject.Properties.Remove('email')
    # $account.PSObject.Properties.Remove('networkLoginName')
    # $account.PSObject.Properties.Remove('loginName')
    # $account.PSObject.Properties.Remove('exchangeAccount')
}
```

### Disable department or budgetholder

The fields _department_ and _budgetholder_ are non-required lookup fields in TOPdesk. This means you first need to look up the field and then use the returned GUID (ID) to set the TOPdesk operator.

For example:

```json
"id": "90ee5493-027d-4cda-8b41-8325130040c3",
"name": "EnYoi Holding B.V.",
"externalLinks": []
```

If you don't need the mapping of the department field or the budgetholder field in TOPdesk, you can remove `department.lookupValue` or `budgetHolder.lookupValue` from the field mapping. The create and update script will skip the lookup action.

> [!IMPORTANT]
> The branch lookup value `branch.lookupValue` is still mandatory.

### Managing tasks permissions

> [!IMPORTANT]
> When managing tasks as permissions, we recommend you set concurrent actions to 1 to prevent timing issues. This is necessary because you can't update a task on an archived operator. When revoking account access and a task permission at the same moment, the operator could be left in the wrong state. This is not possible when concurrent actions are set to 1.

## Development resources

### API endpoints

The following endpoints are used by the connector.

| Endpoint                                    | HTTP Method       | Description                                               |
| ------------------------------------------- | ----------------- | --------------------------------------------------------- |
| /tas/api/operators                          | GET, POST, PATCH  | Read and write operators                                  |
| /tas/api/operators/id/{id}/permissiongroups | GET, POST, DELETE | Retrieve, grant and revoke permission groups for operator |
| /tas/api/operators/id/{id}/operatorgroups   | GET, POST, DELETE | Retrieve, grant and revoke operator groups for operator   |
| /tas/api/operators/id/{id}/filters/operator | GET, POST, DELETE | Retrieve, grant and revoke operator filters for operator  |
| /tas/api/operators/id/{id}/filters/category | GET, POST, DELETE | Retrieve, grant and revoke category filters for operator  |
| /tas/api/operators/id/{id}/tasks            | GET, POST, DELETE | Retrieve, grant and revoke tasks for operator             |
| /tas/api/branches                           | GET               | Retrieve branches for operator updates                    |
| /tas/api/departments                        | GET               | Retrieve departments for operator updates                 |
| /tas/api/budgetholders                      | GET               | Retrieve budgetholders for operator updates               |
| /tas/api/archiving-reasons                  | GET               | Retrieve archiving reasons for operator archive flow      |

### API documentation

- [TOPdesk API Explorer](https://developers.topdesk.com/explorer/?page=supporting-files#/)

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

