#!/bin/bash

# Claude Code Project Mover
# Moves a Claude Code project from one path to another.

set -euo pipefail

SCRIPT_VERSION="1.2.1"
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

# List all projects with numbers
list_projects() {
    local i=1
    printf "${BLUE}%-4s %-17s %-9s %-42s %s${NC}\n" "Nr." "Letzte Sitzung" "Sessions" "Beschreibung" "Projektpfad"
    printf '%s\n' "--------------------------------------------------------------------------------------------------------------"
    for dir in "$PROJECTS_DIR"/-*/; do
        if [[ -d "$dir" ]]; then
            local folder_name=$(basename "$dir")
            local readable_path=$(get_readable_path "$folder_name")
            local details timestamp session_count description
            details=$(get_session_details "$dir")
            IFS=$'\t' read -r timestamp session_count description <<< "$details"
            printf "${BLUE}%3d)${NC} %-17s %-9s %-42.42s %s\n" \
                "$i" "$timestamp" "$session_count" "$description" "$readable_path"
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

    # Escape special characters for sed
    local old_escaped=$(printf '%s\n' "$old_path" | sed 's/[[\.*^$()+?{|]/\\&/g')
    local new_escaped=$(printf '%s\n' "$new_path" | sed 's/[&/\]/\\&/g')

    echo -e "${YELLOW}Replacing paths in files...${NC}" >&2

    # Detect sed flavor once (GNU sed: -i; BSD sed: -i '')
    if sed --version 2>&1 | grep -q GNU; then
        sed_inplace=(sed -i)
    else
        sed_inplace=(sed -i '')
    fi

    # Replace paths in all files
    for file in "$old_full_path"/*; do
        if [[ -f "$file" ]]; then
            "${sed_inplace[@]}" "s|$old_escaped|$new_escaped|g" "$file"
        fi
    done

    echo -e "${YELLOW}Renaming folder...${NC}" >&2

    # Rename folder
    mv "$old_full_path" "$new_full_path"

    echo "$new_full_path"
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

    echo ""
    echo ""
    echo -e "${BLUE}Enter the new project location${NC}"
    echo -e "${BLUE}───────────────────────────────${NC}"
    echo -e "  Current: ${YELLOW}$selected_path${NC}"

    # Get new path
    while true; do
        read -p "  New path: " new_path

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
        if [[ ! -d "$new_path" ]]; then
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

    # Perform move
    move_project "$selected_folder" "$new_path" > /dev/null

    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  Project updated successfully!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "  ${BLUE}$new_path${NC}"
    echo ""
    echo ""
}

main "$@"
