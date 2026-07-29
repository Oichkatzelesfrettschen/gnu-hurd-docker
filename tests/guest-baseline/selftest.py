#!/usr/bin/env python3
"""Drive the guest-baseline checker against baselines whose defect is known.

A checker exercised only by packages it accepts states nothing about its
exclusions. Each case here builds a complete, valid baseline and then breaks
exactly one thing, so a pass means the checker rejected that defect rather than
rejecting the fixture for an unrelated reason. The accepting case runs first: if
the synthetic baseline were malformed, every rejection below would pass for the
wrong reason.

The suite is offline and touches no guest. It says whether the checker reads a
package correctly, not whether any committed package is correct.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))))
CHECKER = os.path.join(ROOT, "scripts", "check-guest-baseline.py")

STATUS = (
    "Package: fixture-one\n"
    "Status: install ok installed\n"
    "Priority: optional\n"
    "Architecture: hurd-amd64\n"
    "Version: 1.0\n"
    "\n"
    "Package: fixture-all\n"
    "Status: install ok installed\n"
    "Priority: optional\n"
    "Architecture: all\n"
    "Version: 2.0\n"
    "\n"
)

IMAGE_DIGEST = "a" * 64

QEMU_ARGV = (
    "/usr/bin/qemu-system-x86_64\n"
    "-accel\ntcg,thread=multi\n"
    "-smp\n1\n"
    "-m\n2048\n"
    "-drive\nid=drive0,file=/opt/hurd-run/overlay.qcow2,format=qcow2\n"
    "-device\nide-hd,drive=drive0\n"
)

OVERLAY_CHAIN = json.dumps({
    "kind": "guest-baseline-overlay-chain",
    "overlay": {"basename": "overlay.qcow2", "format": "qcow2"},
    "backing": {"repository_path": "images/fixture.qcow2",
                "basename": "fixture.qcow2", "format": "qcow2",
                "sha256": IMAGE_DIGEST},
}, indent=2) + "\n"


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write(root, name, text):
    with open(os.path.join(root, name), "w", encoding="utf-8") as handle:
        handle.write(text)
    return sha256(text)


def init_producers(root, probes):
    """Give the fixture a real commit carrying its producers.

    The checker verifies the recorded producer digests against the recorded
    commit's own copies, so a fixture with no history would silently skip that
    assertion and the negative case below would pass for the wrong reason.
    """
    env = dict(os.environ,
               GIT_AUTHOR_NAME="fixture", GIT_AUTHOR_EMAIL="f@fixture",
               GIT_COMMITTER_NAME="fixture", GIT_COMMITTER_EMAIL="f@fixture")
    producers = {
        "collector_sha256": ("scripts/collect-guest-baseline.sh",
                             "collector fixture\n"),
        "transport_sha256": ("scripts/lib/guest-ssh.sh", "transport fixture\n"),
        "exporter_sha256": ("scripts/export-guest-package-state.sh",
                            "exporter fixture\n"),
    }
    subprocess.run(["git", "init", "-q", root], check=True, env=env)
    # A host-level fsmonitor daemon would drop a socket into .git, which a
    # later copytree of the fixture cannot copy.
    subprocess.run(["git", "-C", root, "config", "core.fsmonitor", "false"],
                   check=True, env=env)
    for field, (path, text) in producers.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as handle:
            handle.write(text)
        probes[field] = sha256(text)
    subprocess.run(["git", "-C", root, "add", "scripts"], check=True, env=env)
    subprocess.run(["git", "-C", root, "commit", "-qm", "producers"],
                   check=True, env=env)
    probes["repository_commit"] = subprocess.run(
        ["git", "-C", root, "rev-parse", "HEAD"], capture_output=True,
        text=True, check=True, env=env).stdout.strip()


def build(root):
    """Write a baseline the checker accepts."""
    os.makedirs(root, exist_ok=True)
    artifacts = {}

    contents = {
        "uname.txt": "GNU fixture 0.9 GNU-Mach 1.8-up-amd64/Hurd-0.9 x86_64 GNU\n",
        "nproc.txt": "1\n",
        "debian_version.txt": "forky/sid\n",
        "dpkg-architecture.txt": "hurd-amd64\n",
        "apt-preferences.txt": "",
        "qemu-argv.txt": QEMU_ARGV,
        "overlay-chain.json": OVERLAY_CHAIN,
        "offline-fsck.log": "$ guestfish e2fsck /dev/sda5\nexit=0\n",
        "README.md": "Fixture baseline.\n",
    }
    for name, text in contents.items():
        digest = write(root, name, text)
        # README.md is narrative outside the run index; indexing it would make
        # the accepting fixture claim an artifact the checker excludes.
        if name != "README.md":
            artifacts[name] = digest

    probes = {
        "schema_version": 1,
        "kind": "guest-baseline-probes",
        "started_at": "2026-07-27T00:00:00Z",
        "ended_at": "2026-07-27T00:01:00Z",
        "transport": {"host": "127.0.0.1", "port": 2223, "user": "root",
                      "host_key_fingerprint": "SHA256:fixture"},
        "package_state_export": {"requirement": "required", "status": 0,
                                 "class": "observed",
                                 "started_at": "2026-07-27T00:00:10Z",
                                 "ended_at": "2026-07-27T00:00:20Z"},
        "probes": [],
    }
    init_producers(root, probes)
    required = {"uname", "nproc", "debian_version", "dpkg-architecture"}
    for name in ("uname", "nproc", "debian_version", "dpkg-architecture",
                 "apt-preferences"):
        artifact = "%s.txt" % name
        probes["probes"].append({
            "name": name,
            "requirement": "required" if name in required else "optional",
            "command": "true",
            "class": "observed" if name in required else "observed-absent",
            "remote_status": 0 if name in required else 66,
            "transport_status": 0,
            "started_at": "2026-07-27T00:00:30Z",
            "ended_at": "2026-07-27T00:00:31Z",
            "stdout": artifact,
            "stdout_sha256": artifacts[artifact],
            "stderr": None,
            "stderr_sha256": None,
        })

    status_digest = write(root, "hurd-amd64-dpkg-status", STATUS)
    artifacts["hurd-amd64-dpkg-status"] = status_digest
    manifest = {
        "schema_version": 2,
        "kind": "guest-dpkg-status",
        "architecture": "hurd-amd64",
        "kernel": "GNU fixture",
        "package_count": 2,
        "manifest": "hurd-amd64-dpkg-status",
        "manifest_sha256": status_digest,
        "source_image_sha256": IMAGE_DIGEST,
    }
    artifacts["hurd-amd64-dpkg-status.json"] = write(
        root, "hurd-amd64-dpkg-status.json",
        json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    artifacts["probes.json"] = write(
        root, "probes.json", json.dumps(probes, indent=2, sort_keys=True) + "\n")

    report = {"provenance": {"installed_baseline": {
        "kind": "guest-dpkg-status", "sha256": status_digest,
        "package_count": 2}}}
    write(root, "fixture-set.json",
          json.dumps(report, indent=2, sort_keys=True) + "\n")

    run = {
        "schema_version": 4,
        "kind": "guest-baseline-run",
        "repository_commit": probes["repository_commit"],
        "container_image_id": "sha256:" + "e" * 64,
        "qemu_version": "8.2.2",
        "qemu_argv": "qemu-argv.txt",
        "accelerator": "tcg",
        "accelerator_reason_code": "disable_kvm_requested",
        "qemu_smp": 1,
        "qemu_ram_mb": 2048,
        "disk_bus": "ide",
        "backing_image": "images/fixture.qcow2",
        "backing_sha256_before": IMAGE_DIGEST,
        "backing_sha256_after": IMAGE_DIGEST,
        "backing_unchanged": True,
        "overlay_chain": "overlay-chain.json",
        "overlay_discarded": True,
        "offline_fsck": "clean",
        "offline_fsck_transcript": "offline-fsck.log",
        "guest_packages": 2,
        "artifact_sha256": artifacts,
    }
    write(root, "run.json", json.dumps(run, indent=2, sort_keys=True) + "\n")
    return run


def reindex(root):
    """Rewrite the index so a case tests its own defect and not a stale index.

    The document is read back from disk rather than from the copy the fixture
    built, because a case may have edited run.json itself and rewriting the
    in-memory copy would silently undo the very defect under test.
    """
    path = os.path.join(root, "run.json")
    with open(path, encoding="utf-8") as handle:
        run = json.load(handle)
    for name in list(run["artifact_sha256"]):
        artifact_path = os.path.join(root, name)
        if os.path.exists(artifact_path):
            with open(artifact_path, "rb") as handle:
                run["artifact_sha256"][name] = hashlib.sha256(
                    handle.read()).hexdigest()
    write(root, "run.json", json.dumps(run, indent=2, sort_keys=True) + "\n")


def check(root):
    result = subprocess.run([sys.executable, CHECKER, root],
                            capture_output=True, text=True, check=False)
    return result.returncode, (result.stdout + result.stderr).strip()


class Suite:
    def __init__(self):
        self.passed = 0
        self.failed = 0

    def check(self, description, condition, evidence=""):
        if condition:
            self.passed += 1
            print("ok    %s%s" % (description,
                                  (" (%s)" % evidence[:110]) if evidence else ""))
        else:
            self.failed += 1
            print("FAIL  %s%s" % (description,
                                  (" (%s)" % evidence[:400]) if evidence else ""))


def rewrite_probe_artifact(root, name, text):
    """Replace a probe's stdout and re-derive every digest that describes it.

    A case about what an artifact contains has to leave both the probe record
    and the run index describing the bytes now on disk, or a digest assertion
    fires first and the case proves nothing about the content rule it names.
    """
    write(root, name, text)
    edit_json(root, "probes.json", lambda d: [
        probe.update({"stdout_sha256": sha256(text)})
        for probe in d["probes"] if probe.get("stdout") == name])


def rewrite_status(root, text):
    """Replace the status file and re-derive its manifest.

    A case about paragraph content has to leave the manifest describing the
    file it now holds, or the digest and count assertions fire first and the
    case proves nothing about paragraph parsing.
    """
    write(root, "hurd-amd64-dpkg-status", text)
    edit_json(root, "hurd-amd64-dpkg-status.json",
              lambda d: d.update({
                  "manifest_sha256": sha256(text),
                  "package_count": len([block for block in text.split("\n\n")
                                        if block.strip()]),
              }))


def edit_json(root, name, mutate):
    path = os.path.join(root, name)
    with open(path, encoding="utf-8") as handle:
        document = json.load(handle)
    mutate(document)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2, sort_keys=True)
        handle.write("\n")


def main():
    suite = Suite()
    workspace = tempfile.mkdtemp(prefix="guest-baseline-selftest-")
    try:
        pristine = os.path.join(workspace, "pristine")
        run = build(pristine)

        status, output = check(pristine)
        suite.check("a complete baseline is accepted", status == 0, output)

        # The writer's chain binding is content-addressed: a base file whose
        # basename matches the manifest image but whose bytes differ is the
        # exact composite a name comparison accepts, so the writer must refuse
        # it before any manifest is written.
        stage = os.path.join(workspace, "writer-stage")
        out = os.path.join(stage, "out")
        os.makedirs(os.path.join(stage, "images"))
        os.makedirs(out)
        before = write(stage, "images/fixture.qcow2", "canonical bytes\n")
        write(stage, "fixture.qcow2", "different bytes, same basename\n")
        write(stage, "chain-raw.json", json.dumps([
            {"filename": os.path.join(stage, "overlay.qcow2"),
             "format": "qcow2", "backing-filename": "fixture.qcow2",
             "full-backing-filename": os.path.join(stage, "fixture.qcow2")},
            {"filename": os.path.join(stage, "fixture.qcow2"),
             "format": "qcow2"},
        ]) + "\n")
        write(stage, "argv.txt", QEMU_ARGV)
        write(stage, "fsck.log", "$ guestfish e2fsck /dev/sda5\nexit=0\n")
        writer = os.path.join(ROOT, "scripts", "write-guest-baseline-run.py")
        result = subprocess.run(
            [sys.executable, writer, "--root", out,
             "--backing-image", "images/fixture.qcow2",
             "--backing-sha256-before", before,
             "--accelerator-reason-code", "disable_kvm_requested",
             "--offline-fsck", "clean",
             "--qemu-argv", os.path.join(stage, "argv.txt"),
             "--offline-fsck-transcript", os.path.join(stage, "fsck.log"),
             "--overlay-chain", os.path.join(stage, "chain-raw.json"),
             "--container-image-id", "sha256:" + "e" * 64,
             "--qemu-version", "8.2.2"],
            capture_output=True, text=True, check=False, cwd=stage)
        suite.check(
            "the writer refuses a chain base whose bytes are not the named "
            "image's",
            result.returncode != 0
            and "different image" in result.stderr + result.stdout,
            (result.stderr + result.stdout).replace("\n", " | ")[:200])

        # Each case is (description, damage, marker, reindex). A case that
        # means to break the digest index leaves it stale; every other case
        # rebuilds it first, so the assertion under test is the one that fires
        # rather than the index tripping on the way there.
        cases = [
            ("an edited probe artifact fails its recorded digest",
             lambda root: open(os.path.join(root, "uname.txt"),
                               "a", encoding="utf-8").write("tampered\n"),
             "hashes to", False),
            ("an artifact the manifest advertises may not be absent",
             lambda root: os.remove(os.path.join(root, "nproc.txt")),
             "which is absent", False),
            ("a required probe that did not answer is refused",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: d["probes"][0].update({"class": "partial"})),
             "required probe", True),
            ("a probe class outside the vocabulary is refused",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: d["probes"][0].update({"class": "fine"})),
             "carries class", True),
            ("a failed package-state export voids the collection",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: d["package_state_export"].update(
                     {"class": "failed"})),
             "package-state export", True),
            ("a package count that does not count the paragraphs is refused",
             lambda root: edit_json(
                 root, "hurd-amd64-dpkg-status.json",
                 lambda d: d.update({"package_count": 99})),
             "paragraphs", True),
            ("a status paragraph missing a field apt reads is refused",
             lambda root: rewrite_status(
                 root, "Package: fixture-one\nArchitecture: hurd-amd64\n\n"),
             "omits", True),
            ("a foreign-architecture paragraph is refused",
             lambda root: rewrite_status(
                 root, STATUS.replace("Architecture: hurd-amd64",
                                      "Architecture: hurd-i386", 1)),
             "in a hurd-amd64 baseline", True),
            ("a status export naming another image is refused",
             lambda root: edit_json(
                 root, "hurd-amd64-dpkg-status.json",
                 lambda d: d.update({"source_image_sha256": "f" * 64})),
             "source image", True),
            ("an architecture the guest did not report is refused",
             lambda root: rewrite_probe_artifact(
                 root, "dpkg-architecture.txt", "amd64\n"),
             "reported architecture", True),
            ("a backing image that changed during the run is refused",
             lambda root: edit_json(
                 root, "run.json",
                 lambda d: d.update({"backing_sha256_after": "9" * 64})),
             "changed during the run", True),
            ("a filesystem check that did not run is refused",
             lambda root: edit_json(
                 root, "run.json",
                 lambda d: d.update({"offline_fsck": "not run"})),
             "offline_fsck", True),
            ("a report resolved against another baseline is refused",
             lambda root: edit_json(
                 root, "fixture-set.json",
                 lambda d: d["provenance"]["installed_baseline"].update(
                     {"sha256": "0" * 64})),
             "resolved against installed state", True),
            ("a file that is neither run output nor a bound report is refused",
             lambda root: write(root, "stray.txt", "unaccounted\n"),
             "neither run output", True),
            ("key material in an artifact is refused",
             lambda root: rewrite_probe_artifact(
                 root, "uname.txt",
                 "-----BEGIN OPENSSH PRIVATE KEY-----\n"),
             "BEGIN OPENSSH", True),
            ("a machine-local path in an artifact is refused",
             lambda root: rewrite_probe_artifact(
                 root, "nproc.txt", "/home/someone/tree\n"),
             "machine-local path", True),
            ("a manifest that omits a roster probe is refused",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: d.update({"probes": [probe for probe in d["probes"]
                                                if probe["name"] != "uname"]})),
             "roster requires probe", True),
            ("a roster probe relabeled optional is refused",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: d["probes"][0].update({"requirement": "optional"})),
             "roster requires it", True),
            ("a class the recorded statuses do not derive is refused",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: d["probes"][0].update({"remote_status": 7})),
             "derive", True),
            ("an accelerator the argv did not select is refused",
             lambda root: edit_json(
                 root, "run.json",
                 lambda d: d.update({"accelerator": "kvm"})),
             "argv selects", True),
            ("a vCPU count the argv did not ask for is refused",
             lambda root: edit_json(
                 root, "run.json", lambda d: d.update({"qemu_smp": 2})),
             "argv asks for", True),
            ("an overlay chain onto another image is refused",
             lambda root: edit_json(
                 root, "overlay-chain.json",
                 lambda d: d["backing"].update(
                     {"repository_path": "images/other.qcow2"})),
             "run.json names", True),
            ("a chain base whose bytes are not the manifest image is refused",
             lambda root: edit_json(
                 root, "overlay-chain.json",
                 lambda d: d["backing"].update({"sha256": "c" * 64})),
             "different image than the manifest names", True),
            ("a chain with no measured base digest is refused",
             lambda root: edit_json(
                 root, "overlay-chain.json",
                 lambda d: d["backing"].update({"sha256": ""})),
             "no measured base digest", True),
            ("a raw unsanitized chain capture is refused",
             lambda root: write(root, "overlay-chain.json", json.dumps([
                 {"filename": "overlay.qcow2", "format": "qcow2",
                  "backing-filename": "fixture.qcow2"},
                 {"filename": "fixture.qcow2", "format": "qcow2"},
             ]) + "\n"),
             "sanitized", True),
            ("a package count run.json does not share with the manifest is "
             "refused",
             lambda root: edit_json(
                 root, "run.json", lambda d: d.update({"guest_packages": 99})),
             "guest packages", True),
            ("a run manifest that omits the RAM the argv asks for is refused",
             lambda root: edit_json(
                 root, "run.json", lambda d: d.pop("qemu_ram_mb")),
             "MiB", True),
            ("a flattened home-directory path in an artifact is refused",
             lambda root: rewrite_probe_artifact(
                 root, "nproc.txt", "-home-someone-Github-tree\n"),
             "machine-local path", True),
            ("a host scratchpad path in an artifact is refused",
             lambda root: rewrite_probe_artifact(
                 root, "nproc.txt", "/tmp/claude-1000/session/run\n"),
             "machine-local path", True),
            ("a resolver apt-workspace path in an artifact is refused",
             lambda root: rewrite_probe_artifact(
                 root, "nproc.txt",
                 "100 /tmp/hurd-apt-abc123/var/lib/dpkg/status\n"),
             "machine-local path", True),
            ("an architecture probe with no stdout record is a finding, not a "
             "crash",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: [probe.update({"stdout": None,
                                          "stdout_sha256": None})
                            for probe in d["probes"]
                            if probe["name"] == "dpkg-architecture"]),
             "dpkg-architecture stdout names", True),
            ("a clean verdict the transcript does not derive is refused",
             lambda root: write(
                 root, "offline-fsck.log",
                 "$ guestfish e2fsck /dev/sda5\nexit=1\n"),
             "transcript derives", True),
            ("an artifact that is a symlink is refused",
             lambda root: (
                 os.remove(os.path.join(root, "uname.txt")),
                 os.symlink("/etc/hostname",
                            os.path.join(root, "uname.txt")))[-1],
             "not a regular file", True),
            ("a producer digest the recorded commit does not carry is refused",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: d.update({"collector_sha256": "b" * 64})),
             "at commit", True),
            ("a run manifest under the current schema is required",
             lambda root: edit_json(
                 root, "run.json",
                 lambda d: d.update({"schema_version": 2})),
             "declares schema_version", True),
            ("a run with no host key fingerprint is refused",
             lambda root: edit_json(
                 root, "probes.json",
                 lambda d: d["transport"].update(
                     {"host_key_fingerprint": ""})),
             "host key fingerprint", True),
        ]

        for index, (description, damage, marker, rebuild) in enumerate(cases):
            root = os.path.join(workspace, "case-%02d" % index)
            shutil.copytree(pristine, root,
                            ignore=shutil.ignore_patterns(
                                "fsmonitor--daemon*"))
            damage(root)
            if rebuild:
                reindex(root)
            status, output = check(root)
            suite.check(description, status == 1 and marker in output,
                        "exit %d: %s" % (status, output.replace("\n", " | ")))
    finally:
        shutil.rmtree(workspace, ignore_errors=True)

    print("\n%d checks passed, %d failed" % (suite.passed, suite.failed))
    return 1 if suite.failed else 0


if __name__ == "__main__":
    sys.exit(main())
