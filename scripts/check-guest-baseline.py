#!/usr/bin/env python3
"""Assert that a committed guest baseline says what it claims to say.

The runtime evidence contract already has a checker, and the guest baseline was
committed without one. An unchecked evidence package degrades quietly: a probe
whose command stopped working leaves a marker that reads as a guest fact, a
digest stops matching the file beside it, and a package count drifts from the
paragraphs it counts. None of that is visible in review, because every one of
those artifacts looks exactly like a correct one.

What is asserted here is internal consistency and the repository's own rules
about committed evidence: every advertised artifact exists and hashes to its
recorded digest, every required probe reached the class `observed`, every
partial or failed probe is labelled as such rather than presented as an answer,
the status paragraphs parse as the input apt reads, and no artifact carries key
material or a path that only exists on the machine that produced it.

Whether the guest told the truth is outside this: that is a question for the
guest, and the run manifest records which image answered.
"""

import hashlib
import json
import os
import re
import sys

PROBE_CLASSES = {"observed", "observed-absent", "partial", "failed",
                 "unreachable"}
SECRET_MARKERS = ("PRIVATE KEY", "BEGIN OPENSSH", "BEGIN RSA",
                  "BEGIN EC PRIVATE")
# A committed artifact that names a directory only one machine has binds the
# evidence to that machine, which the repository rules keep out of the tree.
# Guest paths are content -- the baseline exists to record them. What must not
# appear is a directory that exists only on the machine that produced the run.
LOCAL_PATH = re.compile(r"(?:/home/|/Users/|/tmp/claude)")
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
    """Resolve an advertised artifact, refusing anything but a basename.

    A manifest entry that carries a path rather than a name can reach outside
    the evidence directory, and a checker that follows it validates a file the
    package does not contain.
    """
    if not name or os.path.basename(name) != name:
        raise Failure("%s names %r, which is not a basename in the evidence "
                      "directory" % (field, name))
    path = os.path.join(root, name)
    if not os.path.exists(path):
        raise Failure("%s names %s, which is absent" % (field, name))
    return path


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
        if not probe.get("command"):
            failures.append("probe %s records no command" % name)

        # A probe that did not answer still advertises its stdout file, because
        # an absent file and an empty answer are different outcomes and the
        # class is what tells them apart.
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
            found = digest(path)
            if found != recorded_digest:
                failures.append("probe %s %s hashes to %s, the manifest "
                                "records %s" % (name, stream, found,
                                                recorded_digest))
    if not seen:
        failures.append("probes.json advertises no probe")
    return probes


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


def check_run(root, manifest, failures):
    run = load(os.path.join(root, "run.json"))
    if run.get("schema_version") != 2:
        failures.append("run.json declares schema_version %r"
                        % run.get("schema_version"))
    for field in ("repository_commit", "container_image_id", "qemu_version",
                  "accelerator", "accelerator_reason_code"):
        if not run.get(field):
            failures.append("run.json records no %s; the run is then a set of "
                            "numbers with no producer" % field)
    for field in ("qemu_argv", "offline_fsck_transcript"):
        try:
            artifact(root, run.get(field), "run.json %s" % field)
        except Failure as error:
            failures.append(str(error))

    # The index is what makes the run's own output tamper-evident: a file
    # added, removed, or edited after the run shows up as an index that no
    # longer describes what the collector produced.
    index = run.get("artifact_sha256") or {}
    present = {name for name in os.listdir(root)
               if os.path.isfile(os.path.join(root, name))
               and not name.startswith(".") and name != "run.json"}
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
