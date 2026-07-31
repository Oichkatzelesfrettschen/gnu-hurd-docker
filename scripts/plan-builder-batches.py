#!/usr/bin/env python3
"""Create a stock-kernel builder dependency plan from certified inputs.

The host resolver supplies the complete transaction ordering, but it uses amd64
APT and cannot establish how the hurd-amd64 guest will solve the same request.
The plan therefore limits each stock GNU Mach round to the retained 40-package
IPC-map bound and records a guest `apt-get -s` as a required journal entry
before the matching installation.  It schedules work; it does not claim that
the guest simulation or installation has happened.
"""

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path


DEFAULT_LOCK = "config/minty/builder.lock.json"
DEFAULT_STATUS = "evidence/builder-base/hurd-amd64-dpkg-status"
DEFAULT_CLOSURE = (
    "evidence/builder-base/hurd-amd64-build-closure-rebuild-candidates.json"
)
# The campaign that sets the round bound. `.gitattributes` keeps `docs/reports/`
# out of the release archive as past work, so this is a provenance string the
# planner records rather than a file it opens: asserting it here would leave the
# packaged planner and the packaged validator failing inside the product. The
# repository is where the citation has to resolve, and the offline selftest is
# what asserts that.
BATCH_BOUND_EVIDENCE = "docs/reports/GUEST-UPGRADE-CAMPAIGN-2026-07-16.md"
PLAN_SCHEMA_VERSION = 1
JOURNAL_SCHEMA_VERSION = 1
MAX_PACKAGES_PER_BATCH = 40
DIGEST = re.compile(r"^[0-9a-f]{64}$")
PACKAGE = re.compile(r"^[a-z0-9][a-z0-9+.-]*$")


class PlanningError(Exception):
    """An input does not identify one reproducible dependency transaction."""


def sha256(path):
    """Return the digest of one regular input file."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json(document):
    """Encode the plan once, so its journal binding is reproducible."""
    return json.dumps(document, sort_keys=True, separators=(",", ":")).encode("utf-8")


def plan_digest(document):
    """Hash every plan field except the field carrying the hash itself."""
    unsigned = dict(document)
    unsigned.pop("plan_sha256", None)
    return hashlib.sha256(canonical_json(unsigned)).hexdigest()


def repository_file(repository_root, relative_name, label):
    """Open a non-symlinked regular file below the selected repository root."""
    candidate = Path(relative_name)
    if candidate.is_absolute():
        raise PlanningError("%s must be repository-relative, not %s" %
                            (label, relative_name))
    root = repository_root.resolve()
    resolved = (root / candidate).resolve()
    try:
        resolved.relative_to(root)
    except ValueError:
        raise PlanningError("%s escapes the repository root: %s" %
                            (label, relative_name))
    original = root / candidate
    if original.is_symlink():
        raise PlanningError("%s is a symlink: %s" % (label, relative_name))
    if not resolved.is_file():
        raise PlanningError("%s is not a regular file: %s" %
                            (label, relative_name))
    return resolved


def repository_name(repository_root, relative_name, label):
    """Return a normalized repository-relative name without exposing host paths."""
    candidate = Path(relative_name)
    if candidate.is_absolute():
        raise PlanningError("%s must be repository-relative, not %s" %
                            (label, relative_name))
    root = repository_root.resolve()
    resolved = (root / candidate).resolve()
    try:
        return resolved.relative_to(root).as_posix()
    except ValueError:
        raise PlanningError("%s escapes the repository root: %s" %
                            (label, relative_name))


def load_json(path, label):
    """Load one object document and reject arbitrary JSON values."""
    try:
        with open(path, encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise PlanningError("cannot read %s: %s" % (label, error))
    if not isinstance(document, dict):
        raise PlanningError("%s must contain a JSON object" % label)
    return document


def required_digest(document, key, label):
    """Read a SHA-256 field that can bind an input instead of naming one."""
    value = document.get(key)
    if not isinstance(value, str) or not DIGEST.fullmatch(value):
        raise PlanningError("%s records no valid SHA-256 in %s" % (label, key))
    return value


def transaction_members(closure):
    """Turn apt's ordered transaction display into distinct package members."""
    if closure.get("transaction_result") != "success":
        raise PlanningError("the seeded closure transaction_result is not success")
    if closure.get("resolvable_subset_resolves") is not True:
        raise PlanningError("the seeded closure does not resolve its subset")
    entries = closure.get("recursive_transaction")
    declared_size = closure.get("recursive_transaction_size")
    if not isinstance(entries, list) or not entries:
        raise PlanningError("the seeded closure has no recursive transaction")
    if not isinstance(declared_size, int) or declared_size != len(entries):
        raise PlanningError("the seeded closure declares transaction size %r for %d entries" %
                            (declared_size, len(entries)))

    members = []
    seen = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, str) or not entry:
            raise PlanningError("transaction entry %d is not a non-empty string" % index)
        package = entry.split(None, 1)[0]
        if not PACKAGE.fullmatch(package):
            raise PlanningError("transaction entry %d has invalid package %r" %
                                (index, package))
        if package in seen:
            raise PlanningError("transaction names %s more than once" % package)
        seen.add(package)
        members.append({"transaction_index": index, "package": package,
                        "resolver_entry": entry})
    return members


def simulation_command(members):
    """Return the exact guest command a future executor must journal and honor."""
    return ["apt-get", "-s", "install", "-y", "--no-install-recommends"] + [
        member["package"] for member in members
    ]


def build_plan(repository_root, lock_name, status_name, closure_name):
    """Derive all batches after proving every retained input names one base."""
    lock_path = repository_file(repository_root, lock_name, "builder lock")
    status_path = repository_file(repository_root, status_name, "base status")
    closure_path = repository_file(repository_root, closure_name, "seeded closure")
    lock = load_json(lock_path, "builder lock")

    if lock.get("schema_version") != 1:
        raise PlanningError("builder lock schema_version is %r" %
                            lock.get("schema_version"))
    snapshot = lock.get("archive_snapshot")
    if not isinstance(snapshot, str) or not snapshot:
        raise PlanningError("builder lock records no archive_snapshot")
    base = lock.get("builder_base")
    if not isinstance(base, dict):
        raise PlanningError("builder lock records no builder_base object")
    base_digest = required_digest(base, "sha256", "builder base")
    status_digest = required_digest(base, "status_sha256", "builder base")
    closure_digest = required_digest(base, "build_closure_report_sha256",
                                     "builder base")
    base_path = base.get("path")
    if not isinstance(base_path, str) or not base_path:
        raise PlanningError("builder lock records no builder_base.path")
    base_path = repository_name(repository_root, base_path, "builder_base.path")

    measured_status = sha256(status_path)
    if measured_status != status_digest:
        raise PlanningError("base status hashes to %s, lock declares %s" %
                            (measured_status, status_digest))
    measured_closure = sha256(closure_path)
    if measured_closure != closure_digest:
        raise PlanningError("seeded closure hashes to %s, lock declares %s" %
                            (measured_closure, closure_digest))

    closure = load_json(closure_path, "seeded closure")
    provenance = closure.get("provenance")
    if not isinstance(provenance, dict):
        raise PlanningError("seeded closure records no provenance object")
    if provenance.get("archive_snapshot") != snapshot:
        raise PlanningError("seeded closure archive snapshot %r differs from lock %r" %
                            (provenance.get("archive_snapshot"), snapshot))
    baseline = provenance.get("installed_baseline")
    if not isinstance(baseline, dict):
        raise PlanningError("seeded closure records no installed baseline")
    if baseline.get("sha256") != status_digest:
        raise PlanningError("seeded closure baseline digest %r differs from lock %r" %
                            (baseline.get("sha256"), status_digest))
    if baseline.get("architecture") != "hurd-amd64":
        raise PlanningError("seeded closure baseline architecture is %r" %
                            baseline.get("architecture"))

    members = transaction_members(closure)
    batches = []
    for first in range(0, len(members), MAX_PACKAGES_PER_BATCH):
        batch_members = members[first:first + MAX_PACKAGES_PER_BATCH]
        batch_index = len(batches) + 1
        batches.append({
            "batch_id": "builder-dependencies-%03d" % batch_index,
            "batch_index": batch_index,
            "members": batch_members,
            "member_count": len(batch_members),
            "guest_pre_batch_simulation": {
                "command": simulation_command(batch_members),
                "must_succeed_before_install": True,
            },
            "guest_reboot_after_install": True,
        })

    plan = {
        "schema_version": PLAN_SCHEMA_VERSION,
        "kind": "builder-dependency-batch-plan",
        "archive_snapshot": snapshot,
        "builder_base": {
            "path": base_path,
            "sha256": base_digest,
            "status_path": repository_name(repository_root, status_name,
                                             "base status"),
            "status_sha256": status_digest,
        },
        "closure": {
            "path": repository_name(repository_root, closure_name,
                                     "seeded closure"),
            "sha256": closure_digest,
            "transaction_size": len(members),
        },
        "stock_kernel_batch_bound": {
            "max_packages_requested": MAX_PACKAGES_PER_BATCH,
            "evidence": BATCH_BOUND_EVIDENCE,
            "reason": (
                "A reboot resets the stock GNU Mach IPC map; the retained "
                "campaign completed 40-package rounds, while transactions "
                "above 100 packages are recorded as a wedge risk."
            ),
            "bounds": (
                "The size of the request each round names, not the number of "
                "packages that round installs. The transaction is resolved "
                "against the base's own installed state and still names "
                "members the base already satisfies, so the installed count "
                "is whatever the guest's own simulation reports and is "
                "recorded per round as pre_batch_simulation."
                "simulated_package_count."
            ),
            "falsifier": (
                "A guest pre-batch apt-get -s failure or a recorded Mach "
                "IPC-map allocation failure rejects that batch plan."
            ),
        },
        "journal_schema": {
            "schema_version": JOURNAL_SCHEMA_VERSION,
            "kind": "builder-batch-journal",
            "required_record_fields": [
                "batch_id", "batch_index", "members", "started_at_utc",
                "outcome", "guest_console", "pre_batch_simulation", "install",
                "sync", "reboot",
            ],
            "pre_batch_simulation_required_fields": [
                "command", "completed_at_utc", "exit_status",
                "stdout_sha256", "stderr_sha256", "simulated_package_count",
            ],
            "acceptance": "pre_batch_simulation.exit_status == 0",
        },
        "batches": batches,
    }
    plan["plan_sha256"] = plan_digest(plan)
    return plan


def write_plan(path, plan):
    """Atomically replace one requested plan after validating its path boundary."""
    target = Path(path)
    if target.is_absolute():
        raise PlanningError("output path must be repository-relative, not %s" % path)
    root = Path.cwd().resolve()
    resolved = (root / target).resolve()
    try:
        resolved.relative_to(root)
    except ValueError:
        raise PlanningError("output path escapes the repository root: %s" % path)
    if resolved.exists() and resolved.is_symlink():
        raise PlanningError("output path is a symlink: %s" % path)
    if not resolved.parent.is_dir():
        raise PlanningError("output directory does not exist: %s" %
                            target.parent.as_posix())
    temporary = resolved.with_name(resolved.name + ".tmp-%d" % os.getpid())
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(plan, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, resolved)


def parse_arguments():
    """Keep the default inputs aligned with the lock writer's evidence paths."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", default=DEFAULT_LOCK)
    parser.add_argument("--status", default=DEFAULT_STATUS)
    parser.add_argument("--closure", default=DEFAULT_CLOSURE)
    parser.add_argument("--output", help="repository-relative JSON plan path")
    parser.add_argument("--check", action="store_true",
                        help="validate inputs and derive the plan without writing it")
    args = parser.parse_args()
    if args.check and args.output:
        parser.error("--check and --output are mutually exclusive")
    return args


def main():
    """Derive a plan or return a useful failure before any guest run starts."""
    args = parse_arguments()
    try:
        plan = build_plan(Path.cwd(), args.lock, args.status, args.closure)
        if args.output:
            write_plan(args.output, plan)
            print("wrote %s (%d batches, %d packages, sha256 %s)" %
                  (args.output, len(plan["batches"]),
                   plan["closure"]["transaction_size"], plan["plan_sha256"]))
        elif args.check:
            print("builder batch plan is reproducible (%d batches, %d packages, sha256 %s)" %
                  (len(plan["batches"]), plan["closure"]["transaction_size"],
                   plan["plan_sha256"]))
        else:
            json.dump(plan, sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
    except PlanningError as error:
        print("builder batch planner: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
