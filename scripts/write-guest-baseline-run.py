#!/usr/bin/env python3
"""Derive the guest baseline's run manifest from the run it describes.

The collector produces the probe records; the run-level facts sit outside the
guest and outside the collector's reach -- which image the caller booted, what
it hashed before and after, which container ran QEMU, whether the overlay was
discarded, and what the offline filesystem check said. A manifest typed by hand
drifts from those the moment any of them changes, and a drifted manifest is
worse than none: it reports evidence as bound to inputs that are no longer the
inputs. This is the same reason config/minty/builder.lock.json has a writer.

Every run artifact is either read from the collector's own manifest or named as
an explicit option and copied into the package. A file that merely sits in the
output directory never becomes evidence: the directory persists across
collections, so an earlier run's QEMU argv or filesystem transcript beside a
new probes.json would otherwise be hashed into a manifest that describes no
single boot.

A report resolved from the baseline is not run output and stays out of the
index: it justifies its presence by naming the status file it answered against,
which scripts/check-guest-baseline.py asserts separately. README.md is
narrative derived from the evidence rather than output of the run, so it sits
outside the index too and a wording correction leaves the run's integrity
intact.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

SCHEMA_VERSION = 3
RUN_MANIFEST = "run.json"
QEMU_ARGV = "qemu-argv.txt"
FSCK_TRANSCRIPT = "offline-fsck.log"
OVERLAY_CHAIN = "overlay-chain.json"


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def place(source, root, name):
    """Copy an explicitly named input into the package under its canonical
    basename. The source is what the caller measured this run; a copy already
    in place is accepted only when it is the same file."""
    if not source or not os.path.isfile(source):
        raise SystemExit("no %s at %r; the run manifest indexes only what "
                         "this run produced, so the file is named explicitly "
                         "rather than discovered in the directory"
                         % (name, source))
    destination = os.path.join(root, name)
    if not (os.path.exists(destination)
            and os.path.samefile(source, destination)):
        shutil.copyfile(source, destination)
    return name


def capture_overlay_chain(overlay, root):
    """Read the overlay's backing chain while the overlay still exists.

    The chain is what links the drive QEMU opened to the image the manifest
    names; after disposal nothing can re-derive it, which is why the manifest
    is written before the overlay is discarded."""
    result = subprocess.run(["qemu-img", "info", "--backing-chain",
                             "--output=json", overlay],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit("qemu-img could not read the overlay chain of %s: %s"
                         % (overlay, result.stderr.strip()))
    with open(os.path.join(root, OVERLAY_CHAIN), "w",
              encoding="utf-8") as handle:
        handle.write(result.stdout)
    return OVERLAY_CHAIN


def run_artifacts(root):
    """Name what the run produced, reading the probe manifest for the streams."""
    names = {"probes.json", QEMU_ARGV, FSCK_TRANSCRIPT, OVERLAY_CHAIN}
    for name in sorted(os.listdir(root)):
        if name.endswith("-dpkg-status") or name.endswith("-dpkg-status.json"):
            names.add(name)

    probes_path = os.path.join(root, "probes.json")
    if not os.path.exists(probes_path):
        raise SystemExit("no probes.json in %s; the collector has not run" % root)
    with open(probes_path, encoding="utf-8") as handle:
        probes = json.load(handle)
    for probe in probes.get("probes") or []:
        for stream in ("stdout", "stderr"):
            if probe.get(stream):
                names.add(probe[stream])

    missing = [name for name in sorted(names)
               if not os.path.exists(os.path.join(root, name))]
    if missing:
        raise SystemExit("the run advertises absent artifacts: %s"
                         % ", ".join(missing))
    return probes, {name: digest(os.path.join(root, name))
                    for name in sorted(names)}


def container_facts(container):
    """Read the image and QEMU version from a container while it still runs.

    These are properties of the process that produced the evidence, so they are
    unreadable once it exits. A caller that has already stopped the container
    supplies them explicitly instead.
    """
    runtime = os.environ.get("CONTAINER_RUNTIME", "docker")
    image = subprocess.run([runtime, "inspect", "--format", "{{.Image}}",
                            container], capture_output=True, text=True,
                           check=False)
    version = subprocess.run([runtime, "exec", container,
                              "qemu-system-x86_64", "--version"],
                             capture_output=True, text=True, check=False)
    qemu = ""
    if version.returncode == 0:
        first = version.stdout.splitlines()[0] if version.stdout else ""
        qemu = first.replace("QEMU emulator version ", "").strip()
    return image.stdout.strip(), qemu


def human_size(path):
    if not path or not os.path.exists(path):
        return ""
    size = os.path.getsize(path)
    for unit in ("B", "K", "M", "G"):
        if size < 1024 or unit == "G":
            return "%d%s" % (size, unit)
        size //= 1024
    return "%dG" % size


def repository_relative(path):
    """A committed manifest travels with the repository, so the image it names
    is a repository-relative path: an absolute path or a traversal binds the
    evidence to one machine's filesystem."""
    normalized = os.path.normpath(path)
    if os.path.isabs(normalized) or normalized.split(os.sep)[0] == "..":
        raise SystemExit("the backing image is named %r; the manifest records "
                         "a repository-relative path" % path)
    return normalized


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default="evidence/guest-state")
    parser.add_argument("--backing-image", required=True,
                        help="repository-relative path to the image the run "
                             "booted; its digest is read now")
    parser.add_argument("--backing-sha256-before", required=True,
                        help="the digest recorded before the run started")
    parser.add_argument("--accelerator", required=True)
    parser.add_argument("--accelerator-reason-code", required=True)
    parser.add_argument("--offline-fsck", required=True,
                        choices=["clean", "dirty", "not run"])
    parser.add_argument("--qemu-argv", required=True,
                        help="the argv captured from this run's QEMU process")
    parser.add_argument("--offline-fsck-transcript", required=True,
                        help="the filesystem-check transcript from this run's "
                             "overlay")
    parser.add_argument("--overlay", default="",
                        help="this run's overlay, read for its backing chain "
                             "and size before disposal")
    parser.add_argument("--overlay-chain", default="",
                        help="a backing-chain record already captured from "
                             "this run's overlay, for a caller that has "
                             "disposed of it")
    parser.add_argument("--container", default="",
                        help="a running container to read the image and QEMU "
                             "version from")
    parser.add_argument("--container-image-id", default="")
    parser.add_argument("--qemu-version", default="")
    parser.add_argument("--qemu-smp", type=int, default=1)
    parser.add_argument("--qemu-ram-mb", type=int, default=0)
    parser.add_argument("--disk-bus", default="")
    parser.add_argument("--overlay-size", default="")
    parser.add_argument("--overlay-discarded", action="store_true")
    args = parser.parse_args(argv)

    root = args.root
    if not os.path.isdir(root):
        raise SystemExit("no baseline directory at %s" % root)
    backing = repository_relative(args.backing_image)
    if not os.path.exists(backing):
        raise SystemExit("no backing image at %s" % backing)

    place(args.qemu_argv, root, QEMU_ARGV)
    place(args.offline_fsck_transcript, root, FSCK_TRANSCRIPT)
    if args.overlay and os.path.exists(args.overlay):
        capture_overlay_chain(args.overlay, root)
    else:
        place(args.overlay_chain, root, OVERLAY_CHAIN)

    probes, index = run_artifacts(root)

    image_id, qemu_version = args.container_image_id, args.qemu_version
    if args.container and not (image_id and qemu_version):
        found_image, found_qemu = container_facts(args.container)
        image_id = image_id or found_image
        qemu_version = qemu_version or found_qemu
    for name, value in (("container image id", image_id),
                        ("QEMU version", qemu_version)):
        if not value:
            raise SystemExit("no %s; supply it or name a running container, "
                             "because a manifest that omits the process that "
                             "produced the evidence names no producer" % name)

    after = digest(backing)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "kind": "guest-baseline-run",
        "repository_commit": probes.get("repository_commit", ""),
        "container_image_id": image_id,
        "qemu_version": qemu_version,
        "qemu_argv": QEMU_ARGV,
        "accelerator": args.accelerator,
        "accelerator_reason_code": args.accelerator_reason_code,
        "qemu_smp": args.qemu_smp,
        "disk_bus": args.disk_bus,
        "backing_image": backing,
        "backing_sha256_before": args.backing_sha256_before,
        "backing_sha256_after": after,
        "backing_unchanged": after == args.backing_sha256_before,
        "overlay_backing_format": "qcow2",
        "overlay_chain": OVERLAY_CHAIN,
        "overlay_size_at_discard": args.overlay_size or human_size(args.overlay),
        "overlay_discarded": bool(args.overlay_discarded),
        "offline_fsck": args.offline_fsck,
        "offline_fsck_transcript": FSCK_TRANSCRIPT,
        "guest_packages": 0,
        "artifact_sha256": index,
    }
    if args.qemu_ram_mb:
        manifest["qemu_ram_mb"] = args.qemu_ram_mb

    status_manifests = [name for name in index
                        if name.endswith("-dpkg-status.json")]
    if status_manifests:
        with open(os.path.join(root, status_manifests[0]),
                  encoding="utf-8") as handle:
            manifest["guest_packages"] = json.load(handle).get(
                "package_count", 0)

    with open(os.path.join(root, RUN_MANIFEST), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote %s indexing %d run artifacts; backing image %s"
          % (os.path.join(root, RUN_MANIFEST), len(index),
             "unchanged" if manifest["backing_unchanged"] else "MUTATED"))
    return 0 if manifest["backing_unchanged"] else 1


if __name__ == "__main__":
    sys.exit(main())
