# Security Policy

## Sensitive data

Claude Code session metadata can contain:

- prompts and responses
- local usernames and filesystem paths
- source-code fragments
- tool output
- repository information
- environment and project details

Do not attach real `.jsonl` session files, complete `.claude` directories or unredacted backups to public issues or pull requests.

The optional `.claude-project-origin.json` manifest records computer name, user name, paths, timestamps, operating system, and migration verification data. It does not record session content, credentials, IP addresses, hardware IDs, or Windows SIDs. Review or disable this manifest before sharing a project outside your organization.

## Reporting a vulnerability

Please report security-sensitive findings privately through GitHub's private vulnerability reporting feature when it is enabled for this repository. Otherwise, open a minimal issue asking the maintainer for a private contact channel without publishing exploit details or private session data.

Include only the information needed to reproduce the issue:

- affected script and commit
- operating system and PowerShell version
- sanitized path examples
- expected and actual behavior
- security impact
- a minimal synthetic test case

## Safe testing

Use a disposable project and a copied Claude Code configuration directory. You can point Claude Code tooling at an isolated configuration location with `CLAUDE_CONFIG_DIR` where supported.

Before testing a migration:

1. Close active Claude Code sessions.
2. Copy the relevant metadata to a test location.
3. Run the PowerShell script with `-CheckOnly`.
4. Use `-Backup` for the migration test.
5. Confirm that the original project data and session history remain available.

## Supported versions

Security fixes are applied to the current default branch. Older commits and user-modified copies are not supported.
