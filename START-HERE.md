# Start here

1. Download the complete archive from [the latest GitHub Release](https://github.com/heckpiet/claude-code-project-mover/releases/latest).
2. Extract it to a local folder. Do not run a single downloaded `.ps1` file by itself.
3. Close Claude Code and affected sessions.
4. Double-click `Start-ClaudeProjectMover.cmd`.
5. Select projects using the timestamp, description, folder status, and session-file summary.
6. Click **Validate sources**, choose a destination, review the plan, and click **Run**.

The interface uses the Windows display language automatically. Set `CLAUDE_MOVER_LANGUAGE=en` or `de`, or pass `-Language en|de`, to override it.

Keep backup, provenance, session bundle, and safe session files enabled unless you have a specific reason to disable them.

For detailed behavior and recovery information, read [README.md](README.md) and [WINDOWS-GUI.md](WINDOWS-GUI.md).
