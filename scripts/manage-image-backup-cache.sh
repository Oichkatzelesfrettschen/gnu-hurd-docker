#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_DIR="${SOURCE_DIR:-${REPO_ROOT}/images}"
CACHE_DIR="${CACHE_DIR:-${REPO_ROOT}/infrastructure/cache/images}"
PRUNE_DAYS="${PRUNE_DAYS:-14}"
DRY_RUN=0
NO_PRUNE=0

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Move VM backup/snapshot files from images/ into infrastructure/cache/images/,
then prune old cache files.

Options:
  --source-dir PATH   source directory (default: ${SOURCE_DIR})
  --cache-dir PATH    cache directory (default: ${CACHE_DIR})
  --days N            prune files older than N days (default: ${PRUNE_DAYS})
  --no-prune          skip prune step
  -n, --dry-run       show actions without changing files
  -h, --help          show help

Matched files:
  debian-hurd-amd64.qcow2.bak*
  debian-hurd-amd64.qcow2.*.bak
  debian-hurd-amd64.qcow2.pre-*
  debian-hurd-amd64.qcow2.post-*
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --source-dir) SOURCE_DIR="${2:?}"; shift 2 ;;
    --cache-dir) CACHE_DIR="${2:?}"; shift 2 ;;
    --days) PRUNE_DAYS="${2:?}"; shift 2 ;;
    --no-prune) NO_PRUNE=1; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if ! [[ "$PRUNE_DAYS" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] --days must be a non-negative integer (got: ${PRUNE_DAYS})" >&2
  exit 2
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "[ERROR] Source directory does not exist: ${SOURCE_DIR}" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$CACHE_DIR"
else
  echo "[DRY-RUN] mkdir -p ${CACHE_DIR}"
fi

find_backup_files() {
  find "$1" -maxdepth 1 -type f \
    \( -name 'debian-hurd-amd64.qcow2.bak*' \
      -o -name 'debian-hurd-amd64.qcow2.*.bak' \
      -o -name 'debian-hurd-amd64.qcow2.pre-*' \
      -o -name 'debian-hurd-amd64.qcow2.post-*' \) \
    -print0
}

moved_count=0
while IFS= read -r -d '' src; do
  base="$(basename "$src")"
  dst="${CACHE_DIR}/${base}"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] mv -f -- ${src} ${dst}"
  else
    mv -f -- "$src" "$dst"
    echo "[MOVE] ${src} -> ${dst}"
  fi
  moved_count=$((moved_count + 1))
done < <(find_backup_files "$SOURCE_DIR")

echo "[INFO] moved files: ${moved_count}"

if [ "$NO_PRUNE" -eq 1 ]; then
  echo "[INFO] prune step skipped (--no-prune)"
  exit 0
fi

pruned_count=0
while IFS= read -r -d '' old_file; do
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] rm -f -- ${old_file}"
  else
    rm -f -- "$old_file"
    echo "[PRUNE] ${old_file}"
  fi
  pruned_count=$((pruned_count + 1))
done < <(
  find "$CACHE_DIR" -maxdepth 1 -type f -mtime +"$PRUNE_DAYS" \
    \( -name 'debian-hurd-amd64.qcow2.bak*' \
      -o -name 'debian-hurd-amd64.qcow2.*.bak' \
      -o -name 'debian-hurd-amd64.qcow2.pre-*' \
      -o -name 'debian-hurd-amd64.qcow2.post-*' \) \
    -print0 2>/dev/null || true
)

echo "[INFO] pruned files (> ${PRUNE_DAYS} days): ${pruned_count}"
