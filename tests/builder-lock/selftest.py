#!/usr/bin/env python3
"""Prove that the lock writer refuses a chain whose links disagree.

The writer derives the lock from a base image, the package state exported from
it, and the closure seeded with that state. Its own gate runs against a tree
where every link already holds, which shows that a correct chain is accepted and
says nothing about what a broken one does. Each case here copies the committed
tree into a workspace, breaks exactly one link, and asserts the run refuses and
leaves the lock unwritten -- a writer that carried on would emit a lock whose
recorded values came from the previous run rather than from the tree.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WRITER = os.path.join(ROOT, "scripts", "write-builder-lock.py")
LOCK = os.path.join("config", "minty", "builder.lock.json")
RESOLVER = os.path.join("scripts", "report-hurd-package-closure.py")
DOCKERFILE = "Dockerfile.hurd-archive"
BASE = os.path.join("evidence", "builder-base")
STATUS = os.path.join(BASE, "hurd-amd64-dpkg-status")
STATUS_METADATA = os.path.join(BASE, "hurd-amd64-dpkg-status.json")
BASE_CLOSURE = os.path.join(BASE, "hurd-amd64-build-closure-rebuild-candidates.json")
CITED_CLOSURE = os.path.join("evidence", "hurd-archive",
                             "hurd-amd64-build-closure-rebuild-candidates.json")
TRACKED = (LOCK, RESOLVER, DOCKERFILE, STATUS, STATUS_METADATA, BASE_CLOSURE,
           CITED_CLOSURE)

OTHER_DIGEST = "0" * 64


class Suite:
    def __init__(self):
        self.failed = 0

    def check(self, description, condition, evidence=""):
        if condition:
            print("ok    %s" % description)
        else:
            self.failed += 1
            print("FAIL  %s%s" % (description, (" (%s)" % evidence) if evidence else ""))


def make_fixture(workspace):
    """Copy the committed chain, whose links hold, into a writable tree."""
    for relative in TRACKED:
        target = os.path.join(workspace, relative)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy(os.path.join(ROOT, relative), target)
    return workspace


def run(workspace):
    return subprocess.run([sys.executable, WRITER], cwd=workspace, text=True,
                          capture_output=True, check=False)


def edit_json(workspace, relative, mutate):
    path = os.path.join(workspace, relative)
    with open(path, encoding="utf-8") as handle:
        document = json.load(handle)
    mutate(document)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2, sort_keys=True)
        handle.write("\n")


def refuses(suite, description, mutate):
    """Break one link, and require a refusal that leaves the lock untouched."""
    workspace = tempfile.mkdtemp(prefix="builder-lock-selftest-")
    try:
        make_fixture(workspace)
        lock_path = os.path.join(workspace, LOCK)
        mutate(workspace)
        # Read the lock after the mutation, because two cases break the link by
        # editing the lock itself and the claim is that a refused run writes
        # nothing rather than that the lock matches the committed one.
        with open(lock_path, "rb") as handle:
            before = handle.read()
        result = run(workspace)
        with open(lock_path, "rb") as handle:
            after = handle.read()
        suite.check(description, result.returncode != 0,
                    "exit %d" % result.returncode)
        suite.check("%s, and the lock stays as committed" % description,
                    before == after)
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


def drop(relative):
    return lambda workspace: os.remove(os.path.join(workspace, relative))


def set_field(relative, keys, value):
    def mutate(workspace):
        def apply(document):
            cursor = document
            for key in keys[:-1]:
                cursor = cursor[key]
            cursor[keys[-1]] = value
        edit_json(workspace, relative, apply)
    return mutate


def remove_field(relative, keys):
    def mutate(workspace):
        def apply(document):
            cursor = document
            for key in keys[:-1]:
                cursor = cursor[key]
            cursor.pop(keys[-1], None)
        edit_json(workspace, relative, apply)
    return mutate


def main():
    suite = Suite()

    # The control. Every case below differs from this tree in one document, so a
    # refusal here would make every refusal after it unattributable.
    workspace = tempfile.mkdtemp(prefix="builder-lock-selftest-")
    try:
        make_fixture(workspace)
        lock_path = os.path.join(workspace, LOCK)
        with open(lock_path, "rb") as handle:
            before = handle.read()
        result = run(workspace)
        with open(lock_path, "rb") as handle:
            after = handle.read()
        suite.check("the committed chain is accepted", result.returncode == 0,
                    result.stderr.strip())
        suite.check("the committed chain reproduces its lock byte for byte",
                    before == after)
    finally:
        shutil.rmtree(workspace, ignore_errors=True)

    for relative in (RESOLVER, DOCKERFILE, STATUS, STATUS_METADATA,
                     BASE_CLOSURE, CITED_CLOSURE):
        refuses(suite, "a tree missing %s is refused" % relative, drop(relative))

    refuses(suite, "status metadata naming another image is refused",
            set_field(STATUS_METADATA, ("source_image_sha256",), OTHER_DIGEST))
    refuses(suite, "status metadata stating no image is refused",
            remove_field(STATUS_METADATA, ("source_image_sha256",)))
    refuses(suite, "status metadata naming another manifest digest is refused",
            set_field(STATUS_METADATA, ("manifest_sha256",), OTHER_DIGEST))
    refuses(suite, "status metadata describing another manifest is refused",
            set_field(STATUS_METADATA, ("manifest",), "some-other-status"))

    refuses(suite, "a seeded closure from another installed state is refused",
            set_field(BASE_CLOSURE,
                      ("provenance", "installed_baseline", "sha256"), OTHER_DIGEST))
    refuses(suite, "a seeded closure from another archive is refused",
            set_field(BASE_CLOSURE, ("provenance", "archive_snapshot"),
                      "20200101T000000Z"))
    refuses(suite, "a seeded closure stating no archive is refused",
            remove_field(BASE_CLOSURE, ("provenance", "archive_snapshot")))
    refuses(suite, "a seeded closure from another resolver revision is refused",
            set_field(BASE_CLOSURE, ("provenance", "generator_sha256"), OTHER_DIGEST))
    refuses(suite, "a seeded closure from another resolver image is refused",
            set_field(BASE_CLOSURE, ("provenance", "resolver_image"),
                      "debian@sha256:%s" % OTHER_DIGEST))

    refuses(suite, "a cited closure from another archive is refused",
            set_field(CITED_CLOSURE, ("provenance", "archive_snapshot"),
                      "20200101T000000Z"))
    refuses(suite, "a cited closure from another resolver revision is refused",
            set_field(CITED_CLOSURE, ("provenance", "generator_sha256"), OTHER_DIGEST))
    refuses(suite, "a cited closure from another resolver image is refused",
            set_field(CITED_CLOSURE, ("provenance", "resolver_image"),
                      "debian@sha256:%s" % OTHER_DIGEST))

    # An edited resolver moves its own digest, so the closures the lock cites
    # were produced by a revision the tree no longer carries.
    def edit_resolver(workspace):
        path = os.path.join(workspace, RESOLVER)
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("\n# a revision the committed closures did not run\n")
    refuses(suite, "a resolver the cited closures did not run is refused",
            edit_resolver)

    def unpin_resolver_image(workspace):
        path = os.path.join(workspace, DOCKERFILE)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(re.sub(r"^ENV HURD_RESOLVER_IMAGE=.*$", "", text,
                                flags=re.MULTILINE))
    refuses(suite, "a Dockerfile pinning no resolver image is refused",
            unpin_resolver_image)

    refuses(suite, "a lock recording no base digest is refused",
            set_field(LOCK, ("builder_base", "sha256"), ""))
    refuses(suite, "a lock pinning no archive is refused",
            remove_field(LOCK, ("archive_snapshot",)))

    print("")
    print("%d failure(s)" % suite.failed)
    return 1 if suite.failed else 0


if __name__ == "__main__":
    sys.exit(main())
