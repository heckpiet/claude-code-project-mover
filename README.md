# Claude Code Project Mover

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](#platform-support)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell validation](https://github.com/heckpiet/claude-code-project-mover/actions/workflows/powershell.yml/badge.svg)](https://github.com/heckpiet/claude-code-project-mover/actions/workflows/powershell.yml)

Safely update Claude Code project references after moving a project folder to a new path.

This fork keeps the original Bash implementation for macOS and Linux and adds a native, safety-focused PowerShell implementation for Windows.

- `claude-project-mover.sh` — original Bash workflow for macOS and Linux
- `claude-project-mover.ps1` — extended implementation for Windows PowerShell 5.1 and PowerShell 7+

> The scripts update Claude Code metadata only. Move the actual project folder first and close active Claude Code sessions for that project before running the mover.

## Why this tool exists

Claude Code stores project data in `~/.claude/projects/` using folder names derived from the absolute project path. On Windows, `~/.claude` normally resolves to `%USERPROFILE%\.claude`.

When a project is moved, Claude Code can no longer associate the existing sessions with its new location. The mover updates the stored references and renames the matching metadata directory so that Claude Code can continue using the existing project history.

## Platform support

| Platform | Script | Status |
| --- | --- | --- |
| Windows | `claude-project-mover.ps1` | Native PowerShell support with preflight, backup and rollback |
| macOS | `claude-project-mover.sh` | Original Bash implementation |
| Linux | `claude-project-mover.sh` | Original Bash implementation |

## PowerShell safety features

The PowerShell edition adds safeguards around the original workflow.

- Detects the Claude Code configuration directory and respects `CLAUDE_CONFIG_DIR`
- Reads the original path from existing JSONL session records
- Checks that the destination project exists and is readable
- Inventories destination files and common project markers
- Validates JSON and JSONL metadata before making changes
- Confirms that sessions reference the expected old path
- Checks free space on the destination project volume
- Checks free space for the metadata staging copy and optional ZIP backup
- Supports a non-destructive `-CheckOnly` preflight
- Updates normal, JSON-escaped and forward-slash Windows path variants
- Performs changes in a staging copy instead of modifying live metadata directly
- Validates the updated sessions before activation
- Uses a rollback directory during the final metadata swap
- Supports `-WhatIf`, confirmation prompts and unattended execution

## Quick start on Windows

### 1. Move the project folder

Move the real project directory to its new location using Explorer, Git or your preferred file-management tool.

### 2. Close Claude Code

Close active Claude Code sessions that use the project. This avoids concurrent writes while metadata is being migrated.

### 3. Run a preflight check

```powershell
.\claude-project-mover.ps1 `
  -ProjectPath 'C:\Users\Jane\Code\OldLocation\demo' `
  -NewPath 'D:\Projects\demo' `
  -CheckOnly
```

### 4. Run the migration

Interactive mode:

```powershell
.\claude-project-mover.ps1
```

Parameter mode:

```powershell
.\claude-project-mover.ps1 `
  -ProjectPath 'C:\Users\Jane\Code\OldLocation\demo' `
  -NewPath 'D:\Projects\demo' `
  -Backup `
  -Yes
```

The recommended sequence is `-CheckOnly` first and a migration with `-Backup` afterwards.

## PowerShell parameters

| Parameter | Description |
| --- | --- |
| `-ProjectPath` | Previous absolute project path. If omitted, an interactive selection is shown. |
| `-NewPath` | New absolute project path. The folder must already exist. |
| `-Backup` | Creates a ZIP backup before changing metadata. |
| `-Yes` | Skips confirmation prompts. |
| `-CheckOnly` | Runs project, metadata and free-space checks without changing anything. |
| `-MinimumFreeSpaceGB` | Minimum required free space on the destination volume. Default is `1`. |
| `-SkipSpaceCheck` | Skips free-space checks when the volume cannot be queried, such as some UNC shares. |
| `-Force` | Continues past non-critical destination-content warnings. |
| `-WhatIf` | Displays the intended operation without changing metadata. |

### Execution policy

When Windows PowerShell blocks locally downloaded scripts, use a process-scoped bypass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude-project-mover.ps1
```

This does not permanently change the machine-wide execution policy.

## What is validated

### Destination project

The PowerShell script verifies that the new directory exists, can be enumerated and contains project data. It also looks for common project markers such as `.git`, `CLAUDE.md`, `.claude`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, solution files and project files.

A project does not need every marker. They are indicators used to detect accidental selection of an empty or unrelated destination directory.

### Claude Code metadata

The script checks that:

- at least one `.jsonl` session file exists
- at least one valid JSONL record can be parsed
- JSON and JSONL records are not malformed
- at least one stored `cwd` value matches the old project path
- updated metadata contains the new project path
- the number of invalid records does not increase during migration

All files and subdirectories inside the Claude Code project metadata directory are copied to the staging area. The script only edits `.json` and `.jsonl` path references.

### Free space

Two volumes can be checked:

1. The volume containing the moved project must retain configurable free-space headroom. The default minimum is 1 GB, or more for large projects.
2. The volume containing `.claude/projects` must have enough room for the staging copy, operational headroom and the optional ZIP backup.

The tool does not copy the real project folder. The destination check is therefore a safety and continuity check rather than a file-copy capacity calculation.

## Transactional migration flow

The PowerShell edition avoids editing the active metadata directory in place.

1. Validate destination project and existing Claude metadata
2. Check available disk space
3. Optionally create a ZIP backup
4. Copy all metadata into a temporary staging directory
5. Replace path references in the staging copy
6. Parse and validate the updated JSON and JSONL records
7. Rename the original metadata directory to a rollback name
8. Activate the validated staging directory under the new Claude project name
9. Validate the active result and remove the rollback copy

If activation fails, the script attempts to restore the original metadata directory automatically.

## Backup format

PowerShell backups use ZIP:

```text
BACKUP__C--Users-Jane-Code-demo__20260728_191500.zip
```

The original Bash implementation uses `tar.gz`:

```text
BACKUP__-Users-jane-Code-demo__20251225_123130.tar.gz
```

## Bash usage — original implementation

The original project provides a Bash script for macOS and Linux.

```bash
chmod +x claude-project-mover.sh
./claude-project-mover.sh
```

The original workflow is:

1. Move the project folder to the new location
2. Run `./claude-project-mover.sh`
3. Select the project and enter the new path
4. Let the script verify that the destination folder exists
5. Optionally create a compressed backup
6. Update stored path references and rename the metadata folder

If [`fzf`](https://github.com/junegunn/fzf) is installed, project selection switches to a fuzzy finder. Otherwise, the script displays a numbered list.

## Requirements

### PowerShell

- Windows PowerShell 5.1 or PowerShell 7+
- Claude Code installed
- At least one project below `.claude/projects`
- Read/write access to the Claude Code configuration directory

### Bash

- macOS or Linux with Bash
- Claude Code installed and `~/.claude/projects/` available
- Optional `fzf` for fuzzy project selection

## Known limitations

- The scripts rely on Claude Code's current project-directory naming and metadata layout, which may change in future Claude Code releases.
- Free-space detection for UNC paths is not consistently available through .NET. Check network-share capacity manually and use `-SkipSpaceCheck` only when necessary.
- The PowerShell script validates Claude Code metadata structures it can observe, but it cannot guarantee compatibility with undocumented future metadata fields.
- An end-to-end test should use a disposable project before migrating irreplaceable session history.

## Project structure

```text
.
├── .github/workflows/powershell.yml
├── claude-project-mover.ps1
├── claude-project-mover.sh
├── CONTRIBUTING.md
├── LICENSE
├── README.md
└── SECURITY.md
```

## Original project and attribution

This repository is a fork of [`skydiver/claude-code-project-mover`](https://github.com/skydiver/claude-code-project-mover).

The original project by Martin introduced the Bash-based approach for repairing Claude Code project references after a folder move. That implementation, its usage information and its MIT license are retained in this fork. The PowerShell edition and the additional validation, disk-space and transactional safety features are extensions maintained here.

## Contributing

Bug reports and pull requests are welcome. Please include the operating system, PowerShell version, Claude Code version when known, the old and new path format and sanitized diagnostic output.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and validation guidance.

## Security

Do not attach private Claude Code session files to public issues. They can contain local paths, prompts, tool output and project information. See [SECURITY.md](SECURITY.md) for responsible reporting guidance.

## License

MIT. The original copyright and permission notice remain in [LICENSE](LICENSE).
