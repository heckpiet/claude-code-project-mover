# Claude Code Project Mover

Scripts for updating Claude Code project references after moving a project folder to a new path.

- `claude-project-mover.sh` for macOS and Linux
- `claude-project-mover.ps1` for Windows PowerShell and PowerShell 7+

## Why?

Claude Code stores project data below `~/.claude/projects/` using folder names derived from the absolute project path. On Windows, `~/.claude` normally resolves to `%USERPROFILE%\.claude`.

When a project is moved, Claude Code can no longer associate the existing sessions with its new location. These scripts update the stored metadata so the sessions remain available under the new path.

## Important

The scripts update Claude Code's metadata only. Move the actual project folder first, then run the appropriate script.

## PowerShell usage

### Interactive mode

```powershell
.\claude-project-mover.ps1
```

The script lists the detected Claude Code projects, asks for the new path, optionally creates a ZIP backup and requests confirmation before making changes.

If the PowerShell execution policy blocks the script, run it once with:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\claude-project-mover.ps1
```

### Parameter mode

```powershell
.\claude-project-mover.ps1 `
  -ProjectPath 'C:\Users\Jane\Code\OldLocation\demo' `
  -NewPath 'D:\Projects\demo' `
  -Backup `
  -Yes
```

Available parameters:

| Parameter | Description |
| --- | --- |
| `-ProjectPath` | Previous absolute project path. If omitted, an interactive selection is shown. |
| `-NewPath` | New absolute project path. The folder must already exist. |
| `-Backup` | Creates a ZIP backup before changing metadata. |
| `-Yes` | Skips the final confirmation prompt. |
| `-WhatIf` | Shows the intended operation without changing anything. |

The PowerShell version also respects `CLAUDE_CONFIG_DIR` when Claude Code uses a custom configuration directory.

## Bash usage

```bash
chmod +x claude-project-mover.sh
./claude-project-mover.sh
```

If [`fzf`](https://github.com/junegunn/fzf) is installed, project selection switches to a fuzzy finder. Otherwise, a numbered list is displayed.

## What the scripts do

- Detect existing Claude Code project metadata
- Read the original project path from the stored session data
- Validate that the new project folder exists
- Replace old path references in session metadata
- Rename the metadata directory below `.claude/projects`
- Optionally create a compressed backup before making changes

PowerShell backups use ZIP:

```text
BACKUP__C--Users-Jane-Code-demo__20260728_191500.zip
```

Bash backups use `tar.gz`:

```text
BACKUP__-Users-jane-Code-demo__20260728_191500.tar.gz
```

## Requirements

### PowerShell

- Windows PowerShell 5.1 or PowerShell 7+
- Claude Code installed and at least one project below `.claude/projects`

### Bash

- macOS or Linux with Bash
- Claude Code installed and at least one project below `~/.claude/projects`
- Optional: [`fzf`](https://github.com/junegunn/fzf)

## Safety notes

- Close active Claude Code sessions for the project before running the mover.
- Create a backup when moving important session history.
- The destination metadata directory must not already exist.
- The scripts do not move or modify the actual source-code project directory.

## License

MIT
