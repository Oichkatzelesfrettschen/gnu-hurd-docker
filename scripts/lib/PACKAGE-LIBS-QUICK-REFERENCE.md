# Package Libraries - Quick Reference

Fast lookup for common tasks using package-lists.sh and package-helpers.sh.

## Installation

### Step 1: Source the Libraries

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/package-lists.sh"
source "$SCRIPT_DIR/lib/package-helpers.sh"
```

### Step 2: Check Prerequisites

```bash
check_root || exit 1
apt_update || exit 1
```

### Step 3: Install Packages

```bash
# Install a predefined category
install_packages "Phase 1: Essentials" "$MINIMAL_PKGS"
install_packages "Phase 2: Development" "$DEV_PKGS"
install_packages "Phase 3: Hurd" "$HURD_PKGS"

# Or install custom list
install_packages "Phase 4: Custom" "pkg1 pkg2 pkg3"
```

## Common Patterns

### Install Everything

```bash
install_packages "Core Development" "$DEV_PKGS"
install_packages "Compilers" "$COMPILERS_PKGS"
install_packages "Languages" "$LANGUAGES_PKGS"
install_packages "Hurd Development" "$HURD_PKGS"
install_packages "Debugging Tools" "$DEBUG_PKGS"
install_packages "Build Systems" "$BUILD_SYSTEMS_PKGS"
```

### Install Minimal + Dev

```bash
install_packages "Essentials" "$MINIMAL_PKGS"
install_packages "Development" "$DEV_PKGS"
```

### Install with GUI

```bash
install_packages "Essentials" "$MINIMAL_PKGS"
install_packages "X11" "$X11_PKGS"
install_packages "Desktop" "$X11_DESKTOP_PKGS"
install_packages "GUI Apps" "$GUI_APPS_PKGS"
```

### Optional Packages

```bash
# Non-critical, continue on failure
install_optional "ruby-full"
install_optional "golang"
install_optional "firefox-esr"
```

### Batch Install with Fallback

```bash
# Try batch first, fall back to per-package on failure
batch_install "Languages" "$LANGUAGES_PKGS"
```

## Verification

### Check Specific Commands

```bash
# Single command
if verify_command gcc; then
    echo_success "GCC available"
fi

# Multiple commands
verify_commands gcc g++ make cmake git vim
```

### Check Installed Packages

```bash
# Single package
if verify_package build-essential; then
    echo_success "build-essential installed"
fi

# Multiple packages
verify_packages gcc g++ make autoconf automake
```

### Check Service Status

```bash
if verify_service ssh; then
    echo_success "SSH running"
else
    echo_warning "SSH not running"
fi
```

## System Detection

### Check if Hurd

```bash
if is_hurd; then
    echo_info "Running on GNU/Hurd"
else
    echo_warning "Not on Hurd"
fi
```

### Check Network

```bash
if check_connectivity 8.8.8.8; then
    echo_success "Internet available"
else
    echo_error "No internet"
fi
```

## Diagnostics

### Get Package Statistics

```bash
# Count installed packages
count=$(count_packages)
echo_info "Total packages installed: $count"

# Get single package size
size=$(get_package_size gcc)
echo_info "GCC size: $size KB"
```

### Clean Cache

```bash
apt_clean
```

## Available Package Categories

```
MINIMAL_PKGS          SSH, curl, wget, git, vim, nano
NETTOOLS_PKGS         net-tools, dnsutils, telnet, nc, htop, tmux
BROWSERS_PKGS         lynx, w3m, links, firefox
DEV_PKGS              gcc, g++, make, cmake, git, vim, emacs
COMPILERS_PKGS        clang, llvm, lld
LANGUAGES_PKGS        python3, perl, ruby, golang, java
HURD_PKGS             gnumach-dev, hurd-dev, mig
DEBUG_PKGS            gdb, strace, ltrace, valgrind
BUILD_SYSTEMS_PKGS    meson, ninja, scons
DOC_TOOLS_PKGS        doxygen, graphviz
X11_PKGS              xorg, xterm, xinit
X11_DESKTOP_PKGS      xfce4, xfce4-goodies
SYS_UTILS_PKGS        zip, unzip, tree, rsync, screen
```

## Output Functions (from colors.sh)

```bash
echo_info "Blue [INFO] message"
echo_success "Green [SUCCESS] message"
echo_warning "Yellow [WARNING] message"
echo_error "Red [ERROR] message"
```

## Error Handling

### Check Function Return Value

```bash
if install_packages "Dev Tools" "$DEV_PKGS"; then
    echo_success "Installation succeeded"
else
    echo_error "Installation failed"
    exit 1
fi
```

### Handle Optional Failures

```bash
# Install optional package, continue on failure
install_optional "golang" || echo_warning "Go skipped"
```

### Check Multiple Conditions

```bash
check_root || { echo_error "Need root"; exit 1; }
apt_update || { echo_error "apt-get failed"; exit 1; }
install_packages "Core" "$DEV_PKGS" || { echo_error "Install failed"; exit 1; }
```

## Example Scripts

### Minimal Hurd Setup

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/package-lists.sh"
source "$SCRIPT_DIR/lib/package-helpers.sh"

echo_info "Minimal Hurd Setup"
check_root || exit 1

apt_update || exit 1
install_packages "Essentials" "$MINIMAL_PKGS"
install_packages "Development" "$DEV_PKGS"

verify_commands gcc make git

echo_success "Setup complete!"
```

### Development Environment

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/package-lists.sh"
source "$SCRIPT_DIR/lib/package-helpers.sh"

echo_info "Full Development Environment"
check_root || exit 1

apt_update || exit 1

install_packages "Phase 1: Essentials" "$MINIMAL_PKGS"
install_packages "Phase 2: Core Dev" "$DEV_PKGS"
install_packages "Phase 3: Compilers" "$COMPILERS_PKGS"
install_packages "Phase 4: Languages" "$LANGUAGES_PKGS"
install_packages "Phase 5: Hurd" "$HURD_PKGS"
install_packages "Phase 6: Debug" "$DEBUG_PKGS"
install_packages "Phase 7: Build" "$BUILD_SYSTEMS_PKGS"
install_packages "Phase 8: Tools" "$DOC_TOOLS_PKGS"

# Verify critical tools
verify_commands gcc g++ make cmake git gdb

echo_success "Development environment ready!"
```

### Interactive Setup with Optional GUI

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/package-lists.sh"
source "$SCRIPT_DIR/lib/package-helpers.sh"

check_root || exit 1
apt_update || exit 1

# Core installation
install_packages "Essentials" "$MINIMAL_PKGS"
install_packages "Development" "$DEV_PKGS"

# Optional GUI
read -p "Install GUI? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    install_packages "X11" "$X11_PKGS"
    install_packages "Desktop" "$X11_DESKTOP_PKGS"
    install_optional "firefox-esr"
fi

echo_success "Installation complete!"
```

## Troubleshooting

### Package Not Available

```bash
# Use install_optional for optional packages
install_optional "golang" || echo_warning "Not available"

# Check what's available
apt-cache search golang | head -5
```

### Installation Failed

```bash
# Check internet connectivity
check_connectivity 8.8.8.8 || echo_error "No internet"

# Check apt sources
cat /etc/apt/sources.list

# Try manual apt-get
apt-get update
apt-get install -y package-name
```

### Verification Issues

```bash
# Verify command is in PATH
which gcc
command -v gcc

# Check installed package
dpkg -l | grep gcc

# Get package info
dpkg-query -W gcc
```

## Performance Tips

### Update Once, Install Many

```bash
# apt_update is called automatically on first install_packages
apt_update  # Manual update if needed

# Subsequent installs skip updating
install_packages "Phase 1" "$DEV_PKGS"
install_packages "Phase 2" "$LANGUAGES_PKGS"
# No redundant apt-update calls
```

### Use Batch Install for Groups

```bash
# Better: Batch install tries all at once
batch_install "Languages" "$LANGUAGES_PKGS"

# vs individual installs (slower)
for pkg in $LANGUAGES_PKGS; do
    install_optional "$pkg"
done
```

### Clean Cache When Done

```bash
# Free space after large installations
apt_clean
```

## Testing Libraries

```bash
# Run test suite
/home/eirikr/Playground/gnu-hurd-docker/scripts/lib/test-package-libs.sh

# Test individual functions
source scripts/lib/colors.sh
source scripts/lib/package-helpers.sh

echo_info "Testing verify_command"
verify_command bash && echo_success "bash found" || echo_error "bash not found"
```

## Reference

- **Full Docs:** PACKAGE-LIBS-ANALYSIS.md
- **Library README:** scripts/lib/README.md
- **Test Suite:** scripts/lib/test-package-libs.sh
- **Source:** scripts/lib/package-lists.sh, scripts/lib/package-helpers.sh
