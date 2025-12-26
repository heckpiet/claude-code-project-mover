# Claude Code Project Mover

A bash script to relocate Claude Code projects when you move a project folder to a new location.

## Why?

Claude Code stores project data in `~/.claude/projects/` using folder names derived from the project path. When you move a project to a different location, Claude Code loses track of it. This script updates the project metadata to match the new path.

## Usage

```bash
./claude-project-mover.sh
```

The script will:

1. List all your Claude Code projects
2. Let you pick one by number
3. Ask for the new path
4. Optionally create a backup
5. Update all references and rename the folder

## What it does

- Renames the project folder in `~/.claude/projects/`
- Replaces all path references in `.jsonl` session files
- Optionally creates a compressed backup in the same folder:
  ```
  BACKUP__-Users-jdoe-Desktop-myproject__20251225_123130.tar.gz
  ```

## Installation

```bash
chmod +x claude-project-mover.sh
```

## Requirements

- macOS or Linux with Bash
- Claude Code installed (`~/.claude/projects/` must exist)
