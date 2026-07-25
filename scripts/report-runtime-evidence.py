#!/usr/bin/env python3
"""Print a runtime evidence capture as a human summary.

The summary leads with the accelerator QEMU selected, because a target named
up-kvm, a present /dev/kvm, and a set FORCE_KVM each state a request while the
argv states the outcome.  Fields print with their evidence class so a reader
sees at a glance which lines settle a question and which only record intent.
"""

import json
import sys

ORDER = [
    ("Instance", "instance",
     ["container", "compose_service", "compose_project", "container_image_id",
      "qemu_pid"]),
    ("Repository", "repository", ["commit", "dirty", "maintained_shell_surface"]),
    ("Host", "host", ["cpu_model", "cpu_count", "kvm_device",
                      "container_runtime_version"]),
    ("Declared (selected service)", "declared", ["environment"]),
    ("Live container", "live_container", ["environment", "published_ssh_port"]),
    ("Observed runtime", "observed_runtime",
     ["qemu_version", "accelerator", "machine", "smp", "container_kvm_device",
      "monitor_kvm_enabled", "monitor_vcpu_threads"]),
    ("Observed guest", "observed_guest",
     ["uname", "nproc", "installed_packages", "dpkg_status_sha256"]),
    ("Image", "image",
     ["guest_path", "host_path", "virtual_size_bytes", "format", "snapshot_tags",
      "sha256"]),
]

# Environment maps carry many keys; the summary shows the ones that steer the
# accelerator decision and defers the rest to the document.
ENV_KEYS = ("FORCE_KVM", "AUTO_DISABLE_KVM_FOR_IDE", "QEMU_MACHINE",
            "QEMU_DISK_BUS", "QEMU_SMP", "QEMU_DRIVE")


def render(value):
    if isinstance(value, dict) and any(k in value for k in ENV_KEYS):
        return " ".join("%s=%s" % (k, value[k]) for k in ENV_KEYS if k in value)
    if isinstance(value, dict):
        return " ".join("%s=%s" % (k, v) for k, v in sorted(value.items()))
    if isinstance(value, list):
        return "[]" if not value else " ".join(str(v) for v in value)
    return str(value)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: report-runtime-evidence.py <capture.json>\n")
        return 2
    with open(argv[1], encoding="utf-8") as handle:
        document = json.load(handle)

    print("Runtime evidence  schema %s  captured %s"
          % (document.get("schema_version"), document.get("captured_at_utc")))
    print()

    notes = []
    for title, section, keys in ORDER:
        print(title)
        for key in keys:
            entry = document.get(section, {}).get(key)
            if entry is None:
                continue
            value = entry["value"]
            shown = "--" if value is None else render(value)
            print("  %-26s %-13s %s" % (key, entry["class"], shown))
            reason = entry.get("reason")
            if reason and value is not None:
                notes.append("%s: %s" % (key, reason))
            elif reason and value is None:
                notes.append("%s unavailable: %s" % (key, reason))
        print()

    if notes:
        print("Notes")
        for note in notes:
            print("  - %s" % note)
        print()

    raw_count = len(document.get("raw_captures", {}))
    print("%d raw captures retained beside this document." % raw_count)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
