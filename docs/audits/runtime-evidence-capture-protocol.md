# Runtime evidence capture protocol

`scripts/capture-runtime-evidence.sh` records the running system as a JSON
document in which every field carries the class of evidence behind it. The
protocol exists because the configuration this repository declares does not
determine what QEMU does: `detect_acceleration()` in `entrypoint.sh` reports
`kvm` whenever `/dev/kvm` is usable, and the `AUTO_DISABLE_KVM_FOR_IDE` branch
then demotes that to `tcg` for the `pc` machine on the `ide` bus unless
`FORCE_KVM=1`. The QEMU argv and the monitor carry the outcome. Everything else
carries a request.

A capture separates the two, so a reader distinguishes a claim the data settles
from a claim it only motivates.

## Evidence classes

Each field is an object with `value`, `class`, and `source`, plus a `reason`
when one applies.

| Class | Read from | Licenses |
| --- | --- | --- |
| `observed` | the live QEMU process, its monitor, or the guest | a statement about what the system does |
| `derived` | computed from an observed value | a statement about what follows arithmetically |
| `declared` | repository configuration | a statement about what the stack requests |
| `not-captured` | nothing; the probe recorded its absence and why | nothing, and it names what would settle the question |

An unavailable probe records `not-captured` with a reason rather than dropping
the field, because a schema that omits what it could not measure reads as though
it measured everything.

## The four properties that make a capture citable

Provenance accompanies every field. The document records the commit, the dirty
flag, the capture timestamp, and for each field the command that produced it.

Evidence class accompanies every field, as the table above defines.

The reproduction command travels with the data. Each document carries
`"reproduce": "scripts/capture-runtime-evidence.sh"`, so a reader regenerates a
comparable capture without reconstructing the invocation.

Raw output is retained beside the parsed document. The capture directory holds a
`raw/` subdirectory with the QEMU argv, the monitor transcript, the resolved
compose configuration, the guest probe, and the image metadata as the commands
emitted them. A later reader re-parses those rather than trusting this parse,
and `raw_captures` in the JSON lists each file with its byte size.

## Layout and naming

    evidence/runtime/<short-commit>-<UTC-timestamp>/
        capture.json
        raw/

Captures are dated instances, and dated names are correct for them: `AGENTS.md`
forbids chronology in durable names, and finding documents carrying dated
filenames are the stated exception. This protocol document describes a durable
mechanism, so it carries no date. A future pass that renames one into the other
inverts the rule.

Generated captures stay out of version control through `.gitignore`, with one
exemplar committed so the schema is reviewable in-tree.

## What a capture answers

`evidence/runtime/639a047-20260725T101658Z/capture.json` is the committed
exemplar, and it records the case the protocol was built for:

| Field | Class | Value |
| --- | --- | --- |
| `host.kvm_device_present` | observed | `true` |
| `declared.force_kvm` | declared | `0` |
| `declared.auto_disable_kvm_for_ide` | declared | `1` |
| `observed_runtime.qemu_accelerator` | observed | `tcg,thread=multi` |
| `observed_runtime.monitor_kvm_enabled` | observed | `false` |

KVM is present on the host and QEMU runs TCG. The capture attaches the reason to
the accelerator field rather than leaving a reader to reconstruct it. Reading
`/dev/kvm`, the compose overlay name, or the Make target would have supported
the opposite conclusion.

`make runtime-info` runs the capture and prints it through
`scripts/report-runtime-evidence.py`, which leads with the selected accelerator.

## Guest fields and the OOBE gate

`root` and `user` sit at `chage -d 0`, so key-based SSH authenticates and is then
refused pending a password change. The guest probe records that refusal as its
`not-captured` reason rather than reporting an empty guest. Lifting the aging
field for an unattended capture is a temporary, recorded step, and the field is
restored afterwards.

## Cost and opt-in fields

The image digest is opt-in behind `--image-digest`, because hashing a 16 GiB
qcow2 takes minutes. Without the flag the field records `not-captured` and names
the flag as the way to obtain it. `qemu-img info` and the snapshot list are cheap
and are always captured.

## What the schema does not carry

The hardware facts in a capture are the emulated ones QEMU presents and the host
CPU it passes through. The guest sees a PIIX3 IDE controller, an e1000 NIC, and
a standard VGA adapter, and it runs the uniprocessor Mach build on one processor
whatever `QEMU_SMP` requests. Physical topology beyond the host CPU model and
count is outside what this capture measures, and a field asserting it would be
invented rather than observed.
