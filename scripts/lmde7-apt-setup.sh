#!/bin/sh
# Wire LMDE7 (gigi, trixie-based) as a low-priority arch=all source.
# Run inside the Hurd guest as root.
set -e
PATH=$PATH:/usr/sbin:/sbin

log() { printf '\n=== %s ===\n' "$*"; }

log "Step 1: install linuxmint-keyring + curl/gpg"
apt-get install -y --no-install-recommends ca-certificates curl gnupg gpg

# Fetch the LMDE GPG key + install as keyring
log "Step 2: install Mint signing keys"
curl -sL --max-time 30 \
    'http://mirrors.kernel.org/linuxmint-packages/pool/main/l/linuxmint-keyring/linuxmint-keyring_2022.06.21_all.deb' \
    -o /tmp/linuxmint-keyring.deb
dpkg -i /tmp/linuxmint-keyring.deb
rm -f /tmp/linuxmint-keyring.deb

log "Step 3: add LMDE7 (gigi) repo with restricted scope"
cat > /etc/apt/sources.list.d/lmde7.list <<'EOF'
# Linux Mint Debian Edition 7 (gigi) - trixie-based.
# Used ONLY for arch=all Mint-specific packages (themes, mintmenu, mintdesktop,
# etc.).  See /etc/apt/preferences.d/lmde7 for the pin that enforces this.
deb http://mirrors.kernel.org/linuxmint-packages/ gigi main upstream import backport
EOF

log "Step 4: pin LMDE7 packages so only arch=all wins"
cat > /etc/apt/preferences.d/lmde7 <<'EOF'
# Default: heavily de-prefer LMDE packages.  Debian ports/sid wins for anything
# both repos provide.
Package: *
Pin: release o=linuxmint
Pin-Priority: 100

# Allow only these specific Mint-specific arch=all packages to install from LMDE.
# (These don't exist in Debian.)
Package: mintmenu mint-themes mint-x-icons mint-y-icons mint-l-theme mint-l-icons \
         mint-cursor-themes mintdesktop mint-artwork mint-common mint-translations \
         mint-backgrounds-* mint-info-cinnamon mint-meta-codecs linuxmint-keyring
Pin: release o=linuxmint
Pin-Priority: 500
EOF

log "Step 5: apt update"
apt-get update 2>&1 | tail -5

log "Step 6: install Mint arch=all packages"
apt-get install -y \
    mintmenu mint-themes mint-x-icons mint-y-icons \
    mint-l-theme mint-l-icons mint-cursor-themes \
    mintdesktop mint-artwork mint-common

log "Step 7: verify they came from LMDE"
for p in mintmenu mint-themes mint-y-icons; do
    apt-cache policy "$p" | head -10
    echo
done

log "Done."
