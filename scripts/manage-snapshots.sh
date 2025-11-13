#!/bin/bash
# QCOW2 Snapshot Management Script
# Create, list, restore, and delete QCOW2 snapshots
# Version: 1.0
# WHY: Clean up backup files on error during backup operation
# WHAT: Track temporary backup file created during backup command
# HOW: cleanup() removes incomplete backup file on abnormal exit

set -euo pipefail

# Track cleanup state
CLEANUP_NEEDED=false
TEMP_BACKUP_FILE=""

cleanup() {
    local exit_code=$?
    
    if [ "$CLEANUP_NEEDED" = true ] && [ -n "$TEMP_BACKUP_FILE" ] && [ -f "$TEMP_BACKUP_FILE" ]; then
        echo -e "${YELLOW}Cleaning up incomplete backup file...${NC}"
        rm -f "$TEMP_BACKUP_FILE" && echo -e "${GREEN}✓ Removed: $TEMP_BACKUP_FILE${NC}"
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

QCOW2_IMAGE="${QCOW2_IMAGE:-debian-hurd-amd64.qcow2}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  list                  List all snapshots
  create <name>         Create a new snapshot
  restore <name>        Restore to a snapshot (DESTRUCTIVE)
  delete <name>         Delete a snapshot
  info                  Show image information
  backup <dest>         Create full backup copy

Options:
  -i, --image <path>    Specify QCOW2 image (default: $QCOW2_IMAGE)
  -h, --help            Show this help message

Examples:
  $(basename "$0") list
  $(basename "$0") create pre-upgrade
  $(basename "$0") restore pre-upgrade
  $(basename "$0") backup /backup/hurd-backup.qcow2

Environment:
  QCOW2_IMAGE          Default QCOW2 image path
EOF
}

# Check if qemu-img is available
check_qemu_img() {
    if ! command -v qemu-img &> /dev/null; then
        echo -e "${RED}ERROR: qemu-img not found${NC}"
        echo "Install with: apt-get install qemu-utils"
        exit 1
    fi
}

# Check if image exists
check_image() {
    if [ ! -f "$QCOW2_IMAGE" ]; then
        echo -e "${RED}ERROR: QCOW2 image not found: $QCOW2_IMAGE${NC}"
        exit 1
    fi
}

# List snapshots
cmd_list() {
    check_image
    echo -e "${BLUE}Snapshots in: $QCOW2_IMAGE${NC}"
    echo ""
    qemu-img snapshot -l "$QCOW2_IMAGE"
}

# Create snapshot
cmd_create() {
    local snapshot_name="$1"

    if [ -z "$snapshot_name" ]; then
        echo -e "${RED}ERROR: Snapshot name required${NC}"
        echo "Usage: $(basename "$0") create <name>"
        exit 1
    fi

    check_image

    echo -e "${YELLOW}Creating snapshot: $snapshot_name${NC}"
    qemu-img snapshot -c "$snapshot_name" "$QCOW2_IMAGE"
    echo -e "${GREEN}✓ Snapshot created: $snapshot_name${NC}"
    echo ""
    cmd_list
}

# Restore snapshot
cmd_restore() {
    local snapshot_name="$1"

    if [ -z "$snapshot_name" ]; then
        echo -e "${RED}ERROR: Snapshot name required${NC}"
        echo "Usage: $(basename "$0") restore <name>"
        exit 1
    fi

    check_image

    echo -e "${RED}WARNING: This will restore the VM to snapshot '$snapshot_name'${NC}"
    echo -e "${RED}         All changes since the snapshot will be LOST${NC}"
    echo ""
    read -p "Are you sure? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        exit 0
    fi

    echo -e "${YELLOW}Restoring snapshot: $snapshot_name${NC}"
    qemu-img snapshot -a "$snapshot_name" "$QCOW2_IMAGE"
    echo -e "${GREEN}✓ Snapshot restored: $snapshot_name${NC}"
}

# Delete snapshot
cmd_delete() {
    local snapshot_name="$1"

    if [ -z "$snapshot_name" ]; then
        echo -e "${RED}ERROR: Snapshot name required${NC}"
        echo "Usage: $(basename "$0") delete <name>"
        exit 1
    fi

    check_image

    echo -e "${YELLOW}Deleting snapshot: $snapshot_name${NC}"
    read -p "Are you sure? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Delete cancelled."
        exit 0
    fi

    qemu-img snapshot -d "$snapshot_name" "$QCOW2_IMAGE"
    echo -e "${GREEN}✓ Snapshot deleted: $snapshot_name${NC}"
    echo ""
    cmd_list
}

# Show image info
cmd_info() {
    check_image
    echo -e "${BLUE}Image Information: $QCOW2_IMAGE${NC}"
    echo ""
    qemu-img info "$QCOW2_IMAGE"
}

# Create backup
cmd_backup() {
    local dest="$1"

    if [ -z "$dest" ]; then
        echo -e "${RED}ERROR: Destination path required${NC}"
        echo "Usage: $(basename "$0") backup <destination>"
        exit 1
    fi

    check_image

    # Check if destination already exists
    if [ -f "$dest" ]; then
        echo -e "${YELLOW}WARNING: Destination exists: $dest${NC}"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Backup cancelled."
            exit 0
        fi
    fi

    echo -e "${YELLOW}Creating backup...${NC}"
    echo "  Source: $QCOW2_IMAGE"
    echo "  Destination: $dest"
    echo ""

    # Get source size for progress estimation
    local source_size
    source_size=$(qemu-img info --output=json "$QCOW2_IMAGE" | grep -o '"virtual-size": [0-9]*' | cut -d' ' -f2)
    local source_size_gb=$((source_size / 1024 / 1024 / 1024))

    echo "Virtual size: ${source_size_gb}GB"
    echo "Note: Actual copy size depends on disk usage"
    echo ""

    # Track backup file for cleanup on error
    TEMP_BACKUP_FILE="$dest"
    CLEANUP_NEEDED=true

    # Copy with progress (if pv is available)
    if command -v pv &> /dev/null; then
        pv "$QCOW2_IMAGE" > "$dest"
    else
        cp -v "$QCOW2_IMAGE" "$dest"
    fi

    # Backup successful, don't clean it up on exit
    CLEANUP_NEEDED=false
    TEMP_BACKUP_FILE=""

    echo -e "${GREEN}✓ Backup created: $dest${NC}"
    echo ""
    echo "Backup info:"
    qemu-img info "$dest" | head -10
}

# Main
main() {
    check_qemu_img

    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--image)
                QCOW2_IMAGE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    case "$command" in
        list)
            cmd_list
            ;;
        create)
            cmd_create "$@"
            ;;
        restore)
            cmd_restore "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        info)
            cmd_info
            ;;
        backup)
            cmd_backup "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo -e "${RED}ERROR: Unknown command: $command${NC}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
