#!/bin/bash
# GNU/Hurd Docker Documentation Consolidation Script
# Purpose: Automate documentation reorganization based on consolidation report
# Date: 2025-11-08

set -eu

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory (docs/)
DOCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}=== GNU/Hurd Docker Documentation Consolidation ===${NC}"
echo "Working directory: $DOCS_DIR"
echo

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Create backup
backup_docs() {
    local backup_file="docs-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    echo -e "${BLUE}Creating backup...${NC}"

    if tar czf "$backup_file" --exclude='*.tar.gz' --exclude='mydatabase.db' .; then
        print_status "Backup created: $backup_file"
    else
        print_error "Failed to create backup"
        exit 1
    fi
    echo
}

# Create directory structure
create_structure() {
    echo -e "${BLUE}Creating organized directory structure...${NC}"

    # Main directories are already created, add subdirectories
    local dirs=(
        "01-GETTING-STARTED/archive"
        "01-GETTING-STARTED/requirements"
        "02-ARCHITECTURE/qemu"
        "02-ARCHITECTURE/control-plane"
        "03-CONFIGURATION/development"
        "03-CONFIGURATION/user"
        "04-OPERATION/deployment"
        "04-OPERATION/testing"
        "05-CI-CD/workflows"
        "05-CI-CD/images"
        "06-TROUBLESHOOTING/kernel"
        "06-TROUBLESHOOTING/network"
        "06-TROUBLESHOOTING/filesystem"
        "07-RESEARCH-AND-LESSONS/sessions"
        "07-RESEARCH-AND-LESSONS/testing"
        "07-RESEARCH-AND-LESSONS/tools"
        "07-RESEARCH-AND-LESSONS/analysis"
        "08-REFERENCE/checklists"
        "08-REFERENCE/maps"
        "08-REFERENCE/guidelines"
        "08-REFERENCE/scripts"
        "archive/deprecated"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        print_status "Created $dir"
    done

    echo
}

# Phase 1: Critical Actions
phase1_critical() {
    echo -e "${BLUE}Phase 1: Critical Actions${NC}"

    # Delete obvious duplicates and backups
    if [ -f "CREDENTIALS.txt" ]; then
        rm -f "CREDENTIALS.txt"
        print_status "Deleted CREDENTIALS.txt (duplicate)"
    fi

    if [ -f "ARCHITECTURE.md.bak" ]; then
        rm -f "ARCHITECTURE.md.bak"
        print_status "Deleted ARCHITECTURE.md.bak"
    fi

    # Archive old index
    if [ -f "index.md" ]; then
        mv "index.md" "archive/deprecated/"
        print_status "Archived index.md"
    fi

    # Remove duplicate research directory
    if [ -d "07-RESEARCH" ] && [ ! "$(ls -A 07-RESEARCH)" ]; then
        rmdir "07-RESEARCH"
        print_status "Removed empty 07-RESEARCH directory"
    fi

    echo
}

# Phase 2: Move files to organized structure
phase2_organize() {
    echo -e "${BLUE}Phase 2: Organizing Files by Category${NC}"

    # Function to safely move files
    safe_move() {
        local source="$1"
        local dest="$2"

        if [ -f "$source" ]; then
            # Check if destination exists
            if [ -f "$dest" ]; then
                print_warning "Destination exists: $dest (needs manual merge)"
                echo "  Source: $source"
            else
                mv "$source" "$dest"
                print_status "Moved: $(basename "$source") → $dest"
            fi
        fi
    }

    # Getting Started files
    safe_move "requirements.md" "01-GETTING-STARTED/REQUIREMENTS.md"
    safe_move "SIMPLE-START.md" "01-GETTING-STARTED/archive/SIMPLE-START.md"
    safe_move "QUICK_START_GUIDE.md" "01-GETTING-STARTED/archive/QUICK_START_GUIDE.md"

    # Architecture files
    safe_move "CONTROL-PLANE-IMPLEMENTATION.md" "02-ARCHITECTURE/control-plane/IMPLEMENTATION.md"
    safe_move "QEMU-TUNING.md" "02-ARCHITECTURE/qemu/TUNING.md"
    safe_move "QEMU-OPTIMIZATION-2025.md" "02-ARCHITECTURE/qemu/OPTIMIZATION-2025.md"

    # Configuration files
    safe_move "PORT-MAPPING-GUIDE.md" "03-CONFIGURATION/PORT-MAPPING.md"
    safe_move "USER-SETUP.md" "03-CONFIGURATION/user/SETUP.md"
    safe_move "MCP-SERVERS-SETUP.md" "03-CONFIGURATION/development/MCP-SERVERS.md"

    # Operation files
    safe_move "DEPLOYMENT.md" "04-OPERATION/deployment/DEPLOYMENT.md"
    safe_move "DEPLOYMENT-STATUS.md" "04-OPERATION/deployment/STATUS.md"
    safe_move "LOCAL-TESTING-GUIDE.md" "04-OPERATION/testing/LOCAL-TESTING.md"
    safe_move "MANUAL-SETUP-REQUIRED.md" "04-OPERATION/MANUAL-SETUP.md"

    # CI/CD files
    safe_move "CI-CD-GUIDE.md" "05-CI-CD/GUIDE.md"
    safe_move "DOCKER-COMPOSE-CI-CD-GUIDE.md" "05-CI-CD/DOCKER-COMPOSE-GUIDE.md"
    safe_move "HURD-IMAGE-BUILDING.md" "05-CI-CD/images/BUILDING.md"

    # Troubleshooting files
    safe_move "TROUBLESHOOTING.md" "06-TROUBLESHOOTING/GENERAL.md"
    safe_move "FSCK-ERROR-FIX.md" "06-TROUBLESHOOTING/filesystem/FSCK-FIX.md"
    safe_move "IO-ERROR-FIX.md" "06-TROUBLESHOOTING/filesystem/IO-ERROR-FIX.md"
    safe_move "SSH-CONFIGURATION-RESEARCH.md" "06-TROUBLESHOOTING/network/SSH-DETAILED.md"
    safe_move "KERNEL-FIX-GUIDE.md" "06-TROUBLESHOOTING/kernel/FIX-GUIDE.md"
    safe_move "QUICK-START-KERNEL-FIX.txt" "06-TROUBLESHOOTING/kernel/QUICK-FIX.txt"
    safe_move "VALIDATION-AND-TROUBLESHOOTING.md" "06-TROUBLESHOOTING/VALIDATION.md"

    # Research and Lessons files
    safe_move "RESEARCH-FINDINGS.md" "07-RESEARCH-AND-LESSONS/FINDINGS.md"
    safe_move "COMPREHENSIVE-ANALYSIS-AND-IMPLEMENTATION-PLAN.md" "07-RESEARCH-AND-LESSONS/analysis/COMPREHENSIVE-PLAN.md"
    safe_move "KERNEL-STANDARDIZATION-PLAN.md" "07-RESEARCH-AND-LESSONS/KERNEL-STANDARDIZATION.md"
    safe_move "SESSION-COMPLETION-REPORT.md" "07-RESEARCH-AND-LESSONS/sessions/COMPLETION-REPORT.md"
    safe_move "EXECUTION-SUMMARY.md" "07-RESEARCH-AND-LESSONS/sessions/EXECUTION-SUMMARY.md"
    safe_move "TEST-RESULTS.md" "07-RESEARCH-AND-LESSONS/testing/RESULTS.md"
    safe_move "HURD-TESTING-REPORT.md" "07-RESEARCH-AND-LESSONS/testing/HURD-REPORT.md"
    safe_move "MCP-TOOLS-ASSESSMENT-MATRIX.md" "07-RESEARCH-AND-LESSONS/tools/MCP-ASSESSMENT.md"
    safe_move "PROJECT-SUMMARY.md" "07-RESEARCH-AND-LESSONS/PROJECT-SUMMARY.md"
    safe_move "IMPLEMENTATION-COMPLETE.md" "07-RESEARCH-AND-LESSONS/IMPLEMENTATION-COMPLETE.md"
    safe_move "MACH_QEMU_RESEARCH_REPORT.md" "07-RESEARCH-AND-LESSONS/MACH-QEMU-RESEARCH.md"

    # Reference files
    safe_move "QUICK-REFERENCE.md" "08-REFERENCE/QUICK-REFERENCE.md"
    safe_move "X86_64-VALIDATION-CHECKLIST.md" "08-REFERENCE/checklists/X86_64-VALIDATION.md"
    safe_move "STRUCTURAL-MAP.md" "08-REFERENCE/maps/STRUCTURAL-MAP.md"
    safe_move "REPOSITORY-INDEX.md" "08-REFERENCE/maps/REPOSITORY-INDEX.md"
    safe_move "CROSS-LINKING-GUIDELINES.md" "08-REFERENCE/guidelines/CROSS-LINKING.md"

    echo
}

# Check for files needing manual merge
check_duplicates() {
    echo -e "${BLUE}Files Requiring Manual Review:${NC}"

    # Check for remaining files that need comparison
    local needs_merge=(
        "QUICKSTART.md:01-GETTING-STARTED/QUICKSTART.md"
        "INSTALLATION.md:01-GETTING-STARTED/INSTALLATION.md"
        "ARCHITECTURE.md:02-ARCHITECTURE/SYSTEM-DESIGN.md"
        "CUSTOM-HURD-FEATURES.md:03-CONFIGURATION/CUSTOM-FEATURES.md"
        "INTERACTIVE-ACCESS-GUIDE.md:04-OPERATION/INTERACTIVE-ACCESS.md"
        "CI-CD-PROVISIONED-IMAGE.md:05-CI-CD/PROVISIONED-IMAGE.md"
    )

    for pair in "${needs_merge[@]}"; do
        IFS=':' read -r source dest <<< "$pair"
        if [ -f "$source" ] && [ -f "$dest" ]; then
            print_warning "Manual merge needed: $source → $dest"
        fi
    done

    echo
}

# Generate report
generate_report() {
    local report_file="consolidation-report-$(date +%Y%m%d-%H%M%S).txt"

    echo -e "${BLUE}Generating consolidation report...${NC}"

    {
        echo "Documentation Consolidation Report"
        echo "Generated: $(date)"
        echo "=================================="
        echo
        echo "Files in organized directories:"
        for dir in 0[1-8]-*; do
            if [ -d "$dir" ]; then
                echo
                echo "$dir:"
                find "$dir" -type f -name "*.md" -o -name "*.txt" | sort
            fi
        done
        echo
        echo "=================================="
        echo "Remaining files at root:"
        find . -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) | sort
        echo
        echo "=================================="
        echo "Archive contents:"
        find archive -type f 2>/dev/null | sort
    } > "$report_file"

    print_status "Report generated: $report_file"
}

# Main execution
main() {
    echo "This script will reorganize the documentation structure."
    echo "A backup will be created before any changes."
    echo
    read -p "Continue? (y/n) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Aborted by user"
        exit 0
    fi

    # Execute phases
    backup_docs
    create_structure
    phase1_critical
    phase2_organize
    check_duplicates
    generate_report

    echo
    echo -e "${GREEN}Documentation consolidation complete!${NC}"
    echo
    echo "Next steps:"
    echo "1. Review files marked for manual merge"
    echo "2. Update INDEX.md with new structure"
    echo "3. Fix internal cross-references"
    echo "4. Commit changes to git"
    echo
    print_status "Backup available if rollback needed"
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    cd "$DOCS_DIR"
    main "$@"
fi