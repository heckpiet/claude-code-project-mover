#!/usr/bin/env bash
set -euo pipefail

bundle="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
project="$(cd "$bundle/.." && pwd)"

python3 - "$bundle" "$config" "$project" <<'PY'
import json
import os
import pathlib
import shutil
import sys
import tempfile

bundle, config, project = map(pathlib.Path, sys.argv[1:])
with (bundle / "manifest.json").open(encoding="utf-8") as stream:
    manifest = json.load(stream)
folder = str(project).replace("/", "-")
destination = config / "projects" / folder
if destination.exists():
    raise SystemExit(f"Claude metadata already exists: {destination}")
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(bundle / "metadata", destination)
old = manifest["currentPath"]
for jsonl in destination.rglob("*.jsonl"):
    output = []
    with jsonl.open(encoding="utf-8") as stream:
        for line in stream:
            try:
                record = json.loads(line)
            except (TypeError, ValueError):
                output.append(line)
                continue
            if record.get("cwd") == old:
                record["cwd"] = str(project)
                output.append(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
            else:
                output.append(line)
    with jsonl.open("w", encoding="utf-8") as stream:
        stream.writelines(output)
for name in ("file-history",):
    source = bundle / name
    if source.is_dir():
        (config / name).mkdir(parents=True, exist_ok=True)
        for item in source.iterdir():
            shutil.copytree(item, config / name / item.name, dirs_exist_ok=True)
runtime = bundle / "runtime"
if runtime.is_dir():
    runtime_target = pathlib.Path(tempfile.gettempdir()) / "claude" / folder
    runtime_target.mkdir(parents=True, exist_ok=True)
    for item in runtime.iterdir():
        if item.is_dir():
            shutil.copytree(item, runtime_target / item.name, dirs_exist_ok=True)
print(f"Claude session restored for: {project}")
print(f"Metadata: {destination}")
PY
