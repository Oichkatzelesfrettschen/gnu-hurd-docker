# Runtime evidence capture protocol

`scripts/capture-runtime-evidence.py` records one identified QEMU instance as a
JSON document in which every field states the class of evidence behind it. The
protocol exists because the configuration this repository declares does not
determine what QEMU does: `detect_acceleration()` in `entrypoint.sh` reports
`kvm` whenever `/dev/kvm` is usable, and the `AUTO_DISABLE_KVM_FOR_IDE` branch
then demotes that to `tcg` for the `pc` machine on the `ide` bus unless
`FORCE_KVM=1`. The QEMU command line and the monitor carry the outcome.
Everything else carries a request.

`schemas/runtime-evidence-v2.schema.json` is the schema. `make runtime-info`
captures and prints through `scripts/report-runtime-evidence.py`.

## One instance, or none

Every field binds to a single VM. The container is selected by finding an actual
`qemu-system-x86_64` process rather than by matching a name, because a name
match selects a noVNC sidecar or a stale VM as readily as the instance under
study. Two running QEMU instances are ambiguous, so the capture exits 2 and asks
for `--container` or `--service` rather than picking one.

The Compose service comes from the container's `com.docker.compose.service`
label, and declared configuration is read from that service alone through
`docker compose config --format json`. A first-match scan over a resolved
document containing several services attributes one service's declarations to
another's runtime.

The image is resolved by parsing `file=` out of the QEMU command line and
following the container's own mount table. A named volume has no counterpart
under `./images`, so assuming that every `/opt/hurd-image/...` path maps into the
repository names the wrong file.

The QEMU command line is read from `/proc/<pid>/cmdline`, which is NUL-delimited
and preserves argument boundaries that splitting formatted `ps` output on spaces
loses. The QEMU version is read inside the container, because the container's
QEMU produces the VM and differs from the host's.

## Declared and live are separate classes

A container created from an overlay or an earlier revision no longer matches
current source. The capture records `declared.environment` from the resolved
Compose document and `live_container.environment` from `docker inspect`, and
neither stands in for the other. When they disagree, the disagreement is the
finding.

## Evidence classes

| Class | Read from | Licenses |
| --- | --- | --- |
| `observed` | the live system | a statement about what the system does |
| `derived` | computed from an observed value | a statement about what follows |
| `declared` | configuration | a statement about what the stack requests |
| `not-captured` | nothing; the probe reported why | nothing, and it names what would settle the question |

A `not-captured` field carries a null value and the reason the probe reported.
An empty list is an observation of emptiness rather than an absence, so an image
with no snapshots records `observed: []`.

A failing probe receives the reason it reported. Naming a known blocker instead
assigns a cause the run did not show.

## Probe records are the reproduction unit

Each probe records its `argv`, start and completion times, exit status, both
output streams as files, and the SHA-256 of stdout. A reader re-runs the argv and
compares against the retained stream rather than trusting this parse.

Exit status and usable output are independent. The monitor probe omits `quit`,
because in the QEMU monitor that terminates QEMU rather than closing the session
and the reboot-loop mode then restarts the guest. The session therefore stays
open, `timeout` reaps `nc`, and the probe returns 124 after a complete
transcript. The record retains 124 and the parse reads what the monitor sent.

## The contrast pair

`evidence/runtime/cases/` holds two captures taken minutes apart on one host,
from one source commit, one container image, and one 16 GiB guest image, with
`pc`, PIIX IDE, and `-smp 2` held fixed. `FORCE_KVM` is the only differing input.

| Field | `accelerator-kvm-forced` | `accelerator-tcg-ide-demoted` |
| --- | --- | --- |
| `declared.FORCE_KVM` | `1` | `0` |
| `live_container.FORCE_KVM` | `1` | `0` |
| `host.kvm_device` | exists, readable, writable | exists, readable, writable |
| `observed_runtime.container_kvm_device` | exists, readable, writable | exists, readable, writable |
| `observed_runtime.accelerator` | `kvm` | `tcg,thread=multi` |
| `observed_runtime.monitor_kvm_enabled` | `true` | `false` |
| `image.guest_path` | `hurd-working.qcow2` | `hurd-working.qcow2` |
| `image.virtual_size_bytes` | 17179869184 | 17179869184 |

`/dev/kvm` is usable inside the container in both arms, which removes container
device access and permissions as explanations. The accelerator follows
`FORCE_KVM` while every other input holds, so the pair establishes the
`AUTO_DISABLE_KVM_FOR_IDE` demotion as an observation rather than an inference.

## Layout and naming

    evidence/runtime/<short-commit>-<UTC-timestamp>/   generated, untracked
    evidence/runtime/cases/<mechanism-name>/           deliberate, sanitized, tracked

Generated captures are dated instances, and dated names are correct for them:
durable names forbid chronology, and finding documents carrying dated filenames
are the stated exception. Committed cases carry mechanism names because they are
argued artifacts rather than instances. This protocol document describes a
durable mechanism, so it carries no date.

## Publication safety

`--redact` replaces the repository root, the home directory, and the host name in
the document and in every raw file, and replaces the value of any environment key
whose name matches a credential shape (`PASSWORD`, `TOKEN`, `SECRET`, `AUTH`,
`_KEY`, and similar). Matching on shape rather than on an enumerated list keeps a
newly introduced credential from reaching a published capture merely because
nobody extended a list.

## Cost and opt-in fields

The image digest is opt-in behind `--image-digest`, and the capture refuses to
hash an image whose VM is running: the file is writable and the digest would not
be stable. Stop the VM, or hash an immutable base or an external snapshot.

## What the schema does not carry

The hardware in a capture is what QEMU emulates plus the host CPU it passes
through: a PIIX3 IDE controller, an e1000 NIC, and a standard VGA adapter, with
the uniprocessor Mach build running on one processor whatever `QEMU_SMP`
requests. Physical topology beyond the host CPU model and count is outside what
this capture measures, and a field asserting it would be invented.

Synthetic schema fixtures are not yet present. The committed cases are real
sanitized captures and serve as examples rather than as negative fixtures, so
schema regressions are not yet covered by a test.
