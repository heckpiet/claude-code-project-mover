#!/bin/bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPOSITORY_ROOT/claude-project-mover.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
SOURCE_ONE="$TEST_ROOT/source-one"
SOURCE_TWO="$TEST_ROOT/source-two"
DESTINATION="$TEST_ROOT/destination"
mkdir "$SOURCE_ONE" "$SOURCE_TWO" "$DESTINATION"

write_origin_manifest "$SOURCE_ONE" "$DESTINATION" "copy" "2"
write_origin_manifest "$SOURCE_TWO" "$DESTINATION" "move" "3"
METADATA="$TEST_ROOT/metadata"
mkdir "$METADATA"
SESSION_ID="55555555-5555-5555-5555-555555555555"
printf '{"cwd":"%s"}\n' "$SOURCE_ONE" > "$METADATA/$SESSION_ID.jsonl"
mkdir -p "$DESTINATION/.claude-session-bundle"
printf '{"sessions":["%s"]}\n' "$SESSION_ID" > "$DESTINATION/.claude-session-bundle/manifest.json"
PRIOR_MATCHES="$(find_prior_transfers "$TEST_ROOT" "$SOURCE_ONE" "$METADATA")"
[[ "$PRIOR_MATCHES" == *"same original source path"* ]]
[[ "$PRIOR_MATCHES" == *"identical session ID"* ]]

python3 - "$DESTINATION/.claude-project-origin.json" "$SOURCE_ONE" "$SOURCE_TWO" <<'PY'
import json
import sys

path, source_one, source_two = sys.argv[1:]
with open(path, "r", encoding="utf-8") as stream:
    manifest = json.load(stream)
assert manifest["schemaVersion"] == 1
assert manifest["projectId"]
assert manifest["currentPath"] == path.rsplit("/", 1)[0]
assert len(manifest["transfers"]) == 2
assert manifest["transfers"][0]["source"]["path"] == source_one
assert manifest["transfers"][0]["mode"] == "copy"
assert manifest["transfers"][1]["source"]["path"] == source_two
assert manifest["transfers"][1]["mode"] == "move"
assert manifest["transfers"][1]["verification"]["metadataValid"] is True
print("Bash origin manifest test passed.")
PY
