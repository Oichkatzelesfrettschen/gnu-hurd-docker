#!/bin/bash
set -euo pipefail

# Build an unattended Debian GNU/Hurd installer ISO by patching grub.cfg
# and injecting a preseed file at /preseed.cfg.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

BASE_ISO="${BASE_ISO:-}"
OUTPUT_ISO="${OUTPUT_ISO:-}"
PRESEED_FILE="${PRESEED_FILE:-infrastructure/unattended/preseed.cfg}"

if [ -z "$BASE_ISO" ] || [ -z "$OUTPUT_ISO" ]; then
    echo "Usage: BASE_ISO=/path/base.iso OUTPUT_ISO=/path/output-auto.iso [PRESEED_FILE=...] $0" >&2
    exit 2
fi

if [ ! -f "$BASE_ISO" ]; then
    echo "[ERROR] BASE_ISO not found: $BASE_ISO" >&2
    exit 1
fi
if [ ! -f "$PRESEED_FILE" ]; then
    echo "[ERROR] PRESEED_FILE not found: $PRESEED_FILE" >&2
    exit 1
fi
if ! command -v xorriso >/dev/null 2>&1; then
    echo "[ERROR] xorriso is required" >&2
    exit 1
fi
if ! command -v debugfs >/dev/null 2>&1; then
    echo "[ERROR] debugfs is required (install e2fsprogs)" >&2
    exit 1
fi
if ! command -v file >/dev/null 2>&1; then
    echo "[ERROR] file is required" >&2
    exit 1
fi

workdir="$(mktemp -d -t hurd-auto-iso.XXXXXX)"
cleanup() {
    rm -rf "$workdir"
}
trap cleanup EXIT

orig_grub="${workdir}/grub.cfg.orig"
patched_grub="${workdir}/grub.cfg"

xorriso -indev "$BASE_ISO" -osirrox on -extract /boot/grub/grub.cfg "$orig_grub" >/dev/null 2>&1
cp "$orig_grub" "$patched_grub"

# Set a short timeout and default to "Automated install" entry.
# In the current mini.iso grub.cfg, this entry index is 6.
sed -i 's/^set timeout=.*/set timeout=5/' "$patched_grub"
sed -i 's/^set default=.*/set default=6/' "$patched_grub"

# Inject deterministic boot parameters for unattended install.
# preseed.cfg is injected directly into initrd.gz and referenced explicitly.
sed -i \
    's@set options="auto=true priority=critical[^"]*"@set options="auto=true priority=critical preseed/file=/preseed.cfg netcfg/choose_interface=auto console=com0 TERM=mach-gnu-color"@' \
    "$patched_grub"

mkdir -p "$(dirname "$OUTPUT_ISO")"
rm -f "$OUTPUT_ISO"

inject_preseed_into_initrd() {
    local initrd_path="$1"
    local raw_path="${workdir}/initrd.raw"
    local fs_kind=""
    local swap_script=""
    local swap_script_candidates=(
        "/usr/lib/partman/commit.d/45format_swap"
        "/usr/lib/partman/partman/commit.d/45format_swap"
    )
    local swap_src="${workdir}/45format_swap.orig"
    local swap_patched="${workdir}/45format_swap.patched"

    if [ ! -f "$initrd_path" ]; then
        return 0
    fi

    rm -f "$raw_path"
    if ! gzip -dc "$initrd_path" > "$raw_path"; then
        echo "[WARN] Could not decompress initrd: $initrd_path" >&2
        return 0
    fi

    fs_kind="$(file -b "$raw_path" || true)"
    if [[ "$fs_kind" != *"ext2 filesystem"* ]]; then
        echo "[WARN] Unsupported initrd payload format ($fs_kind): $initrd_path" >&2
        return 0
    fi

    # Remove old preseed if present, then inject fresh one into ext2 initrd.
    debugfs -w -R "rm /preseed.cfg" "$raw_path" >/dev/null 2>&1 || true
    if ! debugfs -w -R "write $PRESEED_FILE /preseed.cfg" "$raw_path" >/dev/null 2>&1; then
        echo "[ERROR] Failed to inject preseed into initrd ext2 image: $initrd_path" >&2
        return 1
    fi

    # Patch partman swap formatter so swap failures do not force retries in
    # unattended mode on GNU/Hurd.
    rm -f "$swap_src" "$swap_patched"
    for candidate in "${swap_script_candidates[@]}"; do
        rm -f "$swap_src"
        if debugfs -R "dump -p $candidate $swap_src" "$raw_path" >/dev/null 2>&1 && [ -f "$swap_src" ]; then
            swap_script="$candidate"
            break
        fi
    done
    if [ -n "$swap_script" ] && [ -f "$swap_src" ]; then
        cp "$swap_src" "$swap_patched"
        if ! grep -q "patched by gnu-hurd-docker unattended build" "$swap_patched"; then
            awk '
                BEGIN { in_swap_fail_block = 0; replaced = 0 }
                {
                    if (!in_swap_fail_block && $0 ~ /^[[:space:]]*if \[ "\$status" != OK \]; then[[:space:]]*$/) {
                        in_swap_fail_block = 1
                        replaced = 1
                        print "\t\t\tif [ \"$status\" != OK ]; then"
                        print "\t\t\t\t# patched by gnu-hurd-docker unattended build"
                        print "\t\t\t\tlog \"Skipping swap creation failure in unattended mode: $dev/$id\""
                        print "\t\t\t\tcontinue"
                        print "\t\t\tfi"
                        next
                    }
                    if (in_swap_fail_block) {
                        if ($0 ~ /^[[:space:]]*fi[[:space:]]*$/) {
                            in_swap_fail_block = 0
                        }
                        next
                    }
                    print
                }
                END {
                    if (!replaced) {
                        exit 3
                    }
                    if (in_swap_fail_block) {
                        exit 4
                    }
                }
            ' "$swap_src" >"$swap_patched"
            if cmp -s "$swap_src" "$swap_patched"; then
                echo "[WARN] Swap handler patch did not modify $swap_script in $initrd_path" >&2
            else
                debugfs -w -R "rm $swap_script" "$raw_path" >/dev/null 2>&1 || true
                if ! debugfs -w -R "write $swap_patched $swap_script" "$raw_path" >/dev/null 2>&1; then
                    echo "[ERROR] Failed to write patched swap script into initrd: $initrd_path" >&2
                    return 1
                fi
                debugfs -w -R "sif $swap_script mode 0100755" "$raw_path" >/dev/null 2>&1 || true
                echo "[OK] Patched swap handler in initrd: $initrd_path"
            fi
        fi
    else
        echo "[WARN] Could not locate 45format_swap in initrd: $initrd_path" >&2
    fi

    gzip -9c "$raw_path" > "$initrd_path"
    echo "[OK] Injected preseed into initrd: $initrd_path"
}

build_with_full_remaster() {
    # Robust path for hosts where "boot_image any replay" fails with GPT overlap.
    local tree="${workdir}/iso-tree"
    local volume_id="ISOIMAGE"
    local creation_time=""

    mkdir -p "$tree"
    xorriso -osirrox on -indev "$BASE_ISO" -extract / "$tree" >/dev/null 2>&1
    chmod -R u+w "$tree"
    cp "$PRESEED_FILE" "${tree}/preseed.cfg"
    cp "$patched_grub" "${tree}/boot/grub/grub.cfg"
    inject_preseed_into_initrd "${tree}/boot/initrd.gz"
    inject_preseed_into_initrd "${tree}/boot/gtk/initrd.gz"

    volume_id="$(
        xorriso -indev "$BASE_ISO" -pvd_info 2>/dev/null \
            | awk -F': ' '/Volume Id[[:space:]]*:/ {print $2; exit}'
    )"
    if [ -z "$volume_id" ]; then
        volume_id="ISOIMAGE"
    fi
    creation_time="$(
        xorriso -indev "$BASE_ISO" -pvd_info 2>/dev/null \
            | awk -F': ' '/Creation Time[[:space:]]*:/ {print $2; exit}'
    )"

    if [ -n "$creation_time" ]; then
        xorriso -as mkisofs \
            -r -V "$volume_id" \
            --modification-date="$creation_time" \
            --grub2-mbr "--interval:local_fs:0s-15s:zero_mbrpt,zero_gpt,zero_apm:${BASE_ISO}" \
            --protective-msdos-label \
            -partition_cyl_align off \
            -partition_offset 0 \
            -partition_hd_cyl 64 \
            -partition_sec_hd 32 \
            -apm-block-size 2048 \
            -hfsplus \
            -efi-boot-part --efi-boot-image \
            -c /boot.catalog \
            -b /boot/grub/i386-pc/eltorito.img \
            -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
            -eltorito-alt-boot \
            -e /efi.img \
            -no-emul-boot -boot-load-size 5760 \
            -o "$OUTPUT_ISO" \
            "$tree" >/dev/null
    else
        xorriso -as mkisofs \
            -r -V "$volume_id" \
            --grub2-mbr "--interval:local_fs:0s-15s:zero_mbrpt,zero_gpt,zero_apm:${BASE_ISO}" \
            --protective-msdos-label \
            -partition_cyl_align off \
            -partition_offset 0 \
            -partition_hd_cyl 64 \
            -partition_sec_hd 32 \
            -apm-block-size 2048 \
            -hfsplus \
            -efi-boot-part --efi-boot-image \
            -c /boot.catalog \
            -b /boot/grub/i386-pc/eltorito.img \
            -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
            -eltorito-alt-boot \
            -e /efi.img \
            -no-emul-boot -boot-load-size 5760 \
            -o "$OUTPUT_ISO" \
            "$tree" >/dev/null
    fi
}

# Replay mode is currently disabled by default because Debian Hurd d-i media can
# fail GPT replay on some hosts. Enable explicitly if needed.
if [ "${ISO_REPLAY_FIRST:-0}" = "1" ]; then
    if ! xorriso \
        -indev "$BASE_ISO" \
        -outdev "$OUTPUT_ISO" \
        -boot_image any replay \
        -map "$PRESEED_FILE" /preseed.cfg \
        -map "$patched_grub" /boot/grub/grub.cfg \
        -commit >/dev/null; then
        echo "[WARN] xorriso replay path failed; retrying with full remaster fallback..." >&2
        rm -f "$OUTPUT_ISO"
        build_with_full_remaster
    fi
else
    build_with_full_remaster
fi

echo "[OK] Unattended ISO created: $OUTPUT_ISO"
echo "[INFO] Base ISO: $BASE_ISO"
echo "[INFO] Preseed: $PRESEED_FILE"
