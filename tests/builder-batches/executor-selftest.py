#!/usr/bin/env python3
"""Check the builder executor's simulation and SSH timeout boundaries."""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLANNER_TEST = os.path.join(ROOT, "tests", "builder-batches", "selftest.py")
PLANNER = os.path.join(ROOT, "scripts", "plan-builder-batches.py")
WRITER = os.path.join(ROOT, "scripts", "write-builder-batch-journal.py")
EXECUTOR = os.path.join(ROOT, "scripts", "execute-builder-batches.sh")


def command(arguments, cwd, environment):
    return subprocess.run(arguments, cwd=cwd, text=True, capture_output=True,
                          env=environment, check=False)


def main():
    workspace = tempfile.mkdtemp(prefix="builder-executor-selftest-")
    try:
        fixture = os.path.join(workspace, "fixture")
        os.makedirs(fixture)
        source = open(PLANNER_TEST, encoding="utf-8").read()
        namespace = {"__file__": PLANNER_TEST, "__name__": "fixture_import"}
        exec(compile(source, PLANNER_TEST, "exec"), namespace)
        lock, status, closure = namespace["make_fixture"](fixture, [
            "fixture-one (1.0)", "fixture-two (1.0)"])
        environment = os.environ.copy()
        result = command([sys.executable, PLANNER, "--lock", lock, "--status", status,
                          "--closure", closure, "--output", "plan.json"], fixture,
                         environment)
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            return 1
        result = command([sys.executable, WRITER, "--plan", "plan.json", "--journal",
                          "journal.json", "--initialize"], fixture, environment)
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            return 1

        mock_directory = os.path.join(fixture, "mock-bin")
        os.makedirs(mock_directory)
        mock_ssh = os.path.join(mock_directory, "ssh")
        with open(mock_ssh, "w", encoding="utf-8") as handle:
            handle.write("#!/bin/sh\n")
            handle.write("for argument do command=\"$argument\"; done\n")
            handle.write("printf '%s\\n' \"$command\" >> \"$MOCK_SSH_LOG\"\n")
            handle.write("case \"$command\" in\n")
            handle.write("  'exit 0') sleep \"${MOCK_SSH_LIVENESS_DELAY:-0}\"; exit 0 ;;\n")
            handle.write("  'DEBIAN_FRONTEND=noninteractive apt-get -s '*) printf 'simulation deliberately failed\\n'; exit 100 ;;\n")
            handle.write("  *) printf 'unexpected command: %s\\n' \"$command\" >&2; exit 1 ;;\n")
            handle.write("esac\n")
        os.chmod(mock_ssh, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        environment["PATH"] = mock_directory + os.pathsep + environment["PATH"]
        environment["MOCK_SSH_LOG"] = os.path.join(fixture, "ssh.log")
        environment["BUILDER_SSH_READY_TIMEOUT"] = "1"
        result = command([EXECUTOR, "--plan", "plan.json", "--journal", "journal.json",
                          "--run-dir", "."], fixture, environment)
        with open(os.path.join(fixture, "journal.json"), encoding="utf-8") as handle:
            journal = json.load(handle)
        with open(environment["MOCK_SSH_LOG"], encoding="utf-8") as handle:
            calls = handle.read()
        records = journal.get("records", [])
        passed = (result.returncode != 0 and len(records) == 1 and
                  records[0].get("outcome") == "simulation-failed" and
                  "apt-get -s install" in calls and "apt-get install" not in calls)
        if not passed:
            print("executor stdout:\n%s" % result.stdout, file=sys.stderr)
            print("executor stderr:\n%s" % result.stderr, file=sys.stderr)
            print("SSH calls:\n%s" % calls, file=sys.stderr)
            print("journal:\n%s" % json.dumps(journal, indent=2), file=sys.stderr)
        print("ok    a failed guest simulation records its result and blocks install"
              if passed else "FAIL  failed simulation safety boundary")
        if not passed:
            return 1

        absent = records[0].get("guest_console", {})
        console_absent = absent.get("scanned") is False and \
            absent.get("mach_ipc_allocation_error") is None

        # A transcript carrying firmware and GRUB output but no GNU Mach banner
        # is what a guest whose multiboot line names no console=com0 produces.
        # Its zero Mach matches say nothing, so the record has to keep reporting
        # the falsifier unobserved rather than clear.
        result = command([sys.executable, WRITER, "--plan", "plan.json", "--journal",
                          "vga-journal.json", "--initialize"], fixture, environment)
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            return 1
        with open(os.path.join(fixture, "serial.log"), "w", encoding="utf-8") as handle:
            handle.write("SeaBIOS (version 1.16.3-debian)\nBooting from Hard Disk...\n"
                         "GRUB loading.\nWelcome to GRUB!\n")
        command([EXECUTOR, "--plan", "plan.json", "--journal", "vga-journal.json",
                 "--run-dir", "."], fixture, environment)
        with open(os.path.join(fixture, "vga-journal.json"), encoding="utf-8") as handle:
            vga_console = json.load(handle)["records"][0].get("guest_console", {})
        os.remove(os.path.join(fixture, "serial.log"))
        console_vga = vga_console.get("scanned") is False and \
            vga_console.get("mach_ipc_allocation_error") is None
        console_passed = console_absent and console_vga
        if not console_passed:
            print("absent-console record: %s" % json.dumps(absent), file=sys.stderr)
            print("vga-console record: %s" % json.dumps(vga_console), file=sys.stderr)
        print("ok    a console carrying no GNU Mach output stays an unobserved falsifier"
              if console_passed else "FAIL  console falsifier reported as clear")
        if not console_passed:
            return 1

        result = command([sys.executable, WRITER, "--plan", "plan.json", "--journal",
                          "probe-journal.json", "--initialize"], fixture, environment)
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            return 1
        environment["MOCK_SSH_LIVENESS_DELAY"] = "4"
        environment["GUEST_SSH_PROBE_TIMEOUT"] = "1"
        environment["BUILDER_SSH_READY_TIMEOUT"] = "1"
        started = time.monotonic()
        result = command([EXECUTOR, "--plan", "plan.json", "--journal", "probe-journal.json",
                          "--run-dir", "."], fixture, environment)
        elapsed = time.monotonic() - started
        probe_passed = result.returncode != 0 and elapsed < 2.5
        if not probe_passed:
            print("probe timeout stdout:\n%s" % result.stdout, file=sys.stderr)
            print("probe timeout stderr:\n%s" % result.stderr, file=sys.stderr)
            print("probe timeout elapsed: %.3fs" % elapsed, file=sys.stderr)
        print("ok    a connected SSH probe has a hard wall-clock limit"
              if probe_passed else "FAIL  SSH liveness probe can hang")
        return 0 if probe_passed else 1
    finally:
        shutil.rmtree(workspace)


if __name__ == "__main__":
    sys.exit(main())
