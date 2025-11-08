pkgname=gnu-hurd-docker
pkgver=2.0.0
pkgrel=1
pkgdesc="GNU/Hurd x86_64 microkernel in QEMU within Docker - Complete development environment"
arch=('x86_64' 'i686')
url="https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker"
license=('MIT')
depends=(
    'docker>=20.10'
    'docker-compose>=1.29'
    'qemu-base>=7.0'
    'python>=3.7'
)
makedepends=(
    'git'
    'shellcheck'
)
optdepends=(
    'qemu-system-x86-64: For running QEMU outside Docker'
    'qemu-img: For manual image manipulation'
    'cloud-image-utils: For cloud-init seed creation'
    'socat: For QMP/monitor socket control'
    'screen: For serial console access'
    'telnet: For serial console access (alternative)'
    'openssh: For SSH access to guest'
    'linux-headers: For KVM module compilation (if needed)'
)
provides=('gnu-hurd-docker')
conflicts=('gnu-hurd-docker-kernel-fix')
replaces=('gnu-hurd-docker-kernel-fix')
backup=(
    'etc/gnu-hurd-docker/docker-compose.yml'
    'etc/gnu-hurd-docker/entrypoint.sh'
)
install='gnu-hurd-docker.install'
source=(
    "git+https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git#tag=v${pkgver}"
)
sha256sums=('SKIP')

build() {
    cd "${srcdir}/gnu-hurd-docker"
    
    echo "=== Building GNU/Hurd Docker Package ==="
    
    # Validate shell scripts
    echo "Validating shell scripts..."
    for script in entrypoint.sh scripts/*.sh; do
        if [ -f "$script" ]; then
            echo "  Checking $script..."
            shellcheck -S warning "$script" || {
                echo "ERROR: ShellCheck failed for $script"
                return 1
            }
        fi
    done
    
    # Validate YAML files
    echo "Validating YAML files..."
    python3 -c "
import yaml
import sys

files = ['docker-compose.yml', 'mkdocs.yml']
for f in files:
    try:
        with open(f) as fp:
            yaml.safe_load(fp)
        print(f'  ✓ {f}')
    except Exception as e:
        print(f'  ✗ {f}: {e}')
        sys.exit(1)
" || {
        echo "ERROR: YAML validation failed"
        return 1
    }
    
    echo "=== Build validation complete ==="
}

package() {
    cd "${srcdir}/gnu-hurd-docker"
    
    # Main installation directory
    install -dm755 "${pkgdir}/opt/gnu-hurd-docker"
    install -dm755 "${pkgdir}/usr/bin"
    install -dm755 "${pkgdir}/etc/gnu-hurd-docker"
    install -dm755 "${pkgdir}/usr/share/doc/gnu-hurd-docker"
    install -dm755 "${pkgdir}/usr/share/licenses/gnu-hurd-docker"
    
    # Install core files
    install -Dm644 Dockerfile "${pkgdir}/opt/gnu-hurd-docker/Dockerfile"
    install -Dm755 entrypoint.sh "${pkgdir}/opt/gnu-hurd-docker/entrypoint.sh"
    install -Dm644 docker-compose.yml "${pkgdir}/etc/gnu-hurd-docker/docker-compose.yml"
    
    # Install scripts
    install -dm755 "${pkgdir}/opt/gnu-hurd-docker/scripts"
    for script in scripts/*.sh scripts/*.py; do
        if [ -f "$script" ]; then
            install -Dm755 "$script" "${pkgdir}/opt/gnu-hurd-docker/$script"
        fi
    done
    
    # Install documentation
    install -Dm644 README.md "${pkgdir}/usr/share/doc/gnu-hurd-docker/README.md"
    install -Dm644 requirements.md "${pkgdir}/usr/share/doc/gnu-hurd-docker/requirements.md"
    
    # Install all docs
    cp -r docs "${pkgdir}/usr/share/doc/gnu-hurd-docker/"
    
    # Install license
    install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/gnu-hurd-docker/LICENSE"
    
    # Create convenience launcher script
    cat > "${pkgdir}/usr/bin/gnu-hurd-docker" <<'LAUNCHER'
#!/bin/bash
# GNU/Hurd Docker launcher script

set -e

INSTALL_DIR="/opt/gnu-hurd-docker"
CONFIG_DIR="/etc/gnu-hurd-docker"
WORK_DIR="${HOME}/.local/share/gnu-hurd-docker"

# Ensure work directory exists
mkdir -p "${WORK_DIR}"/{qmp,share,logs}

# Copy docker-compose.yml if not exists
if [ ! -f "${WORK_DIR}/docker-compose.yml" ]; then
    cp "${CONFIG_DIR}/docker-compose.yml" "${WORK_DIR}/"
fi

# Copy Dockerfile if not exists
if [ ! -f "${WORK_DIR}/Dockerfile" ]; then
    cp "${INSTALL_DIR}/Dockerfile" "${WORK_DIR}/"
fi

# Link entrypoint
if [ ! -f "${WORK_DIR}/entrypoint.sh" ]; then
    ln -s "${INSTALL_DIR}/entrypoint.sh" "${WORK_DIR}/entrypoint.sh"
fi

# Link scripts
if [ ! -d "${WORK_DIR}/scripts" ]; then
    ln -s "${INSTALL_DIR}/scripts" "${WORK_DIR}/scripts"
fi

cd "${WORK_DIR}"

case "${1:-help}" in
    start|up)
        echo "Starting GNU/Hurd Docker environment..."
        docker-compose up -d
        echo "Container started. Access via:"
        echo "  SSH: ssh -p 2222 root@localhost"
        echo "  Serial: telnet localhost 5555"
        echo "  Logs: docker-compose logs -f"
        ;;
    stop|down)
        echo "Stopping GNU/Hurd Docker environment..."
        docker-compose down
        ;;
    logs)
        docker-compose logs -f
        ;;
    shell)
        docker-compose exec gnu-hurd-dev bash
        ;;
    build)
        echo "Building Docker image..."
        docker-compose build
        ;;
    status)
        docker-compose ps
        ;;
    download)
        echo "Downloading Debian GNU/Hurd image..."
        "${INSTALL_DIR}/scripts/download-image.sh"
        ;;
    help|--help|-h)
        cat <<HELP
GNU/Hurd Docker - QEMU-based GNU/Hurd development environment

Usage: gnu-hurd-docker [command]

Commands:
    start, up       - Start the container
    stop, down      - Stop the container
    logs            - View container logs
    shell           - Open shell in container
    build           - Build Docker image
    status          - Show container status
    download        - Download Debian GNU/Hurd image
    help            - Show this help

Examples:
    gnu-hurd-docker download   # First time setup
    gnu-hurd-docker build      # Build Docker image
    gnu-hurd-docker start      # Start container
    gnu-hurd-docker logs       # View logs
    gnu-hurd-docker stop       # Stop container

Work directory: ${WORK_DIR}
Documentation: /usr/share/doc/gnu-hurd-docker/

For more information: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker
HELP
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'gnu-hurd-docker help' for usage information"
        exit 1
        ;;
esac
LAUNCHER
    
    chmod 755 "${pkgdir}/usr/bin/gnu-hurd-docker"
    
    # Create README for package
    cat > "${pkgdir}/usr/share/doc/gnu-hurd-docker/PACKAGE.md" <<'PKG_README'
# GNU/Hurd Docker - AUR Package

This package installs the complete GNU/Hurd Docker development environment.

## Installation

```bash
# From AUR (when published)
yay -S gnu-hurd-docker

# From PKGBUILD
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker
makepkg -si
```

## Quick Start

```bash
# 1. Download Debian GNU/Hurd image
gnu-hurd-docker download

# 2. Build Docker image
gnu-hurd-docker build

# 3. Start container
gnu-hurd-docker start

# 4. View logs
gnu-hurd-docker logs
```

## Files Installed

- `/opt/gnu-hurd-docker/` - Main installation
- `/etc/gnu-hurd-docker/` - Configuration files
- `/usr/bin/gnu-hurd-docker` - Launcher script
- `/usr/share/doc/gnu-hurd-docker/` - Documentation

## Work Directory

The package creates a work directory at `~/.local/share/gnu-hurd-docker/` for:
- QEMU images
- Container logs
- Configuration overrides

## Dependencies

**Required:**
- docker (>=20.10)
- docker-compose (>=1.29)
- qemu-base (>=7.0)
- python (>=3.7)

**Optional:**
- qemu-system-x86-64: Run QEMU outside Docker
- cloud-image-utils: Create cloud-init seeds
- socat: QMP automation
- screen/telnet: Serial console access

## Configuration

Edit `~/.local/share/gnu-hurd-docker/docker-compose.yml` to customize:
- RAM allocation
- CPU cores
- Port forwarding
- Display mode (VNC/nographic)

## Troubleshooting

See `/usr/share/doc/gnu-hurd-docker/requirements.md` for:
- System requirements
- Dependency installation
- KVM setup (Linux)
- Network configuration
- Common issues

## References

- GitHub: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker
- Documentation: /usr/share/doc/gnu-hurd-docker/
- License: /usr/share/licenses/gnu-hurd-docker/LICENSE
PKG_README
}
