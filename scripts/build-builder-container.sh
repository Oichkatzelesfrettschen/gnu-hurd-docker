#!/bin/bash
# Build the builder image labeled with the exact commit it was built from, and
# verify the label, the entrypoint digest, and the QEMU_SERIAL_LOG capability
# before this script hands the tag back to a caller.
#
# scripts/lib/builder-image-preflight.sh is the only authority run-hurd-build.sh
# consults before a run starts, so this script proves the image against the
# same function rather than a separate ad hoc check that could drift from it.

set -euo pipefail

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"

script_root="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "${script_root}/.." && pwd)"
cd "$repo_root"

# shellcheck source=scripts/lib/builder-image-preflight.sh
source "${script_root}/lib/builder-image-preflight.sh"

commit="$(git rev-parse HEAD)"
tag="gnu-hurd-docker:git-${commit:0:12}"

printf 'building %s labeled org.opencontainers.image.revision=%s\n' "$tag" "$commit" >&2
"$CONTAINER_RUNTIME" build --label "org.opencontainers.image.revision=${commit}" -t "$tag" .

image_id="$("$CONTAINER_RUNTIME" image inspect --format '{{.Id}}' "$tag")"
printf 'built %s (%s)\n' "$tag" "$image_id" >&2

if ! builder_image_matches_commit "$tag" "$commit"; then
    printf '%s failed its own preflight\n' "$tag" >&2
    exit 1
fi
printf '%s verified against %s\n' "$tag" "$commit" >&2
printf '%s\n' "$tag"
