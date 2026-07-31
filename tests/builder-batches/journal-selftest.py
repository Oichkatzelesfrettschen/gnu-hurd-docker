#!/usr/bin/env python3
"""Prove that a batch journal accepts only the plan it was given."""

import json
import os
import shutil
import subprocess
import sys
import tempfile


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLANNER_TEST = os.path.join(ROOT, "tests", "builder-batches", "selftest.py")
WRITER = os.path.join(ROOT, "scripts", "write-builder-batch-journal.py")


def command(arguments, cwd):
    return subprocess.run(arguments, cwd=cwd, text=True, capture_output=True,
                          check=False)


def main():
    workspace = tempfile.mkdtemp(prefix="builder-journal-selftest-")
    try:
        # Reuse the planner fixture constructor instead of duplicating its lock
        # format. The test imports no guest and makes no network request.
        fixture = os.path.join(workspace, "fixture")
        os.makedirs(fixture)
        source = open(PLANNER_TEST, encoding="utf-8").read()
        namespace = {"__file__": PLANNER_TEST, "__name__": "fixture_import"}
        exec(compile(source, PLANNER_TEST, "exec"), namespace)
        lock, status, closure = namespace["make_fixture"](fixture, [
            "fixture-one (1.0)", "fixture-two (1.0)"])
        planner = os.path.join(ROOT, "scripts", "plan-builder-batches.py")
        result = command([sys.executable, planner, "--lock", lock, "--status", status,
                          "--closure", closure, "--output", "plan.json"], fixture)
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            return 1
        journal = "journal.json"
        result = command([sys.executable, WRITER, "--plan", "plan.json", "--journal",
                          journal, "--initialize"], fixture)
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            return 1
        with open(os.path.join(fixture, "plan.json"), encoding="utf-8") as handle:
            plan = json.load(handle)
        batch = plan["batches"][0]
        record = {
            "batch_id": batch["batch_id"], "batch_index": batch["batch_index"],
            "members": batch["members"], "started_at_utc": "2026-07-30T00:00:00Z",
            "outcome": "completed",
            "pre_batch_simulation": {
                "command": batch["guest_pre_batch_simulation"]["command"],
                "completed_at_utc": "2026-07-30T00:00:01Z", "exit_status": 0,
                "stdout_sha256": "a" * 64, "stderr_sha256": "b" * 64,
                "simulated_package_count": 2},
            "install": {}, "sync": {}, "reboot": {}}
        with open(os.path.join(fixture, "record.json"), "w", encoding="utf-8") as handle:
            json.dump(record, handle)
        accepted = command([sys.executable, WRITER, "--plan", "plan.json", "--journal",
                            journal, "--append-record", "record.json"], fixture)
        record["members"] = []
        with open(os.path.join(fixture, "bad.json"), "w", encoding="utf-8") as handle:
            json.dump(record, handle)
        refused = command([sys.executable, WRITER, "--plan", "plan.json", "--journal",
                           journal, "--append-record", "bad.json"], fixture)
        passed = accepted.returncode == 0 and refused.returncode != 0
        print("ok    the journal binds a guest record to its planned members" if passed
              else "FAIL  journal binding")
        return 0 if passed else 1
    finally:
        shutil.rmtree(workspace)


if __name__ == "__main__":
    sys.exit(main())
