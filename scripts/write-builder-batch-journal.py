#!/usr/bin/env python3
"""Initialize and append an integrity-bound builder batch journal.

The plan is a schedule, not execution evidence.  Every guest action is added
as an immutable record that names the plan digest, planned batch members, its
timestamps, command result, and retained stream digests.  A resume never
silently substitutes a plan or repeats a completed batch.
"""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path


class JournalError(Exception):
    pass


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def plan_digest(plan):
    unsigned = dict(plan)
    unsigned.pop("plan_sha256", None)
    return hashlib.sha256(canonical(unsigned)).hexdigest()


def load(path, label):
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise JournalError("cannot read %s: %s" % (label, error))
    if not isinstance(value, dict):
        raise JournalError("%s is not a JSON object" % label)
    return value


def atomic_write(path, value):
    temporary = path.with_name(path.name + ".tmp-%d" % os.getpid())
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, path)


def checked_plan(path):
    plan = load(path, "batch plan")
    if plan.get("kind") != "builder-dependency-batch-plan":
        raise JournalError("batch plan has kind %r" % plan.get("kind"))
    if plan.get("plan_sha256") != plan_digest(plan):
        raise JournalError("batch plan has an invalid plan_sha256")
    batches = plan.get("batches")
    if not isinstance(batches, list) or not batches:
        raise JournalError("batch plan has no batches")
    return plan


def initialize(plan, journal_path):
    if journal_path.exists():
        raise JournalError("journal already exists: %s" % journal_path)
    journal = {
        "schema_version": 1,
        "kind": "builder-batch-journal",
        "plan_sha256": plan["plan_sha256"],
        "archive_snapshot": plan["archive_snapshot"],
        "records": [],
    }
    atomic_write(journal_path, journal)


def append(plan, journal_path, record_path):
    journal = load(journal_path, "journal")
    if journal.get("kind") != "builder-batch-journal":
        raise JournalError("journal has kind %r" % journal.get("kind"))
    if journal.get("plan_sha256") != plan["plan_sha256"]:
        raise JournalError("journal names another batch plan")
    record = load(record_path, "record")
    batch_id = record.get("batch_id")
    matching = [item for item in plan["batches"] if item.get("batch_id") == batch_id]
    if len(matching) != 1:
        raise JournalError("record names no planned batch: %r" % batch_id)
    batch = matching[0]
    if record.get("batch_index") != batch.get("batch_index"):
        raise JournalError("record index does not match %s" % batch_id)
    if record.get("members") != batch.get("members"):
        raise JournalError("record members do not match %s" % batch_id)
    for field in plan["journal_schema"]["required_record_fields"]:
        if field not in record:
            raise JournalError("record for %s omits %s" % (batch_id, field))
    if record.get("outcome") not in {"completed", "simulation-failed",
                                     "install-failed", "sync-failed",
                                     "reboot-failed"}:
        raise JournalError("record for %s has invalid outcome %r" %
                           (batch_id, record.get("outcome")))
    simulation = record.get("pre_batch_simulation")
    if not isinstance(simulation, dict):
        raise JournalError("record for %s has no simulation object" % batch_id)
    for field in plan["journal_schema"]["pre_batch_simulation_required_fields"]:
        if field not in simulation:
            raise JournalError("simulation for %s omits %s" % (batch_id, field))
    expected_command = batch["guest_pre_batch_simulation"]["command"]
    if simulation.get("command") != expected_command:
        raise JournalError("simulation command does not match %s" % batch_id)
    if any(item.get("batch_id") == batch_id for item in journal["records"]):
        raise JournalError("journal already records %s" % batch_id)
    journal["records"].append(record)
    atomic_write(journal_path, journal)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--journal", required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--initialize", action="store_true")
    group.add_argument("--append-record")
    args = parser.parse_args()
    try:
        plan = checked_plan(Path(args.plan))
        journal_path = Path(args.journal)
        if args.initialize:
            initialize(plan, journal_path)
        else:
            append(plan, journal_path, Path(args.append_record))
    except JournalError as error:
        print("builder batch journal: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
