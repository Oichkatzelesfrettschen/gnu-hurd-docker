#!/usr/bin/env python3
"""Assert that a committed guest baseline says what it claims to say.

The runtime evidence contract already has a checker, and the guest baseline was
committed without one. An unchecked evidence package degrades quietly: a probe
whose command stopped working leaves a marker that reads as a guest fact, a
digest stops matching the file beside it, and a package count drifts from the
paragraphs it counts. None of that is visible in review, because every one of
those artifacts looks exactly like a correct one.

What is asserted here is internal consistency, derivation, and the repository's
own rules about committed evidence. A claim the checker can derive from a
retained artifact is derived rather than trusted: the probe class is recomputed
from the recorded statuses and streams, the accelerator, vCPU count, RAM, and
disk bus are read back out of the retained QEMU argv, the filesystem verdict is
read out of the retained transcript, the overlay chain links the drive QEMU
opened to the image the manifest names, and the producer digests are checked
against the recorded commit's own copies of the producers.

Whether the guest told the truth is outside this: that is a question for the
guest, and the run manifest records which image answered.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

PROBE_CLASSES = {"observed", "observed-absent", "partial", "failed",
                 "unreachable"}
# The checker owns the minimum roster. A collector that dropped uname or
# relabeled it optional would otherwise pass a reduced baseline, because the
# only statement of what is required would be the manifest under test.
REQUIRED_PROBES = {"uname", "nproc", "debian_version", "dpkg-architecture"}
# The probe body reserves exit 66 for a deliberate absence.
ABSENT = 66
PRODUCERS = {
    "collector_sha256": "scripts/collect-guest-baseline.sh",
    "transport_sha256": "scripts/lib/guest-ssh.sh",
    "exporter_sha256": "scripts/export-guest-package-state.sh",
}
SECRET_MARKERS = ("PRIVATE KEY", "BEGIN OPENSSH", "BEGIN RSA",
                  "BEGIN EC PRIVATE")
# A committed artifact that names a directory only one machine has binds the
# evidence to that machine, which the repository rules keep out of the tree.
# Guest and container paths are content -- the baseline exists to record them,
# and QEMU's own argv names /tmp/qemu-guest-errors.log inside the container.
# What must not appear is a home directory, which exists only on the machine
# that produced the run. The complementary rule is that every artifact a
# manifest advertises is a basename, which artifact() enforces, so a run
# directory outside the repository never reaches a recorded path in the first
# place.
LOCAL_PATH = re.compile(r"(?:/home/|/Users/)")
DIGEST = re.compile(r"^[0-9a-f]{64}$")


class Failure(Exception):
    pass


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def load(path):
    if not os.path.exists(path):
        raise Failure("no %s" % path)
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def artifact(root, name, field):
    """Resolve an advertised artifact, refusing anything but a regular file
    named by basename inside the evidence directory.

    A manifest entry that carries a path rather than a name can reach outside
    the evidence directory, and a symlink does the same thing one level later:
    the basename sits inside the package while the bytes the checker hashes
    come from wherever the link points.
    """
    if not name or os.path.basename(name) != name:
        raise Failure("%s names %r, which is not a basename in the evidence "
                      "directory" % (field, name))
    path = os.path.join(root, name)
    if not os.path.exists(path):
        raise Failure("%s names %s, which is absent" % (field, name))
    if os.path.islink(path) or not os.path.isfile(path):
        raise Failure("%s names %s, which is not a regular file inside the "
                      "package" % (field, name))
    real = os.path.realpath(path)
    if os.path.commonpath([real, os.path.realpath(root)]) \
            != os.path.realpath(root):
        raise Failure("%s resolves outside the evidence directory" % field)
    return path


def expected_class(transport_status, remote_status, stdout_size):
    """Recompute the class the collector's own state machine assigns.

    A manifest can otherwise claim `observed` beside a nonzero status, and the
    class -- the field every reader acts on -- becomes a free-text assertion.
    """
    if transport_status != 0:
        return "unreachable"
    if remote_status == 0:
        return "observed"
    if remote_status == ABSENT:
        return "observed-absent"
    return "partial" if stdout_size else "failed"


def check_probes(root, failures):
    probes = load(os.path.join(root, "probes.json"))
    if probes.get("kind") != "guest-baseline-probes":
        failures.append("probes.json is not a guest-baseline-probes manifest")
    if probes.get("schema_version") != 1:
        failures.append("probes.json declares schema_version %r"
                        % probes.get("schema_version"))

    for field in ("collector_sha256", "transport_sha256", "exporter_sha256"):
        if not DIGEST.match(probes.get(field) or ""):
            failures.append("probes.json %s is not a sha256 digest" % field)

    export = probes.get("package_state_export") or {}
    if export.get("class") != "observed":
        failures.append("the package-state export is %r; the baseline exists "
                        "to produce it, so a run without it answers nothing"
                        % export.get("class"))

    transport = probes.get("transport") or {}
    if not transport.get("host_key_fingerprint"):
        failures.append("probes.json records no host key fingerprint, so "
                        "nothing binds the artifacts to one guest")

    seen = set()
    for probe in probes.get("probes") or []:
        name = probe.get("name", "<unnamed>")
        if name in seen:
            failures.append("two probes are named %s" % name)
        seen.add(name)

        klass = probe.get("class")
        if klass not in PROBE_CLASSES:
            failures.append("probe %s carries class %r" % (name, klass))
        if probe.get("requirement") == "required" and klass != "observed":
            failures.append("required probe %s is %r" % (name, klass))
        if name in REQUIRED_PROBES and probe.get("requirement") != "required":
            failures.append("probe %s is labeled %r and the checker's roster "
                            "requires it" % (name, probe.get("requirement")))
        if not probe.get("command"):
            failures.append("probe %s records no command" % name)

        # A probe that did not answer still advertises its stdout file, because
        # an absent file and an empty answer are different outcomes and the
        # class is what tells them apart.
        stdout_size = 0
        for stream in ("stdout", "stderr"):
            recorded = probe.get(stream)
            recorded_digest = probe.get("%s_sha256" % stream)
            if recorded is None:
                if recorded_digest is not None:
                    failures.append("probe %s advertises no %s but records a "
                                    "digest for one" % (name, stream))
                continue
            try:
                path = artifact(root, recorded, "probe %s %s" % (name, stream))
            except Failure as error:
                failures.append(str(error))
                continue
            if stream == "stdout":
                stdout_size = os.path.getsize(path)
            found = digest(path)
            if found != recorded_digest:
                failures.append("probe %s %s hashes to %s, the manifest "
                                "records %s" % (name, stream, found,
                                                recorded_digest))

        derived = expected_class(probe.get("transport_status"),
                                 probe.get("remote_status"), stdout_size)
        if klass in PROBE_CLASSES and klass != derived:
            failures.append("probe %s claims class %s and its statuses "
                            "(transport %r, remote %r, stdout %d bytes) "
                            "derive %s"
                            % (name, klass, probe.get("transport_status"),
                               probe.get("remote_status"), stdout_size,
                               derived))

    for name in sorted(REQUIRED_PROBES - seen):
        failures.append("the roster requires probe %s and the manifest "
                        "carries none" % name)
    if not seen:
        failures.append("probes.json advertises no probe")
    return probes


def check_producers(root, probes, failures):
    """Verify the recorded producer digests against the recorded commit.

    The digests otherwise assert only their own format: a fabricated value
    passes as long as it is 64 hexadecimal characters. Git history carries the
    producers' content at the recorded commit, so the claim is checkable
    wherever the history is present; a source archive without one is reported
    rather than silently passed.
    """
    commit = probes.get("repository_commit") or ""
    if not commit:
        failures.append("probes.json records no repository commit, so the "
                        "producer digests name files nowhere")
        return
    probe = subprocess.run(["git", "-C", root, "rev-parse", "--git-dir"],
                           capture_output=True, text=True, check=False)
    if probe.returncode != 0:
        print("guest baseline: producer identity not verified: no git "
              "history at %s" % root, file=sys.stderr)
        return
    for field, path in sorted(PRODUCERS.items()):
        shown = subprocess.run(["git", "-C", root, "show",
                                "%s:%s" % (commit, path)],
                               capture_output=True, check=False)
        if shown.returncode != 0:
            failures.append("commit %s does not carry %s, so %s is "
                            "unverifiable" % (commit[:12], path, field))
            continue
        found = hashlib.sha256(shown.stdout).hexdigest()
        if found != probes.get(field):
            failures.append("%s records %s and %s at commit %s hashes to %s"
                            % (field, probes.get(field), path, commit[:12],
                               found))


def parse_status(path):
    """Read the status file the way apt reads it, as RFC822 paragraphs."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    paragraphs = []
    for block in re.split(r"\n[ \t]*\n", text):
        if not block.strip():
            continue
        fields = {}
        for line in block.splitlines():
            if not line or line.startswith((" ", "\t")):
                continue
            key, separator, value = line.partition(":")
            if not separator:
                raise Failure("a status line is not a field: %r" % line[:60])
            fields[key.strip()] = value.strip()
        paragraphs.append(fields)
    return paragraphs


def check_package_state(root, failures):
    manifests = [name for name in sorted(os.listdir(root))
                 if name.endswith("-dpkg-status.json")]
    if not manifests:
        failures.append("no guest dpkg status manifest in %s" % root)
        return None
    if len(manifests) > 1:
        failures.append("two dpkg status manifests in one baseline: %s"
                        % ", ".join(manifests))

    manifest = load(os.path.join(root, manifests[0]))
    try:
        status_path = artifact(root, manifest.get("manifest"),
                               "%s manifest" % manifests[0])
    except Failure as error:
        failures.append(str(error))
        return None

    found = digest(status_path)
    if found != manifest.get("manifest_sha256"):
        failures.append("the status file hashes to %s, its manifest records %s"
                        % (found, manifest.get("manifest_sha256")))

    if not DIGEST.match(manifest.get("source_image_sha256") or ""):
        failures.append("the status export names no source image, so the "
                        "package list is from somewhere")

    try:
        paragraphs = parse_status(status_path)
    except Failure as error:
        failures.append(str(error))
        return manifest

    if len(paragraphs) != manifest.get("package_count"):
        failures.append("the status file holds %d paragraphs, the manifest "
                        "records %r packages"
                        % (len(paragraphs), manifest.get("package_count")))

    architecture = manifest.get("architecture")
    for fields in paragraphs:
        missing = [key for key in ("Package", "Status", "Version",
                                   "Architecture") if key not in fields]
        if missing:
            failures.append("a status paragraph (%s) omits %s"
                            % (fields.get("Package", "<unnamed>"),
                               ", ".join(missing)))
            break
        if len(fields.get("Status", "").split()) != 3:
            failures.append("package %s carries Status %r; apt reads the "
                            "three-part form" % (fields["Package"],
                                                 fields.get("Status")))
            break
        if fields["Architecture"] not in (architecture, "all"):
            failures.append("package %s is %s in a %s baseline"
                            % (fields["Package"], fields["Architecture"],
                               architecture))
            break
    return manifest


def parse_argv(path):
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


def check_runtime_against_argv(root, run, failures):
    """The run manifest's accelerator, SMP, RAM, and disk bus are claims the
    retained argv can settle, so they are derived from it rather than trusted.
    Returns the basename of the drive QEMU opened, for the chain check."""
    try:
        path = artifact(root, run.get("qemu_argv"), "run.json qemu_argv")
    except Failure as error:
        failures.append(str(error))
        return None
    pairs = parse_argv(path)

    accels = [value.split(",")[0] for value in pairs.get("-accel", [])]
    if run.get("accelerator") not in accels:
        failures.append("run.json claims accelerator %r and the argv selects "
                        "%s" % (run.get("accelerator"), ", ".join(accels)
                                or "none"))
    smp = [value.split(",")[0] for value in pairs.get("-smp", [])]
    if smp and str(run.get("qemu_smp")) != smp[0]:
        failures.append("run.json claims %r vCPUs and the argv asks for %s"
                        % (run.get("qemu_smp"), smp[0]))
    ram = [value.split(",")[0] for value in pairs.get("-m", [])]
    if ram and run.get("qemu_ram_mb") is not None \
            and str(run.get("qemu_ram_mb")) != ram[0]:
        failures.append("run.json claims %r MiB and the argv asks for %s"
                        % (run.get("qemu_ram_mb"), ram[0]))

    devices = [value.split(",")[0] for value in pairs.get("-device", [])]
    bus = run.get("disk_bus") or ""
    if bus and not any(device.startswith(bus) for device in devices):
        failures.append("run.json claims disk bus %r and the argv attaches %s"
                        % (bus, ", ".join(devices) or "no device"))

    drive = None
    for value in pairs.get("-drive", []):
        for part in value.split(","):
            if part.startswith("file="):
                drive = os.path.basename(part[len("file="):])
    if drive is None:
        failures.append("the argv names no -drive file, so the run manifest "
                        "describes a guest with no disk")
    return drive


def check_overlay_chain(root, run, drive, failures):
    """The chain is what links the drive QEMU opened to the image the manifest
    names. The matching digests in run.json and the status manifest prove the
    two documents agree with each other; the chain is the artifact that says
    QEMU used a child of that image."""
    try:
        path = artifact(root, run.get("overlay_chain"),
                        "run.json overlay_chain")
    except Failure as error:
        failures.append(str(error))
        return
    try:
        chain = load(path)
    except (Failure, ValueError) as error:
        failures.append("the overlay chain does not parse: %s" % error)
        return
    if not isinstance(chain, list) or len(chain) < 2:
        failures.append("the overlay chain records %d image(s); an overlay "
                        "over a base is two" % (len(chain)
                                                if isinstance(chain, list)
                                                else 0))
        return
    overlay, base = chain[0], chain[1]
    if drive and os.path.basename(overlay.get("filename", "")) != drive:
        failures.append("QEMU opened %s and the chain starts at %s"
                        % (drive,
                           os.path.basename(overlay.get("filename", ""))))
    backing = os.path.basename(overlay.get("backing-filename", ""))
    named = os.path.basename(run.get("backing_image", ""))
    if backing != named:
        failures.append("the overlay backs onto %s and run.json names %s"
                        % (backing or "nothing", named))
    if base.get("format") != "qcow2":
        failures.append("the chain records base format %r"
                        % base.get("format"))


def check_fsck_transcript(root, run, failures):
    """The verdict `clean` is derived from the retained transcript: every
    recorded command exited 0 and an e2fsck actually ran."""
    try:
        path = artifact(root, run.get("offline_fsck_transcript"),
                        "run.json offline_fsck_transcript")
    except Failure as error:
        failures.append(str(error))
        return
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    exits = [int(match) for match in re.findall(r"^exit=(\d+)", text,
                                                re.MULTILINE)]
    ran_fsck = re.search(r"^\$ .*e2fsck", text, re.MULTILINE) is not None
    verdict = run.get("offline_fsck")
    if not exits or not ran_fsck:
        failures.append("the filesystem transcript records no e2fsck run, so "
                        "offline_fsck %r is underived" % verdict)
        return
    derived = "clean" if all(status == 0 for status in exits) else "dirty"
    if verdict != derived:
        failures.append("run.json reports offline_fsck %r and the transcript "
                        "derives %s" % (verdict, derived))


def check_run(root, manifest, failures):
    run = load(os.path.join(root, "run.json"))
    if run.get("schema_version") != 3:
        failures.append("run.json declares schema_version %r"
                        % run.get("schema_version"))
    for field in ("repository_commit", "container_image_id", "qemu_version",
                  "accelerator", "accelerator_reason_code"):
        if not run.get(field):
            failures.append("run.json records no %s; the run is then a set of "
                            "numbers with no producer" % field)

    drive = check_runtime_against_argv(root, run, failures)
    check_overlay_chain(root, run, drive, failures)
    check_fsck_transcript(root, run, failures)

    # The index is what makes the run's own output tamper-evident: a file
    # added, removed, or edited after the run shows up as an index that no
    # longer describes what the collector produced. README.md is narrative
    # derived from the evidence rather than output of the run, so it sits
    # outside the index and a wording correction leaves the run intact.
    index = run.get("artifact_sha256") or {}
    present = {name for name in os.listdir(root)
               if os.path.isfile(os.path.join(root, name))
               and not name.startswith(".")
               and name not in ("run.json", "README.md")}
    for name in sorted(set(index) - present):
        failures.append("the run artifact index names %s, which is absent"
                        % name)
    for name in sorted(present & set(index)):
        found = digest(os.path.join(root, name))
        if found != index[name]:
            failures.append("%s hashes to %s, the run index records %s"
                            % (name, found, index[name]))

    # Everything else in the directory is analysis derived from the baseline
    # rather than output of the run, so it justifies its presence by naming the
    # status file it was resolved against. A report seeded from a different
    # guest sitting beside this one would otherwise read as a fact about this
    # image.
    status_digest = (manifest or {}).get("manifest_sha256")
    for name in sorted(present - set(index)):
        path = os.path.join(root, name)
        if not name.endswith(".json"):
            failures.append("%s is neither run output nor a report bound to "
                            "this baseline" % name)
            continue
        try:
            with open(path, encoding="utf-8") as handle:
                report = json.load(handle)
        except ValueError as error:
            failures.append("%s does not parse: %s" % (name, error))
            continue
        baseline = (report.get("provenance") or {}).get("installed_baseline")
        recorded = baseline.get("sha256") if isinstance(baseline, dict) else None
        if recorded != status_digest:
            failures.append("%s was resolved against installed state %r and "
                            "this baseline is %r"
                            % (name, recorded, status_digest))

    before = run.get("backing_sha256_before")
    after = run.get("backing_sha256_after")
    if not DIGEST.match(before or "") or not DIGEST.match(after or ""):
        failures.append("run.json records no pair of backing digests")
    elif before != after:
        failures.append("the backing image changed during the run: %s -> %s"
                        % (before, after))
    elif run.get("backing_unchanged") is not True:
        failures.append("run.json reports backing_unchanged %r while the "
                        "digests agree" % run.get("backing_unchanged"))
    if run.get("offline_fsck") != "clean":
        failures.append("run.json reports offline_fsck %r; a baseline read "
                        "from a dirty filesystem describes an image nobody "
                        "can reproduce" % run.get("offline_fsck"))
    return run


def check_hygiene(root, failures):
    for name in sorted(os.listdir(root)):
        if name.startswith("."):
            continue
        path = os.path.join(root, name)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        for marker in SECRET_MARKERS:
            if marker in text:
                failures.append("%s carries %r" % (name, marker))
        match = LOCAL_PATH.search(text)
        if match:
            failures.append("%s names a machine-local path near %r"
                            % (name, text[max(0, match.start() - 20):
                                          match.end() + 20]))


def cross_check(root, probes, manifest, failures):
    """The architecture a probe reported and the one the export recorded are
    two answers from one guest, so a disagreement means the two artifacts came
    from different places."""
    if manifest is None:
        return
    reported = None
    for probe in probes.get("probes") or []:
        if probe.get("name") == "dpkg-architecture" \
                and probe.get("class") == "observed":
            with open(os.path.join(root, probe["stdout"]),
                      encoding="utf-8") as handle:
                reported = handle.read().strip()
    if reported and reported != manifest.get("architecture"):
        failures.append("the guest reported architecture %s and the status "
                        "export recorded %s"
                        % (reported, manifest.get("architecture")))


def main(argv):
    root = argv[1] if len(argv) > 1 else "evidence/guest-state"
    if not os.path.isdir(root):
        print("no guest baseline at %s" % root, file=sys.stderr)
        return 2

    failures = []
    try:
        probes = check_probes(root, failures)
        check_producers(root, probes, failures)
        manifest = check_package_state(root, failures)
        run = check_run(root, manifest, failures)
        check_hygiene(root, failures)
        cross_check(root, probes, manifest, failures)
        # A status file that names no image, or names a different one than the
        # run booted, cannot be attributed to any image: it is a package list
        # from somewhere.
        if manifest is not None and run is not None:
            recorded = manifest.get("source_image_sha256")
            if recorded != run.get("backing_sha256_before"):
                failures.append("the status export names source image %r and "
                                "the run booted %r"
                                % (recorded, run.get("backing_sha256_before")))
    except Failure as error:
        failures.append(str(error))

    for failure in failures:
        print("guest baseline: %s" % failure, file=sys.stderr)
    if failures:
        print("%d finding(s) in %s" % (len(failures), root), file=sys.stderr)
        return 1
    print("guest baseline at %s is self-consistent" % root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
