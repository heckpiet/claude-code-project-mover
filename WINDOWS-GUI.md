# Windows GUI guide

The native GUI is the recommended Windows entry point. Start the complete release with `Start-ClaudeProjectMover.cmd`; the starter uses PowerShell 7 when available and Windows PowerShell 5.1 otherwise.

## Language

The GUI supports English and German. `-Language Auto` follows the current Windows UI culture: German cultures receive German, all others English.

```powershell
.\claude-project-mover-gui.ps1 -Language en
.\claude-project-mover-gui.ps1 -Language de
```

The environment variable `CLAUDE_MOVER_LANGUAGE` works with the CMD starter and both scripts.

## Project overview

Projects are sorted by latest session. The table includes validation status, timestamp, session count, folder status, suggested folder, description, source path, discovered session files, transfer type, file count, and size.

Select one or more rows and use **Validate sources** before running a transfer. Blocking errors prevent execution; warnings remain visible for review.

## Destination behavior

Choose a common destination parent. For normal projects, the source folder name is retained. If a session has no dedicated project folder, the GUI proposes a safe name based on its title or first useful message. Name conflicts require an explicit choice.

Available file operations:

- **Move** transfers project files and metadata.
- **Copy** copies project files and transfers metadata.
- **Metadata only** expects the project files to exist at the destination already.

## Recommended options

- **Back up Claude metadata as ZIP** provides a recovery point.
- **Document origin at destination** writes `.claude-project-origin.json`.
- **Preserve session bundle** writes `.claude-session-bundle`.
- **Copy safe session files** includes safe project-relative artifacts found in session activity.

The tool excludes sensitive and machine-bound paths by design.

## Verification and recovery

The GUI checks source readability, project markers, JSONL validity, available space, target contents, copied file hashes, updated `cwd` values, portable bundle contents, and provenance metadata. Metadata changes use a validated staging directory and rollback path.

If a transfer fails, read the displayed error, leave Claude Code closed, and inspect the backup/rollback information. The bundle includes `Restore-ClaudeSession.ps1` for restoring portable session data on another Windows installation.
