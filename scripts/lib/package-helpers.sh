#!/bin/bash
# lib/package-helpers.sh - Package installation and verification helpers
#
# WHY: Eliminate ~200 lines of duplicated apt/package error handling code
#      across install-essentials-hurd.sh, install-hurd-packages.sh, setup-hurd-dev.sh
# WHAT: Provides install_packages(), verify_package(), verify_command(),
#       install_optional(), batch_install(), and check_root() functions
# HOW: Source this file and colors.sh, then use helpers:
#      source "$(dirname "$0")/lib/colors.sh"
#      source "$(dirname "$0")/lib/package-helpers.sh"
#      install_packages "Phase Name" "${ARRAY[@]}"

# ============================================================================
# PREREQUISITE CHECK - Verify root access
# ============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo_error "This script must be run as root or with sudo"
        echo_info "Run: sudo $0"
        return 1
    fi
    return 0
}

# ============================================================================
# APT OPERATIONS - Core package management
# ============================================================================

# Initialize apt with non-interactive frontend
# Usage: apt_init
apt_init() {
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    return 0
}

# Update package lists
# Usage: apt_update
# Returns: 0 on success, 1 on failure
apt_update() {
    echo_info "Updating package lists..."
    
    if apt-get update -qq 2>/dev/null; then
        echo_success "Package lists updated"
        return 0
    else
        echo_error "Failed to update package lists"
        echo_info "Check /etc/apt/sources.list and network connectivity"
        return 1
    fi
}

# ============================================================================
# PACKAGE INSTALLATION - Main installation function
# ============================================================================

# Install packages with error handling and progress reporting
# Usage: install_packages "phase_name" "${PACKAGE_ARRAY[@]}"
# Arguments:
#   $1 = phase_name: descriptive name for this installation phase
#   $@ = packages: array of package names to install
# Returns: 0 on success, 1 on failure
install_packages() {
    local phase="$1"
    shift
    local packages="$*"
    
    if [ -z "$phase" ] || [ -z "$packages" ]; then
        echo_error "install_packages: missing arguments"
        echo_info "Usage: install_packages 'phase_name' \"\${ARRAY[@]}\""
        return 1
    fi
    
    # Count non-empty package names
    local count=0
    for pkg in $packages; do
        count=$((count + 1))
    done
    
    echo ""
    echo_info "[$phase] Installing $count packages..."
    
    # Ensure apt is initialized
    apt_init
    
    # Update if needed (once per session)
    if [ -z "${APT_UPDATED:-}" ]; then
        apt_update || return 1
        APT_UPDATED=1
    fi
    
    # Install packages with error handling
    if DEBIAN_FRONTEND=noninteractive apt-get install -y $packages 2>&1 | \
       grep -v "^Get:" | grep -v "^Reading" | grep -v "^Building" ; then
        echo_success "[$phase] Installation complete! ($count packages)"
        return 0
    else
        # Installation may have failed; check what packages actually failed
        echo_error "[$phase] Some packages failed to install"
        return 1
    fi
}

# ============================================================================
# OPTIONAL INSTALLATION - Graceful failure for non-critical packages
# ============================================================================

# Install optional packages (warn but don't fail on error)
# Usage: install_optional "package_name"
# Returns: 0 on success, 1 on failure (but doesn't exit script)
install_optional() {
    local package="$1"
    
    if [ -z "$package" ]; then
        echo_error "install_optional: missing package name"
        return 1
    fi
    
    apt_init
    
    echo_info "Installing optional: $package..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" >/dev/null 2>&1; then
        echo_success "  ✓ $package"
        return 0
    else
        echo_warning "  ! $package not available (skipping)"
        return 1
    fi
}

# ============================================================================
# BATCH INSTALLATION - Install multiple packages with per-package fallback
# ============================================================================

# Install multiple packages, attempting each individually if batch fails
# Usage: batch_install "phase_name" "pkg1 pkg2 pkg3 ..."
# Returns: 0 only if ALL packages installed successfully
batch_install() {
    local phase="$1"
    local packages="$2"
    local success_count=0
    local fail_count=0
    
    if [ -z "$phase" ] || [ -z "$packages" ]; then
        echo_error "batch_install: missing arguments"
        return 1
    fi
    
    apt_init
    
    echo ""
    echo_info "[$phase] Attempting batch installation..."
    
    # Try batch install first
    if DEBIAN_FRONTEND=noninteractive apt-get install -y $packages >/dev/null 2>&1; then
        echo_success "[$phase] Batch installation successful"
        return 0
    fi
    
    # Fall back to individual package installation
    echo_warning "[$phase] Batch install failed, trying individual packages..."
    
    for pkg in $packages; do
        if DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1; then
            echo_success "  ✓ $pkg"
            success_count=$((success_count + 1))
        else
            echo_warning "  ! $pkg (unavailable)"
            fail_count=$((fail_count + 1))
        fi
    done
    
    if [ $fail_count -eq 0 ]; then
        echo_success "[$phase] All $success_count packages installed"
        return 0
    else
        echo_warning "[$phase] $success_count installed, $fail_count unavailable"
        return 1
    fi
}

# ============================================================================
# VERIFICATION - Check if packages are installed
# ============================================================================

# Verify single package installation
# Usage: verify_package "gcc"
# Returns: 0 if installed, 1 if not
verify_package() {
    local package="$1"
    
    if [ -z "$package" ]; then
        echo_error "verify_package: missing package name"
        return 1
    fi
    
    if dpkg -l 2>/dev/null | grep -q "^ii.*$package"; then
        return 0
    else
        return 1
    fi
}

# Verify command is available in PATH
# Usage: verify_command "gcc"
# Returns: 0 if command exists, 1 if not
verify_command() {
    local command="$1"
    
    if [ -z "$command" ]; then
        echo_error "verify_command: missing command name"
        return 1
    fi
    
    if command -v "$command" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Verify list of commands
# Usage: verify_commands "gcc" "make" "cmake"
# Outputs: pass/fail for each command
verify_commands() {
    local failed=0
    
    for cmd in "$@"; do
        if verify_command "$cmd"; then
            pass "$cmd"
        else
            fail "$cmd"
            failed=$((failed + 1))
        fi
    done
    
    return $failed
}

# ============================================================================
# VERIFICATION SUITE - Comprehensive installation checks
# ============================================================================

# Verify list of packages are installed
# Usage: verify_packages "gcc" "make" "git"
# Outputs: pass/fail for each package
verify_packages() {
    local failed=0
    
    for pkg in "$@"; do
        if verify_package "$pkg"; then
            pass "$pkg installed"
        else
            fail "$pkg not found"
            failed=$((failed + 1))
        fi
    done
    
    return $failed
}

# Check service is running (if systemd available)
# Usage: verify_service "ssh"
# Returns: 0 if running, 1 if not
verify_service() {
    local service="$1"
    
    if [ -z "$service" ]; then
        echo_error "verify_service: missing service name"
        return 1
    fi
    
    # Try systemd first
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Fall back to service command
    if command -v service >/dev/null 2>&1; then
        if service "$service" status 2>/dev/null | grep -q "running"; then
            return 0
        fi
    fi
    
    return 1
}

# ============================================================================
# SYSTEM CHECKS
# ============================================================================

# Check if running on Hurd
# Returns: 0 if on Hurd, 1 if not
is_hurd() {
    if uname -a 2>/dev/null | grep -qi "GNU"; then
        return 0
    else
        return 1
    fi
}

# Check network connectivity
# Usage: check_connectivity 8.8.8.8
# Returns: 0 if reachable, 1 if not
check_connectivity() {
    local target="${1:-8.8.8.8}"
    
    if ping -c 1 -W 2 "$target" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Clean apt cache to free space
# Usage: apt_clean
apt_clean() {
    echo_info "Cleaning package cache..."
    apt-get clean || echo_warning "Cache cleanup failed"
    echo_success "Cache cleaned"
}

# Get installed package count
# Usage: pkg_count=$(count_packages)
count_packages() {
    dpkg -l 2>/dev/null | grep "^ii" | wc -l
}

# Get package size
# Usage: pkg_size=$(get_package_size "gcc")
get_package_size() {
    local package="$1"
    dpkg-query -W -f='${Installed-Size}\n' "$package" 2>/dev/null || echo "0"
}

# ============================================================================
# EXPORT FUNCTIONS for subshells
# ============================================================================
export -f check_root apt_init apt_update install_packages install_optional
export -f batch_install verify_package verify_command verify_commands
export -f verify_packages verify_service is_hurd check_connectivity
export -f apt_clean count_packages get_package_size 2>/dev/null || true
