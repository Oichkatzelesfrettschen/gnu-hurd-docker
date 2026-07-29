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
import re
import shutil
import subprocess
import sys

SCHEMA_VERSION = 4
RUN_MANIFEST = "run.json"
QEMU_ARGV = "qemu-argv.txt"
FSCK_TRANSCRIPT = "offline-fsck.log"
OVERLAY_CHAIN = "overlay-chain.json"
DIGEST = re.compile(r"^[0-9a-f]{64}$")


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


def parse_argv_file(path):
    """Read the retained argv as the option/value pairs QEMU parsed."""
    with open(path, encoding="utf-8") as handle:
        words = [line.rstrip("\n") for line in handle if line.strip()]
    pairs = {}
    index = 1
    while index < len(words):
        word = words[index]
        if word.startswith("-"):
            value = ""
            if index + 1 < len(words) and not words[index + 1].startswith("-"):
                value = words[index + 1]
                index += 1
            pairs.setdefault(word, []).append(value)
        index += 1
    return pairs


def derive_runtime(argv_path):
    """Derive the accelerator, vCPU count, RAM, disk bus, and drive from the
    retained argv. The argv is the run's own record of what QEMU was asked to
    do, so a value supplied a second time on this command line would be a claim
    the manifest could contradict; deriving them leaves one authority."""
    pairs = parse_argv_file(argv_path)
    facts = {}
    for option, name in (("-accel", "accelerator"), ("-smp", "vCPU count"),
                         ("-m", "RAM")):
        values = pairs.get(option, [])
        if not values:
            raise SystemExit("the argv carries no %s option, so the run's %s "
                             "is underivable" % (option, name))
        facts[option] = values[0].split(",")[0]
    drive_id, drive_basename = "", ""
    for value in pairs.get("-drive", []):
        for part in value.split(","):
            if part.startswith("file="):
                drive_basename = os.path.basename(part[len("file="):])
            if part.startswith("id="):
                drive_id = part[len("id="):]
    if not drive_basename:
        raise SystemExit("the argv names no -drive file, so the run describes "
                         "a guest with no disk")
    bus = ""
    for value in pairs.get("-device", []):
        parts = value.split(",")
        if drive_id and ("drive=%s" % drive_id) in parts[1:]:
            bus = parts[0].split("-")[0]
    if not bus:
        raise SystemExit("no -device attaches drive %r, so the disk bus is "
                         "underivable from the argv" % drive_id)
    return {"accelerator": facts["-accel"], "qemu_smp": int(facts["-smp"]),
            "qemu_ram_mb": int(facts["-m"]), "disk_bus": bus,
            "drive_basename": drive_basename}


def sanitize_chain(chain, chain_source, backing, before, drive_basename):
    """Reduce a raw qemu-img backing chain to the facts the evidence carries,
    binding the base by content rather than by name.

    The raw capture names the producing machine's directories in every
    filename field, and its base is identified only by basename -- a
    same-named copy with different bytes would satisfy a name comparison. The
    actual base file is therefore hashed while it still exists, and the digest
    is what the committed record carries.
    """
    if not isinstance(chain, list) or len(chain) < 2:
        raise SystemExit("the overlay chain records %d image(s); an overlay "
                         "over a base is two"
                         % (len(chain) if isinstance(chain, list) else 0))
    overlay, base = chain[0], chain[1]
    found = os.path.basename(overlay.get("filename", ""))
    if found != drive_basename:
        raise SystemExit("QEMU opened %s and the captured chain starts at %s"
                         % (drive_basename, found or "nothing"))
    actual_base = overlay.get("full-backing-filename") or os.path.join(
        os.path.dirname(chain_source), overlay.get("backing-filename", ""))
    if not os.path.isfile(actual_base):
        raise SystemExit("the chain's base %r is gone, so the image QEMU "
                         "actually read cannot be hashed; capture the chain "
                         "before disposing of the run directory" % actual_base)
    base_sha256 = digest(actual_base)
    if base_sha256 != before:
        raise SystemExit("the chain's base hashes to %s and the run declares "
                         "%s; QEMU read a different image than the one the "
                         "manifest names" % (base_sha256, before))
    return {
        "kind": "guest-baseline-overlay-chain",
        "overlay": {"basename": os.path.basename(overlay.get("filename", "")),
                    "format": overlay.get("format", "")},
        "backing": {"repository_path": backing,
                    "basename": os.path.basename(backing),
                    "format": base.get("format", ""),
                    "sha256": base_sha256},
    }


def capture_overlay_chain(overlay, root, backing, before, drive_basename):
    """Read and sanitize the overlay's backing chain while the overlay and its
    base still exist; after disposal nothing can re-derive or re-hash them,
    which is why the manifest is written before the overlay is discarded."""
    result = subprocess.run(["qemu-img", "info", "--backing-chain",
                             "--output=json", overlay],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit("qemu-img could not read the overlay chain of %s: %s"
                         % (overlay, result.stderr.strip()))
    sanitized = sanitize_chain(json.loads(result.stdout), overlay, backing,
                               before, drive_basename)
    with open(os.path.join(root, OVERLAY_CHAIN), "w",
              encoding="utf-8") as handle:
        json.dump(sanitized, handle, indent=2, sort_keys=True)
        handle.write("\n")
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
                        help="a raw qemu-img backing-chain capture from this "
                             "run's overlay whose base file still exists, for "
                             "a caller that has disposed of the overlay")
    parser.add_argument("--container", default="",
                        help="a running container to read the image and QEMU "
                             "version from")
    parser.add_argument("--container-image-id", default="")
    parser.add_argument("--qemu-version", default="")
    parser.add_argument("--overlay-size", default="")
    parser.add_argument("--overlay-discarded", action="store_true")
    args = parser.parse_args(argv)

    # Every input is validated before the package is touched: a writer that
    # copies files in and then refuses leaves the persistent evidence
    # directory half-mutated by a run whose manifest was never written.
    root = args.root
    if not os.path.isdir(root):
        raise SystemExit("no baseline directory at %s" % root)
    backing = repository_relative(args.backing_image)
    if not os.path.exists(backing):
        raise SystemExit("no backing image at %s" % backing)
    if not DIGEST.match(args.backing_sha256_before):
        raise SystemExit("--backing-sha256-before is %r, which names no "
                         "image" % args.backing_sha256_before)
    if args.offline_fsck != "clean":
        raise SystemExit("the filesystem check is %r; an accepted baseline "
                         "certifies a clean filesystem, and a failed run is "
                         "retained as a separate package (roadmap 79f) rather "
                         "than written over the accepted one"
                         % args.offline_fsck)
    if not (args.qemu_argv and os.path.isfile(args.qemu_argv)):
        raise SystemExit("no QEMU argv at %r" % args.qemu_argv)
    if not (args.offline_fsck_transcript
            and os.path.isfile(args.offline_fsck_transcript)):
        raise SystemExit("no filesystem-check transcript at %r"
                         % args.offline_fsck_transcript)
    runtime = derive_runtime(args.qemu_argv)

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

    place(args.qemu_argv, root, QEMU_ARGV)
    place(args.offline_fsck_transcript, root, FSCK_TRANSCRIPT)
    if args.overlay and os.path.exists(args.overlay):
        capture_overlay_chain(args.overlay, root, backing,
                              args.backing_sha256_before,
                              runtime["drive_basename"])
    else:
        if not (args.overlay_chain and os.path.isfile(args.overlay_chain)):
            raise SystemExit("no overlay and no captured chain; the chain is "
                             "what links the drive QEMU opened to the image "
                             "the manifest names")
        with open(args.overlay_chain, encoding="utf-8") as handle:
            raw = json.load(handle)
        sanitized = sanitize_chain(raw, args.overlay_chain, backing,
                                   args.backing_sha256_before,
                                   runtime["drive_basename"])
        with open(os.path.join(root, OVERLAY_CHAIN), "w",
                  encoding="utf-8") as handle:
            json.dump(sanitized, handle, indent=2, sort_keys=True)
            handle.write("\n")

    probes, index = run_artifacts(root)

    after = digest(backing)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "kind": "guest-baseline-run",
        "repository_commit": probes.get("repository_commit", ""),
        "container_image_id": image_id,
        "qemu_version": qemu_version,
        "qemu_argv": QEMU_ARGV,
        "accelerator": runtime["accelerator"],
        "accelerator_reason_code": args.accelerator_reason_code,
        "qemu_smp": runtime["qemu_smp"],
        "qemu_ram_mb": runtime["qemu_ram_mb"],
        "disk_bus": runtime["disk_bus"],
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
