#!/bin/bash

# Claude Code Project Mover
# Moves a Claude Code project from one path to another.

set -euo pipefail

SCRIPT_VERSION="1.6.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    FILE_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
    if [[ "$FILE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        SCRIPT_VERSION="$FILE_VERSION"
    fi
fi

CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECTS_DIR="$CLAUDE_CONFIG_DIR/projects"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}  Claude Code Project Mover v${SCRIPT_VERSION}${NC}"
    echo "  Moves projects and safely updates their Claude Code metadata."
    echo -e "  ${BLUE}By heckpiet | https://github.com/heckpiet/claude-code-project-mover${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo ""
}

show_help() {
    cat <<EOF
Claude Code Project Mover v${SCRIPT_VERSION}

Usage:
  ./claude-project-mover.sh
  ./claude-project-mover.sh --list-projects
  ./claude-project-mover.sh --version
  ./claude-project-mover.sh --help

CLAUDE_CONFIG_DIR can override the default Claude home directory (~/.claude).
EOF
}

# Get the actual path from .jsonl files (reads cwd field)
get_readable_path() {
    local folder_name="$1"
    local folder_path="$PROJECTS_DIR/$folder_name"

    # Find first .jsonl file and extract cwd
    for file in "$folder_path"/*.jsonl; do
        if [[ -f "$file" ]]; then
            local cwd=$(grep -o '"cwd":"[^"]*"' "$file" 2>/dev/null | head -1 | sed 's/"cwd":"//;s/"$//')
            if [[ -n "$cwd" ]]; then
                echo "$cwd"
                return 0
            fi
        fi
    done

    # Fallback: decode from folder name if no cwd found
    echo "$folder_name" | sed 's/^-/\//' | sed 's/--/\/./g' | sed 's/-/\//g'
}

get_session_details() {
    local folder_path="$1"
    local latest_file=""
    local session_count=0
    local file

    for file in "$folder_path"/*.jsonl; do
        [[ -f "$file" ]] || continue
        session_count=$((session_count + 1))
        if [[ -z "$latest_file" || "$file" -nt "$latest_file" ]]; then
            latest_file="$file"
        fi
    done

    if [[ -z "$latest_file" ]]; then
        printf '%s\t%s\t%s\n' "-" "0" "Keine Beschreibung verfügbar"
        return
    fi

    local timestamp
    if timestamp=$(date -r "$latest_file" "+%d.%m.%Y %H:%M" 2>/dev/null); then
        :
    else
        timestamp="-"
    fi

    local description=""
    if command -v python3 >/dev/null 2>&1; then
        description=$(python3 - "$latest_file" <<'PY' 2>/dev/null || true
import json
import sys

path = sys.argv[1]
best = ""
with open(path, "r", encoding="utf-8", errors="replace") as stream:
    for line in stream:
        try:
            item = json.loads(line)
        except (ValueError, TypeError):
            continue
        title = item.get("aiTitle") or item.get("title")
        if isinstance(title, str) and title.strip():
            best = title.strip()
        message = item.get("message")
        if not best and isinstance(message, dict) and message.get("role") == "user":
            content = message.get("content")
            if isinstance(content, str):
                best = content.strip()
            elif isinstance(content, list):
                texts = [part.get("text", "") for part in content if isinstance(part, dict)]
                best = " ".join(texts).strip()
        if best:
            break
print(" ".join(best.split())[:100])
PY
)
    fi
    [[ -n "$description" ]] || description="Keine Beschreibung verfügbar"
    printf '%s\t%s\t%s\n' "$timestamp" "$session_count" "$description"
}

# Convert path to folder name
# /Users/martin/foo -> -Users-martin-foo
# /Users/martin/.config/omp -> -Users-martin--config-omp (dot = double dash)
get_folder_name() {
    local path="$1"
    # First replace /. with -- (dot folders), then replace remaining / with -
    echo "$path" | sed 's/\/\./--%/g' | sed 's/\//-/g' | sed 's/%//g'
}

has_project_marker() {
    local path="$1"
    [[ -d "$path/.git" || -f "$path/CLAUDE.md" || -f "$path/package.json" || \
       -f "$path/pyproject.toml" || -f "$path/Cargo.toml" || -f "$path/go.mod" ]]
}

is_general_source_path() {
    local path="${1%/}"
    [[ "$path" == "${HOME%/}" || "$path" == "${HOME%/}/Desktop" || \
       "$path" == "${HOME%/}/Documents" || "$path" == "${HOME%/}/Downloads" || \
       ( -n "${OneDrive:-}" && "$path" == "${OneDrive%/}" ) ]]
}

smart_folder_suggestion() {
    local description="$1"
    local timestamp="$2"
    local session_hint="$3"
    local suggestion
    suggestion=$(printf '%s' "$description" \
        | sed -E 's/^(Bitte|Kannst du|Ich möchte|Ich will|Erstelle|Baue|Prüfe|Schau(e)?( mal)?)[[:space:]]+//I' \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^[:alnum:]ÄÖÜäöüß]+/-/g;s/^-+//;s/-+$//' \
        | cut -c1-56)
    if [[ -z "$suggestion" || "$description" == "Keine Beschreibung verfügbar" ]]; then
        suggestion="claude-projekt-$(printf '%s' "$timestamp" | tr -cd '0-9' | cut -c1-12)-${session_hint:0:8}"
    fi
    printf '%s' "$suggestion"
}

write_origin_manifest() {
    local source_path="$1" destination_path="$2" mode="$3" session_count="$4"
    local manifest_path="$destination_path/.claude-project-origin.json"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$manifest_path" "$source_path" "$destination_path" "$mode" "$session_count" "$SCRIPT_VERSION" <<'PY'
import datetime
import getpass
import json
import os
import platform
import socket
import sys
import uuid

manifest_path, source, destination, mode, session_count, version = sys.argv[1:]
existing = {}
if os.path.isfile(manifest_path):
    try:
        with open(manifest_path, "r", encoding="utf-8") as stream:
            existing = json.load(stream)
    except (OSError, ValueError):
        existing = {}
now = datetime.datetime.now().astimezone()
transfer = {
    "transferId": str(uuid.uuid4()),
    "transferredAtUtc": now.astimezone(datetime.timezone.utc).isoformat(),
    "transferredAtLocal": now.isoformat(),
    "timeZone": str(now.tzinfo),
    "mode": mode,
    "tool": {
        "name": "Claude Code Project Mover",
        "version": version,
        "projectUrl": "https://github.com/heckpiet/claude-code-project-mover",
    },
    "source": {
        "path": source,
        "computerName": socket.gethostname(),
        "userName": getpass.getuser(),
        "operatingSystem": platform.platform(),
    },
    "destination": {
        "path": destination,
        "computerName": socket.gethostname(),
        "userName": getpass.getuser(),
    },
    "claude": {"sessionFiles": int(session_count)},
    "verification": {"destinationFolderExists": os.path.isdir(destination), "metadataValid": True, "cwdUpdated": True},
}
history = existing.get("transfers", [])
history.append(transfer)
manifest = {
    "schemaVersion": 1,
    "projectId": existing.get("projectId", str(uuid.uuid4())),
    "currentPath": destination,
    "updatedAtUtc": transfer["transferredAtUtc"],
    "transfers": history,
}
temporary = manifest_path + ".tmp"
with open(temporary, "w", encoding="utf-8") as stream:
    json.dump(manifest, stream, ensure_ascii=False, indent=2)
os.replace(temporary, manifest_path)
PY
    else
        local escaped_source escaped_destination
        escaped_source=$(printf '%s' "$source_path" | sed 's/\\/\\\\/g;s/"/\\"/g')
        escaped_destination=$(printf '%s' "$destination_path" | sed 's/\\/\\\\/g;s/"/\\"/g')
        printf '{\n  "schemaVersion": 1,\n  "projectId": "%s",\n  "currentPath": "%s",\n  "updatedAtUtc": "%s",\n  "transfers": [{"transferredAtUtc": "%s", "mode": "%s", "source": {"path": "%s", "computerName": "%s", "userName": "%s"}, "destination": {"path": "%s"}, "tool": {"name": "Claude Code Project Mover", "version": "%s"}, "claude": {"sessionFiles": %s}, "verification": {"destinationFolderExists": true, "metadataValid": true, "cwdUpdated": true}}]\n}\n' \
            "$(date +%s)-$$" "$escaped_destination" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            "$mode" "$escaped_source" "$(hostname)" "${USER:-unknown}" "$escaped_destination" "$SCRIPT_VERSION" "$session_count" > "$manifest_path"
    fi
}

# List all projects with numbers
list_projects() {
    local i=1
    printf "${BLUE}%-4s %-17s %-9s %-14s %-30s %-38s %s${NC}\n" "Nr." "Letzte Sitzung" "Sessions" "Ordnerstatus" "Vorschlag" "Beschreibung" "Projektpfad"
    printf '%s\n' "------------------------------------------------------------------------------------------------------------------------------------------------"
    for dir in "$PROJECTS_DIR"/-*/; do
        if [[ -d "$dir" ]]; then
            local folder_name=$(basename "$dir")
            local readable_path=$(get_readable_path "$folder_name")
            local details timestamp session_count description
            details=$(get_session_details "$dir")
            IFS=$'\t' read -r timestamp session_count description <<< "$details"
            local folder_status="Eigener Ordner" suggestion="-"
            if is_general_source_path "$readable_path"; then
                folder_status="ORDNER FEHLT"
                suggestion=$(smart_folder_suggestion "$description" "$timestamp" "$folder_name")
            fi
            printf "${BLUE}%3d)${NC} %-17s %-9s %-14s %-30.30s %-38.38s %s\n" \
                "$i" "$timestamp" "$session_count" "$folder_status" "$suggestion" "$description" "$readable_path"
            i=$((i + 1))
        fi
    done
}

# Emit rich machine-readable data for fzf.
list_projects_data() {
    for dir in "$PROJECTS_DIR"/-*/; do
        if [[ -d "$dir" ]]; then
            local folder_name=$(basename "$dir")
            local readable_path=$(get_readable_path "$folder_name")
            local details timestamp session_count description
            details=$(get_session_details "$dir")
            IFS=$'\t' read -r timestamp session_count description <<< "$details"
            printf '%s\t%s | %s Sessions | %s | %s\n' \
                "$folder_name" "$timestamp" "$session_count" "$description" "$readable_path"
        fi
    done
}

# Get project folder by index
get_project_by_index() {
    local index="$1"
    local i=1
    for dir in "$PROJECTS_DIR"/-*/; do
        if [[ -d "$dir" ]]; then
            if [[ "$i" -eq "$index" ]]; then
                basename "$dir"
                return 0
            fi
            i=$((i + 1))
        fi
    done
    return 1
}

# Count total projects
count_projects() {
    local count=0
    for dir in "$PROJECTS_DIR"/-*/; do
        if [[ -d "$dir" ]]; then
            count=$((count + 1))
        fi
    done
    echo "$count"
}

# Backup a project folder as .tar.gz
backup_project() {
    local folder_name="$1"
    local timestamp=$(date +"%Y%m%d_%H%M%S")

    local backup_name="BACKUP__${folder_name}__${timestamp}.tar.gz"
    # Use -- to prevent folder name starting with - being interpreted as flag
    tar -czf "$PROJECTS_DIR/$backup_name" -C "$PROJECTS_DIR" -- "$folder_name"

    echo "$PROJECTS_DIR/$backup_name"
}

# Move project to new path
move_project() {
    local old_folder="$1"
    local new_path="$2"

    local old_path=$(get_readable_path "$old_folder")
    local new_folder=$(get_folder_name "$new_path")

    local old_full_path="$PROJECTS_DIR/$old_folder"
    local new_full_path="$PROJECTS_DIR/$new_folder"

    # Check if destination already exists
    if [[ -d "$new_full_path" ]]; then
        echo -e "${RED}Error: A project already exists at ${new_path}${NC}"
        return 1
    fi

    echo -e "${YELLOW}Updating cwd fields in JSONL metadata...${NC}" >&2
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${RED}Error: Python 3 is required for safe JSONL path updates.${NC}" >&2
        return 1
    fi
    python3 - "$old_full_path" "$old_path" "$new_path" <<'PY'
import json
import os
import sys

root, old_path, new_path = sys.argv[1:]
updated = 0
for current_root, _, names in os.walk(root):
    for name in names:
        if not name.endswith(".jsonl"):
            continue
        path = os.path.join(current_root, name)
        output = []
        changed = False
        with open(path, "r", encoding="utf-8", errors="strict") as stream:
            for raw in stream:
                try:
                    record = json.loads(raw)
                except (TypeError, ValueError):
                    output.append(raw)
                    continue
                if record.get("cwd") == old_path:
                    record["cwd"] = new_path
                    changed = True
                    output.append(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
                else:
                    output.append(raw)
        if changed:
            temporary = path + ".tmp"
            with open(temporary, "w", encoding="utf-8", newline="") as stream:
                stream.writelines(output)
            os.replace(temporary, path)
            updated += 1
if updated == 0:
    raise SystemExit("No JSONL cwd field referenced the old project path.")
PY

    echo -e "${YELLOW}Renaming folder...${NC}" >&2

    # Rename folder
    mv "$old_full_path" "$new_full_path"

    echo "$new_full_path"
}

create_session_bundle() {
    local metadata_path="$1" old_path="$2" new_path="$3" old_folder="$4"
    python3 - "$metadata_path" "$CLAUDE_CONFIG_DIR" "$old_path" "$new_path" "$old_folder" <<'PY'
import datetime
import json
import os
import pathlib
import shutil
import sys
import tempfile

metadata, config, old_path, new_path, old_folder = sys.argv[1:]
destination = pathlib.Path(new_path)
bundle = destination / ".claude-session-bundle"
temporary = destination / ".claude-session-bundle.tmp"
if temporary.exists():
    shutil.rmtree(temporary)
if bundle.exists():
    shutil.copytree(bundle, temporary)
else:
    temporary.mkdir(parents=True)
metadata_target = temporary / "metadata"
if metadata_target.exists():
    shutil.rmtree(metadata_target)
shutil.copytree(metadata, metadata_target)

session_ids = sorted({
    pathlib.Path(path).stem
    for path in pathlib.Path(metadata).rglob("*.jsonl")
    if len(pathlib.Path(path).stem) == 36
})
for session_id in session_ids:
    history = pathlib.Path(config) / "file-history" / session_id
    if history.is_dir():
        target = temporary / "file-history" / session_id
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(history, target, dirs_exist_ok=True)
    runtime = pathlib.Path(tempfile.gettempdir()) / "claude" / old_folder / session_id
    if runtime.is_dir():
        target = temporary / "runtime" / session_id
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(runtime, target, dirs_exist_ok=True)

safe_roots = set()
sensitive = set()
source = pathlib.Path(old_path)
for jsonl in pathlib.Path(metadata).rglob("*.jsonl"):
    with jsonl.open("r", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                record = json.loads(line)
            except (TypeError, ValueError):
                continue
            message = record.get("message")
            content = message.get("content", []) if isinstance(message, dict) else []
            for part in content if isinstance(content, list) else []:
                if not isinstance(part, dict) or part.get("type") != "tool_use" or part.get("name") not in ("Write", "Edit", "NotebookEdit"):
                    continue
                data = part.get("input", {})
                value = data.get("file_path") or data.get("notebook_path") or data.get("path")
                if not isinstance(value, str):
                    continue
                path = pathlib.Path(value)
                if not path.is_absolute():
                    path = source / path
                try:
                    relative = path.resolve().relative_to(source.resolve())
                except (OSError, ValueError):
                    continue
                first = relative.parts[0]
                if first in (".ssh", ".claude", ".codex", "AppData") or first.startswith("."):
                    sensitive.add(str(path))
                elif (source / first).exists():
                    safe_roots.add(first)
for first in sorted(safe_roots):
    source_item = source / first
    target_item = destination / first
    if not target_item.exists():
        if source_item.is_dir():
            shutil.copytree(source_item, target_item)
        else:
            shutil.copy2(source_item, target_item)

manifest = {
    "schemaVersion": 1,
    "createdAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "sourcePath": old_path,
    "currentPath": new_path,
    "sessions": session_ids,
    "copiedArtifacts": sorted(safe_roots),
    "skippedSensitivePaths": sorted(sensitive),
}
with (temporary / "manifest.json").open("w", encoding="utf-8") as stream:
    json.dump(manifest, stream, ensure_ascii=False, indent=2)
if bundle.exists():
    shutil.rmtree(bundle)
os.replace(temporary, bundle)
print(bundle)
PY
    if [[ -f "$SCRIPT_DIR/scripts/restore-claude-session.sh" ]]; then
        cp "$SCRIPT_DIR/scripts/restore-claude-session.sh" "$new_path/.claude-session-bundle/restore-claude-session.sh"
    fi
}

# Main script
main() {
    case "${1:-}" in
        --version|-v)
            echo "Claude Code Project Mover v${SCRIPT_VERSION}"
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --list-projects)
            print_header
            if [[ ! -d "$PROJECTS_DIR" ]]; then
                echo -e "${RED}Error: Projects directory not found at $PROJECTS_DIR${NC}"
                exit 1
            fi
            list_projects
            exit 0
            ;;
        "")
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 2
            ;;
    esac

    print_header

    # Check if projects directory exists
    if [[ ! -d "$PROJECTS_DIR" ]]; then
        echo -e "${RED}Error: Projects directory not found at $PROJECTS_DIR${NC}"
        exit 1
    fi

    # Count projects
    local total=$(count_projects)
    if [[ "$total" -eq 0 ]]; then
        echo -e "${RED}No projects found in $PROJECTS_DIR${NC}"
        exit 1
    fi

    echo -e "${BLUE}Select a project to update${NC}"
    echo -e "${BLUE}──────────────────────────${NC}"
    echo ""

    local selected_folder
    if command -v fzf >/dev/null 2>&1; then
        selected_folder=$(list_projects_data \
            | fzf --delimiter=$'\t' --with-nth=2 \
                  --prompt='Search project: ' --height=60% --reverse \
                  --header='Last session | Sessions | Description | Project path' \
            | cut -f1)

        if [[ -z "$selected_folder" ]]; then
            echo -e "${YELLOW}No project selected.${NC}"
            exit 0
        fi
    else
        list_projects
        echo ""

        local selection
        while true; do
            read -p "Enter project number (1-$total): " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$total" ]]; then
                break
            fi
            echo -e "${RED}Invalid selection. Please enter a number between 1 and $total.${NC}"
        done

        selected_folder=$(get_project_by_index "$selection")
    fi

    local selected_path=$(get_readable_path "$selected_folder")
    local create_project_folder=false
    local selected_details selected_timestamp selected_count selected_description suggested_folder_name
    selected_details=$(get_session_details "$PROJECTS_DIR/$selected_folder")
    IFS=$'\t' read -r selected_timestamp selected_count selected_description <<< "$selected_details"
    suggested_folder_name=$(smart_folder_suggestion "$selected_description" "$selected_timestamp" "$selected_folder")

    echo ""
    echo ""
    echo -e "${BLUE}Enter the new project location${NC}"
    echo -e "${BLUE}───────────────────────────────${NC}"
    echo -e "  Current: ${YELLOW}$selected_path${NC}"

    if is_general_source_path "$selected_path"; then
        echo -e "${YELLOW}No dedicated project folder was detected for this session group.${NC}"
        read -p "Create a dedicated project folder at the destination? (Y/n): " create_answer
        if [[ ! "$create_answer" =~ ^[Nn]$ ]]; then
            create_project_folder=true
        fi
    fi

    # Get new path
    while true; do
        if [[ "$create_project_folder" == true ]]; then
            read -p "  Destination parent folder: " target_root
            read -p "  New project folder name [$suggested_folder_name]: " project_folder_name
            project_folder_name="${project_folder_name:-$suggested_folder_name}"
            project_folder_name=$(printf '%s' "$project_folder_name" | sed 's#[/\\:*?\"<>|]#-#g;s/[[:space:]]\\+/-/g;s/^[.-]*//;s/[.-]*$//')
            if [[ -z "$project_folder_name" || ! -d "$target_root" ]]; then
                echo -e "${RED}Enter an existing parent folder and a valid new folder name.${NC}"
                continue
            fi
            new_path="${target_root%/}/$project_folder_name"
            if [[ -e "$new_path" ]]; then
                echo -e "${RED}Destination already exists: $new_path${NC}"
                continue
            fi
        else
            read -p "  New path: " new_path
        fi

        # Validate path
        if [[ -z "$new_path" ]]; then
            echo -e "${RED}Path cannot be empty.${NC}"
            continue
        fi

        if [[ ! "$new_path" =~ ^/ ]]; then
            echo -e "${RED}Path must be absolute (start with /).${NC}"
            continue
        fi

        # Remove trailing slash if present
        new_path="${new_path%/}"

        # Check if destination folder exists
        if [[ "$create_project_folder" != true && ! -d "$new_path" ]]; then
            echo -e "${RED}Folder does not exist: $new_path${NC}"
            echo -e "${YELLOW}Make sure you move your project folder first, then run this script.${NC}"
            continue
        fi

        break
    done

    echo ""
    echo ""
    echo -e "${BLUE}Path references will be updated${NC}"
    echo -e "${BLUE}────────────────────────────────${NC}"
    echo -e "  From: ${YELLOW}$selected_path${NC}"
    echo -e "    To: ${GREEN}$new_path${NC}"
    echo ""

    # Ask about backup
    echo ""
    echo -e "${BLUE}Backup${NC}"
    echo -e "${BLUE}──────${NC}"
    read -p "Create backup? (y/n): " do_backup

    if [[ "$do_backup" =~ ^[Yy]$ ]]; then
        backup_path=$(backup_project "$selected_folder")
        echo -e "  ${GREEN}$backup_path${NC}"
    fi

    # Confirm action
    echo ""
    echo -e "${BLUE}Confirm${NC}"
    echo -e "${BLUE}───────${NC}"
    read -p "Proceed with update? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        exit 0
    fi

    echo ""

    if [[ "$create_project_folder" == true ]]; then
        mkdir "$new_path"
        echo -e "${GREEN}Created dedicated project folder: $new_path${NC}"
    fi

    # Perform move
    if ! new_metadata_path=$(move_project "$selected_folder" "$new_path"); then
        if [[ "$create_project_folder" == true ]]; then
            rmdir "$new_path" 2>/dev/null || true
        fi
        return 1
    fi
    local transfer_mode="metadata-only"
    if [[ "$create_project_folder" == true ]]; then transfer_mode="create-folder"; fi
    write_origin_manifest "$selected_path" "$new_path" "$transfer_mode" "$selected_count"
    echo -e "${GREEN}Origin metadata: $new_path/.claude-project-origin.json${NC}"
    session_bundle=$(create_session_bundle "$new_metadata_path" "$selected_path" "$new_path" "$selected_folder")
    echo -e "${GREEN}Portable session bundle: $session_bundle${NC}"

    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  Project updated successfully!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "  ${BLUE}$new_path${NC}"
    echo ""
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
