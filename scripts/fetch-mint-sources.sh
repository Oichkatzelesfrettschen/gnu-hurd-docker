#!/bin/sh
# Fetch Linux Mint upstream sources on-demand into mint-sources/.
# Avoids vendoring ~454k lines of upstream code into this repo.
# Run from the gnu-hurd-docker repo root.
set -e

DEST="${1:-mint-sources}"
mkdir -p "$DEST"

clone_or_pull() {
    local repo="$1"
    local dest="$DEST/$repo"
    if [ -d "$dest/.git" ]; then
        printf '== updating %s ==\n' "$repo"
        git -C "$dest" pull --ff-only --quiet
    else
        printf '== cloning %s ==\n' "$repo"
        git clone --depth=1 "https://github.com/linuxmint/$repo.git" "$dest"
    fi
}

clone_or_pull mintmenu
clone_or_pull mint-themes
clone_or_pull mint-y-icons
clone_or_pull mint-x-icons
clone_or_pull mintdesktop

echo
echo "Cloned to: $DEST/"
echo "These are upstream sources for reference / local builds; the actual"
echo "Mint .debs come via the LMDE7 (gigi) repo configured by"
echo "scripts/lmde7-apt-setup.sh."
