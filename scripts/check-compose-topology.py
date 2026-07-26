#!/usr/bin/env python3
"""Assert the service and port topology each Compose composition renders to.

A Compose overlay that declares a service name the base file does not adds a
service rather than overriding one, and the two then run as separate containers
against the same qcow2. That failure is invisible in the overlay's own text: it
reads as a complete service definition, which is exactly what makes it wrong.
The rendered configuration is where it becomes visible, so this renders each
composition through the engine and asserts what came out.

Rendering also settles ownership. The image bind, the KVM device, and the VNC
surface each belong to one overlay; a second file declaring them publishes the
same host port twice or exposes a device the composition did not ask for.

The engine performs the merge, so this needs a working `docker compose` or
`podman compose`. Without one the check reports itself as not run and exits
non-zero, because a topology gate that passes when it cannot look is worse than
no gate.
"""

import json
import os
import subprocess
import sys

RUNTIME = os.environ.get("CONTAINER_RUNTIME", "docker")

QEMU_SERVICE = "gnu-hurd-dev"
MINTY = "compose.yaml:compose.bind.yaml:compose.minty.yaml"

# Every composition a Minty target starts, with the services it may render to.
# A name outside the allowed set is a second container, whatever it is called.
COMPOSITIONS = (
    ("minty", MINTY, {QEMU_SERVICE}, {"kvm": False}),
    ("minty-kvm", MINTY + ":compose.kvm.yaml", {QEMU_SERVICE}, {"kvm": True}),
    ("minty-vnc", MINTY + ":compose.vnc.yaml",
     {QEMU_SERVICE, "novnc", "vnc-recorder"}, {"kvm": False}),
    ("minty-kvm-vnc", MINTY + ":compose.kvm.yaml:compose.vnc.yaml",
     {QEMU_SERVICE, "novnc", "vnc-recorder"}, {"kvm": True}),
)

# The Minty guest is the only drive these compositions may boot. A different
# qcow2 here means a target mutates an image its name does not claim.
MINTY_DRIVE = "/opt/hurd-image/hurd-working.qcow2"

# Settings whose Minty value was chosen against measured guest behavior.
# QEMU_SMP above 1 buys no guest parallelism, because the installed kernel is
# the uniprocessor Mach build, and it varies host-side QEMU timing instead.
EXPECTED_ENVIRONMENT = {"QEMU_SMP": "1"}


class Failure(Exception):
    pass


def render(files):
    """Return the merged configuration the engine produces for a file set."""
    environment = dict(os.environ, COMPOSE_FILE=files)
    process = subprocess.run(
        [RUNTIME, "compose", "--profile", "vnc", "config", "--format", "json"],
        env=environment, capture_output=True, text=True, timeout=180)
    if process.returncode != 0:
        raise Failure("%s compose config failed: %s"
                      % (RUNTIME, " ".join(process.stderr.split())[:300]))
    return json.loads(process.stdout)


def published(service):
    """Every host port the service publishes, as protocol-qualified ranges."""
    found = []
    for entry in service.get("ports", []):
        target = entry.get("published", "")
        protocol = entry.get("protocol", "tcp")
        if target:
            found.append("%s/%s" % (target, protocol))
    return found


def check(name, files, allowed, expect):
    config = render(files)
    services = config.get("services", {})
    problems = []

    unexpected = set(services) - allowed
    if unexpected:
        problems.append("renders services outside the allowed set: %s"
                        % ", ".join(sorted(unexpected)))

    # One QEMU-bearing service. A second one boots a second VM against the same
    # image, which is the failure a service-name overlay introduces silently.
    bearing = [key for key, value in services.items()
               if any(MINTY_DRIVE in str(item) or "hurd-image" in str(item)
                      for item in value.get("environment", {}).values())]
    if len(bearing) != 1:
        problems.append("names %d services carrying a guest drive, not 1: %s"
                        % (len(bearing), ", ".join(sorted(bearing)) or "none"))

    qemu = services.get(QEMU_SERVICE, {})
    environment = qemu.get("environment", {})

    drive = str(environment.get("QEMU_DRIVE", ""))
    if drive != MINTY_DRIVE:
        problems.append("boots %r rather than the Minty guest %r"
                        % (drive, MINTY_DRIVE))

    for key, value in EXPECTED_ENVIRONMENT.items():
        if str(environment.get(key, "")) != value:
            problems.append("sets %s to %r rather than %r"
                            % (key, str(environment.get(key, "")), value))

    devices = [str(entry) for entry in qemu.get("devices", [])]
    has_kvm = any("/dev/kvm" in entry for entry in devices)
    if has_kvm != expect["kvm"]:
        problems.append("exposes /dev/kvm=%s where the composition expects %s; "
                        "the KVM overlay owns that device"
                        % (has_kvm, expect["kvm"]))

    # A host port published twice makes the second binding fail at start, and
    # the message names the port rather than the file that duplicated it.
    everything = []
    for value in services.values():
        everything.extend(published(value))
    duplicates = sorted({entry for entry in everything
                         if everything.count(entry) > 1})
    if duplicates:
        problems.append("publishes the same host port more than once: %s"
                        % ", ".join(duplicates))

    # The Minty overlay delegates the framebuffer surface, so a direct noVNC
    # port without the sidecar publishes a proxy that nothing serves.
    novnc_ports = [entry for entry in published(qemu) if entry.startswith("6080")]
    if novnc_ports and "novnc" not in services:
        problems.append("publishes a noVNC port from the QEMU service with no "
                        "sidecar to serve it")

    return problems


def main():
    if subprocess.run([RUNTIME, "compose", "version"],
                      capture_output=True).returncode != 0:
        print("not run: %s compose is unavailable, so the rendered topology "
              "was never inspected" % RUNTIME, file=sys.stderr)
        return 2

    failures = 0
    for name, files, allowed, expect in COMPOSITIONS:
        try:
            problems = check(name, files, allowed, expect)
        except Failure as exc:
            print("FAIL  %-14s %s" % (name, exc))
            failures += 1
            continue
        if problems:
            failures += 1
            for problem in problems:
                print("FAIL  %-14s %s" % (name, problem))
        else:
            print("ok    %-14s one QEMU service, owned devices and ports" % name)

    print("\n%d compositions checked, %d failed"
          % (len(COMPOSITIONS), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
