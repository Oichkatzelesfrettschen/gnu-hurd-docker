#!/usr/bin/env bash
# Run ShellCheck over the maintained shell surface and fail closed.
#
# Every gate calls this script rather than assembling its own
# enumerator-into-xargs pipeline, because those pipelines fail open.  A `while`
# loop reading from process substitution discards the producer's exit status,
# and a Make recipe runs under /bin/sh without pipefail, so an enumerator that
# dies leaves `xargs` with no input and both report success over zero files.
# Materialising the list first turns that into an explicit emptiness check.
#
# SHELLCHECK_SEVERITY selects the level.  error is what the tree passes today;
# warning shows the findings that roadmap item 43 tracks.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

severity="${SHELLCHECK_SEVERITY:-error}"

surface="$(mktemp)"
trap 'rm -f "$surface"' EXIT

./scripts/list-maintained-shell.sh -0 >"$surface"

if [ ! -s "$surface" ]; then
    echo "${0##*/}: the maintained shell surface is empty; the enumerator" \
         "produced nothing and this gate would otherwise pass over no files" >&2
    exit 1
fi

xargs -0 shellcheck -S "$severity" "$@" <"$surface"
