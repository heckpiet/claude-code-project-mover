# Changelog

## Unreleased

## [1.0.0] - 2026-07-30

### Added

- Versioned startup header with purpose, author, project URL, and script version
- Semantic Versioning policy backed by the central `VERSION` file
- Version increment helper for synchronized MAJOR, MINOR, and PATCH updates
- CI validation for version format and consistency
- Read-only `-ListSessions` mode for recent Claude Code sessions
- Local date/time, project path, session ID, and best-effort session descriptions
- `-LastSessions` option for controlling the number of displayed sessions
- Native Windows Forms interface for selecting one or multiple Claude Code projects
- Native destination-folder picker
- Optional physical movement of project directories
- Batch free-space calculation and collision checks
- Per-project metadata migration through the hardened PowerShell engine
- Windows GUI usage documentation
- Pull request and GUI bug-report templates

### Changed

- PowerShell CI now parses and analyzes every top-level `.ps1` entry point
