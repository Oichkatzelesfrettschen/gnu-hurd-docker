# gnu-hurd-docker Agent and Developer Reference

## Instruction Source

This root AGENTS.md is the durable instruction file for gnu-hurd-docker.
`CLAUDE.md` defers to it and carries only Claude-Code entry points and session
habits. Some repositories in this ecosystem symlink `CLAUDE.md` to `AGENTS.md`
instead; this repository keeps two distinct files.

Nested AGENTS.md files may add narrower rules for their subtree. When rules
conflict, the narrower file controls only inside its subtree.

## Hard Rules

- Checked-in text is emoji-free. An emoji carries no information its word does
  not, and it breaks greps, widens diffs, and renders as a box or a double-width
  cell wherever the glyph is missing. Typographic substitutes stay out on the
  same grounds: straight quotes over curly ones, `--` over an em dash, `...` over
  an ellipsis glyph. Symbols that carry meaning stay in -- mathematical
  operators, Greek letters, arrows in state transitions, box-drawing in diagrams,
  the degree and micro signs -- and a name keeps the spelling its owner uses, so
  accented characters in author and copyright lines are preserved verbatim.
- Use `docker compose` (v2). The legacy `docker-compose` v1 entry point stays
  out of scripts, docs, and Makefile targets.
- Treat warnings as defects. Touched shell passes ShellCheck at the enforced
  severity.
- Keep changes surgical. Unrelated files stay unreformatted.
- Keep secrets, local absolute paths, private hostnames, and generated
  machine-only state out of commits.

## Architecture

A QEMU x86-64 virtual machine runs inside a Docker or Podman container. Two
boundaries stack, and conflating them produces wrong conclusions:

- The container boundary holds the Ubuntu host tools, the `qemu-system-x86_64`
  binary, the entrypoint and scripts, port forwarding, and bind mounts.
- The VM boundary holds GNU Mach and the Hurd on emulated PC hardware.

QEMU is always the VM process. KVM is hardware-assisted CPU virtualization that
QEMU may use; TCG is QEMU's software translator. The KVM Compose overlay only
exposes `/dev/kvm`; the entrypoint then selects `-accel kvm` or
`-accel tcg,thread=multi`.

VirtualBox is a separate host-side manual frontend. Its repository automation is
an intentional stub, not an unfinished feature.

The guest is Debian GNU/Hurd `hurd-amd64` from debian-ports, tracking `sid` plus
`unreleased`. `/etc/debian_version` reads `forky/sid`. References to Trixie in
this tree describe LMDE 7 `gigi`'s Debian base, which is the theme source's
suite rather than the guest's.

MATE is the canonical Minty Hurd desktop. The product is Debian GNU/Hurd sid on
GNU Mach under QEMU, with Xorg as the display server, MATE as the default
session, Debian Ports supplying native `hurd-amd64` executables, and LMDE 7
`gigi` supplying architecture-independent Mint themes, icons, cursors, artwork,
backgrounds, and translations. The separately named Minty Emerald MATE theme
derives from those unmodified Mint assets.

The tree installs XFCE and boots `minty-hurd-xfce`, so the installer and the
autostart wrapper are migration targets rather than the product. XFCE stays as
an explicitly selected rescue session while MATE is ported, and XFCE reaching a
desktop satisfies no MATE gate.

An `Architecture: all` metapackage states nothing about `hurd-amd64` native
dependency closure. MATE readiness is settled by `apt-cache policy` and a
simulated install against the live guest, and the difficult boundary is session
integration -- D-Bus authentication, GSettings, polkit, seat substitutes,
logout and shutdown -- rather than Caja or Marco.

The installed kernel is the uniprocessor Mach build: `uname -a` reports
`GNU-Mach 1.8+git20260224-up-amd64` and `nproc` returns 1 while QEMU presents
two vCPUs. Guest parallelism is one processor whatever `QEMU_SMP` sets, so an
experiment arm that varies `QEMU_SMP` measures host-side QEMU behaviour rather
than guest scaling.

## Evidence Discipline

Sources rank in this order, and an earlier tier overrides a later one when they
conflict:

1. Live QEMU state: the process argv and the monitor (`info kvm`, `info cpus`,
   `info status`).
2. Guest state: `uname -a`, `nproc`, `dpkg-query`, `/etc/apt/sources.list`,
   `/boot/grub/grub.cfg`.
3. Repository documentation, compose comments, and Makefile comments.

Availability and selection are different facts. `/dev/kvm` existing, `FORCE_KVM`
being set, and a target named `up-kvm` all sit upstream of the outcome. The
outcome is `-accel kvm` in the QEMU argv or `kvm support: enabled` from the
monitor. `FORCE_KVM=1` bypasses the IDE safety fallback after KVM is found
usable; it does not by itself establish that KVM was selected.

State a falsification criterion before running the probe. When a result deviates
from prediction, the deviation is the finding.

## Source Comments and Durable Prose

Source comments, commit subjects and bodies, PR text, durable docs, and
agent-authored checked-in prose use direct, declarative present tense.

Write the mechanism first. Name the authority that makes the statement true: a
function, a package field, a QEMU option, a register, a spec chapter, or a
measured value. State the consequence plainly. One direct mechanism paragraph
replaces a ceremonial WHY/WHAT/HOW block.

Good shape:

```sh
# A NUL-delimited walk counts the same files a newline-delimited walk did, so a
# mismatch means a path carries an embedded newline and every downstream gate
# would receive a fabricated file set.
```

State what a thing is and does, and let the positive form carry the absence a
negation would spell out. A binary contrast becomes its positive term; a stacked
absence becomes the category its members share. A boundary takes its positive
dual: the restriction it imposes, the named home the content belongs in, or the
mechanism itself. A hard-stop safety or security boundary keeps its prohibition,
where that is the whole content. Emphasis comes from the claim, so typographic
shouting and definition-by-negation both drop out.

The count of distinct load-bearing facts sets a comment's length, and a line
threshold does not. Every sentence carries a distinct cause, consequence, scope,
or falsifier, and a sentence that paraphrases another is removed. A compact table
or diagram that carries a mapping more precisely than prose is content; banner
boxes, ASCII art, and wrappers such as `# -----` are decoration.

New and modified text uses American English spelling (`behavior`, `initialize`).
Existing text keeps its spelling, because churn-only spelling edits create merge
conflicts for no gain.

Task numbers, PR references, phase and wave labels, session dates, reviewer
breadcrumbs, and deictic terms ("currently", "previously", "this driver") stay
out of source comments. History and tradeoffs live in commit messages, PR
descriptions, and design docs.

TODO bodies name the function, register, or spec chapter that grounds the fix,
the constraint that blocks completing it now, and a durable tracking name.

Durable names describe target, mechanism, and evidence or outcome. Branch names,
commit subjects, PR titles, doc filenames, and bundle directories carry those;
phase, wave, mission, sprint, and session labels do not serve as primary names.

## Engineering Posture

- Every implementation decision is a genuine solution. When blocked, rescope and
  trace the root cause through the interacting components rather than working
  around it.
- Scope cuts are named, never silent. A deferred piece gets one line in
  `ROADMAP.md` with its mechanism name and the reason.
- A check that did not run is reported as `not run` with the reason, and is
  never described as passing.
- Claims separate what was observed from what was inferred.

## Gates

`scripts/check-maintained-shell.sh` is the single ShellCheck enforcement
mechanism, and it fails closed on an empty surface. Its callers are `make lint`,
`scripts/validate-config.sh`, `.github/workflows/static-gates.yml`,
`.github/workflows/validate.yml`, `.github/workflows/validate-config.yml`, and
`PKGBUILD build()`.

`scripts/list-maintained-shell.sh` is the only authority on the size of the
maintained shell surface. Documentation and roadmap entries name the enumerator
rather than pinning a count, because pinned counts drift.

`make links` asserts the broken-link count through
`scripts/check-link-scan-result.py`, because `scripts/utils/link-scanner.py`
reports its findings and exits 0 whatever it finds.

Every file a gate reads belongs to that gate's trigger closure. Widening what a
validator loads means widening the workflow path filters in the same change.

`SHELLCHECK_SEVERITY` selects the enforced severity and defaults to `error`.
The warning tier is reported and not enforced while its findings remain open.

## Guest Image Discipline

The Compose profiles bind-mount `./images` read-write with no overlay and no
`-snapshot`, so the guest writes straight through to the qcow2. A qcow2 internal
snapshot is the only rollback.

- Snapshot before any mutation, with the guest powered off:
  `qemu-img snapshot -c <mechanism>-<date> images/<image>.qcow2`.
- Halt the guest (`halt`) and then stop the container. Killing the container
  leaves the filesystem dirty.
- Run an offline `e2fsck` after the guest stops. Preen mode can stop on damage
  that a full non-interactive pass repairs, so a preen failure means run the
  full pass rather than boot anyway.
- A dirty root filesystem makes the guest fsck, request a restart, and never
  reach `sshd`, which reads from outside as a boot hang.

The QEMU monitor's `quit` command terminates QEMU rather than ending the monitor
session. A script that drives the monitor omits it and lets the connection close
on timeout; sending it resets the guest and reads as a spurious guest reboot.

`root` and `user` sit at `chage -d 0`, so key-based SSH authenticates and is then
refused pending a password change. Lifting that for automation is a temporary,
recorded step, and the aging field is restored afterwards.

## Booting the Minty Profile

    docker compose -f compose.yaml -f compose.minty.yaml up -d hurd

Naming the `hurd` service is required. `compose.minty.yaml` declares a service
named `hurd` while `compose.yaml` declares `gnu-hurd-dev`, so the second file
adds a service rather than overriding the first. The bare invocation and
`make minty-up` start both, and the extra container pulls a GHCR image that no
workflow publishes.

## Commits and Pull Requests

Commit subjects use a component prefix and a concise mechanism:
`ci: bind the published release to the commit its archive was cut from`.

The body makes the invariant, the change, and the evidence reviewable in one to
five sentences: name the root cause or constraint, name the fix, cite the
function, option, or package field when load-bearing, and state test movement
plainly. Cover motivation, change, and evidence as content, never as WHY/WHAT/HOW
headers.

Chronology, build invocations, tool output, host names, and validation
checklists live in the PR description. Design debate about rejected alternatives
lives in the commit message or PR, never in source comments.

Each commit is buildable, reviewable, and bisectable. Formatting churn and logic
changes ride separate commits. One logical change per commit, one topic per PR.

Trailers disclose AI participation, and file headers and source comments do not.
`Assisted-by: <tool> (<model>)` covers mixed human and AI work,
`Generated-by: <tool> (<model>)` covers a change AI generated almost entirely,
and `Co-authored-by:` stays reserved for human co-authors. Trivial mechanical
changes may omit disclosure. Existing commits carrying the older trailer are
historical artifacts, and history is not rewritten to change them.

New files carry no copyright or SPDX line, because the existing files in this
repository carry none.

## Reproducibility

The guest tracks `sid` and `unreleased`, neither pinned, so re-running the
provisioning scripts produces a different package set than the one in any
existing image. Reproducing an image requires pinning `snapshot.debian.org` and
recording the archive timestamp beside the image digest.

Mint publishes release codenames rather than a rolling suite, so no LMDE suite
tracks `sid`. LMDE 7 `gigi` advertises `romeo` and `incoming` components whose
amd64 indices are zero bytes, so enabling them adds nothing.
deb-multimedia.org publishes a `sid` suite and builds no `hurd-amd64`.

Release artifacts are cut with `git archive` from a recorded commit, and
`.gitattributes` `export-ignore` is the single exclusion policy.
