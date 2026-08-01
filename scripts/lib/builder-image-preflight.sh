# shellcheck shell=bash
# Prove the container about to run is the tree that is about to be cited.
#
# A run records its container's image ID, and an image ID says which bytes ran
# without saying which source they were built from. A local tag makes the gap
# reachable: `gnu-hurd-docker:latest` on this host was built before the serial
# console mechanism existed and carried an entrypoint with no QEMU_SERIAL_LOG at
# all, so a probe against it produced no transcript and the absence read as a
# guest fact rather than as a stale image. Evidence produced that way describes
# code the repository does not contain.
#
# The check is therefore an identity between three things: the commit the
# evidence will name, the revision the image records, and the entrypoint bytes
# inside the image. It runs before the overlay exists, because refusing after
# creation leaves a disposable artifact whose owner has already exited.

# Read the revision an image records for itself. An image built without the
# label answers empty, which is a refusal rather than a match against an empty
# expectation.
builder_image_revision() {
    local reference="$1"
    $CONTAINER_RUNTIME image inspect \
        --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
        "$reference" 2>/dev/null || true
}

builder_image_entrypoint_digest() {
    local reference="$1"
    $CONTAINER_RUNTIME run --rm --entrypoint sha256sum "$reference" \
        /entrypoint.sh 2>/dev/null | cut -d' ' -f1
}

# The committed bytes, read from the commit rather than from the working tree,
# because the tree can carry an edit the evidence would not be able to cite.
#
# git show failing (an absent commit or an absent entrypoint.sh at that commit)
# still exits 0 through this pipeline and pipes nothing into sha256sum, which
# hashes to the same digest as a real, empty entrypoint.sh would. The caller
# below tells the two apart only if git's failure is checked directly, so the
# existence of the path at that commit is checked first.
builder_commit_entrypoint_digest() {
    local commit="$1"
    git cat-file -e "${commit}:entrypoint.sh" 2>/dev/null || return 1
    git show "${commit}:entrypoint.sh" 2>/dev/null | sha256sum | cut -d' ' -f1
}

# Returns 0 when the image is the commit. Every refusal names which of the three
# identities disagreed, because "the image is wrong" does not say whether to
# rebuild, to commit, or to correct the reference.
builder_image_matches_commit() {
    local reference="$1" commit="$2" revision image_digest commit_digest

    if ! $CONTAINER_RUNTIME image inspect "$reference" >/dev/null 2>&1; then
        printf 'preflight: no image %s; build it from %s first\n' \
            "$reference" "$commit" >&2
        return 1
    fi

    revision="$(builder_image_revision "$reference")"
    if [ -z "$revision" ]; then
        printf 'preflight: %s records no org.opencontainers.image.revision, so the image states no source commit\n' \
            "$reference" >&2
        return 1
    fi
    if [ "$revision" != "$commit" ]; then
        printf 'preflight: %s was built from %s and the run would cite %s\n' \
            "$reference" "$revision" "$commit" >&2
        return 1
    fi

    commit_digest="$(builder_commit_entrypoint_digest "$commit")"
    if [ -z "$commit_digest" ]; then
        printf 'preflight: commit %s carries no entrypoint.sh to compare against\n' \
            "$commit" >&2
        return 1
    fi
    image_digest="$(builder_image_entrypoint_digest "$reference")"
    if [ "$image_digest" != "$commit_digest" ]; then
        printf 'preflight: entrypoint in %s hashes to %s and commit %s carries %s\n' \
            "$reference" "${image_digest:-unreadable}" "$commit" "$commit_digest" >&2
        return 1
    fi

    # The label and the entrypoint can agree while the mechanism the run depends
    # on is absent, because a correct label only says which commit was built.
    # The console transcript is the surface the Mach falsifier is read from, so
    # its absence is a refusal rather than a downgrade discovered mid-run.
    if ! $CONTAINER_RUNTIME run --rm --entrypoint grep "$reference" \
            -q 'QEMU_SERIAL_LOG' /entrypoint.sh 2>/dev/null; then
        printf 'preflight: the entrypoint in %s implements no QEMU_SERIAL_LOG, so the guest console cannot reach the run directory\n' \
            "$reference" >&2
        return 1
    fi
    return 0
}
