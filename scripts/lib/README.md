# Script Libraries

Common functionality extracted from scripts to eliminate duplication and improve maintainability.

## Usage

Source the libraries you need at the beginning of your script:

```bash
#!/bin/bash
set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/ssh-helpers.sh"
source "$SCRIPT_DIR/lib/container-helpers.sh"

# Now use library functions
echo_info "Starting process..."
wait_for_ssh_port localhost 2222 600
ensure_container_running gnu-hurd-dev
echo_success "Complete!"
```

## Libraries

### colors.sh
**WHY:** Eliminate ~200 lines duplicated across 12+ scripts
**WHAT:** Standardized color output and test framework functions
**Functions:**
- `echo_info <message>` - Blue [INFO] prefix
- `echo_success <message>` - Green [SUCCESS] prefix
- `echo_error <message>` - Red [ERROR] prefix
- `echo_warning <message>` - Yellow [WARNING] prefix
- `step <message>` - Test step indicator
- `pass <message>` - Test pass marker (green checkmark)
- `fail <message>` - Test fail marker (red X)

### ssh-helpers.sh
**WHY:** Eliminate ~80 lines of SSH waiting logic across 5+ scripts
**WHAT:** SSH connection helpers with timeout and retry
**Functions:**
- `wait_for_ssh_port <host> <port> <timeout>` - Wait for SSH to become available
- `ssh_exec <host> <port> <password> <command>` - Execute command via SSH with sshpass

**Requirements:** `nc` (netcat), `sshpass` for ssh_exec

### container-helpers.sh
**WHY:** Eliminate duplicated Docker/QEMU checking across scripts
**WHAT:** Container and QEMU process management
**Functions:**
- `is_container_running <name>` - Check if container is running (returns 0/1)
- `ensure_container_running <name>` - Start container if not running
- `is_qemu_running` - Check if QEMU process exists
- `get_qemu_pid` - Get QEMU process ID

**Requirements:** `docker`, `pgrep`

### package-lists.sh
**WHY:** Eliminate 75% duplication across install-essentials-hurd.sh, install-hurd-packages.sh, setup-hurd-dev.sh
**WHAT:** Categorized package arrays for Debian GNU/Hurd (67 unique packages across 12 categories)
**Variables:**
- `MINIMAL_PKGS` - SSH, networking, basic tools (9 packages)
- `DEV_PKGS` - Core compilers, build tools, editors (19 packages)
- `COMPILERS_PKGS` - Clang, LLVM, and toolchains (5 packages)
- `LANGUAGES_PKGS` - Python, Perl, Ruby, Go, Java (8 packages)
- `HURD_PKGS` - GNU Mach, Hurd development, MIG (4 packages)
- `DEBUG_PKGS` - GDB, strace, profiling tools (5 packages)
- `BUILD_SYSTEMS_PKGS` - Meson, Ninja, Scons (3 packages)
- `DOC_TOOLS_PKGS` - Doxygen, Graphviz (4 packages)
- `NETTOOLS_PKGS` - curl, wget, htop, tmux (12 packages)
- `BROWSERS_PKGS` - Text and GUI browsers (5 packages)
- `X11_PKGS` - X11 server and tools (4 packages)
- `SYS_UTILS_PKGS` - zip, tree, less, rsync (11 packages)

**Usage:**
```bash
source "$SCRIPT_DIR/lib/package-lists.sh"
install_packages "Development Tools" "$DEV_PKGS"
```

### package-helpers.sh
**WHY:** Eliminate ~200 lines of duplicated apt error handling, DEBIAN_FRONTEND patterns, and verification code
**WHAT:** apt-get wrapper functions with error handling, progress reporting, and package verification
**Functions:**
- `check_root` - Verify script runs as root
- `apt_init` - Set non-interactive frontend
- `apt_update` - Update package lists with error handling
- `install_packages <phase> <packages>` - Install packages with progress (primary function)
- `install_optional <package>` - Install optional packages (warn on failure)
- `batch_install <phase> <packages>` - Batch install with per-package fallback
- `verify_package <package>` - Check if package is installed (dpkg)
- `verify_command <command>` - Check if command is in PATH
- `verify_commands <cmd1> <cmd2>` - Verify multiple commands
- `verify_packages <pkg1> <pkg2>` - Verify multiple packages
- `verify_service <service>` - Check if systemd service is running
- `is_hurd` - Detect GNU/Hurd system
- `check_connectivity <host>` - Test network reachability
- `apt_clean` - Clean apt cache
- `count_packages` - Get installed package count

**Usage:**
```bash
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/package-lists.sh"
source "$SCRIPT_DIR/lib/package-helpers.sh"

check_root || exit 1
apt_update || exit 1
install_packages "Phase 1: Essentials" "$MINIMAL_PKGS"
install_packages "Phase 2: Development" "$DEV_PKGS"
verify_commands gcc make git
```

## Benefits

- **Code Reduction:** ~400-500 lines eliminated from duplication
- **Maintainability:** Single source of truth for common patterns
- **Consistency:** Standardized behavior across all scripts
- **Testing:** Library functions can be unit tested in isolation
- **Documentation:** Centralized documentation for common operations

## Standards

All libraries follow these conventions:
- POSIX sh compatible (no bashisms unless necessary)
- Error handling: return non-zero on failure
- Exported functions for subshell usage
- WHY/WHAT/HOW documentation in headers
- No external dependencies beyond core utils (documented if needed)

## Future Libraries (Planned)

- **user-setup.sh** - User creation and sudo configuration
- **9p-helpers.sh** - 9p filesystem mounting utilities
- **download-helpers.sh** - Download with progress, checksum verification

## Migration Guide

When refactoring a script to use libraries:

1. Identify duplicated code matching library functions
2. Add library source statement at top of script
3. Replace inline code with library function calls
4. Test thoroughly
5. Remove old inline implementations
6. Update script documentation

Example migration:
```bash
# Before (inline)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# After (library)
source "$(dirname "$0")/lib/colors.sh"
```

## Testing

Test libraries in isolation:
```bash
# Test colors.sh
source lib/colors.sh
echo_info "This is info"
echo_success "This is success"
echo_error "This is error"
echo_warning "This is warning"

# Test ssh-helpers.sh
source lib/ssh-helpers.sh
wait_for_ssh_port localhost 2222 10  # Should timeout
wait_for_ssh_port localhost 22 5     # Should succeed (if SSH running)

# Test container-helpers.sh
source lib/container-helpers.sh
is_container_running gnu-hurd-dev && echo "Running" || echo "Not running"
ensure_container_running gnu-hurd-dev
```
