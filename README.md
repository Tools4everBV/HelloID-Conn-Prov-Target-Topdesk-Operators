| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Versioning
| Version | Description | Date |
| - | - | - |
| 1.1.0   | Updated to use the Exchange v2 module | 2022/05/09  |
| 1.0.0   | Initial release | 2022/03/28  |

## Table of contents
- [Versioning](#versioning)
- [Table of contents](#table-of-contents)
- [Introduction](#introduction)
- [Getting started](#getting-started)
  - [Connection settings](#connection-settings)
  - [Prerequisites](#prerequisites)
  - [Remarks](#remarks)
- [Getting help](#getting-help)
- [HelloID docs](#helloid-docs)

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