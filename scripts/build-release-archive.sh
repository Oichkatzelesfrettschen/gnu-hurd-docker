#!/usr/bin/env bash
# Build the release source archive and accept it against its own documented
# contract.
#
# git archive makes the repository tree the definition of the release, so the
# tarball cannot drift from what the repository contains.  A handcrafted
# manifest copied only top-level scripts/*.sh and scripts/*.py, which dropped
# scripts/lib, scripts/automation, scripts/test-phases, and share/ -- files the
# packaged scripts/validate-config.sh requires, so the archive shipped a
# validator it could not satisfy.  .gitattributes carries the exclusion policy:
# ARCHIVE/, docs/reports/, and ssh-test-keys/ are export-ignore.
#
# The release job and the pull-request check both run this script, so the
# artifact that gets published is the artifact that got tested.
#
# Usage:
#   scripts/build-release-archive.sh --version vX.Y.Z [--commit REF] [--output-dir DIR]
#
# Exit codes:
#   0 - archive built and accepted
#   1 - archive built and rejected, or a build step failed
#   2 - usage error, including a version outside the supported tag grammar
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

version=""
commit="HEAD"
output_dir="$PWD"

while [ $# -gt 0 ]; do
    case "$1" in
        --version) version="${2:?--version needs a value}"; shift 2 ;;
        --commit) commit="${2:?--commit needs a value}"; shift 2 ;;
        --output-dir) output_dir="${2:?--output-dir needs a value}"; shift 2 ;;
        -h|--help) sed -n '17,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "${0##*/}: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if [ -z "$version" ]; then
    echo "${0##*/}: --version is required" >&2
    exit 2
fi

# A workflow_dispatch version is arbitrary operator input that reaches file
# names and the release tag, so it is checked against the supported grammar
# before anything writes it anywhere.  Whitespace, newlines, path separators,
# and shell metacharacters all fail this pattern.
case "$version" in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *)
        echo "${0##*/}: version must be vMAJOR.MINOR.PATCH, got '$version'" >&2
        exit 2
        ;;
esac
if ! printf '%s' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
    echo "${0##*/}: version must be vMAJOR.MINOR.PATCH with optional" \
         "prerelease and build metadata, got '$version'" >&2
    exit 2
fi
git check-ref-format "refs/tags/$version" || {
    echo "${0##*/}: '$version' is not a valid tag name" >&2
    exit 2
}

cd "$REPO_ROOT"

version_clean="${version#v}"
resolved_commit="$(git rev-parse --verify "$commit^{commit}")"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

archive="$output_dir/gnu-hurd-docker-$version_clean.tar.gz"
prefix="gnu-hurd-docker-$version_clean"

echo "=== Creating release archive from the repository tree ==="
echo "version: $version"
echo "commit:  $resolved_commit"
git archive --format=tar.gz --prefix="$prefix/" --output="$archive" "$resolved_commit"
sha256sum "$archive" >"$archive.sha256"
echo "archive entries: $(tar -tzf "$archive" | wc -l)"

echo ""
echo "=== Verifying the archive a user actually downloads ==="
# Checking repository sources proves the inputs exist; it cannot prove the
# product works.  This extracts the tarball and runs the operations its own
# documentation tells a user to run, including the packaged validator.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
tar -xzf "$archive" -C "$workdir"

root="$workdir/$prefix"
if [ ! -d "$root" ]; then
    echo "ERROR: archive has no $prefix/ top-level directory" >&2
    ls -la "$workdir" >&2
    exit 1
fi

# Every file the quick start in the release notes depends on.
REQUIRED="entrypoint.sh Dockerfile compose.yaml compose.bind.yaml Makefile
          scripts/validate-config.sh scripts/setup-hurd-amd64.sh
          scripts/list-maintained-shell.sh scripts/check-maintained-shell.sh
          README.md docs/index.md
          docs/01-GETTING-STARTED/INSTALLATION.md
          docs/01-GETTING-STARTED/REQUIREMENTS.md"
missing=0
for required_path in $REQUIRED; do
    if [ ! -f "$root/$required_path" ]; then
        echo "ERROR: archive is missing $required_path" >&2
        missing=$((missing + 1))
    fi
done
[ "$missing" -eq 0 ] || exit 1

for entry_point in scripts/setup-hurd-amd64.sh scripts/validate-config.sh \
                   scripts/list-maintained-shell.sh scripts/check-maintained-shell.sh; do
    if [ ! -x "$root/$entry_point" ]; then
        echo "ERROR: packaged $entry_point is not executable" >&2
        exit 1
    fi
done

# Both documented entry points have to parse against the packaged Makefile.
( cd "$root" && make -n up >/dev/null && make -n build >/dev/null ) || {
    echo "ERROR: 'make -n up' or 'make -n build' fails inside the archive" >&2
    exit 1
}

# The archive ships scripts/validate-config.sh and its README tells the user to
# run it.  It has to pass against the archive's own contents.
( cd "$root" && ./scripts/validate-config.sh ) || {
    echo "ERROR: the packaged validator fails against the packaged tree" >&2
    exit 1
}

# Documentation links have to resolve inside the archive, not only in the
# repository the docs were written in.  link-scanner.py reports its findings and
# exits 0 either way, so check-link-scan-result.py supplies the exit status.
( cd "$root" \
    && python3 scripts/utils/link-scanner.py --docs-root docs \
         --json "$workdir/link-scan.json" >/dev/null \
    && python3 scripts/check-link-scan-result.py "$workdir/link-scan.json" ) || {
    echo "ERROR: the packaged documentation contains broken internal links" >&2
    exit 1
}

# The default development composition has to resolve from the archive.
if command -v docker >/dev/null 2>&1; then
    ( cd "$root" && docker compose -f compose.yaml -f compose.bind.yaml config -q ) || {
        echo "ERROR: packaged compose files do not validate" >&2
        exit 1
    }
else
    echo "[SKIP] docker unavailable; packaged compose files not validated"
fi

echo "[OK] the extracted archive satisfies its own documented contract"

# The subset packages are cut from the verified extraction, so they carry
# exactly the files the acceptance test just exercised.
echo ""
echo "=== Creating subset packages from the accepted extraction ==="
scripts_archive="$output_dir/gnu-hurd-docker-scripts-$version_clean.tar.gz"
docs_archive="$output_dir/gnu-hurd-docker-docs-$version_clean.tar.gz"
tar -czf "$scripts_archive" -C "$root" scripts share
tar -czf "$docs_archive" -C "$root" README.md ROADMAP.md docs
sha256sum "$scripts_archive" >"$scripts_archive.sha256"
sha256sum "$docs_archive" >"$docs_archive.sha256"

ls -la "$output_dir"/gnu-hurd-docker-*"$version_clean"*
