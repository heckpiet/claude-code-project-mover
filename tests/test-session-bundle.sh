#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

export CLAUDE_CONFIG_DIR="$test_root/.claude"
source "$repo_root/claude-project-mover.sh"

old_path="$test_root/home"
new_path="$test_root/project"
old_folder="$(get_folder_name "$old_path")"
old_metadata="$PROJECTS_DIR/$old_folder"
session_id="28e4307f-feb3-4911-b3b3-f3dd264b6a58"
mkdir -p "$old_metadata" "$old_path/server-docs" "$old_path/.ssh" "$new_path"
printf '# report\n' > "$old_path/server-docs/report.md"
printf 'Host test\n' > "$old_path/.ssh/config"

python3 - "$old_metadata/$session_id.jsonl" "$old_path" <<'PY'
import json
import os
import sys
path, old = sys.argv[1:]
records = [
    {"type": "user", "cwd": old, "message": {"content": "test"}},
    {"type": "assistant", "cwd": old, "message": {"content": [
        {"type": "tool_use", "name": "Write", "input": {"file_path": os.path.join(old, "server-docs", "report.md")}},
        {"type": "tool_use", "name": "Edit", "input": {"file_path": os.path.join(old, ".ssh", "config")}},
    ]}},
]
with open(path, "w", encoding="utf-8") as stream:
    for record in records:
        stream.write(json.dumps(record) + "\n")
PY

mkdir -p "$CLAUDE_CONFIG_DIR/file-history/$session_id"
printf 'old report\n' > "$CLAUDE_CONFIG_DIR/file-history/$session_id/report@v1"
runtime_source="${TMPDIR:-/tmp}/claude/$old_folder/$session_id"
mkdir -p "$runtime_source/scratchpad" "$runtime_source/tasks"
printf 'helper\n' > "$runtime_source/scratchpad/helper.sh"
printf 'done\n' > "$runtime_source/tasks/task.output"

new_metadata="$(move_project "$old_folder" "$new_path")"
bundle="$(create_session_bundle "$new_metadata" "$old_path" "$new_path" "$old_folder")"

python3 - "$new_metadata/$session_id.jsonl" "$bundle/manifest.json" "$old_path" "$new_path" <<'PY'
import json
import sys
jsonl, manifest_path, old, new = sys.argv[1:]
with open(jsonl, encoding="utf-8") as stream:
    records = [json.loads(line) for line in stream]
assert all(record["cwd"] == new for record in records)
assert records[1]["message"]["content"][0]["input"]["file_path"].startswith(old)
with open(manifest_path, encoding="utf-8") as stream:
    manifest = json.load(stream)
assert manifest["copiedArtifacts"] == ["server-docs"]
assert manifest["skippedSensitivePaths"]
PY

test -f "$new_path/server-docs/report.md"
test ! -e "$new_path/.ssh/config"
test -f "$bundle/metadata/$session_id.jsonl"
test -f "$bundle/file-history/$session_id/report@v1"
test -f "$bundle/runtime/$session_id/scratchpad/helper.sh"
test -f "$bundle/runtime/$session_id/tasks/task.output"
test -f "$bundle/restore-claude-session.sh"
restore_config="$test_root/restored-claude"
CLAUDE_CONFIG_DIR="$restore_config" bash "$bundle/restore-claude-session.sh" "$bundle"
restored_folder="$(get_folder_name "$new_path")"
test -f "$restore_config/projects/$restored_folder/$session_id.jsonl"
test -f "$restore_config/file-history/$session_id/report@v1"
restored_runtime="${TMPDIR:-/tmp}/claude/$restored_folder/$session_id"
test -f "$restored_runtime/scratchpad/helper.sh"
test -f "$restored_runtime/tasks/task.output"
rm -rf -- "$runtime_source" "$restored_runtime"
echo "Bash session bundle test passed."
