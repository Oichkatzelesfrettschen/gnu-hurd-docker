# The committed accelerator cases are superseded

`accelerator-kvm-forced` and `accelerator-tcg-ide-demoted` are retained as
history. They are not citable evidence, and `scripts/check-runtime-evidence.py`
skips any capture carrying a `SUPERSEDED.md`.

## What the pair still establishes

The QEMU argv, the monitor transcript, and the container inspection in these
directories are real. Read as a description of one afternoon's two runs, the
pair shows that changing the captured `FORCE_KVM` input from `1` to `0` changed
the selected accelerator from `-accel kvm` to `-accel tcg,thread=multi` while the
guest image, machine type, controller, memory, and vCPU count stayed equal. That
is strong evidence consistent with the `AUTO_DISABLE_KVM_FOR_IDE` branch in
`entrypoint.sh`.

It is not an observation of that branch. The entrypoint emits no decision
record, so the reason is reconstructed from the inputs, the source, and the
outcome. ROADMAP 52e carries the instrumentation that would make the reason an
observation.

## Why the pair is not citable

Four defects, each reproducible by running
`scripts/check-runtime-evidence.py --require-redacted` against either directory:

- Four recorded stdout digests per arm describe the unsanitized bytes.
  `host-uname`, `container-inspect`, `compose-config`, and `image-info` are
  exactly the streams that carried the hostname, home path, or repository path,
  and redaction rewrote them after hashing. Every one of them fails its own
  integrity record.
- No probe records a stderr digest, so half of each retained stream is
  uncertified.
- The TCG arm names
  `/tmp/claude-1000/.../scratchpad/compose.noforce.yaml` in `capture.json` and in
  `raw/container-inspect.out`. That path discloses a machine-local location and
  names the only input that produced `FORCE_KVM=0`, which is absent from this
  repository. The arm cannot be reproduced from the tree.
- Both arms were captured from `b5db85a` with `repository.dirty=true`. That
  commit predates the instrument that produced them, and the dirty bit names no
  differences, so no revision reconstructs the source state that generated these
  documents.

The `/dev/kvm` finding in the TCG arm also overreaches. `test -e/-r/-w` shows the
device node is visible and the mode bits permit an open; it does not show that
`KVM_CREATE_VM` succeeds. `container_kvm_usable` in the current instrument runs a
one-shot QEMU with `-accel kvm` to settle that directly.

## Replacement

ROADMAP 52d carries the recapture: tracked inputs for both arms, a clean
committed revision, both streams retained and hashed after redaction, and the
KVM usability probe in each arm. It runs after the single-service Compose
topology lands, so the pair is cut once against the topology it will describe.
