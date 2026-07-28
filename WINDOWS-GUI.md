# Native Windows interface

`claude-project-mover-gui.ps1` provides a Windows Forms interface for moving one or more Claude Code projects.

## Start

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\claude-project-mover-gui.ps1
```

The interface reads the available projects from the Claude Code session metadata below `%USERPROFILE%\.claude\projects` or from `CLAUDE_CONFIG_DIR` when that environment variable is configured.

## Workflow

1. Close active Claude Code sessions.
2. Start `claude-project-mover-gui.ps1`.
3. Select one or more source projects in the checklist.
4. Select a common destination root with the native Windows folder picker.
5. Keep **Projektverzeichnisse physisch verschieben** enabled when the tool should move the real project directories.
6. Keep the ZIP backup enabled for important session history.
7. Review the generated source-to-destination plan and confirm it.

For a source project such as:

```text
C:\Users\Jane\Code\ProjectA
```

and the selected destination root:

```text
D:\Development
```

the resulting target is:

```text
D:\Development\ProjectA
```

Each selected project keeps its existing leaf directory name.

## Multiple projects

The checklist supports selecting any number of detected Claude Code projects. Before changing anything, the interface verifies that:

- every source project still exists
- every generated target path is unused
- the target root exists
- enough free space is available for all selected projects plus safety headroom

The projects are then processed one after another. For each project the interface:

1. moves the real project directory when enabled
2. calls `claude-project-mover.ps1`
3. creates the requested metadata backup
4. validates and updates the Claude Code metadata

If metadata migration fails immediately after moving a project directory, the interface attempts to move that directory back to its original path.

## Metadata-only mode

To use the interface only for Claude Code metadata updates, disable **Projektverzeichnisse physisch verschieben**. The expected target project folders must already exist below the selected destination root.

The same mode can be selected when starting the interface:

```powershell
.\claude-project-mover-gui.ps1 -NoProjectMove
```

## Custom Claude configuration

```powershell
.\claude-project-mover-gui.ps1 -ClaudeConfigDirectory 'D:\ClaudeConfig'
```

The command-line script remains available for automation, preflight-only checks, custom free-space thresholds and non-Windows systems.

## Limitations

- The native interface requires Windows and Windows Forms.
- All selected projects are moved below one common destination root.
- Existing target directories are never overwritten or merged.
- The interface processes projects sequentially rather than as one cross-project transaction. Projects completed before a later failure remain migrated.
- Network-share free-space information may not be available through .NET. Review network capacity manually before moving large projects.
