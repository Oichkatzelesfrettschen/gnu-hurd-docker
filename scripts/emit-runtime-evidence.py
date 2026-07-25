#!/usr/bin/env python3
"""Assemble the runtime evidence document from environment-passed captures.

capture-runtime-evidence.sh gathers values and raw command output; this module
encodes them.  A JSON encoder escapes field values, so a QEMU argv containing
quotes or a guest uname containing a slash reaches the document intact rather
than depending on shell quoting.

Each field is an object rather than a bare value, because a reader needs to know
what a value licenses: an observed accelerator settles which one QEMU chose, and
a declared FORCE_KVM states only what the stack requested.
"""

import json
import os
import sys

OBSERVED = "observed"
DERIVED = "derived"
DECLARED = "declared"
ABSENT = "not-captured"


def field(value, evidence_class, source, reason=""):
    """Build one evidence field.  An empty value degrades to not-captured, so a
    missing probe records its absence instead of dropping out of the schema."""
    if value == "" or value is None:
        return {
            "value": None,
            "class": ABSENT,
            "source": source,
            "reason": reason or "probe returned no value",
        }
    entry = {"value": value, "class": evidence_class, "source": source}
    if reason:
        entry["reason"] = reason
    return entry


def env(name, default=""):
    return os.environ.get(name, default).strip()


def as_bool(name):
    raw = env(name)
    if raw == "true":
        return True
    if raw == "false":
        return False
    return None


def as_int(name):
    raw = env(name)
    try:
        return int(raw)
    except ValueError:
        return None


def raw_files(raw_dir):
    """List the retained raw captures by name and byte size, so a reader sees
    which probes produced output without opening each file."""
    listing = {}
    if not os.path.isdir(raw_dir):
        return listing
    for name in sorted(os.listdir(raw_dir)):
        path = os.path.join(raw_dir, name)
        if os.path.isfile(path):
            listing[name] = os.path.getsize(path)
    return listing


def main():
    raw_dir = env("RAW_DIR")
    container_reason = env("CONTAINER_REASON")
    guest_reason = env("GUEST_REASON")

    accel = env("ACCEL_OBSERVED")
    force_kvm = env("DECL_FORCE_KVM")
    auto_disable = env("DECL_AUTO_DISABLE")

    # The selected accelerator is the only field that settles the availability
    # question.  /dev/kvm existing, FORCE_KVM being set, and a target named
    # up-kvm are all upstream of it.
    selection_note = ""
    if accel.startswith("tcg") and as_bool("KVM_PRESENT"):
        selection_note = (
            "KVM is available on the host and QEMU runs TCG: the "
            "AUTO_DISABLE_KVM_FOR_IDE branch demotes kvm to tcg for this "
            "machine and disk bus unless FORCE_KVM=1"
        )

    document = {
        "schema_version": as_int("SCHEMA_VERSION"),
        "captured_at_utc": env("CAPTURED_AT"),
        "reproduce": "scripts/capture-runtime-evidence.sh",
        "evidence_classes": {
            OBSERVED: "read from the live QEMU process, its monitor, or the guest",
            DERIVED: "computed from an observed value",
            DECLARED: "read from repository configuration, stating intent",
            ABSENT: "unavailable, with the reason recorded",
        },
        "repository": {
            "commit": field(env("COMMIT"), OBSERVED, "git rev-parse HEAD"),
            "dirty": field(as_bool("DIRTY"), OBSERVED, "git status --porcelain"),
            "maintained_shell_surface": field(
                as_int("SHELL_SURFACE"), OBSERVED,
                "scripts/list-maintained-shell.sh",
            ),
        },
        "host": {
            "uname": field(env("HOST_UNAME"), OBSERVED, "uname -a", "see raw/host-uname.txt"),
            "cpu_model": field(env("HOST_CPU"), OBSERVED, "/proc/cpuinfo"),
            "cpu_count": field(as_int("HOST_CPUS"), OBSERVED, "nproc"),
            "kvm_device_present": field(as_bool("KVM_PRESENT"), OBSERVED, "test -e /dev/kvm"),
            "qemu_version": field(env("QEMU_VERSION"), OBSERVED, "qemu-system-x86_64 --version"),
            "container_runtime": field(env("RUNTIME_BIN"), DECLARED, "CONTAINER_RUNTIME"),
            "container_runtime_version": field(
                env("RUNTIME_VERSION"), OBSERVED, "container runtime version",
            ),
        },
        "declared": {
            "compose_files": field(env("COMPOSE_FILES"), DECLARED, "COMPOSE_FILE"),
            "machine": field(env("DECL_MACHINE"), DECLARED, "compose config"),
            "disk_bus": field(env("DECL_DISK_BUS"), DECLARED, "compose config"),
            "smp": field(env("DECL_SMP"), DECLARED, "compose config"),
            "force_kvm": field(force_kvm, DECLARED, "compose config"),
            "auto_disable_kvm_for_ide": field(auto_disable, DECLARED, "compose config"),
            "drive": field(env("IMAGE_PATH"), DECLARED, "compose config"),
        },
        "observed_runtime": {
            "container": field(env("CONTAINER"), OBSERVED, "container ps", container_reason),
            "container_state": field(
                env("CONTAINER_STATE") if env("CONTAINER_STATE") != ABSENT else "",
                OBSERVED, "container inspect", container_reason,
            ),
            "qemu_accelerator": field(
                accel, OBSERVED, "qemu-system-x86_64 argv (-accel)", selection_note,
            ),
            "qemu_machine": field(env("MACHINE_OBSERVED"), OBSERVED, "qemu argv (-machine)"),
            "qemu_smp": field(env("SMP_OBSERVED"), OBSERVED, "qemu argv (-smp)"),
            "monitor_kvm_enabled": field(
                as_bool("KVM_ENABLED"), OBSERVED, "QEMU monitor: info kvm",
            ),
            "monitor_vcpu_threads": field(
                as_int("VCPU_THREADS"), OBSERVED, "QEMU monitor: info cpus",
            ),
        },
        "observed_guest": {
            "uname": field(env("GUEST_UNAME"), OBSERVED, "guest uname -a", guest_reason),
            "nproc": field(env("GUEST_NPROC"), OBSERVED, "guest nproc", guest_reason),
            "installed_packages": field(
                env("GUEST_PACKAGES"), OBSERVED, "guest dpkg-query -W", guest_reason,
            ),
            "dpkg_status_sha256": field(
                env("GUEST_DPKG_SHA"), OBSERVED,
                "guest sha256sum /var/lib/dpkg/status", guest_reason,
            ),
        },
        "image": {
            "guest_path": field(env("IMAGE_PATH"), DECLARED, "compose config"),
            "host_path": field(env("HOST_IMAGE"), DERIVED, "guest path mapped through ./images"),
            "virtual_size": field(env("IMAGE_VIRTUAL_SIZE"), OBSERVED, "qemu-img info"),
            "snapshot_tags": field(env("IMAGE_SNAPSHOTS"), OBSERVED, "qemu-img snapshot -l"),
            "sha256": field(
                env("IMAGE_DIGEST_VALUE"), OBSERVED, "sha256sum",
                env("IMAGE_DIGEST_REASON"),
            ),
        },
        "raw_captures": raw_files(raw_dir),
    }

    json.dump(document, sys.stdout, indent=2, sort_keys=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
