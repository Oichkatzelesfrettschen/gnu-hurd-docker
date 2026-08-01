#!/usr/bin/env python3
"""Derive a package build's artifact manifest from the files the build wrote.

A manifest assembled from a directory listing states what is present, which is
the one thing a listing cannot get wrong and also the one thing that says
nothing: a build that produced half its outputs lists half of them and reads as
complete. The authority here is the `.changes` file dpkg-genchanges wrote, which
names every artifact the build intended to produce together with the size and
digest of each, so a missing or altered output is a disagreement rather than an
absence nobody notices.

Each `.deb` is opened for its own control fields instead of having them parsed
out of its filename, because a filename is a convention and `Architecture` is
the field that separates a native hurd-amd64 package from an amd64 one built by
accident.
"""

import hashlib
import json
import os
import re
import subprocess
import sys


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def paragraphs(text):
    """Split an RFC822 control stream into its stanzas."""
    return [block for block in re.split(r"\n(?=\S)", text) if block.strip()]


def changes_files(path):
    """Read the Files/Checksums-Sha256 stanza of a .changes or .buildinfo file.

    The Sha256 list carries the digest and the name; the Files list carries the
    size. Reading both and joining on the name means a manifest states the size
    and the digest the producer recorded rather than the ones measured here.
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    sizes, digests = {}, {}
    section = None
    for line in text.splitlines():
        if re.match(r"^\S+:", line):
            section = line.split(":", 1)[0].lower()
            continue
        if not line.startswith(" "):
            continue
        fields = line.split()
        if section == "checksums-sha256" and len(fields) >= 3:
            digests[fields[-1]] = fields[0]
        elif section == "files" and len(fields) >= 5:
            sizes[fields[-1]] = fields[1]
    return sizes, digests


def control_fields(deb):
    """Read a binary package's own control fields.

    dpkg-deb is the reader when it is present. A host without it still gets a
    manifest, with the fields recorded as unread rather than guessed from the
    file name, because a guessed Architecture would defeat the check this
    manifest exists to support.
    """
    try:
        output = subprocess.run(["dpkg-deb", "-f", deb], check=True,
                                capture_output=True, text=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return {}
    fields = {}
    for line in output.splitlines():
        if re.match(r"^\S+:", line):
            key, value = line.split(":", 1)
            fields[key.strip().lower()] = value.strip()
    return fields


def main():
    if len(sys.argv) < 5:
        print("usage: write-package-build-manifest.py --package DIR --request PATH "
              "--output PATH [--run PATH]", file=sys.stderr)
        return 2
    arguments = dict(zip(sys.argv[1::2], sys.argv[2::2]))
    package_dir = arguments["--package"]
    request_path = arguments["--request"]
    output = arguments["--output"]
    run_path = arguments.get("--run")

    with open(request_path, encoding="utf-8") as handle:
        request = json.load(handle)

    present = sorted(name for name in os.listdir(package_dir)
                     if os.path.isfile(os.path.join(package_dir, name)))
    changes = [name for name in present if name.endswith(".changes")]
    buildinfo = [name for name in present if name.endswith(".buildinfo")]
    debs = [name for name in present if name.endswith((".deb", ".ddeb"))]

    declared, mismatches = [], []
    if changes:
        sizes, digests = changes_files(os.path.join(package_dir, changes[0]))
        for name, recorded in sorted(digests.items()):
            path = os.path.join(package_dir, name)
            entry = {"name": name, "declared_sha256": recorded,
                     "declared_size": sizes.get(name),
                     "present": os.path.isfile(path)}
            if entry["present"]:
                entry["measured_sha256"] = digest(path)
                entry["measured_size"] = str(os.path.getsize(path))
                if entry["measured_sha256"] != recorded:
                    mismatches.append(name)
            else:
                mismatches.append(name)
            declared.append(entry)

    binaries = []
    for name in sorted(debs):
        fields = control_fields(os.path.join(package_dir, name))
        binaries.append({
            "file": name,
            "package": fields.get("package", ""),
            "version": fields.get("version", ""),
            "architecture": fields.get("architecture", ""),
            "control_read": bool(fields),
            "sha256": digest(os.path.join(package_dir, name)),
        })

    result = {}
    result_path = os.path.join(package_dir, "build-result.json")
    if os.path.isfile(result_path):
        with open(result_path, encoding="utf-8") as handle:
            result = json.load(handle)

    manifest = {
        "schema_version": 1,
        "kind": "hurd-native-package-build-manifest",
        "request": {
            "path": os.path.basename(request_path),
            "sha256": digest(request_path),
            "source": request.get("source"),
            "version": request.get("version"),
            "architecture": request.get("architecture"),
            "required_binary_packages": request.get("required_binary_packages", []),
        },
        "build_result": {
            "outcome": result.get("outcome", "not recorded"),
            "build_exit_status": result.get("build_exit_status"),
            "architecture": result.get("architecture"),
            "build_user": result.get("build_user"),
            "sha256": digest(result_path) if os.path.isfile(result_path) else "",
        },
        "changes_file": changes[0] if changes else "",
        "buildinfo_file": buildinfo[0] if buildinfo else "",
        "declared_artifacts": declared,
        "digest_mismatches": sorted(mismatches),
        "binary_packages": binaries,
        "files_present": present,
    }
    if run_path and os.path.isfile(run_path):
        with open(run_path, encoding="utf-8") as handle:
            run = json.load(handle)
        manifest["build_run"] = {
            "outcome": run.get("outcome"),
            "request_sha256": run.get("request_sha256"),
            "guest_console": run.get("guest_console", {}),
        }

    with open(output, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote %s" % output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
