#!/bin/bash
set -euo pipefail

# Build a script inventory and synthesis report for consolidation decisions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "$REPO_ROOT"

OUT_MD="${OUT_MD:-scripts/INVENTORY.md}"
OUT_TSV="${OUT_TSV:-scripts/inventory.tsv}"

tmp="${TMPDIR:-/tmp}/script-inventory.$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

mapfile -t files < <(
    find scripts -type f \
        -not -path '*/__pycache__/*' \
        -not -name '*.pyc' \
        -not -name '*.db' \
        | sort
)

is_core() {
    case "$1" in
        scripts/install-hurd-unattended.sh|\
        scripts/build-hurd-unattended-iso.sh|\
        scripts/rebuild-hurd-unattended-iso.sh|\
        scripts/qemu-auto-verify.sh|\
        scripts/qemu-matrix-runner.sh|\
        scripts/qemu-install-serial-fsm.sh|\
        scripts/qemu-install-fsm.expect|\
        scripts/qemu-stall-probe.sh|\
        scripts/setup-hurd-amd64-daily-installer.sh|\
        scripts/resolve-latest-hurd-amd64-daily-installer.sh|\
        scripts/validate-config.sh)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

classify() {
    local path="$1"
    if [[ "$path" == scripts/archive/* ]]; then
        echo "legacy-archive"
        return
    fi
    if [[ "$path" == scripts/automation/stubs/* ]] || [[ "$path" == scripts/vboxmanage-hurd.sh ]]; then
        echo "conceptual-stub"
        return
    fi
    if [[ "$path" == scripts/automation/* ]]; then
        echo "modular-canonical"
        return
    fi
    if is_core "$path"; then
        echo "active-core"
        return
    fi
    if [[ "$path" == scripts/test-* ]] || [[ "$path" == scripts/test-phases/* ]]; then
        echo "test-support"
        return
    fi
    if [[ "$path" == scripts/lib/* ]]; then
        echo "shared-library"
        return
    fi
    echo "active-support"
}

purpose_hint() {
    local path="$1"
    local base
    base="$(basename "$path")"
    case "$base" in
        *unattended*|*matrix*|*qemu*)
            echo "qemu-automation"
            ;;
        *vbox*|*virtualbox*)
            echo "virtualbox-stub"
            ;;
        *validate*|*smoke*)
            echo "validation"
            ;;
        *setup*|*bootstrap*)
            echo "setup"
            ;;
        *provision*|*install*)
            echo "provision-install"
            ;;
        *)
            echo "general"
            ;;
    esac
}

echo -e "path\tstatus\tpurpose" >"$OUT_TSV"
for path in "${files[@]}"; do
    status="$(classify "$path")"
    purpose="$(purpose_hint "$path")"
    echo -e "${path}\t${status}\t${purpose}" >>"$OUT_TSV"
done

{
    echo "# Scripts Inventory and Consolidation Report"
    echo ""
    echo "- generated_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- total_scripts: $((${#files[@]}))"
    echo "- inventory_tsv: \`$OUT_TSV\`"
    echo ""
    echo "## Counts by Status"
    echo ""
    awk -F'\t' 'NR>1 {c[$2]++} END {for (k in c) print "- " k ": " c[k]}' "$OUT_TSV" | sort
    echo ""
    echo "## Active Core"
    echo ""
    awk -F'\t' 'NR>1 && $2=="active-core" {print "- `" $1 "`"}' "$OUT_TSV"
    echo ""
    echo "## Modular Canonical"
    echo ""
    awk -F'\t' 'NR>1 && $2=="modular-canonical" {print "- `" $1 "`"}' "$OUT_TSV"
    echo ""
    echo "## Conceptual Stub"
    echo ""
    awk -F'\t' 'NR>1 && $2=="conceptual-stub" {print "- `" $1 "`"}' "$OUT_TSV"
    echo ""
    echo "## Legacy Archive"
    echo ""
    awk -F'\t' 'NR>1 && $2=="legacy-archive" {print "- `" $1 "`"}' "$OUT_TSV"
    echo ""
    echo "## Synthesis Recommendations"
    echo ""
    echo "- Keep wrappers at \`scripts/*.sh\` for compatibility, route implementation to \`scripts/automation/*\`."
    echo "- Centralize serial parsing/evidence helpers under \`scripts/lib/installer/\`."
    echo "- Treat VirtualBox flows as conceptual-only until QEMU matrix reaches stable pass criteria."
    echo "- Use \`scripts/automation/qemu/\` as canonical path for unattended, stall probe, verify, and matrix orchestration."
} >"$OUT_MD"

echo "[INFO] Wrote $OUT_TSV"
echo "[INFO] Wrote $OUT_MD"
