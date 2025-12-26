#!/bin/bash

# Claude Code Project Mover
# Moves a Claude Code project from one path to another

set -e

PROJECTS_DIR="$HOME/.claude/projects"
BACKUP_DIR="$HOME/.claude/projects-backup"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    for dir in "$PROJECTS_DIR"/-*/; do
        if [[ -d "$dir" ]]; then
            local folder_name=$(basename "$dir")
            local readable_path=$(get_readable_path "$folder_name")
            printf "${BLUE}%3d)${NC} %s\n" "$i" "$readable_path"
            i=$((i + 1))
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

# Backup a project folder
backup_project() {
    local folder_name="$1"
    local timestamp=$(date +"%Y%m%d_%H%M%S")

    mkdir -p "$BACKUP_DIR"

    local backup_name="${folder_name}_backup_${timestamp}"
    cp -r "$PROJECTS_DIR/$folder_name" "$BACKUP_DIR/$backup_name"

    echo "$BACKUP_DIR/$backup_name"
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

    echo -e "${YELLOW}Replacing paths in files...${NC}"

    # Replace paths in all files
    for file in "$old_full_path"/*; do
        if [[ -f "$file" ]]; then
            sed -i '' "s|$old_escaped|$new_escaped|g" "$file"
        fi
    done

    echo -e "${YELLOW}Renaming folder...${NC}"

    # Rename folder
    mv "$old_full_path" "$new_full_path"

    echo "$new_full_path"
}

# Main script
main() {
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  Claude Code Project Mover${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""

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

    echo -e "Found ${BLUE}$total${NC} projects:\n"

    # List projects
    list_projects

    echo ""

    # Get user selection
    while true; do
        read -p "Select project number (1-$total): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$total" ]]; then
            break
        fi
        echo -e "${RED}Invalid selection. Please enter a number between 1 and $total.${NC}"
    done

    local selected_folder=$(get_project_by_index "$selection")
    local selected_path=$(get_readable_path "$selected_folder")

    echo ""
    echo -e "Selected: ${BLUE}$selected_path${NC}"
    echo ""

    # Get new path
    while true; do
        read -p "Enter new path: " new_path

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

        break
    done

    echo ""
    echo -e "Moving: ${YELLOW}$selected_path${NC}"
    echo -e "    To: ${GREEN}$new_path${NC}"
    echo ""

    # Ask about backup
    read -p "Create backup before moving? (y/n): " do_backup

    if [[ "$do_backup" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Creating backup...${NC}"
        backup_path=$(backup_project "$selected_folder")
        echo -e "${GREEN}Backup created at: $backup_path${NC}"
        echo ""
    fi

    # Confirm action
    read -p "Proceed with move? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        exit 0
    fi

    echo ""

    # Perform move
    new_folder_path=$(move_project "$selected_folder" "$new_path")

    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  Project moved successfully!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo -e "New location: ${BLUE}$new_folder_path${NC}"
}

main "$@"
