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
# -0 emits NUL separators for `xargs -0`, which survives paths containing
# whitespace.
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
find entrypoint.sh scripts share \
        \( -type d \( -name archive -o -name ARCHIVE \) -prune \) -o \
        \( -type f -name '*.sh' -print \) \
    | LC_ALL=C sort \
    | if [ "$separator" = nul ]; then tr '\n' '\0'; else cat; fi
