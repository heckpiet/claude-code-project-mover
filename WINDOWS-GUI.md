# Native Windows interface

`claude-project-mover-gui.ps1` provides a Windows Forms interface for moving one or more Claude Code projects.

## Recommended start

Use the included launcher:

```text
Start-ClaudeProjectMover.cmd
```

You can double-click the file in Windows Explorer or start it from a terminal:

```powershell
.\Start-ClaudeProjectMover.cmd
```

The launcher automatically:

- starts in the directory containing the tool
- selects PowerShell 7 when `pwsh.exe` is available
- otherwise uses Windows PowerShell 5.1
- starts PowerShell in STA mode for Windows Forms
- applies `ExecutionPolicy Bypass` only to this process
- keeps the terminal open when startup fails so the error remains visible

It does not permanently change the system-wide or user-wide PowerShell execution policy.

## Direct PowerShell start

The GUI can also be started directly:

```powershell
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1
```

or with Windows PowerShell:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1
```

Running only `./claude-project-mover-gui.ps1` may be blocked when Windows marks files downloaded from the internet as untrusted or when the current execution policy requires signed scripts. The launcher avoids that problem without weakening the permanent PowerShell configuration.

To change into the download directory in PowerShell, use `Set-Location` or `cd` rather than entering the directory path as a command:

```powershell
cd "$HOME\Downloads"
```

## Project detection

The interface reads the available projects from the Claude Code session metadata below `%USERPROFILE%\.claude\projects` or from `CLAUDE_CONFIG_DIR` when that environment variable is configured.

## Workflow

1. Close active Claude Code sessions.
2. Start `Start-ClaudeProjectMover.cmd`.
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

The same mode can be selected when starting the interface directly:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1 -NoProjectMove
```

## Custom Claude configuration

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\claude-project-mover-gui.ps1 -ClaudeConfigDirectory 'D:\ClaudeConfig'
```

The command-line script remains available for automation, preflight-only checks, custom free-space thresholds and non-Windows systems.

## Limitations

- The native interface requires Windows and Windows Forms.
- All selected projects are moved below one common destination root.
- Existing target directories are never overwritten or merged.
- The interface processes projects sequentially rather than as one cross-project transaction. Projects completed before a later failure remain migrated.
- Network-share free-space information may not be available through .NET. Review network capacity manually before moving large projects.
