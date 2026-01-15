#!/bin/bash
set -euo pipefail

# =============================================================================
# GNU/Hurd Libvirt Domain Manager
# =============================================================================
# PURPOSE:
# - Provide unified interface for libvirt domain management
# - Auto-detect libvirt availability
# - Manage domain lifecycle (define, start, stop, console)
# - Handle SSH port forwarding and port mapping
# - Graceful error handling with helpful messages
#
# REQUIREMENTS:
# - libvirt daemon (libvirtd) running
# - virsh command available
# - Optional: virt-manager for graphical management
# - KVM support (nested if running in VM) OR QEMU/TCG fallback
#
# USAGE:
#   ./scripts/libvirt-hurd.sh define       # Define domain from template
#   ./scripts/libvirt-hurd.sh start        # Start the domain
#   ./scripts/libvirt-hurd.sh stop         # Stop the domain
#   ./scripts/libvirt-hurd.sh console      # Connect to console (virsh console)
#   ./scripts/libvirt-hurd.sh ssh          # SSH to domain (via port 2222)
#   ./scripts/libvirt-hurd.sh status       # Show domain status
#   ./scripts/libvirt-hurd.sh info         # Show detailed domain info
#   ./scripts/libvirt-hurd.sh undefine     # Remove domain definition
#
# ENVIRONMENT VARIABLES:
#   DOMAIN_NAME     - Libvirt domain name (default: gnu-hurd-dev)
#   CONFIG_PATH     - Path to domain XML template (default: config/libvirt/)
#   IMAGE_PATH      - Path to disk image (default: /var/lib/libvirt/images/)
#   SSH_PORT        - SSH forwarding port (default: 2222)
#   HTTP_PORT       - HTTP forwarding port (default: 8080)
#   ENABLE_KVM      - Force KVM mode (default: auto-detect)
#   CONSOLE_TYPE    - Console type: serial or vnc (default: serial)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../" && pwd)"
cd "$REPO_ROOT"

# Configuration
DOMAIN_NAME="${DOMAIN_NAME:-gnu-hurd-dev}"
CONFIG_PATH="${CONFIG_PATH:-${REPO_ROOT}/config/libvirt}"
IMAGE_PATH="${IMAGE_PATH:-/var/lib/libvirt/images}"
SSH_PORT="${SSH_PORT:-2222}"
HTTP_PORT="${HTTP_PORT:-8080}"
ENABLE_KVM="${ENABLE_KVM:-auto}"
CONSOLE_TYPE="${CONSOLE_TYPE:-serial}"

# Color output (simple fallback)
echo_info() { echo "[INFO] $*"; }
echo_success() { echo "[SUCCESS] $*"; }
echo_warning() { echo "[WARNING] $*" >&2; }
echo_error() { echo "[ERROR] $*" >&2; }

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_libvirt() {
    if ! command -v virsh >/dev/null 2>&1; then
        echo_error "virsh not found. Please install libvirt."
        echo_error "Arch/CachyOS: sudo pacman -S libvirt"
        echo_error "Ubuntu/Debian: sudo apt install libvirt-bin"
        echo_error "Fedora/RHEL: sudo dnf install libvirt"
        exit 1
    fi

    # Check if libvirtd is running
    if ! systemctl is-active --quiet libvirtd 2>/dev/null; then
        echo_warning "libvirtd daemon not running. Attempting to start..."
        if ! sudo systemctl start libvirtd 2>/dev/null; then
            echo_error "Cannot start libvirtd. Ensure you have sudo access."
            echo_error "Try: sudo systemctl start libvirtd"
            exit 1
        fi
    fi

    echo_success "libvirtd is running"
}

check_qemu() {
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        echo_error "qemu-system-x86_64 not found. Please install QEMU."
        echo_error "Arch/CachyOS: sudo pacman -S qemu-system-x86"
        echo_error "Ubuntu/Debian: sudo apt install qemu-system-x86"
        echo_error "Fedora/RHEL: sudo dnf install qemu-system-x86"
        exit 1
    fi

    echo_success "QEMU is available"
}

check_disk_image() {
    if [[ ! -f "${IMAGE_PATH}/debian-hurd-amd64.qcow2" ]]; then
        echo_error "Disk image not found: ${IMAGE_PATH}/debian-hurd-amd64.qcow2"
        echo_info "To download: ./scripts/download-image.sh"
        exit 1
    fi

    echo_success "Disk image found: ${IMAGE_PATH}/debian-hurd-amd64.qcow2"
}

check_domain_xml() {
    if [[ ! -f "${CONFIG_PATH}/${DOMAIN_NAME}.xml" ]]; then
        # Try fallback name
        if [[ ! -f "${CONFIG_PATH}/gnu-hurd.xml" ]]; then
            echo_error "Domain XML template not found in ${CONFIG_PATH}/"
            exit 1
        fi
        CONFIG_PATH="${CONFIG_PATH}"
    fi

    echo_success "Domain XML found: ${CONFIG_PATH}/${DOMAIN_NAME}.xml or ${CONFIG_PATH}/gnu-hurd.xml"
}

# =============================================================================
# Utility Functions
# =============================================================================

domain_exists() {
    virsh list --all 2>/dev/null | grep -q "$DOMAIN_NAME"
}

domain_running() {
    virsh list --running 2>/dev/null | grep -q "$DOMAIN_NAME"
}

get_domain_ip() {
    # Slirp networking uses static IP 10.0.2.15
    echo "10.0.2.15"
}

# =============================================================================
# Core Commands
# =============================================================================

cmd_define() {
    echo_info "Defining libvirt domain from template..."

    check_libvirt
    check_qemu
    check_disk_image

    # Select XML file (prefer specific name, fall back to generic)
    local xml_file="${CONFIG_PATH}/gnu-hurd.xml"
    [[ -f "${CONFIG_PATH}/${DOMAIN_NAME}.xml" ]] && xml_file="${CONFIG_PATH}/${DOMAIN_NAME}.xml"

    if ! [[ -f "$xml_file" ]]; then
        echo_error "Domain XML not found: $xml_file"
        exit 1
    fi

    echo_info "Using domain template: $xml_file"

    if domain_exists; then
        echo_warning "Domain '${DOMAIN_NAME}' already exists"
        echo_info "To redefine, run: virsh undefine ${DOMAIN_NAME}"
        return 0
    fi

    # Create libvirt images directory if needed
    if [[ ! -d "$IMAGE_PATH" ]]; then
        echo_info "Creating libvirt images directory: ${IMAGE_PATH}"
        sudo mkdir -p "$IMAGE_PATH"
    fi

    # Define domain
    if virsh define "$xml_file"; then
        echo_success "Domain '${DOMAIN_NAME}' defined successfully"
        echo_info "Next: ./scripts/libvirt-hurd.sh start"
        return 0
    else
        echo_error "Failed to define domain"
        exit 1
    fi
}

cmd_start() {
    echo_info "Starting domain '${DOMAIN_NAME}'..."

    check_libvirt

    if ! domain_exists; then
        echo_error "Domain '${DOMAIN_NAME}' not defined"
        echo_info "Run: ./scripts/libvirt-hurd.sh define"
        exit 1
    fi

    if domain_running; then
        echo_warning "Domain is already running"
        return 0
    fi

    if virsh start "$DOMAIN_NAME"; then
        echo_success "Domain started"
        echo_info "Waiting for boot (30-60 seconds with KVM, 3-5 minutes with TCG)..."
        sleep 5

        echo_info "Access methods:"
        echo "  - Serial console: virsh console ${DOMAIN_NAME}"
        echo "  - SSH (port ${SSH_PORT}): ssh -p ${SSH_PORT} root@localhost"
        echo "  - HTTP (port ${HTTP_PORT}): http://localhost:${HTTP_PORT}"
        return 0
    else
        echo_error "Failed to start domain"
        exit 1
    fi
}

cmd_stop() {
    echo_info "Stopping domain '${DOMAIN_NAME}'..."

    check_libvirt

    if ! domain_exists; then
        echo_error "Domain '${DOMAIN_NAME}' not defined"
        exit 1
    fi

    if ! domain_running; then
        echo_warning "Domain is not running"
        return 0
    fi

    if virsh shutdown "$DOMAIN_NAME"; then
        echo_info "Shutdown initiated, waiting..."
        sleep 3

        # If still running after shutdown, force stop
        if domain_running; then
            echo_info "Graceful shutdown timeout, forcing stop..."
            virsh destroy "$DOMAIN_NAME"
        fi

        echo_success "Domain stopped"
        return 0
    else
        echo_error "Failed to stop domain"
        exit 1
    fi
}

cmd_console() {
    echo_info "Connecting to domain console..."

    check_libvirt

    if ! domain_exists; then
        echo_error "Domain '${DOMAIN_NAME}' not defined"
        exit 1
    fi

    if ! domain_running; then
        echo_error "Domain is not running"
        echo_info "Start it: ./scripts/libvirt-hurd.sh start"
        exit 1
    fi

    case "$CONSOLE_TYPE" in
        serial)
            echo_info "Connecting to serial console (Ctrl+] to exit)..."
            virsh console "$DOMAIN_NAME" || true
            ;;
        vnc)
            echo_info "VNC console available on 127.0.0.1"
            if command -v virt-manager >/dev/null 2>&1; then
                virt-manager --connect qemu:///system --show-console "$DOMAIN_NAME" &
            else
                echo_info "virt-manager not found for graphical display"
                echo_info "Use: virsh edit ${DOMAIN_NAME} to find VNC port"
            fi
            ;;
        *)
            echo_error "Unknown console type: $CONSOLE_TYPE"
            exit 1
            ;;
    esac
}

cmd_ssh() {
    echo_info "Connecting via SSH..."

    if ! domain_running; then
        echo_error "Domain is not running"
        echo_info "Start it: ./scripts/libvirt-hurd.sh start"
        exit 1
    fi

    echo_info "SSH host: localhost"
    echo_info "SSH port: ${SSH_PORT}"
    echo_info "SSH user: root"

    ssh -p "$SSH_PORT" root@localhost "$@" || true
}

cmd_status() {
    echo_info "Domain status:"

    check_libvirt

    if ! domain_exists; then
        echo_warning "Domain '${DOMAIN_NAME}' not defined"
        return 1
    fi

    virsh dominfo "$DOMAIN_NAME" || true
}

cmd_info() {
    echo_info "Domain information:"

    check_libvirt

    if ! domain_exists; then
        echo_error "Domain '${DOMAIN_NAME}' not defined"
        exit 1
    fi

    if domain_running; then
        echo_success "Domain is RUNNING"
    else
        echo_warning "Domain is STOPPED"
    fi

    echo ""
    echo "=== Domain Info ==="
    virsh dominfo "$DOMAIN_NAME" || true

    echo ""
    echo "=== Port Forwarding ==="
    echo "SSH:  localhost:${SSH_PORT} -> domain:22"
    echo "HTTP: localhost:${HTTP_PORT} -> domain:80"

    echo ""
    echo "=== Access Methods ==="
    if domain_running; then
        echo "Serial console: virsh console ${DOMAIN_NAME}"
        echo "SSH: ssh -p ${SSH_PORT} root@localhost"
        echo "VNC: localhost (check virsh edit ${DOMAIN_NAME} for port)"
    else
        echo "[Domain not running]"
    fi
}

cmd_undefine() {
    echo_warning "Undefining domain '${DOMAIN_NAME}'..."

    check_libvirt

    if ! domain_exists; then
        echo_warning "Domain is not defined"
        return 0
    fi

    if domain_running; then
        echo_info "Domain is still running, stopping first..."
        cmd_stop
    fi

    read -p "Are you sure? This removes the domain definition (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_info "Cancelled"
        return 0
    fi

    if virsh undefine "$DOMAIN_NAME"; then
        echo_success "Domain undefined"
        return 0
    else
        echo_error "Failed to undefine domain"
        exit 1
    fi
}

cmd_help() {
    cat << 'EOF'
GNU/Hurd Libvirt Domain Manager

USAGE:
  ./scripts/libvirt-hurd.sh [COMMAND] [OPTIONS]

COMMANDS:
  define          Define domain from template (one-time setup)
  start           Start the domain
  stop            Stop the domain
  console         Connect to serial console
  ssh [args]      SSH to domain (pass args to ssh command)
  status          Show domain status
  info            Show detailed domain information
  undefine        Remove domain definition

ENVIRONMENT VARIABLES:
  DOMAIN_NAME     Domain name (default: gnu-hurd-dev)
  CONFIG_PATH     Path to domain XML (default: config/libvirt/)
  IMAGE_PATH      Path to disk image (default: /var/lib/libvirt/images/)
  SSH_PORT        SSH port (default: 2222)
  HTTP_PORT       HTTP port (default: 8080)
  CONSOLE_TYPE    Console type: serial or vnc (default: serial)

EXAMPLES:
  # One-time setup
  ./scripts/libvirt-hurd.sh define
  ./scripts/libvirt-hurd.sh start

  # Regular usage
  ./scripts/libvirt-hurd.sh console    # Access via serial
  ./scripts/libvirt-hurd.sh ssh        # SSH connection
  ./scripts/libvirt-hurd.sh status     # Check status

  # Cleanup
  ./scripts/libvirt-hurd.sh stop
  ./scripts/libvirt-hurd.sh undefine

REQUIREMENTS:
  - libvirt daemon (libvirtd)
  - virsh command available
  - QEMU installed
  - Debian GNU/Hurd disk image

SEE ALSO:
  - docs/02-ARCHITECTURE/libvirt/LIBVIRT-GUIDE.md
  - config/libvirt/gnu-hurd.xml
  - ./scripts/download-image.sh
EOF
}

# =============================================================================
# Main Dispatch
# =============================================================================

main() {
    local cmd="${1:-help}"

    case "$cmd" in
        define)
            cmd_define
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        console)
            cmd_console
            ;;
        ssh)
            shift || true
            cmd_ssh "$@"
            ;;
        status)
            cmd_status
            ;;
        info)
            cmd_info
            ;;
        undefine)
            cmd_undefine
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            echo_error "Unknown command: $cmd"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
