# Changelog

## Unreleased

## [1.4.0] - 2026-07-30

### Added

- Smart destination-folder suggestions derived from AI titles or first meaningful session content
- Timestamp and shortened session-ID fallback when no meaningful content is available
- Folder status and suggested name in Windows GUI, PowerShell CLI, and Bash project overviews
- Editable prefilled folder name when creating a dedicated target project
- Cross-version automated tests for deterministic, filesystem-safe suggestions

## [1.3.0] - 2026-07-30

### Added

- Detection and guided creation of dedicated target folders for session groups without their own project directory
- Safe folder-name entry in the Windows GUI and PowerShell CLI
- Automation parameters `-CreateProjectFolder` and `-ProjectFolderName`
- Bash compatibility flow for creating dedicated destination project folders

### Changed

- General source folders such as a user profile are no longer physically moved when a dedicated folder is created
- Post-migration validation now confirms the new project folder together with rewritten Claude metadata and `cwd` values
- Documentation now distinguishes normal project moves from folderless session-group migration
- Windows PowerShell 5.1 now preserves array behavior when exactly one Claude project exists

## [1.2.2] - 2026-07-30

### Fixed

- Replaced the interactive CLI warning exception with a short explanation, explicit confirmation, and immediate destination re-entry
- Clarified the difference between the GUI collection folder and the CLI's complete destination project path
- Kept non-interactive validation strict unless `-Force` is explicitly supplied
- Localized destination warnings and preflight summaries for the Windows CLI

## [1.2.1] - 2026-07-30

### Changed

- Clarified Windows 10/11, PowerShell, Windows Forms, and CMD as the primary project focus
- Marked Bash on macOS and Linux as a maintained compatibility variant
- Aligned contribution guidance, issue templates, pull request checks, and Windows documentation with the Windows-first scope
- Made PowerShell CI restore the default PSGallery registration when runner images omit it

## [1.2.0] - 2026-07-30

### Added

- Rich Bash project overview with last-session timestamp, session count, description, and project path
- Bash options for project listing, version output, help, and custom `CLAUDE_CONFIG_DIR`
- CMD options for GUI, CLI, project overview, help, and version output
- Bash syntax validation in GitHub Actions

### Changed

- Version updates and CI consistency checks now cover PowerShell, Bash, CMD, README, and `VERSION`
- Windows starter validates all shared runtime files before launch
- Download documentation now distinguishes GitHub source ZIPs from future release packages

## [1.1.1] - 2026-07-30

### Added

- Read-only `-ListProjects` overview for the non-GUI script
- Rich standalone CLI inventory fallback when the shared module is not present

### Changed

- German interactive CLI project selection with timestamp, session count, description, and full path

## [1.1.0] - 2026-07-30

### Added

- Selectable GUI project overview with last-session timestamp, session count, and best-effort description
- Recent-first project ordering and full path/description tooltips
- README version synchronization in the version helper and CI
- Shared GUI/CLI project inventory module for consistent timestamps and descriptions
- Rich CLI project selection overview with session context and full paths
- UTF-8 BOM policy for correct Windows PowerShell 5.1 localization

### Changed

- Refined Windows layout with clearer hierarchy, responsive spacing, selection count, styled actions, and repository link

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
