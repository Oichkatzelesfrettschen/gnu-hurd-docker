#!/bin/bash
# Prove the image-identity preflight against every disagreement it exists to
# catch, plus the one case that matters most: a refusal leaves no run
# directory behind for a caller to mistake for a started run.
#
# scripts/lib/builder-image-preflight.sh reads three things -- the image's
# org.opencontainers.image.revision label, the image's own entrypoint digest,
# and whether the image implements QEMU_SERIAL_LOG -- against the commit a run
# is about to cite. Each is asserted against a stub container runtime so the
# eight ways they can disagree are answerable without a real image build.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/builder-image-preflight-XXXXXX")"
failures=0

cleanup() { rm -rf "$WORKSPACE"; }
trap cleanup EXIT

check() {
    local description="$1" observed="$2" expected="$3"
    if [ "$observed" = "$expected" ]; then
        printf 'ok    %s\n' "$description"
    else
        failures=$((failures + 1))
        printf 'FAIL  %s (observed %s, expected %s)\n' \
            "$description" "$observed" "$expected"
    fi
}

# A tiny git repository stands in for the tree: one commit carries a known
# entrypoint.sh, so builder_commit_entrypoint_digest reads real committed
# bytes rather than a fixture-only stand-in.
git_dir="$WORKSPACE/repo"
mkdir -p "$git_dir"
(
    cd "$git_dir" || exit 1
    git init -q
    git config user.email fixture@example.invalid
    git config user.name fixture
    printf '#!/bin/bash\necho real entrypoint\n' > entrypoint.sh
    git add entrypoint.sh
    git commit -q -m "fixture entrypoint"
)
commit_a="$(git -C "$git_dir" rev-parse HEAD)"
entrypoint_digest_a="$(git -C "$git_dir" show "${commit_a}:entrypoint.sh" | sha256sum | cut -d' ' -f1)"

bin="$WORKSPACE/bin"
mkdir -p "$bin"
cat > "$bin/docker" <<'EOF'
#!/bin/bash
# Answers only what the preflight asks, from environment variables the case
# controls: DOCKER_IMAGE_EXISTS, DOCKER_REVISION, DOCKER_ENTRYPOINT_DIGEST,
# DOCKER_HAS_SERIAL_LOG.
if [ "$1" = "image" ] && [ "$2" = "inspect" ]; then
    shift 2
    if [ "$1" = "--format" ]; then
        [ -n "${DOCKER_REVISION:-}" ] && printf '%s\n' "$DOCKER_REVISION"
        exit 0
    fi
    [ "${DOCKER_IMAGE_EXISTS:-1}" = "1" ] && exit 0 || exit 1
fi
if [ "$1" = "run" ]; then
    shift
    entry=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --entrypoint) entry="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    case "$entry" in
        sha256sum)
            printf '%s  /entrypoint.sh\n' "${DOCKER_ENTRYPOINT_DIGEST:-}"
            exit 0 ;;
        grep)
            [ "${DOCKER_HAS_SERIAL_LOG:-1}" = "1" ] && exit 0 || exit 1 ;;
    esac
    exit 0
fi
exit 0
EOF
chmod +x "$bin/docker"

export PATH="$bin:$PATH"
export CONTAINER_RUNTIME=docker

# shellcheck source=scripts/lib/builder-image-preflight.sh
source "$ROOT/scripts/lib/builder-image-preflight.sh"

# builder_commit_entrypoint_digest runs a bare `git show`, which answers from
# whatever repository the working directory belongs to. The function-level
# cases below run inside the fixture repository so that call resolves against
# the fixture commit rather than against this tree's own history.
cd "$git_dir" || exit 1

reset_case() {
    unset DOCKER_IMAGE_EXISTS DOCKER_REVISION DOCKER_ENTRYPOINT_DIGEST DOCKER_HAS_SERIAL_LOG
    export DOCKER_IMAGE_EXISTS=1
    export DOCKER_REVISION="$commit_a"
    export DOCKER_ENTRYPOINT_DIGEST="$entrypoint_digest_a"
    export DOCKER_HAS_SERIAL_LOG=1
}

reset_case
if builder_image_matches_commit "fixture-image" "$commit_a" 2>"$WORKSPACE/accept.stderr"; then
    check "exact revision, entrypoint, and capability accept" 0 0
else
    check "exact revision, entrypoint, and capability accept" 1 0
fi

reset_case
export DOCKER_IMAGE_EXISTS=0
builder_image_matches_commit "fixture-image" "$commit_a" 2>"$WORKSPACE/absent.stderr"
check "image absent is refused" "$?" 1
check "image absent names the reason" \
    "$(grep -c 'no image' "$WORKSPACE/absent.stderr")" 1

reset_case
export DOCKER_REVISION=""
builder_image_matches_commit "fixture-image" "$commit_a" 2>"$WORKSPACE/no-label.stderr"
check "revision label absent is refused" "$?" 1
check "revision label absent names the reason" \
    "$(grep -c 'records no org.opencontainers.image.revision' "$WORKSPACE/no-label.stderr")" 1

reset_case
export DOCKER_REVISION="0000000000000000000000000000000000dead"
builder_image_matches_commit "fixture-image" "$commit_a" 2>"$WORKSPACE/wrong-revision.stderr"
check "revision label differing is refused" "$?" 1
check "revision label differing names both commits" \
    "$(grep -c "$commit_a" "$WORKSPACE/wrong-revision.stderr")" 1

reset_case
export DOCKER_REVISION="1111111111111111111111111111111111beef"
builder_image_matches_commit "fixture-image" "1111111111111111111111111111111111beef" \
    2>"$WORKSPACE/absent-commit.stderr"
check "a cited commit absent from git history is refused" "$?" 1
check "absent commit names the reason" \
    "$(grep -c 'carries no entrypoint.sh' "$WORKSPACE/absent-commit.stderr")" 1

reset_case
export DOCKER_ENTRYPOINT_DIGEST="2222222222222222222222222222222222222222222222222222222222beef"
builder_image_matches_commit "fixture-image" "$commit_a" 2>"$WORKSPACE/wrong-entrypoint.stderr"
check "entrypoint digest differing is refused" "$?" 1
check "entrypoint digest differing names both digests" \
    "$(grep -c "$entrypoint_digest_a" "$WORKSPACE/wrong-entrypoint.stderr")" 1

reset_case
export DOCKER_HAS_SERIAL_LOG=0
builder_image_matches_commit "fixture-image" "$commit_a" 2>"$WORKSPACE/no-serial.stderr"
check "a missing QEMU_SERIAL_LOG capability is refused" "$?" 1
check "missing capability names the reason" \
    "$(grep -c 'QEMU_SERIAL_LOG' "$WORKSPACE/no-serial.stderr")" 1

# Integration: a refusal at this boundary must leave no run directory, because
# the overlay, the container, and the evidence a run would go on to produce
# all come after it.
runner_tree="$WORKSPACE/runner"
mkdir -p "$runner_tree/config/minty" "$runner_tree/scripts/lib" "$runner_tree/bin"
cp "$ROOT/scripts/run-hurd-build.sh" "$runner_tree/scripts/"
cp "$ROOT/scripts/lib/builder-image-preflight.sh" "$runner_tree/scripts/lib/"
touch "$runner_tree/config/minty/builder.lock.json"
cp "$bin/docker" "$runner_tree/bin/docker"
(
    cd "$runner_tree" || exit 1
    export PATH="$runner_tree/bin:$PATH"
    export CONTAINER_RUNTIME=docker
    export DOCKER_IMAGE_EXISTS=0
    export BUILDER_SOURCE_COMMIT="$commit_a"
    export BUILDER_CONTAINER_IMAGE="fixture-image"
    export BUILD_ROOT="$runner_tree/builds"
    export BUILD_RUN_ID=fixture
    bash scripts/run-hurd-build.sh >runner.log 2>&1
)
check "a refused preflight creates no run directory" \
    "$([ -d "$runner_tree/builds/fixture" ] && echo present || echo absent)" "absent"

echo ""
echo "${failures} failure(s)"
[ "$failures" -eq 0 ]
