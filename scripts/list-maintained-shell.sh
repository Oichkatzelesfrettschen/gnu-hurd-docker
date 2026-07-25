#!/usr/bin/env bash
# Print the maintained shell-script surface, one path per line relative to the
# repository root, sorted.  Every ShellCheck gate reads its file set from here,
# so the gates agree by construction rather than by five separate globs that
# drift apart.
#
# The surface is entrypoint.sh, scripts/**, and share/**.  share/ ships into the
# guest through the /share mount and is maintained in this tree, so it belongs
# in the same gate as scripts/.  Archived scripts are kept for history and are
# not maintained against current standards, so they stay out.
#
# -0 emits NUL separators for `xargs -0`.  The conversion happens after the
# newline-delimited sort, so it is correct exactly while no maintained path
# contains a newline.  That is an invariant of this tree, and the script
# asserts it rather than assuming it: a path with an embedded newline aborts
# the enumeration instead of silently producing two wrong entries.  Sorting the
# NUL stream directly would need `sort -z`, which is as GNU-specific as the
# `xargs` extensions this design set out to avoid.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

separator=newline
case "${1:-}" in
    -0|--null) separator=nul ;;
    "") ;;
    *) echo "usage: ${0##*/} [-0]" >&2; exit 2 ;;
esac

cd "$REPO_ROOT"

# find prunes archive directories rather than filtering them afterwards, so a
# deep archive tree costs nothing to walk.
listing="$(
    find entrypoint.sh scripts share \
            \( -type d \( -name archive -o -name ARCHIVE \) -prune \) -o \
            \( -type f -name '*.sh' -print \) \
        | LC_ALL=C sort
)"

# A NUL-delimited walk counts the same files a newline-delimited walk did, so a
# mismatch means a path carries an embedded newline and every downstream gate
# would receive a fabricated file set.
newline_count="$(printf '%s\n' "$listing" | grep -c '' || true)"
nul_count="$(
    find entrypoint.sh scripts share \
            \( -type d \( -name archive -o -name ARCHIVE \) -prune \) -o \
            \( -type f -name '*.sh' -print0 \) \
        | tr -dc '\0' | wc -c
)"
if [ "$newline_count" -ne "$nul_count" ]; then
    echo "${0##*/}: a maintained shell path contains a newline" \
         "($newline_count lines from $nul_count files); the gates cannot" \
         "enumerate this tree" >&2
    exit 2
fi

if [ "$separator" = nul ]; then
    printf '%s\n' "$listing" | tr '\n' '\0'
else
    printf '%s\n' "$listing"
fi
