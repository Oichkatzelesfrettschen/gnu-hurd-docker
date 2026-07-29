#!/usr/bin/env python3
"""Recompute the build lock from the artifacts it identifies.

A lock whose digests are typed by hand drifts from what it claims the moment any
of them changes, and a drifted lock is worse than none: it reports a build as
reproducible against inputs that are no longer the inputs. Every digest here is
read from the file it names, so the lock is a derived artifact and a stale one
shows up as a diff.

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
DOCKERFILE = "Dockerfile.hurd-archive"


def digest(path):
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def resolver_image():
    """Read the pinned base digest from the Dockerfile that fixed it.

    The image a report names and the image the Dockerfile pins have to be the
    same value, and reading a local tag would record whatever that tag points at
    on the invoking host rather than the digest that ran.
    """
    if not os.path.exists(DOCKERFILE):
        return ""
    with open(DOCKERFILE, encoding="utf-8") as handle:
        match = re.search(r"^ENV HURD_RESOLVER_IMAGE=(\S+)", handle.read(),
                          re.MULTILINE)
    return match.group(1) if match else ""


def main():
    if not os.path.exists(LOCK):
        print("no lock at %s" % LOCK, file=sys.stderr)
        return 2
    with open(LOCK, encoding="utf-8") as handle:
        lock = json.load(handle)

    lock["resolver_image"] = resolver_image()
    lock["resolver_generator_sha256"] = digest(RESOLVER)
    lock["build_closure_report_sha256"] = digest(BUILD_CLOSURE)

    base = lock.setdefault("builder_base", {})
    base["sha256"] = digest(base.get("path", ""))
    if not base["sha256"]:
        base["status"] = "not built; roadmap 55a"
    else:
        base.pop("status", None)

    # The report the lock cites has to have answered against the timestamp the
    # lock pins, or the two describe different archives and the build would
    # schedule from one and run against the other.
    if os.path.exists(BUILD_CLOSURE):
        with open(BUILD_CLOSURE, encoding="utf-8") as handle:
            report = json.load(handle)
        recorded = report.get("provenance", {}).get("archive_snapshot", "")
        lock["build_closure_archive_snapshot"] = recorded
        # An empty timestamp is not a match that happens to be blank: it means
        # the report answered against whatever sid and unreleased held that
        # minute, so the lock would pin a build to an archive state the report
        # never saw.
        if recorded != lock.get("archive_snapshot"):
            print("the cited build closure answered against %s and the lock "
                  "pins %s" % (recorded or "a moving suite",
                               lock.get("archive_snapshot")), file=sys.stderr)
            return 1

    with open(LOCK, "w", encoding="utf-8") as handle:
        json.dump(lock, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote %s" % LOCK)
    return 0


if __name__ == "__main__":
    sys.exit(main())
