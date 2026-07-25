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

Four defects. The checker skips schema and digest validation for a superseded
capture and still enforces its privacy checks, so re-running it here reports the
skip rather than the four findings below; they were measured before the marker
was added, and `git show` on this file's first commit carries the transcript:

- Four recorded stdout digests per arm describe the unsanitized bytes.
  `host-uname`, `container-inspect`, `compose-config`, and `image-info` are
  exactly the streams that carried the hostname, home path, or repository path,
  and redaction rewrote them after hashing. Every one of them fails its own
  integrity record.
- No probe records a stderr digest, so half of each retained stream is
  uncertified.
- The TCG arm named a session scratchpad override in `capture.json` and in
  `raw/container-inspect.out`. That path disclosed a machine-local location and
  named the only input that produced `FORCE_KVM=0`, which is absent from this
  repository, so the arm cannot be reproduced from the tree. Both occurrences
  now read `<scratch-override>`: the disclosure is removed while the defect it
  records stands. Scrubbing those bytes moves the file further from its recorded
  digest, which already failed for the reason above.
- Both arms were captured from `b5db85a` with `repository.dirty=true`. That
  commit predates the instrument that produced them, and the dirty bit names no
  differences, so no revision reconstructs the source state that generated these
  documents.

A fifth defect was found after the first four. A global `core.excludesFile`
ignoring `*.out` kept every retained stdout out of these commits while the
`.err` counterparts committed normally, so a clone received `capture.json` with
digests for streams it did not have. On this working tree the files were
present, which is why a filesystem listing showed them and `git ls-files` did
not. `.gitignore` now overrides that rule for `evidence/runtime/cases`, and the
36 stdout streams are tracked.

The `/dev/kvm` finding in the TCG arm also overreaches. `test -e/-r/-w` shows the
device node is visible and the mode bits permit an open; it does not show that
`KVM_CREATE_VM` succeeds. `container_kvm_usable` in the current instrument runs a
one-shot QEMU with `-accel kvm` to settle that directly.

## Replacement

ROADMAP 52d carries the recapture: tracked inputs for both arms, a clean
committed revision, both streams retained and hashed after redaction, and the
KVM usability probe in each arm. It runs after the single-service Compose
topology lands, so the pair is cut once against the topology it will describe.
