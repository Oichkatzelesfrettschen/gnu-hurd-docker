# Accelerator decision records

The accelerator that ran was previously reconstructed from entrypoint log prose
and a QEMU argv, and reconstruction cannot separate a candidate that was never
available from one that was found and then demoted. Those two produce the same
`-accel tcg,thread=multi`. The selecting code now writes what it decided, with
the inputs that decided it, to `/run/hurd/accelerator-decision.json` before it
execs QEMU, and `make minty-accel` reads it back from a running container.

These four records are that mechanism observed on one host, one arm per input
combination. QEMU pointed at a throwaway 64 MB qcow2 rather than the Minty
guest, so no guest filesystem was mounted and none was mutated. That bounds what
they establish: the decision path, not any guest behavior.

| record | inputs | candidate | selected | reason |
|---|---|---|---|---|
| `no-kvm-device.json` | no `/dev/kvm` in the container | tcg | tcg | `host_detection` |
| `kvm-device-ide-demoted.json` | `/dev/kvm`, machine `pc`, bus `ide` | kvm | tcg | `ide_safety_demotion` |
| `kvm-device-forced.json` | the same plus `FORCE_KVM=1` | kvm | kvm | `forced_kvm` |
| `kvm-device-disabled.json` | the same plus `DISABLE_KVM=1` | tcg | tcg | `disable_kvm_requested` |

The second row is the one that matters for scheduling work. KVM is available and
the entrypoint declines it, because KVM with PIIX IDE on `pc` has produced
bus-master DMA faults and ext2fs I/O errors on this guest. A package build is a
sustained-write workload, which is the same load that provokes that fault, so
the builder runs TCG until a build completes under `FORCE_KVM=1` with a clean
offline `e2fsck`. Roadmap item 69 carries that qualification.

The host that produced these records exposes `/dev/kvm`. On a host without it,
rows two through four collapse into row one, and `container_kvm_exists` in the
record is what distinguishes the two situations.

These are not runtime evidence captures under `evidence/runtime/`: they carry no
QEMU argv, no monitor output, and no guest facts, and they are not bound to an
identified QEMU instance. Roadmap item 68 covers promoting the decision record
into that contract so a matched TCG and KVM boot pair closes the recapture items.
