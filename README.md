# Claude Code Project Mover

Windows-first tooling for moving or copying Claude Code projects while keeping their sessions, metadata, file history, safe session artifacts, and provenance usable at the new location.

Current version: **2.0.0**
## Highlights

- Native Windows GUI plus an interactive PowerShell CLI
- English and German user interface with automatic system-language detection
- Manual language override through `-Language en|de` or `CLAUDE_MOVER_LANGUAGE`
- Recent-project overview with timestamps, session counts, descriptions, and smart folder-name suggestions
- Move, copy, metadata-only, and dedicated-folder workflows
- Detection of previous transfers at the destination
- Validated staging, optional ZIP backup, rollback, disk-space checks, and post-transfer verification
- Portable `.claude-session-bundle` containing project metadata, matching file history, runtime data, and safe artifacts
- `.claude-project-origin.json` provenance history with source computer, user, time, paths, tool version, and verification results
- Bash implementation for macOS/Linux; Windows remains the primary supported platform

## Download and start on Windows

Use the latest archive from [GitHub Releases](https://github.com/heckpiet/claude-code-project-mover/releases/latest). Extract the complete archive and double-click `Start-ClaudeProjectMover.cmd`.

Do not download only one `.ps1` file. The scripts share inventory and localization modules, so the complete release folder is required.

The starter prefers PowerShell 7 and falls back to Windows PowerShell 5.1. Its execution-policy override applies only to the launched process.

Command-line alternatives:

```powershell
.\Start-ClaudeProjectMover.cmd /cli
.\Start-ClaudeProjectMover.cmd /list-projects
.\claude-project-mover.ps1 -ListProjects
.\claude-project-mover.ps1 -ListSessions -LastSessions 20
```

Select a language explicitly:

```powershell
.\claude-project-mover.ps1 -Language en
.\claude-project-mover-gui.ps1 -Language de
$env:CLAUDE_MOVER_LANGUAGE = 'en'
.\Start-ClaudeProjectMover.cmd
```

`Auto` is the default. German UI cultures use German; all other cultures use English.

## Recommended workflow

1. Close Claude Code and the affected sessions.
2. Start the GUI or CLI from the complete release folder.
3. Review the project/session overview and select the source.
4. Validate the source.
5. Choose the destination and transfer mode.
6. Keep backup, provenance, session bundle, and safe-artifact options enabled.
7. Review the transfer plan and run it.
8. Open the destination in Claude Code and verify the restored session.

When a session used a collection folder such as the user profile or Downloads directory, the tool proposes a dedicated project folder derived from the session title or content. Existing names are detected and the user can adopt the folder, choose another name, or cancel.

## What is preserved

Claude Code project metadata under `~/.claude/projects` is updated with JSON-aware processing. The portable session bundle can additionally include:

- project JSONL session data;
- matching `~/.claude/file-history/<session-id>` directories;
- matching temporary Claude runtime directories when present;
- safe project-relative files referenced by write/edit tool activity;
- a manifest listing copied and deliberately skipped sensitive paths;
- restore helpers for PowerShell and Bash.

Sensitive or machine-bound areas such as `.ssh`, `.claude`, `.codex`, `AppData`, hidden credential stores, and paths outside the project are not copied automatically.

## Provenance and duplicate detection

By default, the destination receives `.claude-project-origin.json`. It records a stable project ID, source and destination paths, computer and user names, timestamps, transfer mode, tool version, project statistics, session statistics, and verification results. It does not store session content, credentials, IP addresses, hardware IDs, or Windows SIDs.

Before a transfer, the tool searches the destination area for matching provenance records and session IDs. Repeating a transfer requires explicit confirmation.

## Safety model

The PowerShell workflow validates source and destination, creates a staging metadata copy, updates structured JSONL fields, checks records and path references, activates the new metadata atomically, writes portable records, and retains rollback information until verification succeeds. Non-critical project-marker warnings require confirmation or `-Force`; corrupted metadata and insufficient space remain blocking.

Use `-CheckOnly` to run preflight checks without changing data.

## Bash

On macOS or Linux:

```bash
chmod +x claude-project-mover.sh
./claude-project-mover.sh
CLAUDE_MOVER_LANGUAGE=de ./claude-project-mover.sh
```

The Bash implementation requires Bash 4+, Python 3, and standard Unix tools. The Windows PowerShell implementation receives primary product and QA focus.

## Project layout

```text
claude-code-project-mover/
├── claude-project-mover.ps1
├── claude-project-mover-gui.ps1
├── claude-project-mover.sh
├── Start-ClaudeProjectMover.cmd
├── ClaudeProjectInventory.psm1
├── ClaudeProjectLocalization.psm1
├── scripts/
│   ├── Restore-ClaudeSession.ps1
│   ├── restore-claude-session.sh
│   └── Update-Version.ps1
├── tests/
├── START-HERE.md
├── WINDOWS-GUI.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
└── VERSION
```

## Versioning and releases

The project follows [Semantic Versioning](https://semver.org/) using `MAJOR.MINOR.PATCH`. `VERSION` is the source of truth; the release helper synchronizes the CLI, GUI, Bash, CMD starter, and README:

```powershell
.\scripts\Update-Version.ps1 -Part Major
```

Every release must update `CHANGELOG.md`, pass all PowerShell and Bash tests, publish an archive plus SHA-256 checksum, and use a matching Git tag.

## Contributing and security

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing behavior or release metadata. Report security-sensitive findings according to [SECURITY.md](SECURITY.md), not in a public issue.

## Credits and license

The original Bash approach was introduced by Martin. This fork adds the Windows-first PowerShell CLI, native GUI, validation, backup, rollback, session portability, provenance, and bilingual UI.

Licensed under the [MIT License](LICENSE).
