#!/bin/bash
# Script Name - Brief One-Line Description
#
# WHY: Why this script exists - the problem it solves or requirement it addresses
#
# WHAT: What this script does - scope, operations performed, artifacts affected
#
# HOW: How to use this script - repeatable commands, workflow steps, examples
#
# USAGE:
#   ./script-name.sh [options] [arguments]
#
# OPTIONS:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -n, --dry-run           Show what would be done without doing it
#   -f, --force             Force operation without confirmation
#
# ARGUMENTS:
#   argument1               Description of first argument
#   argument2               Description of second argument (optional)
#
# PREREQUISITES:
#   - Requirement 1 (e.g., Must run as root)
#   - Requirement 2 (e.g., Network connectivity required)
#   - Requirement 3 (e.g., Package X must be installed)
#   - Requirement 4 (e.g., Environment variable X must be set)
#
# ENVIRONMENT VARIABLES:
#   VAR_NAME                Description and default value
#   ANOTHER_VAR             Description and default value
#
# EXAMPLES:
#   # Example 1: Basic usage
#   ./script-name.sh
#
#   # Example 2: With options
#   ./script-name.sh --verbose argument1
#
#   # Example 3: With environment variable
#   VAR_NAME=value ./script-name.sh argument1 argument2
#
#   # Example 4: Dry run
#   ./script-name.sh --dry-run argument1
#
# EXIT CODES:
#   0 - Success
#   1 - General error
#   2 - Invalid usage or arguments
#   3 - Missing prerequisites
#   4 - Network or connectivity error
#   5 - Permission denied
#
# VERIFICATION:
#   # How to verify the script succeeded
#   command-to-verify
#   expected-output
#
# TROUBLESHOOTING:
#   Issue: Common problem description
#   Cause: Why this happens
#   Fix: How to resolve it
#
#   Issue: Another common problem
#   Cause: Root cause
#   Fix: Resolution steps
#
# NOTES:
#   - Important note 1 (e.g., This operation is destructive)
#   - Important note 2 (e.g., Requires 2GB free disk space)
#   - Important note 3 (e.g., Takes 20-30 minutes to complete)
#
# SEE ALSO:
#   - related-script.sh - Brief description of relationship
#   - ../docs/DOCUMENTATION.md - Link to detailed documentation
#
# VERSION: 1.0.0
# LAST UPDATED: 2025-11-08
# AUTHOR: Your Name or Project Name

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default values for options
VERBOSE=false
DRY_RUN=false
FORCE=false

# Default values for environment variables
VAR_NAME="${VAR_NAME:-default_value}"
ANOTHER_VAR="${ANOTHER_VAR:-default_value}"

# Color codes (only if terminal)
if [ -t 1 ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m'  # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly NC=''
fi

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[DEBUG]${NC} $*" >&2
    fi
}

# Print usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options] [arguments]

Brief description of what this script does.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -n, --dry-run           Show what would be done without doing it
    -f, --force             Force operation without confirmation

ARGUMENTS:
    argument1               Description of first argument
    argument2               Description of second argument (optional)

ENVIRONMENT VARIABLES:
    VAR_NAME                Description (default: $VAR_NAME)
    ANOTHER_VAR             Description (default: $ANOTHER_VAR)

EXAMPLES:
    # Basic usage
    $SCRIPT_NAME

    # With options
    $SCRIPT_NAME --verbose argument1

    # With environment variable
    VAR_NAME=value $SCRIPT_NAME argument1

For detailed information, see the script header or documentation.

EOF
    exit 0
}

# Validate prerequisites
check_prerequisites() {
    log_debug "Checking prerequisites..."

    # Example: Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        log_error "Run with: sudo $SCRIPT_NAME"
        exit 5
    fi

    # Example: Check if required command exists
    if ! command -v required_command &> /dev/null; then
        log_error "Required command 'required_command' not found"
        log_error "Install with: apt-get install package-name"
        exit 3
    fi

    # Example: Check if required file exists
    if [ ! -f "/path/to/required/file" ]; then
        log_error "Required file not found: /path/to/required/file"
        exit 3
    fi

    # Example: Check if environment variable is set
    if [ -z "${REQUIRED_VAR:-}" ]; then
        log_error "Environment variable REQUIRED_VAR is not set"
        log_error "Set with: export REQUIRED_VAR=value"
        exit 3
    fi

    log_debug "Prerequisites OK"
}

# User confirmation prompt
confirm() {
    local message="$1"

    if [ "$FORCE" = true ]; then
        log_debug "Force mode enabled, skipping confirmation"
        return 0
    fi

    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Operation cancelled by user"
        exit 0
    fi
}

# Main function that does the work
main_operation() {
    local arg1="$1"
    local arg2="${2:-default}"

    log_info "Starting main operation..."
    log_debug "Argument 1: $arg1"
    log_debug "Argument 2: $arg2"

    # Example: Dry run check
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
        log_info "Would execute: command $arg1 $arg2"
        return 0
    fi

    # Example: Actual operation
    log_info "Performing operation..."

    # Do the work here
    # ...

    log_success "Operation completed successfully"
}

# Verification function
verify_result() {
    log_info "Verifying result..."

    # Example verification
    if [ -f "/expected/output/file" ]; then
        log_success "Output file created successfully"
    else
        log_error "Expected output file not found"
        return 1
    fi

    # Example command verification
    if command-to-verify &> /dev/null; then
        log_success "Verification passed"
    else
        log_error "Verification failed"
        return 1
    fi

    return 0
}

# Cleanup function (runs on exit)
cleanup() {
    local exit_code=$?

    log_debug "Cleanup function called with exit code: $exit_code"

    # Clean up temporary files
    # rm -f /tmp/temp-file

    # Restore original state if needed
    # ...

    exit $exit_code
}

# Parse command line arguments
parse_args() {
    # No arguments case
    if [ $# -eq 0 ]; then
        usage
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo ""
                usage
                ;;
            *)
                # Positional arguments
                ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# Main script execution
main() {
    # Array to hold positional arguments
    local ARGS=()

    # Set up cleanup trap
    trap cleanup EXIT INT TERM

    # Parse arguments
    parse_args "$@"

    # Show banner
    echo ""
    echo "================================================================"
    echo "  Script Name - Brief Description"
    echo "================================================================"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Get positional arguments
    local arg1="${ARGS[0]:-}"
    local arg2="${ARGS[1]:-}"

    # Validate required arguments
    if [ -z "$arg1" ]; then
        log_error "Missing required argument: argument1"
        echo ""
        usage
    fi

    # Optional: Show what will be done
    if [ "$VERBOSE" = true ]; then
        log_info "Configuration:"
        log_info "  Argument 1: $arg1"
        log_info "  Argument 2: $arg2"
        log_info "  VAR_NAME: $VAR_NAME"
        log_info "  ANOTHER_VAR: $ANOTHER_VAR"
        log_info "  Dry run: $DRY_RUN"
        log_info "  Force: $FORCE"
        echo ""
    fi

    # Optional: Ask for confirmation
    confirm "This will perform the operation on $arg1"

    # Do the work
    main_operation "$arg1" "$arg2"

    # Verify result
    if ! verify_result; then
        log_error "Verification failed"
        exit 1
    fi

    # Success message
    echo ""
    echo "================================================================"
    echo "  Operation Complete!"
    echo "================================================================"
    echo ""
    log_success "Script completed successfully"
    echo ""
    log_info "Next steps:"
    log_info "  1. Verify output: command-to-verify"
    log_info "  2. Test functionality: command-to-test"
    log_info "  3. Check status: command-to-check"
    echo ""
}

# Run main function with all arguments
main "$@"
