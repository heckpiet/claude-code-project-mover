# Claude Code Project Mover

A small utility for updating Claude Code project references after moving a project folder to a new path.

This fork adds a native **PowerShell 7** implementation for Windows, macOS, and Linux while retaining the original Bash version.

## Why?

Claude Code stores project data below `~/.claude/projects/` using directory names derived from the absolute project path. After moving a source project, Claude Code can no longer associate its stored sessions with the new location.

The mover updates the stored path references and renames the corresponding Claude Code metadata directory.

> The tool only updates Claude Code metadata. Move the actual project directory first.

## PowerShell usage

### Requirements

- PowerShell 7 or newer
- Claude Code installed
- At least one project below `~/.claude/projects/`
- Optional `fzf` for fuzzy project selection

### Interactive mode

```powershell
pwsh ./claude-project-mover.ps1
```

The script will:

1. discover Claude Code projects
2. read the real project path from the `cwd` field in JSONL session files
3. let you select a project
4. validate the new project directory
5. create a ZIP backup by default
6. replace old path references
7. rename the Claude Code metadata directory

### Parameter mode

```powershell
pwsh ./claude-project-mover.ps1 `
  -OldPath 'C:\Development\old-location\my-project' `
  -NewPath 'D:\Projects\my-project'
```

Skip the backup:

```powershell
pwsh ./claude-project-mover.ps1 `
  -OldPath 'C:\Development\old-location\my-project' `
  -NewPath 'D:\Projects\my-project' `
  -NoBackup
```

Non-interactive execution:

```powershell
pwsh ./claude-project-mover.ps1 `
  -OldPath 'C:\Development\old-location\my-project' `
  -NewPath 'D:\Projects\my-project' `
  -Force `
  -Confirm:$false
```

Preview the operation without changing files:

```powershell
pwsh ./claude-project-mover.ps1 `
  -OldPath 'C:\Development\old-location\my-project' `
  -NewPath 'D:\Projects\my-project' `
  -WhatIf
```

## Bash usage

The original implementation remains available:

```bash
chmod +x claude-project-mover.sh
./claude-project-mover.sh
```

## Backups

The PowerShell version creates ZIP backups in `~/.claude/projects/`:

```text
BACKUP__C--Users-Martin-project__20260728_193000.zip
```

The Bash version creates `.tar.gz` backups.

## Safety notes

- Close active Claude Code sessions for the affected project before running the mover.
- Move the actual project folder before updating Claude Code metadata.
- Keep the generated backup until the project and previous sessions open correctly.
- The destination metadata entry must not already exist.

## License

MIT. The original copyright and license notice are retained.
