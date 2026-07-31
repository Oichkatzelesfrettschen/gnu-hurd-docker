#!/usr/bin/env python3
"""Exercise the builder batch planner with certified-style fixture inputs.

The live closure is archive evidence.  These fixtures assert the planner's
binding and partition rules without treating a moving archive as a test input.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLANNER = os.path.join(ROOT, "scripts", "plan-builder-batches.py")


def digest_bytes(value):
    return hashlib.sha256(value).hexdigest()


def write(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(value)


def write_json(path, value):
    write(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8"))


def make_fixture(root, entries=None, archive_snapshot="20260726T003219Z"):
    """Write a lock, status, and closure whose digests bind to each other."""
    if entries is None:
        entries = ["fixture-%03d (1.0 fixture [hurd-amd64])" % number
                   for number in range(1, 84)]
    status_name = "evidence/builder-base/hurd-amd64-dpkg-status"
    closure_name = (
        "evidence/builder-base/hurd-amd64-build-closure-rebuild-candidates.json"
    )
    lock_name = "config/minty/builder.lock.json"
    # The planner asserts that the campaign its round bound cites resolves, so
    # a fixture root that omits it exercises that assertion rather than the
    # binding rules these cases are about.
    write(os.path.join(root, "docs/reports/GUEST-UPGRADE-CAMPAIGN-2026-07-16.md"),
          b"# fixture stand-in for the retained upgrade campaign\n")
    status_bytes = b"Package: fixture-base\nStatus: install ok installed\n\n"
    write(os.path.join(root, status_name), status_bytes)
    closure = {
        "provenance": {
            "archive_snapshot": archive_snapshot,
            "installed_baseline": {
                "architecture": "hurd-amd64",
                "sha256": digest_bytes(status_bytes),
            },
        },
        "transaction_result": "success",
        "resolvable_subset_resolves": True,
        "recursive_transaction_size": len(entries),
        "recursive_transaction": entries,
    }
    closure_path = os.path.join(root, closure_name)
    write_json(closure_path, closure)
    with open(closure_path, "rb") as handle:
        closure_digest = hashlib.sha256(handle.read()).hexdigest()
    lock = {
        "schema_version": 1,
        "archive_snapshot": archive_snapshot,
        "builder_base": {
            "path": "images/minty-hurd-builder-base.qcow2",
            "sha256": "a" * 64,
            "status_sha256": digest_bytes(status_bytes),
            "build_closure_report_sha256": closure_digest,
        },
    }
    write_json(os.path.join(root, lock_name), lock)
    return lock_name, status_name, closure_name


def run(root, lock_name, status_name, closure_name, output_name="plan.json"):
    return subprocess.run(
        [sys.executable, PLANNER, "--lock", lock_name, "--status", status_name,
         "--closure", closure_name, "--output", output_name],
        cwd=root, capture_output=True, text=True, check=False)


class Suite:
    def __init__(self):
        self.failed = 0

    def check(self, description, condition, evidence=""):
        if condition:
            print("ok    %s" % description)
        else:
            self.failed += 1
            print("FAIL  %s%s" % (description,
                                   (" (%s)" % evidence[:300]) if evidence else ""))


def plan_sha256(plan):
    unsigned = dict(plan)
    unsigned.pop("plan_sha256", None)
    encoded = json.dumps(unsigned, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def main():
    suite = Suite()
    workspace = tempfile.mkdtemp(prefix="builder-batches-selftest-")
    try:
        pristine = os.path.join(workspace, "pristine")
        lock_name, status_name, closure_name = make_fixture(pristine)
        result = run(pristine, lock_name, status_name, closure_name)
        with open(os.path.join(pristine, "plan.json"), encoding="utf-8") as handle:
            plan = json.load(handle)
        batches = plan.get("batches", [])
        package_names = [member["package"] for batch in batches
                         for member in batch["members"]]
        suite.check("a bound closure plan is accepted", result.returncode == 0,
                    result.stdout + result.stderr)
        suite.check("83 packages form 40, 40, and 3-member batches",
                    [batch["member_count"] for batch in batches] == [40, 40, 3],
                    str([batch.get("member_count") for batch in batches]))
        suite.check("the resolver order survives partitioning",
                    package_names == ["fixture-%03d" % number
                                      for number in range(1, 84)])
        suite.check("the plan digest covers its unsigned JSON document",
                    plan.get("plan_sha256") == plan_sha256(plan))
        suite.check("each batch requires its own guest simulation",
                    all(batch["guest_pre_batch_simulation"].get(
                        "must_succeed_before_install") is True
                        and batch["guest_pre_batch_simulation"]["command"][:5]
                        == ["apt-get", "-s", "install", "-y",
                            "--no-install-recommends"]
                        for batch in batches))
        required = set(plan.get("journal_schema", {}).get(
            "pre_batch_simulation_required_fields", []))
        suite.check("the journal schema retains simulation time, hashes, and count",
                    {"completed_at_utc", "stdout_sha256", "stderr_sha256",
                     "simulated_package_count"}.issubset(required), str(required))

        changed = os.path.join(workspace, "changed-closure")
        lock_name, status_name, closure_name = make_fixture(changed)
        with open(os.path.join(changed, closure_name), "ab") as handle:
            handle.write(b" ")
        result = run(changed, lock_name, status_name, closure_name)
        suite.check("a closure changed after lock creation is rejected",
                    result.returncode != 0 and "hashes to" in result.stderr,
                    result.stderr)

        divergent = os.path.join(workspace, "divergent-snapshot")
        lock_name, status_name, closure_name = make_fixture(divergent)
        closure_path = os.path.join(divergent, closure_name)
        with open(closure_path, encoding="utf-8") as handle:
            closure = json.load(handle)
        closure["provenance"]["archive_snapshot"] = "20260727T000000Z"
        write_json(closure_path, closure)
        with open(closure_path, "rb") as handle:
            closure_digest = hashlib.sha256(handle.read()).hexdigest()
        lock_path = os.path.join(divergent, lock_name)
        with open(lock_path, encoding="utf-8") as handle:
            lock = json.load(handle)
        lock["builder_base"]["build_closure_report_sha256"] = closure_digest
        write_json(lock_path, lock)
        result = run(divergent, lock_name, status_name, closure_name)
        suite.check("a closure from another snapshot is rejected",
                    result.returncode != 0 and "archive snapshot" in result.stderr,
                    result.stderr)

        duplicate = os.path.join(workspace, "duplicate-package")
        lock_name, status_name, closure_name = make_fixture(
            duplicate, ["fixture-one (1.0)", "fixture-one (1.1)"])
        result = run(duplicate, lock_name, status_name, closure_name)
        suite.check("a transaction naming one package twice is rejected",
                    result.returncode != 0 and "more than once" in result.stderr,
                    result.stderr)
    finally:
        shutil.rmtree(workspace)

    print("%d failure(s)" % suite.failed)
    return 1 if suite.failed else 0


if __name__ == "__main__":
    sys.exit(main())
