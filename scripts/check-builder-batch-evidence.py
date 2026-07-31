#!/usr/bin/env python3
"""Assert the committed builder batch evidence against itself and the lock.

A package of runs states what a guest did, and nothing read it. The journal
writer already refuses a record that does not match its plan, but that check
runs when a record is written and says nothing about the files a clone receives.
This reads the committed package: every journal resolves to a committed plan by
digest, every record names a planned batch with the planned members, every
manifest indexes files the package contains, and the base the runs declare is
the base the lock pins. Runs that name one plan are compared against each other,
because the package's own argument is that they agree except in the one QEMU
setting they are named for.
"""

import hashlib
import json
import os
import sys

PACKAGE = "evidence/builder-batches"
LOCK = "config/minty/builder.lock.json"
OUTCOMES = {"completed", "simulation-failed", "install-failed", "sync-failed",
            "reboot-failed", "mach-console-error"}


class Suite:
    def __init__(self):
        self.failed = 0

    def check(self, description, condition, evidence=""):
        if condition:
            print("ok    %s" % description)
        else:
            self.failed += 1
            print("FAIL  %s%s" % (description, (" (%s)" % evidence) if evidence else ""))
        return bool(condition)


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def plan_digest(plan):
    unsigned = dict(plan)
    unsigned.pop("plan_sha256", None)
    return hashlib.sha256(json.dumps(unsigned, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def indexed_names(manifest):
    """Every file name a run manifest points at, wherever it records one."""
    names = []
    for key in ("batch_journal",):
        if isinstance(manifest.get(key), str):
            names.append(manifest[key])
    plan = manifest.get("batch_plan")
    if isinstance(plan, dict) and isinstance(plan.get("path"), str):
        names.append(plan["path"])
    checks = manifest.get("offline_checks")
    if isinstance(checks, dict):
        names.extend(value for key, value in checks.items()
                     if key.endswith("transcript") and isinstance(value, str))
    console = manifest.get("guest_console")
    if isinstance(console, dict) and isinstance(console.get("transcript"), str):
        names.append(console["transcript"])
    return names


def main():
    suite = Suite()
    if not os.path.isdir(PACKAGE):
        print("no builder batch evidence at %s" % PACKAGE, file=sys.stderr)
        return 2
    lock = load(LOCK)
    snapshot = lock.get("archive_snapshot")
    base_sha = lock.get("builder_base", {}).get("sha256")

    runs = sorted(name for name in os.listdir(PACKAGE)
                  if os.path.isdir(os.path.join(PACKAGE, name)))
    suite.check("the package holds at least one run", bool(runs))

    plans = {}
    for run in runs:
        candidate = os.path.join(PACKAGE, run, "batch-plan.json")
        if os.path.isfile(candidate):
            plan = load(candidate)
            plans[plan.get("plan_sha256")] = plan
            suite.check("%s: the plan digest covers its own document" % run,
                        plan.get("plan_sha256") == plan_digest(plan))

    counts_by_plan = {}
    for run in runs:
        directory = os.path.join(PACKAGE, run)
        manifest = load(os.path.join(directory, "run.json"))
        journal = load(os.path.join(directory, "batch-journal.json"))

        suite.check("%s: the run left the builder base unchanged" % run,
                    manifest["builder_base"]["sha256_before"]
                    == manifest["builder_base"]["sha256_after"])
        suite.check("%s: the run names the base the lock pins" % run,
                    manifest["builder_base"]["sha256_before"] == base_sha)
        suite.check("%s: the run names the archive the lock pins" % run,
                    manifest.get("archive_snapshot") == snapshot)

        missing = [name for name in indexed_names(manifest)
                   if not os.path.isfile(os.path.join(directory, name))]
        suite.check("%s: every file the manifest indexes is present" % run,
                    not missing, ", ".join(missing))

        digest = journal.get("plan_sha256")
        plan = plans.get(digest)
        if not suite.check("%s: the journal resolves to a committed plan" % run,
                           plan is not None, str(digest)):
            continue
        planned = {batch["batch_id"]: batch for batch in plan["batches"]}

        records = journal.get("records", [])
        unplanned = [record.get("batch_id") for record in records
                     if record.get("batch_id") not in planned]
        suite.check("%s: every record names a planned batch" % run,
                    not unplanned, ", ".join(str(name) for name in unplanned))
        suite.check("%s: every record carries its planned members" % run,
                    all(record.get("members") == planned[record["batch_id"]]["members"]
                        for record in records if record.get("batch_id") in planned))
        suite.check("%s: every record has a known outcome" % run,
                    all(record.get("outcome") in OUTCOMES for record in records))
        suite.check("%s: the journal records every planned batch once" % run,
                    sorted(record.get("batch_id") for record in records)
                    == sorted(planned))

        # A completed round whose record predates the console mechanism states
        # nothing about it, and reporting that as a clear console would repeat
        # the failure the mechanism exists to prevent.
        observed = [record.get("guest_console", {}).get("scanned") is True
                    for record in records if record.get("outcome") == "completed"]
        print("info  %s: %d completed round(s), Mach console %s" %
              (run, len(observed),
               "observed" if observed and all(observed) else "not observed"))

        counts_by_plan.setdefault(digest, {})[run] = [
            record.get("pre_batch_simulation", {}).get("simulated_package_count")
            for record in records]

    for digest, by_run in counts_by_plan.items():
        if len(by_run) < 2:
            continue
        series = list(by_run.values())
        suite.check("runs sharing plan %s installed the same packages per round"
                    % digest[:12],
                    all(entry == series[0] for entry in series),
                    "; ".join("%s=%s" % item for item in by_run.items()))

    print("")
    print("%d failure(s)" % suite.failed)
    return 1 if suite.failed else 0


if __name__ == "__main__":
    sys.exit(main())
