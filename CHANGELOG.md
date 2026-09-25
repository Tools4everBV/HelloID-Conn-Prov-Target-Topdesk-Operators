# Change Log

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com), and
this project adheres to [Semantic Versioning](https://semver.org).

## [3.3.1] - 25-09-2026

### Changed
- `Get-TopdeskBranch` in `create.ps1` and `update.ps1` now uses a server-side query (`?query=<LookupField>==<value>`) instead of retrieving all branches and filtering client-side
- Added `LookupField` parameter to `Get-TopdeskBranch`, so the branch can be looked up on a configurable field (default `name`)
- Added error handling when multiple branches match the lookup value

## [3.3.0] - 12-06-2026

### Added
- Import permission scripts
- Permission groups

## [3.2.2] - 20-10-2025

### Added
- Feature: added partner solution id in header

## [3.2.1] - 17-09-2025

### Changed
- Fix: allow empty dynamicname and loginname

## [3.2.0] - 03-09-2025

### Added
- Added reconciliation functionality

## [3.1.0] - 26-05-2025

### Added
- Feature import entitlements

## [3.0.1] - 10-02-2025

## [3.0.0] - 12-07-2024

### Added
- New powershell connector (PSv2)

## [2.0.0] - 14-02-2024

### Added
- Feature: major rework based on topdesk connector

## [1.1.0] - 08-05-2024

### Changed
- Changed $currentMembers to $currentGroupMembers

## [1.0.0] - 25-07-2023

This is the first official.

### Added

### Changed

### Deprecated

### Removed
