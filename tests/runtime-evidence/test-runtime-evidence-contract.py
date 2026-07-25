#!/usr/bin/env python3
"""Assert the runtime evidence contract rejects the documents that broke it.

Each case names a defect that reached a committed capture or that the schema
admitted, and asserts the contract now rejects it.  A schema exercised only by
documents it accepts states nothing about what it excludes, so every case here
is a document that must fail.

The positive case is last: a minimal well-formed capture passes, so a change
that rejects everything fails this file rather than reading as a strengthened
gate.
"""

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CHECKER = os.path.join(ROOT, "scripts", "check-runtime-evidence.py")


def probe(name, out_text, err_text=""):
    return {
        "argv": ["true"],
        "started_at_utc": "2026-01-01T00:00:00Z",
        "completed_at_utc": "2026-01-01T00:00:01Z",
        "exit_status": 0,
        "stdout_file": "raw/%s.out" % name,
        "stderr_file": "raw/%s.err" % name,
        "stdout_sha256": hashlib.sha256(out_text.encode()).hexdigest(),
        "stderr_sha256": hashlib.sha256(err_text.encode()).hexdigest(),
    }


def observed(value, source="probe"):
    return {"value": value, "class": "observed", "source": source}


def absent(source="probe", reason="probe returned no value"):
    return {"value": None, "class": "not-captured", "source": source, "reason": reason}


def base_document():
    return {
        "schema_version": 2,
        "captured_at_utc": "20260101T000000Z",
        "reproduce": {"command": ["scripts/capture-runtime-evidence.py"],
                      "environment": {}},
        "evidence_classes": {"observed": "read from the live system"},
        "instance": {"container": observed("hurd-minty")},
        "repository": {"commit": observed("0" * 40)},
        "host": {"uname": observed("Linux <host>")},
        "declared": {"environment": observed({"FORCE_KVM": "1"})},
        "live_container": {"environment": observed({"FORCE_KVM": "1"})},
        "observed_runtime": {"accelerator": observed("kvm")},
        "observed_guest": {"uname": absent()},
        "image": {"guest_path": observed("/opt/hurd-image/hurd.qcow2")},
        "probes": {"host-uname": probe("host-uname", "Linux <host>\n")},
    }


def write_capture(directory, document, streams):
    os.makedirs(os.path.join(directory, "raw"), exist_ok=True)
    for name, (out_text, err_text) in streams.items():
        for suffix, text in ((".out", out_text), (".err", err_text)):
            with open(os.path.join(directory, "raw", name + suffix), "w",
                      encoding="utf-8") as fh:
                fh.write(text)
    with open(os.path.join(directory, "capture.json"), "w", encoding="utf-8") as fh:
        json.dump(document, fh, indent=2)


def run_checker(directory, require_redacted=False):
    argv = [sys.executable, CHECKER, directory]
    if require_redacted:
        argv.append("--require-redacted")
    done = subprocess.run(argv, capture_output=True, text=True, check=False)
    return done.returncode, done.stdout + done.stderr


CASES = []


def case(name):
    def register(fn):
        CASES.append((name, fn))
        return fn
    return register


@case("a null value claiming to be observed is rejected")
def null_observed(directory):
    doc = base_document()
    doc["observed_runtime"]["accelerator"] = {
        "value": None, "class": "observed", "source": "QEMU argv -accel"}
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 1


@case("a null value without a reason is rejected")
def null_without_reason(directory):
    doc = base_document()
    doc["observed_guest"]["uname"] = {
        "value": None, "class": "not-captured", "source": "guest uname -a"}
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 1


@case("a stdout digest that does not describe the retained file is rejected")
def stdout_digest_mismatch(directory):
    doc = base_document()
    write_capture(directory, doc, {"host-uname": ("Linux <different-host>\n", "")})
    return 1


@case("a stderr digest that does not describe the retained file is rejected")
def stderr_digest_mismatch(directory):
    doc = base_document()
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "unexpected\n")})
    return 1


@case("a probe advertising an absent stream is rejected")
def missing_stream(directory):
    doc = base_document()
    doc["probes"]["monitor-info"] = probe("monitor-info", "")
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 1


@case("a probe recording no stderr digest is rejected")
def missing_stderr_digest(directory):
    doc = base_document()
    del doc["probes"]["host-uname"]["stderr_sha256"]
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 1


@case("a home path in a capture published as redacted is rejected")
def unredacted_home_path(directory):
    doc = base_document()
    doc["reproduce"]["command"].append("/home/someone/scratch/compose.yaml")
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 1


@case("a scratchpad override path in a redacted capture is rejected")
def unredacted_scratch_path(directory):
    doc = base_document()
    stream = "COMPOSE_FILE=/tmp/claude-1000/session/compose.noforce.yaml\n"
    doc["probes"]["host-uname"] = probe("host-uname", stream)
    write_capture(directory, doc, {"host-uname": (stream, "")})
    return 1


@case("a wrong schema version is rejected")
def wrong_schema_version(directory):
    doc = base_document()
    doc["schema_version"] = 1
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 1


@case("a capture missing a required section is rejected")
def missing_section(directory):
    doc = base_document()
    del doc["live_container"]
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 1


@case("a directory with no capture.json is rejected")
def no_document(directory):
    os.makedirs(os.path.join(directory, "raw"), exist_ok=True)
    return 1


@case("an empty snapshot list stays an observation rather than an absence")
def empty_snapshot_list(directory):
    doc = base_document()
    doc["image"]["snapshot_tags"] = observed([], "qemu-img info --output=json")
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 0


@case("a well-formed redacted capture passes")
def well_formed(directory):
    doc = base_document()
    write_capture(directory, doc, {"host-uname": ("Linux <host>\n", "")})
    return 0


def main():
    failures = 0
    for name, build in CASES:
        with tempfile.TemporaryDirectory() as directory:
            capture_dir = os.path.join(directory, "capture")
            os.makedirs(capture_dir, exist_ok=True)
            expected = build(capture_dir)
            status, output = run_checker(capture_dir, require_redacted=True)
            if status != expected:
                failures += 1
                print("FAIL  %s\n  expected exit %d, got %d\n%s"
                      % (name, expected, status,
                         "\n".join("    " + l for l in output.splitlines()[:6])))
            else:
                print("ok    %s" % name)
    if failures:
        print("test-runtime-evidence-contract: FAIL (%d of %d)"
              % (failures, len(CASES)))
        return 1
    print("test-runtime-evidence-contract: OK (%d cases)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
