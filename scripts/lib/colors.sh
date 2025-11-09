#!/bin/sh
# lib/colors.sh - Standardized color output functions
# WHY: Eliminate ~200 lines of duplicated color functions across 12+ scripts
# WHAT: Provides echo_info, echo_success, echo_error, echo_warning, step, pass, fail
# HOW: Source this file: source "$(dirname "$0")/lib/colors.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Standard logging functions
echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Test framework functions
step() {
    echo -e "${BLUE}[$1]${NC}"
}

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
}

# Export functions for subshells
export -f echo_info echo_success echo_error echo_warning step pass fail 2>/dev/null || true
