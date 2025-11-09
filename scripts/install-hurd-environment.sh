#!/bin/bash
# install-hurd-environment.sh - Unified GNU/Hurd Environment Installer
#
# WHY: Eliminate 75% duplication across 3 install scripts (510 lines saved)
#      - install-essentials-hurd.sh (310 LOC)
#      - install-hurd-packages.sh (231 LOC)
#      - setup-hurd-dev.sh (143 LOC)
#
# WHAT: Unified installer with --minimal, --dev, --gui, --full modes
#       Uses package-lists.sh (12 categories, 67 packages) and
#       package-helpers.sh (17 helper functions) for consistent installation
#
# HOW: Source package libraries, parse arguments, install categorized packages,
#      configure system (SSH, aliases, MOTD), verify installation, report summary

set -euo pipefail

# ============================================================================
# LIBRARY IMPORTS
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/colors.sh
source "$SCRIPT_DIR/lib/colors.sh"
# shellcheck source=lib/package-lists.sh
source "$SCRIPT_DIR/lib/package-lists.sh"
# shellcheck source=lib/package-helpers.sh
source "$SCRIPT_DIR/lib/package-helpers.sh"

# ============================================================================
# USAGE AND HELP
# ============================================================================

usage() {
    cat << 'EOF'
Usage: install-hurd-environment.sh [OPTIONS]

Install GNU/Hurd packages in various configurations.

OPTIONS:
    --minimal       SSH, networking, basic tools (~50 packages)
    --dev           Minimal + compilers, build tools, Hurd dev packages (~150 packages)
    --gui           Dev + X11, Xfce, browsers (~300 packages)
    --full          Everything including optional languages and tools (~400 packages)
    --help          Show this help message

EXAMPLES:
    install-hurd-environment.sh --minimal    # Quick setup for SSH access
    install-hurd-environment.sh --dev        # Complete development environment
    install-hurd-environment.sh --gui        # Full desktop environment
    install-hurd-environment.sh --full       # Everything

DEFAULT: --dev if no option specified

PACKAGE CATEGORIES:
    Minimal:  SSH, networking, text editors, basic utilities
    Dev:      Compilers (GCC, Clang), build tools (Make, CMake), debuggers (GDB),
              Hurd development (gnumach-dev, hurd-dev, mig), version control (Git)
    GUI:      X11, Xfce desktop, Firefox, text browsers, development IDEs
    Full:     Everything + additional languages (Ruby, Go, Java), optional tools

MODES:
    minimal = MINIMAL_PKGS + NETTOOLS_PKGS + ENTROPY_PKGS + SYS_UTILS_PKGS
    dev     = minimal + DEV_PKGS + COMPILERS_PKGS + HURD_PKGS + DEBUG_PKGS +
              BUILD_SYSTEMS_PKGS + DOC_TOOLS_PKGS + BROWSERS_PKGS (text only)
    gui     = dev + X11_PKGS + X11_DESKTOP_PKGS + GUI_DEV_TOOLS_PKGS + GUI_APPS_PKGS
    full    = gui + LANGUAGES_PKGS (Python, Perl, Ruby, Go, Java)

DISK SPACE:
    minimal: ~500 MB
    dev:     ~1.5 GB
    gui:     ~3.5 GB
    full:    ~4.5 GB
EOF
}

# ============================================================================
# INSTALLATION MODES
# ============================================================================

install_minimal() {
    echo_info "INSTALLATION MODE: Minimal (SSH + networking + basic tools)"
    
    # shellcheck disable=SC2086  # Intentional word splitting for package lists
    install_packages "SSH and Entropy" $MINIMAL_PKGS $ENTROPY_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "Network Tools" $NETTOOLS_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "System Utilities" $SYS_UTILS_PKGS || return 1
    
    configure_ssh
    return 0
}

install_dev() {
    echo_info "INSTALLATION MODE: Development (Minimal + compilers + Hurd dev)"
    
    install_minimal || return 1
    
    # shellcheck disable=SC2086  # Intentional word splitting for package lists
    install_packages "Development Tools" $DEV_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "Compilers and Toolchains" $COMPILERS_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "Hurd Development" $HURD_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "Debugging Tools" $DEBUG_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "Build Systems" $BUILD_SYSTEMS_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "Documentation Tools" $DOC_TOOLS_PKGS || return 1
    
    # Text browsers only (no GUI)
    batch_install "Text Browsers" "lynx w3m links elinks"
    
    configure_dev_environment
    return 0
}

install_gui() {
    echo_info "INSTALLATION MODE: GUI (Dev + X11 + Xfce desktop)"
    
    install_dev || return 1
    
    # shellcheck disable=SC2086  # Intentional word splitting for package lists
    install_packages "X11 Core" $X11_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "Xfce Desktop" $X11_DESKTOP_PKGS || return 1
    # shellcheck disable=SC2086
    install_packages "GUI Development Tools" $GUI_DEV_TOOLS_PKGS || return 1
    
    # GUI applications (Firefox, GIMP) - install optionally
    batch_install "GUI Applications" "$GUI_APPS_PKGS"
    
    configure_gui_environment
    return 0
}

install_full() {
    echo_info "INSTALLATION MODE: Full (Everything + additional languages)"
    
    install_gui || return 1
    
    # Additional programming languages (install individually for better error handling)
    batch_install "Programming Languages" "$LANGUAGES_PKGS"
    
    echo_success "Full installation complete!"
    return 0
}

# ============================================================================
# SYSTEM CONFIGURATION
# ============================================================================

configure_ssh() {
    echo ""
    echo_info "Configuring SSH server..."
    
    # Enable root login (change if needed)
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' \
        /etc/ssh/sshd_config 2>/dev/null || true
    
    # Set root password if not set
    if ! passwd -S root 2>/dev/null | grep -q "P"; then
        echo_warning "Root password not set. Setting to 'root'..."
        echo "root:root" | chpasswd
        echo_info "  Password: root (CHANGE THIS: passwd)"
    fi
    
    # Start SSH service
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable ssh 2>/dev/null || true
        systemctl restart ssh 2>/dev/null || true
    else
        service ssh restart 2>/dev/null || true
    fi
    
    echo_success "SSH server configured"
}

configure_dev_environment() {
    echo ""
    echo_info "Configuring development environment..."
    
    # Create development directories
    mkdir -p /home/*/workspace /home/*/projects /usr/local/src 2>/dev/null || true
    
    # Add development aliases
    for home_dir in /home/*/ /root/; do
        if [ -d "$home_dir" ]; then
            if ! grep -q "# GNU/Hurd Development Aliases" "${home_dir}.bashrc" 2>/dev/null; then
                cat >> "${home_dir}.bashrc" << 'BASHRC_EOF'

# GNU/Hurd Development Aliases
alias ll='ls -alF'
alias la='ls -A'
alias gs='git status'
alias gl='git log --oneline -10'
alias update='apt-get update && apt-get upgrade'
alias install='apt-get install'
alias search='apt-cache search'
BASHRC_EOF
            fi
        fi
    done
    
    # Configure 9p mount for Docker host sharing
    if ! grep -q "/mnt/host" /etc/fstab 2>/dev/null; then
        mkdir -p /mnt/host
        cat >> /etc/fstab << 'FSTAB_EOF'
# 9p filesystem sharing from Docker host
scripts /mnt/host 9p trans=virtio,version=9p2000.L,nofail 0 0
FSTAB_EOF
    fi
    
    echo_success "Development environment configured"
}

configure_gui_environment() {
    echo ""
    echo_info "Configuring GUI environment..."
    
    # Create .xinitrc for easy X11 startup
    for home_dir in /home/*/ /root/; do
        if [ -d "$home_dir" ]; then
            cat > "${home_dir}.xinitrc" << 'XINITRC_EOF'
#!/bin/sh
exec startxfce4
XINITRC_EOF
            chmod +x "${home_dir}.xinitrc"
        fi
    done
    
    echo_success "GUI environment configured"
    echo_info "  Start Xfce: startxfce4"
}

create_motd() {
    echo ""
    echo_info "Creating login banner..."
    
    cat > /etc/motd << 'MOTD_EOF'
================================================================
  Debian GNU/Hurd 2025 Development Environment
================================================================

Quick Commands:
  apt-get update && apt-get upgrade   # Update system
  apt-cache search <term>             # Search packages
  lynx https://www.gnu.org            # Web browser
  startxfce4                          # Start GUI (if installed)

Installed Components:
  SSH Server, Network Tools, Development Tools
  GCC, Clang, Make, CMake, Git, GDB
  Hurd Development Packages (gnumach-dev, hurd-dev, mig)

Documentation: /usr/share/doc/gnu-hurd-docker/

MOTD_EOF
    
    echo_success "Login banner created"
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_installation() {
    echo ""
    echo_info "Verifying installation..."
    echo ""
    
    local failed=0
    
    # Check SSH service
    if verify_service ssh; then
        pass "SSH server running"
    else
        fail "SSH server not running"
        failed=$((failed + 1))
    fi
    
    # Check essential commands
    step "Verifying essential commands..."
    verify_commands curl wget git vim || failed=$((failed + 1))
    
    # Check compilers if dev mode or higher
    if [ "$MODE" != "minimal" ]; then
        step "Verifying compilers..."
        verify_commands gcc make cmake || failed=$((failed + 1))
    fi
    
    # Check Hurd tools if dev mode or higher
    if [ "$MODE" != "minimal" ]; then
        step "Verifying Hurd development tools..."
        verify_commands mig || failed=$((failed + 1))
    fi
    
    # Check GUI if gui mode
    if [ "$MODE" = "gui" ] || [ "$MODE" = "full" ]; then
        step "Verifying GUI components..."
        verify_commands startx startxfce4 || failed=$((failed + 1))
    fi
    
    echo ""
    if [ $failed -eq 0 ]; then
        echo_success "All verifications passed!"
        return 0
    else
        echo_warning "$failed verification(s) failed"
        return 1
    fi
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================

print_summary() {
    local pkg_count
    pkg_count=$(count_packages)
    
    echo ""
    echo "================================================================"
    echo "  Installation Complete!"
    echo "================================================================"
    echo ""
    echo_success "Installation Mode: $MODE"
    echo_success "Total Packages Installed: $pkg_count"
    echo ""
    
    case "$MODE" in
        minimal)
            echo "Installed Components:"
            echo "  SSH Server (openssh-server, random-egd)"
            echo "  Network Tools (curl, wget, ping, traceroute)"
            echo "  System Utilities (vim, git, htop, screen)"
            ;;
        dev)
            echo "Installed Components:"
            echo "  Everything in Minimal +"
            echo "  Compilers (GCC, Clang, LLVM)"
            echo "  Build Tools (Make, CMake, Autotools)"
            echo "  Hurd Development (gnumach-dev, hurd-dev, mig)"
            echo "  Debuggers (GDB, strace, ltrace)"
            echo "  Text Browsers (lynx, w3m, links)"
            ;;
        gui)
            echo "Installed Components:"
            echo "  Everything in Dev +"
            echo "  X11 Window System"
            echo "  Xfce Desktop Environment"
            echo "  GUI Applications (Firefox, GIMP)"
            echo "  Development IDEs (Emacs, Geany)"
            ;;
        full)
            echo "Installed Components:"
            echo "  Everything in GUI +"
            echo "  Programming Languages (Python, Perl, Ruby, Go, Java)"
            ;;
    esac
    
    echo ""
    echo "Next Steps:"
    echo "  1. Test SSH: ssh -p 2222 root@localhost"
    
    if [ "$MODE" != "minimal" ]; then
        echo "  2. Test compilation: echo 'int main(){return 0;}' > test.c && gcc test.c"
        echo "  3. Mount shared filesystem: mount /mnt/host"
    fi
    
    if [ "$MODE" = "gui" ] || [ "$MODE" = "full" ]; then
        echo "  4. Start GUI: startxfce4"
    fi
    
    echo ""
    echo "Configuration:"
    echo "  Bash aliases added to ~/.bashrc (source ~/.bashrc to load)"
    echo "  9p mount point: /mnt/host"
    echo "  Development directories: ~/workspace, ~/projects"
    echo ""
    echo "================================================================"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Parse arguments
    MODE="${1:-dev}"
    
    case "$MODE" in
        --minimal|minimal)
            MODE="minimal"
            ;;
        --dev|dev)
            MODE="dev"
            ;;
        --gui|gui)
            MODE="gui"
            ;;
        --full|full)
            MODE="full"
            ;;
        --help|-h|help)
            usage
            exit 0
            ;;
        *)
            echo_error "Invalid option: $MODE"
            echo ""
            usage
            exit 1
            ;;
    esac
    
    # Print banner
    echo ""
    echo "================================================================"
    echo "  Debian GNU/Hurd 2025 - Environment Installer"
    echo "================================================================"
    echo ""
    
    # Check prerequisites
    check_root || exit 1
    
    if ! is_hurd; then
        echo_warning "This doesn't appear to be GNU/Hurd. Continuing anyway..."
    fi
    
    # Initialize apt
    apt_init
    apt_update || exit 1
    
    # Execute installation based on mode
    case "$MODE" in
        minimal)
            install_minimal || exit 1
            ;;
        dev)
            install_dev || exit 1
            ;;
        gui)
            install_gui || exit 1
            ;;
        full)
            install_full || exit 1
            ;;
    esac
    
    # Post-installation configuration
    create_motd
    
    # Clean up
    apt_clean
    
    # Verification
    verify_installation
    
    # Summary
    print_summary
}

# Execute main function
main "$@"
