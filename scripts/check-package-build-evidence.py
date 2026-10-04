#!/usr/bin/env python3
"""Assert a package build's evidence against its own request and outputs.

The manifest writer derives what a build produced. Nothing yet asks whether what
it produced is what was asked for, and the gap is where a build reads as a
success it did not earn: a manifest can name a `.changes` file whose artifacts
are absent, carry an amd64 package where the point was hurd-amd64, claim a clear
Mach console on a transcript that never carried kernel output, or omit the one
binary package the build exists to produce.

Every check here compares two documents that were written independently. A
manifest agreeing with itself proves nothing; a manifest agreeing with the
request, the `.changes`, and the run is what the checker reports.
"""

import json
import os
import sys

LINUX_ARCHITECTURES = {"amd64", "i386", "arm64", "armhf", "all-linux"}


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


def check_package(suite, directory):
    manifest_path = os.path.join(directory, "artifact-manifest.json")
    if not suite.check("%s: the package carries an artifact manifest" % directory,
                       os.path.isfile(manifest_path)):
        return
    manifest = load(manifest_path)
    request = manifest.get("request", {})
    result = manifest.get("build_result", {})
    run = manifest.get("build_run", {})

    request_path = os.path.join(directory, request.get("path", ""))
    if suite.check("%s: the request the manifest names is present" % directory,
                   os.path.isfile(request_path)):
        stated = load(request_path)
        suite.check("%s: the manifest describes the request it ships" % directory,
                    stated.get("source") == request.get("source")
                    and stated.get("version") == request.get("version"))
        suite.check("%s: the request permits no local patch" % directory,
                    not stated.get("local_patches"))
        if run:
            suite.check("%s: the run answered the request the manifest names"
                        % directory,
                        run.get("request_sha256") == request.get("sha256"),
                        "%s against %s" % (run.get("request_sha256"),
                                           request.get("sha256")))

    outcome = result.get("outcome")
    # A failure package is a legitimate result and states a classified outcome
    # rather than a success it did not reach. Only the succeeding branch is
    # required to carry a complete artifact set.
    if outcome != "completed":
        suite.check("%s: a failed build states a classified outcome" % directory,
                    isinstance(outcome, str) and outcome not in ("", "not recorded"),
                    str(outcome))
        suite.check("%s: a failed build does not claim a zero exit status"
                    % directory, result.get("build_exit_status") != 0)
        print("info  %s: classified failure package, outcome %s" % (directory, outcome))
        return

    suite.check("%s: a completed build exited zero" % directory,
                result.get("build_exit_status") == 0,
                str(result.get("build_exit_status")))
    suite.check("%s: the build ran as the unprivileged account" % directory,
                result.get("build_user") not in (None, "", "root"),
                str(result.get("build_user")))
    suite.check("%s: the build ran on the requested architecture" % directory,
                result.get("architecture") == request.get("architecture"),
                "%s against %s" % (result.get("architecture"),
                                   request.get("architecture")))

    # "The first one" is not a fact about the build: one .changes and one
    # .buildinfo is a count the writer requires before naming either, so zero
    # or more than one both surface here rather than silently picking one.
    changes_present = manifest.get("changes_files_present", [])
    suite.check("%s: the build produced exactly one .changes file" % directory,
                len(changes_present) == 1, ", ".join(changes_present) or "none")
    buildinfo_present = manifest.get("buildinfo_files_present", [])
    # .buildinfo is the only artifact that ties the outputs to the environment
    # that produced them, so a package without one cannot be reproduced from.
    suite.check("%s: the build produced exactly one .buildinfo file" % directory,
                len(buildinfo_present) == 1, ", ".join(buildinfo_present) or "none")

    declared = manifest.get("declared_artifacts", [])
    suite.check("%s: the .changes file declares artifacts" % directory,
                bool(declared))
    absent = [entry["name"] for entry in declared if not entry.get("present")]
    suite.check("%s: every artifact the .changes declares is present" % directory,
                not absent, ", ".join(absent))
    suite.check("%s: every present artifact hashes and sizes to its declared value"
                % directory, not manifest.get("digest_mismatches"),
                ", ".join(manifest.get("digest_mismatches", [])))

    binaries = manifest.get("binary_packages", [])
    suite.check("%s: the build produced binary packages" % directory, bool(binaries))
    unread = [entry["file"] for entry in binaries if not entry.get("control_read")]
    suite.check("%s: every binary package's control fields were read" % directory,
                not unread, ", ".join(unread))
    # A .deb the .changes never declared is not part of the build's stated
    # output, whatever produced it, so accepting it here would let the
    # manifest describe a package the archive never signed off on.
    undeclared = manifest.get("undeclared_binary_packages", [])
    suite.check("%s: every binary package is declared by .changes" % directory,
                not undeclared, ", ".join(undeclared))
    # A Linux architecture here means the build ran somewhere other than the
    # guest, which is the failure a native port exists to exclude.
    foreign = [entry["file"] for entry in binaries
               if entry.get("architecture") in LINUX_ARCHITECTURES]
    suite.check("%s: no binary package carries a Linux architecture" % directory,
                not foreign, ", ".join(foreign))
    architectures = {entry.get("architecture") for entry in binaries}
    suite.check("%s: binary architectures are the guest's or architecture-independent"
                % directory,
                architectures <= {request.get("architecture"), "all"},
                ", ".join(sorted(str(name) for name in architectures)))

    produced = {entry.get("package") for entry in binaries}
    missing = [name for name in request.get("required_binary_packages", [])
               if name not in produced]
    suite.check("%s: the build produced every required binary package" % directory,
                not missing, ", ".join(missing))

    # A console that never carried kernel output cannot report the falsifier
    # clear, and reporting it clear is the failure the discriminator exists to
    # prevent.
    console = run.get("guest_console", {}) if run else {}
    if console:
        observed = console.get("kernel_output_observed")
        suite.check("%s: a cleared Mach falsifier rests on observed kernel output"
                    % directory,
                    console.get("mach_ipc_allocation_error") is not False
                    or observed is True)
        suite.check("%s: no Mach IPC allocation error was recorded" % directory,
                    console.get("mach_ipc_allocation_error") is not True)
        print("info  %s: Mach console %s" %
              (directory, "observed" if observed else "not observed"))


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "evidence/package-builds"
    suite = Suite()
    if not os.path.isdir(root):
        print("no package build evidence at %s" % root)
        print("")
        print("0 failure(s)")
        return 0
    packages = []
    for current, _directories, files in os.walk(root):
        if "artifact-manifest.json" in files:
            packages.append(current)
    suite.check("the tree holds at least one package build", bool(packages))
    for directory in sorted(packages):
        check_package(suite, directory)
    print("")
    print("%d failure(s)" % suite.failed)
    return 1 if suite.failed else 0


if __name__ == "__main__":
    sys.exit(main())
