pkgname=gnu-hurd-docker-kernel-fix
pkgver=1.1.0
pkgrel=1
pkgdesc="GNU/Hurd Docker kernel networking fix: Configure system for Docker daemon nf_tables requirement"
arch=('x86_64')
url="https://github.com/oaich/gnu-hurd-docker"
license=('MIT')
depends=('docker' 'docker-compose')
optdepends=(
    'linux-headers: Required for Option 1 (kernel rebuild)'
    'gcc: Required for Option 1 (kernel rebuild)'
    'make: Required for Option 1 (kernel rebuild)'
)
provides=('docker-kernel-fix')
conflicts=('docker-iptables-legacy-compat')
install='gnu-hurd-docker-kernel-fix.install'
source=('fix-script.sh')
sha256sums=('SKIP')

build() {
    # Pre-build validation
    echo "[INFO] Validating Docker and kernel requirements..."
    
    # Check if docker is installed
    if ! pacman -Q docker &>/dev/null; then
        echo "[ERROR] Docker must be installed first: pacman -S docker"
        return 1
    fi
    
    # Check kernel version
    KERNEL_VER=$(uname -r | cut -d. -f1-2)
    echo "[OK] Kernel version detected: $KERNEL_VER"
    
    # Check current networking status
    echo "[INFO] Checking networking configuration..."
    if lsmod | grep -q "nf_tables"; then
        echo "[OK] nf_tables kernel module is available"
    else
        echo "[WARN] nf_tables kernel module NOT currently loaded"
    fi
}

package() {
    install -Dm755 "${srcdir}/fix-script.sh" "${pkgdir}/usr/local/bin/gnu-hurd-docker-kernel-fix"
    
    # Documentation
    mkdir -p "${pkgdir}/usr/share/doc/gnu-hurd-docker-kernel-fix"
    
    # Create README with all options
    cat > "${pkgdir}/usr/share/doc/gnu-hurd-docker-kernel-fix/README.md" << 'README_EOF'
# GNU/Hurd Docker - Kernel Networking Fix

This package addresses the Docker daemon failure due to missing nf_tables/iptables NAT chains.

## Problem

Docker daemon fails with:
```
CHAIN_ADD failed (No such file or directory): chain PREROUTING
iptables v1.8.11 (nf_tables): CHAIN_ADD failed
```

Root cause: Linux kernel nf_tables subsystem not properly initialized with NAT table chains.

## Three Solutions Available

### Option 1: Rebuild Kernel with nf_tables Support (RECOMMENDED for long-term)

Requires kernel recompilation with nf_tables NAT support enabled.

Prerequisites:
- linux-headers installed
- gcc, make, binutils
- 2-3 hours compile time on Ryzen 5 5600X

```bash
git clone https://github.com/CachyOS/linux-cachyos
cd linux-cachyos
# Edit .config to enable CONFIG_NETFILTER=y, CONFIG_NF_TABLES=y, etc.
makepkg -fsi
reboot
```

### Option 2: Load nf_tables Kernel Modules (QUICK FIX)

If nf_tables module is compiled but not loaded:

```bash
sudo modprobe nf_tables
sudo modprobe nf_tables_ipv4
sudo modprobe nft_masq
sudo modprobe nf_nat
```

Make permanent by adding to /etc/modules-load.d/:
```bash
echo "nf_tables" | sudo tee -a /etc/modules-load.d/docker.conf
```

### Option 3: Use iptables-legacy Wrapper (TEMPORARY WORKAROUND)

Switch to legacy iptables mode:

```bash
sudo pacman -S iptables-legacy
sudo update-alternatives --set iptables /usr/bin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/bin/ip6tables-legacy
sudo systemctl restart docker
```

## Automated Fix Script

Run the provided script to detect and apply the best fix:

```bash
gnu-hurd-docker-kernel-fix
```

The script will:
1. Check current networking configuration
2. Detect available kernel modules
3. Recommend and apply the best option
4. Verify Docker daemon functionality

## Status Check

After applying any fix, verify:

```bash
docker ps
# Should return empty list or containers, not permission error
```

## Additional Resources

- See VALIDATION-AND-TROUBLESHOOTING.md in the main repository
- Check kernel compile guide at https://wiki.archlinux.org/title/Kernel/Compilation

README_EOF
    
    chmod 644 "${pkgdir}/usr/share/doc/gnu-hurd-docker-kernel-fix/README.md"
}
