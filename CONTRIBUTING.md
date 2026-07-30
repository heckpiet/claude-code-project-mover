# Contributing

Contributions that improve platform compatibility, validation, data safety or documentation are welcome.

## Before opening an issue

Please check existing issues and include:

- operating system and version
- Windows PowerShell or PowerShell version
- Claude Code version when known
- whether `CLAUDE_CONFIG_DIR` is set
- sanitized old and new path formats
- the exact command used
- sanitized error output

Do not upload real Claude Code session files. They may contain prompts, local paths, tool output and project information.

## Development workflow

1. Fork the repository and create a focused branch.
2. Keep the original Bash behavior compatible unless a change is explicitly platform-specific.
3. Run the PowerShell parser and PSScriptAnalyzer.
4. Test with a disposable Claude Code project and a copied `.claude/projects` directory.
5. Run `-CheckOnly` before an end-to-end migration test.
6. Document behavior changes in the pull request.

## PowerShell validation

Parser check:

```powershell
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path '.\claude-project-mover.ps1'),
  [ref]$tokens,
  [ref]$errors
)
$errors
```

Static analysis:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path .\claude-project-mover.ps1
```

Preflight test:

```powershell
.\claude-project-mover.ps1 `
  -ProjectPath 'C:\Test\OldProject' `
  -NewPath 'D:\Test\OldProject' `
  -CheckOnly
```

## Pull request expectations

A pull request should explain:

- what changed
- why the change is needed
- effects on Bash and PowerShell users
- safety or compatibility implications
- validation performed
- limitations that remain

Prefer small, reviewable changes over unrelated updates in one pull request.

# Versioning

This project follows Semantic Versioning (`MAJOR.MINOR.PATCH`).

- Add every user-visible feature or bug fix to the `Unreleased` section in `CHANGELOG.md`.
- Increment `MINOR` for backward-compatible features.
- Increment `PATCH` for backward-compatible bug fixes.
- Increment `MAJOR` for breaking behavior or parameter changes.
- Keep the root `VERSION` file and `$ScriptVersion` in `claude-project-mover.ps1` identical.
- Use `.\scripts\Update-Version.ps1 -Part Major|Minor|Patch` to update both values safely.
- For a release, move the relevant changelog entries under `## [X.Y.Z] - YYYY-MM-DD`, then create the tag `vX.Y.Z`.

GitHub Actions validates the version format and consistency automatically.
