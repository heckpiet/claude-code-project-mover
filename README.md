# Claude Code Project Mover

A bash script to relocate Claude Code projects when you move a project folder to a new location.

## Why?

Claude Code stores project data in `~/.claude/projects/` using folder names derived from the project path. When you move a project to a different location, Claude Code loses track of it. This script updates the project metadata to match the new path.

## Usage

**Important:** This script only updates Claude Code's metadata. You must move your project folder first, then run this script to update the reference.

1. Move your project folder to the new location
2. Run the script:
   ```bash
   ./claude-project-mover.sh
   ```
3. Select the project and enter the new path
4. The script validates the destination folder exists before proceeding

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
