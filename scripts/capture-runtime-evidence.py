#!/usr/bin/env python3
"""Capture one identified QEMU instance as a machine-readable evidence document.

Every field binds to a single VM instance: the container is selected by finding
an actual qemu-system process, its Compose service comes from the
com.docker.compose.service label, its declared configuration is read from that
service alone, and its image is resolved by parsing file= out of the QEMU
command line and following the container's own mount table.  A capture that
reads declarations from one service and observations from another produces a
composite that describes no system, which is the failure this binding removes.

Repository declarations and the live container's environment are separate
evidence classes.  A container created from an overlay or an earlier revision
no longer matches the current source, so both are recorded and neither stands
in for the other.

Probe results carry the argv, exit status, and both output streams.  A probe
that fails records what failed; it never receives a preselected explanation.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time

SCHEMA_VERSION = 2

OBSERVED = "observed"
DERIVED = "derived"
DECLARED = "declared"
ABSENT = "not-captured"

# Environment keys whose values are redacted wholesale.  Matching on shape
# rather than on an enumerated list keeps a newly introduced credential from
# reaching a published capture merely because nobody added it here.
SECRET_KEY = re.compile(
    r"(PASSWORD|PASSWD|PASS|TOKEN|SECRET|CREDENTIAL|AUTH|COOKIE|_KEY|APIKEY)",
    re.IGNORECASE,
)

_SECRET_NAME = SECRET_KEY.pattern

# A credential reaches a raw stream in three spellings: the KEY=value element of
# docker inspect .Config.Env, the JSON member docker inspect and compose config
# emit, and the YAML mapping a resolved Compose document carries.  Redacting the
# parsed environment objects alone leaves all three verbatim in the retained
# streams, so the scrub runs over the stream text itself.
SECRET_PATTERNS = (
    re.compile(r'("[^"]*%s[^"]*"\s*:\s*)"(?:[^"\\]|\\.)*"' % _SECRET_NAME, re.IGNORECASE),
    re.compile(r'(\b[A-Za-z0-9_]*%s[A-Za-z0-9_]*=)[^"\s,\]}]+' % _SECRET_NAME, re.IGNORECASE),
    re.compile(r'(^[ \t-]*[A-Za-z0-9_]*%s[A-Za-z0-9_]*:[ \t]+)\S.*$' % _SECRET_NAME,
               re.IGNORECASE | re.MULTILINE),
)


def field(value, evidence_class, source, reason=""):
    """Build one evidence field.  An empty value degrades to not-captured so a
    missing probe records its absence rather than dropping from the schema."""
    if value is None or value == "":
        return {"value": None, "class": ABSENT, "source": source,
                "reason": reason or "probe returned no value"}
    entry = {"value": value, "class": evidence_class, "source": source}
    if reason:
        entry["reason"] = reason
    return entry


class Capture:
    def __init__(self, capture_dir, runtime, replacements=None):
        self.dir = capture_dir
        self.raw = os.path.join(capture_dir, "raw")
        os.makedirs(self.raw, exist_ok=True)
        self.runtime = runtime
        # An empty replacement list leaves streams verbatim, so an unredacted
        # capture and a redacted one travel the same write-then-hash path.
        self.replacements = replacements or []
        self.probes = {}

    def run(self, name, argv, stdin_text=None, timeout=60):
        """Run one probe and retain its argv, status, and both streams.

        The record is the reproduction unit: a reader re-runs argv and compares
        against the retained streams rather than trusting this parse.
        """
        started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        try:
            # errors="replace": the QEMU monitor opens with telnet IAC bytes,
            # which are not UTF-8, and a probe that raises on them loses the
            # transcript that follows.
            done = subprocess.run(
                argv, input=stdin_text, capture_output=True, text=True,
                errors="replace", timeout=timeout, check=False)
            status, out, err = done.returncode, done.stdout, done.stderr
        except (OSError, subprocess.SubprocessError) as exc:
            status, out, err = None, "", "%s: %s" % (type(exc).__name__, exc)
        completed = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

        # Sanitize before writing and before hashing, so the retained bytes and
        # the digest that certifies them are the same bytes.  The parse below
        # continues on the sanitized text: a value the capture refuses to
        # publish is a value it refuses to assert.
        out = redact_stream(out, self.replacements)
        err = redact_stream(err, self.replacements)

        out_file = "raw/%s.out" % name
        err_file = "raw/%s.err" % name
        for rel, text in ((out_file, out), (err_file, err)):
            with open(os.path.join(self.dir, rel), "w", encoding="utf-8") as fh:
                fh.write(text)

        self.probes[name] = {
            "argv": [redact_stream(a, self.replacements) for a in argv],
            "started_at_utc": started,
            "completed_at_utc": completed,
            "exit_status": status,
            "stdout_file": out_file,
            "stderr_file": err_file,
            "stdout_sha256": hashlib.sha256(out.encode("utf-8")).hexdigest(),
            "stderr_sha256": hashlib.sha256(err.encode("utf-8")).hexdigest(),
        }
        return status, out, err

    def ok(self, name):
        return self.probes.get(name, {}).get("exit_status") == 0


def json_probe(capture, name, argv, timeout=60):
    """Run a probe whose stdout is JSON and return the decoded value, or None
    when the probe failed or its output does not decode."""
    status, out, _ = capture.run(name, argv, timeout=timeout)
    if status != 0 or not out.strip():
        return None
    try:
        return json.loads(out)
    except ValueError:
        return None


def select_container(capture, runtime, wanted_container, wanted_service):
    """Return (container, reason).  Selection requires an actual QEMU process,
    because a name match alone selects a noVNC sidecar or a stale VM as readily
    as the instance under study.  Two running QEMU instances are ambiguous, so
    the caller is told to name one rather than being given an arbitrary pick.
    """
    status, out, _ = capture.run(
        "container-list",
        [runtime, "ps", "--filter", "status=running", "--format",
         "{{.Names}}\t{{.Label \"com.docker.compose.service\"}}"])
    if status != 0:
        return None, "container runtime did not list running containers"

    candidates = []
    for line in out.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        name = parts[0].strip()
        service = parts[1].strip() if len(parts) > 1 else ""
        if wanted_container and name != wanted_container:
            continue
        if wanted_service and service != wanted_service:
            continue
        candidates.append((name, service))

    if not candidates:
        return None, "no running container matched the selection"

    with_qemu = []
    for name, service in candidates:
        probe = "qemu-present-%s" % name
        rc, procs, _ = capture.run(
            probe, [runtime, "exec", name, "sh", "-c",
                    # ps -eo comm truncates to 15 characters, so the full
                    # binary name never matches there; args carries it whole.
                    "ps -eo pid,args | grep '[q]emu-system-x86_64' || true"])
        if rc == 0 and procs.strip():
            with_qemu.append((name, service))

    if not with_qemu:
        return None, ("no selected container runs qemu-system-x86_64; "
                      "candidates were %s" % ", ".join(n for n, _ in candidates))
    if len(with_qemu) > 1:
        names = ", ".join(n for n, _ in with_qemu)
        # SystemExit carrying a string prints it and exits 1.  Ambiguity exits 2
        # so a caller distinguishes "name one instance" from an ordinary failure,
        # which means the diagnostic goes to stderr on its own.
        print("capture-runtime-evidence: %d containers run QEMU (%s); "
              "name one with --container or --service" % (len(with_qemu), names),
              file=sys.stderr)
        raise SystemExit(2)
    return with_qemu[0], ""


def qemu_argv_from_proc(capture, runtime, container, wanted_pid=""):
    """Read the QEMU command line from /proc, which is NUL-delimited and keeps
    argument boundaries that splitting formatted ps output on spaces loses.

    One container may host several QEMU processes.  Taking the first silently
    binds the argv, accelerator, machine, and image of an arbitrary one of them
    to a document that claims to describe a single instance, so several PIDs
    without --qemu-pid is ambiguity and exits 2.
    """
    rc, pids, _ = capture.run(
        "qemu-pid", [runtime, "exec", container, "sh", "-c",
                     "ps -eo pid,args | grep '[q]emu-system-x86_64' | awk '{print $1}'"])
    if rc != 0 or not pids.strip():
        return None, None
    found = pids.split()
    if wanted_pid:
        if wanted_pid not in found:
            print("capture-runtime-evidence: no QEMU process %s in %s; found %s"
                  % (wanted_pid, container, ", ".join(found)), file=sys.stderr)
            raise SystemExit(2)
        pid = wanted_pid
    elif len(found) > 1:
        print("capture-runtime-evidence: %d QEMU processes in %s (%s); "
              "name one with --qemu-pid" % (len(found), container, ", ".join(found)),
              file=sys.stderr)
        raise SystemExit(2)
    else:
        pid = found[0]
    rc, raw, _ = capture.run(
        "qemu-cmdline", [runtime, "exec", container, "sh", "-c",
                         "tr '\\0' '\\n' < /proc/%s/cmdline" % pid])
    if rc != 0 or not raw.strip():
        return pid, None
    return pid, [a for a in raw.split("\n") if a != ""]


def argv_option(argv, name):
    """Return the value following an option, or None.  QEMU options take a
    separate argument, so the value is the element after the flag."""
    if not argv:
        return None
    for index, item in enumerate(argv):
        if item == name and index + 1 < len(argv):
            return argv[index + 1]
    return None


def drive_file(argv):
    """Extract file= from any -drive argument."""
    if not argv:
        return None
    for index, item in enumerate(argv):
        if item == "-drive" and index + 1 < len(argv):
            for part in argv[index + 1].split(","):
                if part.startswith("file="):
                    return part[len("file="):]
    return None


def device_access(path):
    """Report existence and access for a device by attempting the access, since
    a mode bit does not establish that this process may open it."""
    result = {"exists": os.path.exists(path)}
    result["readable"] = os.access(path, os.R_OK)
    result["writable"] = os.access(path, os.W_OK)
    if result["exists"]:
        try:
            result["mode"] = stat.filemode(os.stat(path).st_mode)
        except OSError:
            result["mode"] = None
    return result


def container_device_access(capture, runtime, container, path):
    rc, out, _ = capture.run(
        "container-kvm", [runtime, "exec", container, "sh", "-c",
                          ("if [ -e %(p)s ]; then echo exists=1; else echo exists=0; fi; "
                           "if [ -r %(p)s ]; then echo readable=1; else echo readable=0; fi; "
                           "if [ -w %(p)s ]; then echo writable=1; else echo writable=0; fi")
                          % {"p": path}])
    if rc != 0:
        return None
    parsed = {}
    for line in out.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            parsed[key.strip()] = value.strip() == "1"
    return parsed or None


def container_kvm_usable(capture, runtime, container):
    """Report whether QEMU can initialize KVM in this container, and why not.

    test -e/-r/-w establishes that the device node is visible and that the mode
    bits permit an open; it does not establish that KVM_CREATE_VM succeeds.  A
    one-shot QEMU with -accel kvm and no disk exercises the same initialization
    path the VM under study uses, so a TCG arm can state device usability as an
    observation rather than inheriting it from the KVM arm.
    """
    rc, out, err = capture.run(
        "container-kvm-usable",
        [runtime, "exec", container, "sh", "-c",
         # -no-user-config and -nodefaults keep the probe off the studied VM's
         # configuration; the QEMU exits on its own once the machine is created.
         "qemu-system-x86_64 -accel kvm -machine pc -nodefaults -no-user-config "
         "-display none -no-reboot -kernel /dev/null 2>&1; echo rc=$?"],
        timeout=30)
    text = (out or "") + (err or "")
    if rc != 0 and not text.strip():
        return None, "the KVM initialization probe produced no output"
    lowered = text.lower()
    # QEMU reports an unusable accelerator before it reaches the missing kernel
    # image, so an accelerator complaint is the failing signal and a kernel-load
    # complaint means KVM initialized.
    for marker in ("failed to initialize kvm", "could not access kvm kernel module",
                   "kvm not supported", "invalid accelerator", "no accelerator found"):
        if marker in lowered:
            return False, "QEMU reported: %s" % " ".join(text.split())[:200]
    return True, ""


def resolve_image_host_path(inspect, guest_path):
    """Map the guest-visible image path to a host path through the container's
    own mount table.  A named volume has no ./images counterpart, so assuming
    every /opt/hurd-image path maps into the repository misidentifies the file.
    """
    if not inspect or not guest_path:
        return None, "no container inspection or no drive path"
    mounts = inspect[0].get("Mounts", []) if isinstance(inspect, list) else []
    for mount in mounts:
        dest = mount.get("Destination", "")
        if not dest or not guest_path.startswith(dest.rstrip("/") + "/"):
            continue
        remainder = guest_path[len(dest.rstrip("/")) + 1:]
        if mount.get("Type") == "bind" and mount.get("Source"):
            return os.path.join(mount["Source"], remainder), ""
        return None, ("image lives on a %s mount (%s), which has no host path "
                      "under the repository" % (mount.get("Type"), mount.get("Name", "")))
    return None, "no container mount covers %s" % guest_path


def redact_text(text, replacements):
    for needle, token in replacements:
        if needle:
            text = text.replace(needle, token)
    return text


def redact_stream(text, replacements):
    """Sanitize one retained stream: machine-local strings become tokens and
    secret-shaped assignments lose their values.

    This runs inside Capture.run, before the stream is written and before its
    digest is taken.  A pass that rewrites the file afterwards leaves the digest
    describing the unsanitized bytes, so every redacted stream then fails the
    integrity record the capture publishes for it.
    """
    text = redact_text(text, replacements)
    for pattern in SECRET_PATTERNS:
        text = pattern.sub(lambda m: m.group(1) + "<redacted>", text)
    return text


def redact_env(env):
    """Replace secret-shaped values, so a capture advertised as publishable does
    not carry a credential the resolved configuration happened to include."""
    clean = {}
    for key, value in (env or {}).items():
        clean[key] = "<redacted>" if SECRET_KEY.search(key) else value
    return clean


def main():
    parser = argparse.ArgumentParser(
        description="Capture one identified QEMU instance as evidence.")
    parser.add_argument("--container", default="", help="inspect this container")
    parser.add_argument("--service", default="", help="inspect this Compose service")
    parser.add_argument("--qemu-pid", default="",
                        help="bind to this QEMU pid when the container hosts several")
    parser.add_argument("--image-digest", action="store_true",
                        help="hash the guest image; requires the VM stopped")
    parser.add_argument("--image", default="",
                        help="hash this qcow2 path directly, without selecting a "
                             "running instance")
    parser.add_argument("--output-dir", default="", help="capture root directory")
    parser.add_argument("--redact", action="store_true",
                        help="replace paths, host name, and secret-shaped values")
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(repo_root)
    runtime = os.environ.get("CONTAINER_RUNTIME", "docker")

    commit = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True,
                            text=True, check=False).stdout.strip() or "unknown"
    short = commit[:7]
    captured_at = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    root = args.output_dir or os.environ.get(
        "RUNTIME_EVIDENCE_ROOT", os.path.join(repo_root, "evidence", "runtime"))
    replacements = [(repo_root, "<repo>"),
                    (os.path.expanduser("~"), "<home>"),
                    (os.uname().nodename, "<host>")] if args.redact else []
    capture = Capture(os.path.join(root, "%s-%s" % (short, captured_at)),
                      runtime, replacements)

    # ---- repository ------------------------------------------------------
    _, dirty_out, _ = capture.run("git-status", ["git", "status", "--porcelain"])
    _, surface, _ = capture.run("shell-surface", ["./scripts/list-maintained-shell.sh"])
    surface_count = len([l for l in surface.splitlines() if l.strip()]) or None

    # ---- host ------------------------------------------------------------
    _, host_uname, _ = capture.run("host-uname", ["uname", "-a"])
    host_cpu = ""
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("model name"):
                    host_cpu = line.split(":", 1)[1].strip()
                    break
    except OSError:
        pass
    host_kvm = device_access("/dev/kvm")
    _, runtime_version, _ = capture.run(
        "runtime-version", [runtime, "version", "--format", "{{.Server.Version}}"])

    # ---- selection -------------------------------------------------------
    selected, select_reason = select_container(
        capture, runtime, args.container, args.service)
    container = selected[0] if selected else ""
    service = selected[1] if selected else ""

    inspect = None
    live_env = {}
    image_id = ""
    container_labels = {}
    published_ssh = ""
    if container:
        inspect = json_probe(capture, "container-inspect",
                             [runtime, "inspect", container])
        if inspect:
            config = inspect[0].get("Config", {})
            image_id = inspect[0].get("Image", "")
            container_labels = config.get("Labels", {}) or {}
            for item in config.get("Env", []) or []:
                if "=" in item:
                    key, value = item.split("=", 1)
                    live_env[key] = value
            ports = inspect[0].get("NetworkSettings", {}).get("Ports", {}) or {}
            for guest_port, bindings in ports.items():
                if guest_port.startswith("2222") and bindings:
                    published_ssh = bindings[0].get("HostPort", "")
            if not service:
                service = container_labels.get("com.docker.compose.service", "")

    # ---- declared configuration for the selected service only ------------
    compose_doc = json_probe(
        capture, "compose-config",
        [runtime, "compose", "config", "--format", "json"], timeout=120)
    declared_env = {}
    declared_reason = ""
    if compose_doc and service:
        svc = (compose_doc.get("services") or {}).get(service)
        if svc:
            declared_env = {k: ("" if v is None else str(v))
                            for k, v in (svc.get("environment") or {}).items()}
        else:
            declared_reason = ("the resolved Compose document has no service %r; "
                               "the running container may predate it" % service)
    elif not service:
        declared_reason = "no Compose service identified for the selected container"
    else:
        declared_reason = "docker compose config did not produce a JSON document"

    # ---- QEMU ------------------------------------------------------------
    qemu_pid, qemu_argv = (None, None)
    qemu_version = ""
    container_kvm = None
    kvm_usable, kvm_usable_reason = None, "no container selected"
    if container:
        qemu_pid, qemu_argv = qemu_argv_from_proc(
            capture, runtime, container, args.qemu_pid)
        _, version_out, _ = capture.run(
            "qemu-version",
            [runtime, "exec", container, "qemu-system-x86_64", "--version"])
        qemu_version = version_out.splitlines()[0] if version_out.strip() else ""
        container_kvm = container_device_access(capture, runtime, container, "/dev/kvm")
        kvm_usable, kvm_usable_reason = container_kvm_usable(
            capture, runtime, container)

    accel = argv_option(qemu_argv, "-accel")
    machine = argv_option(qemu_argv, "-machine")
    smp = argv_option(qemu_argv, "-smp")
    guest_image = drive_file(qemu_argv)

    # ---- monitor ---------------------------------------------------------
    monitor_spec = argv_option(qemu_argv, "-monitor")
    monitor_port = ""
    if monitor_spec:
        # QEMU spells the endpoint telnet:HOST:PORT[,flags] or tcp:HOST:PORT,
        # and only some chardev forms use port=.  Both shapes are read here so
        # the monitor endpoint comes from the process rather than a constant.
        match = re.search(r"port=(\d+)", monitor_spec) or \
            re.match(r"(?:telnet|tcp):[^:]*:(\d+)", monitor_spec)
        if match:
            monitor_port = match.group(1)
    monitor_kvm = None
    vcpu_threads = None
    monitor_reason = ""
    if container and monitor_port:
        # The stream omits "quit": in the QEMU monitor that terminates QEMU
        # rather than closing the session, and the reboot-loop mode restarts the
        # guest, which reads as a spurious guest reboot.
        rc, monitor_out, _ = capture.run(
            "monitor-info",
            [runtime, "exec", container, "sh", "-c",
             "printf 'info status\\ninfo kvm\\ninfo cpus\\n' | timeout 10 nc 127.0.0.1 %s"
             % monitor_port])
        # The transcript is the evidence, not the exit status.  Omitting "quit"
        # leaves the monitor session open, so timeout(1) reaps nc and returns
        # 124 on a probe that answered fully.  The probe record retains that
        # status; the parse reads whatever the monitor sent.
        if monitor_out.strip():
            if "kvm support: enabled" in monitor_out:
                monitor_kvm = True
            elif "kvm support:" in monitor_out:
                monitor_kvm = False
            # A running QEMU presents at least one CPU, so a zero count means
            # the transcript ended before "info cpus" answered rather than that
            # the machine has no vCPU.  Counting unconditionally would publish
            # that truncation as an observation of zero.
            counted = monitor_out.count("CPU #")
            if counted:
                vcpu_threads = counted
            else:
                monitor_reason = ("the monitor transcript carries no 'CPU #' line, "
                                  "so the info cpus response is incomplete")

    # ---- image -----------------------------------------------------------
    host_image, image_reason = resolve_image_host_path(inspect, guest_image)
    image_info = None
    if host_image and os.path.exists(host_image) and shutil.which("qemu-img"):
        # A running VM holds the qcow2 write lock, so metadata reads pass -U.
        # The flag shares the lock for reading and writes nothing.
        share = ["-U"] if container else []
        image_info = json_probe(
            capture, "image-info",
            ["qemu-img", "info", "--output=json"] + share + [host_image])
        capture.run("image-snapshots",
                    ["qemu-img", "snapshot", "-l"] + share + [host_image])
    elif container and guest_image:
        image_info = json_probe(
            capture, "image-info",
            [runtime, "exec", container, "qemu-img", "info", "--output=json", guest_image])
        if not image_reason:
            image_reason = "image inspected inside the container"

    snapshots = None
    if image_info:
        snapshots = [s.get("name") for s in image_info.get("snapshots", [])]

    digest = ""
    digest_reason = "hashing a running writable qcow2 yields no stable digest; " \
                    "stop the VM and rerun with --image PATH"
    # Image identity is otherwise discovered from a running QEMU process, while
    # a stable digest requires the VM stopped.  Those conditions never hold at
    # once, so --image names the file directly and makes offline image evidence
    # independent of runtime selection.
    digest_target = args.image or (host_image if not container else "")
    if args.image and container:
        digest_reason = ("refusing to hash %s while a VM runs; the file may be "
                         "the one it is writing" % args.image)
        digest_target = ""
    if (args.image_digest or args.image) and digest_target:
        if os.path.exists(digest_target):
            hasher = hashlib.sha256()
            with open(digest_target, "rb") as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    hasher.update(chunk)
            digest, digest_reason = hasher.hexdigest(), ""
        else:
            digest_reason = "no file at %s" % digest_target
    elif args.image_digest and container:
        digest_reason = ("refusing to hash %s while its VM runs; the file is "
                         "writable and the digest would not be stable" % guest_image)

    # ---- guest -----------------------------------------------------------
    ssh_port = published_ssh or os.environ.get("RUNTIME_EVIDENCE_SSH_PORT", "")
    ssh_key = os.environ.get("RUNTIME_EVIDENCE_SSH_KEY",
                             os.path.join(repo_root, "ssh-test-keys", "hurd_test_key"))
    ssh_user = os.environ.get("RUNTIME_EVIDENCE_SSH_USER", "root")
    guest = {}
    guest_reason = ""
    if not container:
        guest_reason = "no container selected"
    elif not ssh_port:
        guest_reason = "the selected container publishes no host port for guest 22"
    elif not os.access(ssh_key, os.R_OK):
        guest_reason = "no readable ssh key at the configured path"
    else:
        rc, out, err = capture.run(
            "guest-probe",
            ["ssh", "-i", ssh_key, "-p", ssh_port,
             "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
             "-o", "ConnectTimeout=15", "-o", "BatchMode=yes",
             "%s@127.0.0.1" % ssh_user,
             'uname -a; nproc; dpkg-query -f "${Status}\\n" -W 2>/dev/null | '
             'grep -c "install ok installed"; sha256sum /var/lib/dpkg/status | cut -d" " -f1'],
            timeout=90)
        lines = out.splitlines()
        if rc == 0 and len(lines) >= 4:
            guest = {"uname": lines[0], "nproc": lines[1],
                     "packages": lines[2], "dpkg_sha256": lines[3]}
        else:
            # The recorded reason is what the probe reported.  Naming a known
            # blocker here instead would assign a cause the run did not show.
            guest_reason = "ssh probe exited %s: %s" % (
                rc, " ".join(err.split())[:200] or "no stderr")

    # ---- assemble --------------------------------------------------------
    document = {
        "schema_version": SCHEMA_VERSION,
        "captured_at_utc": captured_at,
        "reproduce": {
            "command": [os.path.relpath(os.path.abspath(__file__), repo_root)]
                       + (["--container", args.container] if args.container else [])
                       + (["--service", args.service] if args.service else [])
                       + (["--image-digest"] if args.image_digest else [])
                       + (["--redact"] if args.redact else []),
            "environment": {k: v for k, v in os.environ.items()
                            if k in ("COMPOSE_FILE", "CONTAINER_RUNTIME",
                                     "RUNTIME_EVIDENCE_SSH_PORT",
                                     "RUNTIME_EVIDENCE_SSH_USER")},
        },
        "evidence_classes": {
            OBSERVED: "read from the live system",
            DERIVED: "computed from an observed value",
            DECLARED: "read from configuration, stating intent",
            ABSENT: "unavailable, with the reason the probe reported",
        },
        "instance": {
            "container": field(container, OBSERVED, "container ps + qemu process check",
                               select_reason),
            "compose_service": field(service, OBSERVED,
                                     "com.docker.compose.service label"),
            "compose_project": field(container_labels.get("com.docker.compose.project"),
                                     OBSERVED, "com.docker.compose.project label"),
            "container_image_id": field(image_id, OBSERVED, "container inspect .Image"),
            "qemu_pid": field(qemu_pid, OBSERVED, "ps inside the container"),
        },
        "repository": {
            "commit": field(commit, OBSERVED, "git rev-parse HEAD"),
            "dirty": field(bool(dirty_out.strip()), OBSERVED, "git status --porcelain"),
            "maintained_shell_surface": field(surface_count, OBSERVED,
                                              "scripts/list-maintained-shell.sh"),
        },
        "host": {
            "uname": field(host_uname.strip(), OBSERVED, "uname -a"),
            "cpu_model": field(host_cpu, OBSERVED, "/proc/cpuinfo"),
            "cpu_count": field(os.cpu_count(), OBSERVED, "os.cpu_count"),
            "kvm_device": field(host_kvm, OBSERVED, "stat and access on /dev/kvm"),
            "container_runtime": field(runtime, DECLARED, "CONTAINER_RUNTIME"),
            "container_runtime_version": field(runtime_version.strip(), OBSERVED,
                                               "container runtime version"),
        },
        "declared": {
            "environment": field(redact_env(declared_env) if args.redact else declared_env,
                                 DECLARED,
                                 "docker compose config --format json, service %r" % service,
                                 declared_reason),
        },
        "live_container": {
            "environment": field(redact_env(live_env) if args.redact else live_env,
                                 OBSERVED, "container inspect .Config.Env",
                                 "the live container may predate the resolved "
                                 "Compose document, so this is recorded separately"),
            "published_ssh_port": field(published_ssh, OBSERVED,
                                        "container inspect .NetworkSettings.Ports"),
        },
        "observed_runtime": {
            "qemu_version": field(qemu_version, OBSERVED,
                                  "qemu-system-x86_64 --version inside the container"),
            "qemu_argv": field(qemu_argv, OBSERVED, "/proc/<pid>/cmdline, NUL-delimited"),
            "accelerator": field(accel, OBSERVED, "QEMU argv -accel"),
            "machine": field(machine, OBSERVED, "QEMU argv -machine"),
            "smp": field(smp, OBSERVED, "QEMU argv -smp"),
            "container_kvm_device": field(container_kvm, OBSERVED,
                                          "test -e/-r/-w /dev/kvm inside the container"),
            "monitor_kvm_enabled": field(monitor_kvm, OBSERVED, "QEMU monitor: info kvm"),
            "monitor_vcpu_threads": field(vcpu_threads, OBSERVED,
                                          "QEMU monitor: info cpus", monitor_reason),
            "container_kvm_usable": field(kvm_usable, OBSERVED,
                                          "one-shot qemu-system-x86_64 -accel kvm "
                                          "inside the container", kvm_usable_reason),
        },
        "observed_guest": {
            "uname": field(guest.get("uname"), OBSERVED, "guest uname -a", guest_reason),
            "nproc": field(guest.get("nproc"), OBSERVED, "guest nproc", guest_reason),
            "installed_packages": field(guest.get("packages"), OBSERVED,
                                        "guest dpkg-query -W", guest_reason),
            "dpkg_status_sha256": field(guest.get("dpkg_sha256"), OBSERVED,
                                        "guest sha256sum /var/lib/dpkg/status",
                                        guest_reason),
        },
        "image": {
            "guest_path": field(guest_image, OBSERVED, "QEMU argv -drive file="),
            "host_path": field(host_image, DERIVED,
                               "guest path resolved through container mounts",
                               image_reason),
            "virtual_size_bytes": field(
                (image_info or {}).get("virtual-size"), OBSERVED, "qemu-img info --output=json"),
            "actual_size_bytes": field(
                (image_info or {}).get("actual-size"), OBSERVED, "qemu-img info --output=json"),
            "format": field((image_info or {}).get("format"), OBSERVED,
                            "qemu-img info --output=json"),
            # An empty snapshot list is an observation; only a failed probe is
            # not-captured, so the two stay distinguishable.
            "snapshot_tags": ({"value": snapshots, "class": OBSERVED,
                               "source": "qemu-img info --output=json"}
                              if snapshots is not None
                              else field(None, ABSENT, "qemu-img info --output=json",
                                         "image metadata unavailable")),
            "sha256": field(digest, OBSERVED, "sha256sum", digest_reason),
        },
        "probes": capture.probes,
    }

    # The retained streams are already sanitized and hashed.  capture.json is
    # assembled from those sanitized values, so it takes one scrub of its own
    # serialization and no stream is rewritten after its digest is taken.
    out_path = os.path.join(capture.dir, "capture.json")
    serialized = json.dumps(document, indent=2) + "\n"
    if args.redact:
        serialized = redact_stream(serialized, replacements)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(serialized)

    print(out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
