#!/usr/bin/env python3
"""Recompute the build lock from the artifacts it identifies.

A lock whose digests are typed by hand drifts from what it claims the moment any
of them changes, and a drifted lock is worse than none: it reports a build as
reproducible against inputs that are no longer the inputs. Every digest here is
read from the file it names, so the lock is a derived artifact and a stale one
shows up as a diff.

The lock states one chain: a base image, the package state exported from it, and
the closure seeded with that state. Each link is read from the document that
carries it. The status metadata names the image it was exported from and the
manifest it describes; the seeded closure names the status it answered against,
the archive timestamp it resolved at, and the resolver revision and image that
produced it. A link left unread is a link every scheduled build trusts without
evidence, so an absent input and an absent field are refusals rather than values
that compare equal to each other.

The archive timestamp and the source versions stay hand-chosen, because those
are decisions rather than measurements.
"""

import hashlib
import json
import os
import re
import sys

LOCK = os.environ.get("BUILDER_LOCK", "config/minty/builder.lock.json")
RESOLVER = "scripts/report-hurd-package-closure.py"
BUILD_CLOSURE = "evidence/hurd-archive/hurd-amd64-build-closure-rebuild-candidates.json"
BASE_STATUS = "evidence/builder-base/hurd-amd64-dpkg-status"
BASE_STATUS_METADATA = "evidence/builder-base/hurd-amd64-dpkg-status.json"
BASE_CLOSURE = "evidence/builder-base/hurd-amd64-build-closure-rebuild-candidates.json"
DOCKERFILE = "Dockerfile.hurd-archive"

# Every input a digest or a binding is derived from, and the repository tracks
# all of them. A writer that skips a block when its input is absent leaves the
# previous run's value in the lock and presents it as current, so a clone
# missing any of these refuses rather than reproducing a lock from memory.
REQUIRED = (RESOLVER, BUILD_CLOSURE, BASE_STATUS, BASE_STATUS_METADATA,
            BASE_CLOSURE, DOCKERFILE)


class LockError(Exception):
    """A binding the lock states does not hold against the tree."""


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def stated(document, keys, source):
    """Read a field a binding compares, and refuse the one that is absent.

    Two documents that each state nothing about their own provenance agree on
    every comparison drawn between them, so an absent field satisfies a binding
    it never met. Reading through here makes absence a refusal and keeps the
    rule that an empty value is not a match that happens to be blank.
    """
    value = document
    for depth, key in enumerate(keys):
        if not isinstance(value, dict) or key not in value:
            raise LockError("%s states no %s"
                            % (source, ".".join(keys[:depth + 1])))
        value = value[key]
    if not value:
        raise LockError("%s carries an empty %s" % (source, ".".join(keys)))
    return value


def bind(subject, left, right):
    """One link of the chain, held by the two documents that state it."""
    if left != right:
        raise LockError("%s: %s against %s" % (subject, left, right))


def resolver_image():
    """Read the pinned base digest from the Dockerfile that fixed it.

    The image a report names and the image the Dockerfile pins have to be the
    same value, and reading a local tag would record whatever that tag points at
    on the invoking host rather than the digest that ran.
    """
    with open(DOCKERFILE, encoding="utf-8") as handle:
        match = re.search(r"^ENV HURD_RESOLVER_IMAGE=(\S+)", handle.read(),
                          re.MULTILINE)
    if not match:
        raise LockError("%s pins no HURD_RESOLVER_IMAGE" % DOCKERFILE)
    return match.group(1)


def derive(lock):
    """Recompute every derived field and hold every binding the lock states."""
    resolver_sha256 = digest(RESOLVER)
    lock["resolver_image"] = resolver_image()
    lock["resolver_generator_sha256"] = resolver_sha256
    lock["build_closure_report_sha256"] = digest(BUILD_CLOSURE)
    snapshot = stated(lock, ("archive_snapshot",), LOCK)

    # The base image is multi-gigabyte local state that the repository excludes,
    # so a checkout without it cannot re-measure the digest. The recorded value
    # survives when the file is absent and is recomputed whenever the file is
    # present, which keeps the drift gate meaningful for every digest CI can
    # read while a host holding the image still verifies this one. The exported
    # status names the image it came from, so the value a clone carries is held
    # against a committed document rather than trusted on its own.
    base = lock.setdefault("builder_base", {})
    if os.path.exists(base.get("path", "")):
        base["sha256"] = digest(base["path"])
    if not base.get("sha256"):
        raise LockError("the lock records no builder base digest while %s "
                        "states the image its status was exported from"
                        % BASE_STATUS_METADATA)

    base["status_sha256"] = digest(BASE_STATUS)
    status_metadata = load(BASE_STATUS_METADATA)
    bind("the status metadata describes a manifest other than the one it sits beside",
         stated(status_metadata, ("manifest",), BASE_STATUS_METADATA),
         os.path.basename(BASE_STATUS))
    bind("the exported status does not hash to the digest its metadata records",
         stated(status_metadata, ("manifest_sha256",), BASE_STATUS_METADATA),
         base["status_sha256"])
    bind("the exported status was taken from an image the lock does not pin",
         stated(status_metadata, ("source_image_sha256",), BASE_STATUS_METADATA),
         base["sha256"])

    # The batch planner sizes its work from the transaction derived against the
    # finished base, so the lock binds the base's exported status and the
    # closure seeded with it. A seeded report naming another status, another
    # snapshot, or another resolver would have the planner schedule from a
    # prediction made against some other installed state.
    base["build_closure_report_sha256"] = digest(BASE_CLOSURE)
    seeded = load(BASE_CLOSURE)
    bind("the seeded closure was resolved against another installed state",
         stated(seeded, ("provenance", "installed_baseline", "sha256"), BASE_CLOSURE),
         base["status_sha256"])
    bind("the seeded closure answered against another archive",
         stated(seeded, ("provenance", "archive_snapshot"), BASE_CLOSURE),
         snapshot)
    bind("the seeded closure was produced by another resolver revision",
         stated(seeded, ("provenance", "generator_sha256"), BASE_CLOSURE),
         resolver_sha256)
    bind("the seeded closure ran in another resolver image",
         stated(seeded, ("provenance", "resolver_image"), BASE_CLOSURE),
         lock["resolver_image"])

    # The report the lock cites has to have answered against the timestamp the
    # lock pins and come from the resolver the tree carries, or the two describe
    # different archives and the build schedules from one and runs against the
    # other.
    report = load(BUILD_CLOSURE)
    lock["build_closure_archive_snapshot"] = stated(
        report, ("provenance", "archive_snapshot"), BUILD_CLOSURE)
    bind("the cited closure answered against another archive",
         lock["build_closure_archive_snapshot"], snapshot)
    bind("the cited closure was produced by another resolver revision",
         stated(report, ("provenance", "generator_sha256"), BUILD_CLOSURE),
         resolver_sha256)
    bind("the cited closure ran in another resolver image",
         stated(report, ("provenance", "resolver_image"), BUILD_CLOSURE),
         lock["resolver_image"])


def main():
    if not os.path.exists(LOCK):
        print("no lock at %s" % LOCK, file=sys.stderr)
        return 2
    missing = [path for path in REQUIRED if not os.path.isfile(path)]
    if missing:
        print("the lock derives from files the tree does not carry: %s"
              % ", ".join(missing), file=sys.stderr)
        return 1

    lock = load(LOCK)
    try:
        derive(lock)
    except LockError as error:
        print(str(error), file=sys.stderr)
        return 1

    with open(LOCK, "w", encoding="utf-8") as handle:
        json.dump(lock, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote %s" % LOCK)
    return 0


if __name__ == "__main__":
    sys.exit(main())
