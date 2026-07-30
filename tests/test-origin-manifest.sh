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
