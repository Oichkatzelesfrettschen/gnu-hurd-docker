# Repository debt inventory: dependency graph, gate coverage, and boot evidence

Date: 2026-07-24
Method: static extraction over the shell/Make/CI/Compose dependency graph, execution of
the repository's own gates, and a two-arm instrumented QEMU boot capture against qcow2
overlays.
Repository state: branch `main` at `807aec5`, working tree clean.

This audit reports measured integers and reproduce commands. Every claim below carries the
command that produces it. Claims that require a booted guest are marked as such and are
backed by the capture in the boot evidence section; claims that no capture reached are
marked `unverified`.

## Load-bearing findings

Five findings change what a maintainer does next. The rest of this document is inventory.

### 1. The canonical dev image cannot boot unattended

`images/debian-hurd-amd64.qcow2` carries a dirty guest root filesystem. GNU Mach boots,
`ext2fs` refuses the root device, automatic `fsck` fails, and the guest stops at a
maintenance-shell password prompt. No amount of Compose or entrypoint configuration reaches
SSH from this image, because the guest never leaves single-user recovery.

Guest console text, captured on both accelerator arms, which differ only in the kernel
timestamp column:

```
ext2fs: part:5:device:wd0: warning: FILESYSTEM NOT UNMOUNTED CLEANLY; PLEASE fsck
Checking root file system.../dev/wd0s5 was not cleanly unmounted, check forced.
/dev/wd0s5: Missing '.' in directory inode 146835.
/dev/wd0s5: UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY.
fsck exited with status code 4
A maintenance shell will now be started.
Enter root password for system maintenance
```

This is the root cause standing upstream of ROADMAP items 33 and 34. Both items describe
symptoms observed on a guest that, on this image, never reaches multi-user state.

### 2. Container-level image checks pass while the guest is unbootable

`qemu-img check images/debian-hurd-amd64.qcow2` reports `No errors were found on the image`
against the same file that halts in a maintenance shell. The qcow2 container is intact; the
ext2 filesystem inside it is not. Every image gate in the repository inspects the container
layer, so the gates report healthy and the guest still fails.

The missing gate is a guest-filesystem check. `guestfish`-based tooling already exists in
the repository (`scripts/guestfish-set-grub-root-device.sh`,
`scripts/guestfish-bootstrap-hurd-console.sh`), so the mechanism to run `e2fsck -fn` against
`wd0s5` offline is present and unused.

### 3. The release pipeline fails on every version tag

`.github/workflows/release-artifacts.yml` copies `scripts/*.sh` into a staging directory,
then gates on a hardcoded required-script list:

```yaml
REQUIRED_SCRIPTS="entrypoint.sh docker-orchestration.sh validate-config.sh setup-hurd-amd64.sh"
for script in $REQUIRED_SCRIPTS; do
  if [ ! -f "release-artifacts/scripts/$script" ]; then
    echo "ERROR: Required script missing: $script"
    exit 1
  fi
done
```

`scripts/docker-orchestration.sh` was deleted in commit `2b66c90` when the control plane
migrated to Compose. The copy step can never supply it, so the gate always fires `exit 1`.
The workflow triggers on `push: tags: ['v*']`, so this fails on every attempted release and
on no ordinary push.

Two further references publish stale instructions rather than failing:
`.github/workflows/push-ghcr.yml:165` and `.github/workflows/release-qemu-image.yml:113`
both echo `./scripts/docker-orchestration.sh up` into user-facing release notes and step
summaries.

### 4. The documentation site fails to build

`mkdocs.yml` declares 26 explicit `nav:` entries. All 26 name files that do not exist. The
nav still describes the flat pre-consolidation layout (`ARCHITECTURE.md`, `USER-SETUP.md`,
`mach-variants/INDEX.md` at the docs root) that
`docs/CONSOLIDATION-FINAL-REPORT.md` records as having been reorganized into the numbered
`01-08` hierarchy. Meanwhile 260-plus real documents are absent from the nav entirely.

`.github/workflows/deploy-pages.yml:61` runs `mkdocs build --clean --strict --verbose`.
Under `--strict` these are errors, not warnings.

Reproduce, with the plugin block stripped so the missing
`git-revision-date-localized` plugin does not mask the nav result:

```sh
mkdocs build -f ./mkdocs-navtest.yml --strict --site-dir /tmp/site; echo $?
```

Result: exit 1. The Pages deployment fails on every push touching `docs/**` or
`mkdocs.yml`, which are exactly the paths its trigger watches.

### 5. The shellcheck gate inspects 28 percent of the shell surface

`scripts/validate-config.sh` enumerates its shellcheck targets one literal path per line
(29 invocations of `shellcheck -S error <path>`) against 102 live shell scripts. New scripts
are not covered until someone remembers to add a line. Entire tiers are unenumerated: all
seven `scripts/test-phases/*.sh` and five of the seven `scripts/lib/*.sh`.

The severity threshold compounds the gap. `validate-config.sh` and
`.github/workflows/validate-config.yml` both use `-S error`, which suppresses every finding
this audit measured, because the repository has zero shellcheck errors and 93 findings at
`warning` and `note`. `.github/workflows/quality-and-security.yml:60` independently uses
`-S warning` over a glob, so two gates disagree on both scope and threshold.

## Measured baseline

Commands and their results as of this audit.

| Metric | Value | Reproduce |
| --- | --- | --- |
| Tracked files | 445 | `git ls-files \| wc -l` |
| Markdown / shell / YAML / Python | 271 / 109 / 25 / 4 | `git ls-files \| sed 's/.*\.//' \| sort \| uniq -c` |
| C or header files | 0 | `git ls-files '*.c' '*.h' \| wc -l` |
| Live shell scripts (excluding archive) | 102 | `find scripts entrypoint.sh -name '*.sh' \| grep -v /archive/ \| wc -l` |
| shellcheck errors | 0 | `shellcheck -f gcc $(...)` |
| shellcheck warnings / notes | 15 / 78 | as above, grouped by severity |
| yamllint errors / warnings | 1 / 1 | `yamllint -c .yamllint -f parsable compose*.yaml .github/ config/` |
| Compose files parsing clean | 8 of 8 | `docker compose -f <file> config -q` |
| `validate-config.sh` | rc=0 | `bash scripts/validate-config.sh` |
| `smoke-host.sh` | rc=0 | `bash scripts/smoke-host.sh` |
| Tracked binaries (qcow2/iso/pyc) | 0 | `git ls-files \| grep -E '\.(qcow2\|iso\|pyc)$'` |
| Orphan scripts (zero inbound edges) | 36 of 102 | dependency graph, below |
| Duplicate Makefile targets | 5 | `grep -oP '^[a-zA-Z][\w-]*(?=:)' Makefile \| sort \| uniq -d` |
| Live `docker-compose` v1 invocations | 0 | see the compose-v2 note below |

The zero-error shellcheck result and both green gates are real. Repository hygiene at the
level the gates measure is good; the debt is in what the gates decline to measure.

## Dependency graph

The repository contains no C sources, so `cflow` and `cscope` have nothing to parse. The
dependency graph that does exist has five edge types, extracted over `scripts/**`,
`entrypoint.sh`, `Makefile`, `.github/workflows/*.yml`, and `compose*.yaml`:

| Edge type | Rule | Count |
| --- | --- | --- |
| `source` | `^\s*(\.\|source)\s+` inside a `.sh` | 38 |
| `exec` | script path invoked by another script | 70 |
| `make` | Makefile recipe naming a script or compose file | 32 |
| `ci` | workflow `run:` naming a script or make target | 40 |
| `compose` | compose file naming a script or entrypoint | 2 |

Structural observations:

- `scripts/lib/colors.sh` and `scripts/lib/container-runtime.sh` are the graph hubs. Every
  other `lib/` member has at most two inbound edges.
- `scripts/validate-config.sh` has 30 outbound `exec` edges, all of them shellcheck target
  enumerations. It is the widest node in the graph and the narrowest gate, which is finding 4.
- `scripts/test-hurd-system.sh` sources all seven `test-phases/*.sh`, which each source
  `test-phases/common.sh`. This tier is reachable only from `test-hurd-system.sh`, which is
  itself an orphan: no Makefile target, CI job, or script invokes it. The integration test
  suite is unreachable from any entry point.

### Dangling edges

Edges whose callee does not exist on disk:

| Caller | Missing callee | Consequence |
| --- | --- | --- |
| `.github/workflows/release-artifacts.yml` | `scripts/docker-orchestration.sh` | hard `exit 1`, finding 3 |
| `.github/workflows/push-ghcr.yml:165` | `scripts/docker-orchestration.sh` | stale step-summary text |
| `.github/workflows/release-qemu-image.yml:113` | `scripts/docker-orchestration.sh` | stale release-note text |
| `scripts/SCRIPT-HEADER-TEMPLATE.sh` | `./script-name.sh` | template placeholder, benign |

### Orphans

36 of the 102 live shell scripts have zero inbound edges from any script, Makefile target, workflow, or
compose file. This is 35 percent of the live shell surface with no automated caller. (The raw graph orphan list holds 41 entries; three are `scripts/archive/*.sh` and two are `scripts/utils/*.py`, which fall outside the 102-script live-shell denominator used throughout this document.) The set
divides into three kinds, and the distinction determines the disposition:

- **Operator tools, intentionally hand-run**: `manage-snapshots.sh`,
  `manage-image-backup-cache.sh`, `connect-console.sh`, `qemu-cli-control.sh`,
  `guestfish-*.sh`, `check-ssh-banner.sh`. These are reachable by a human reading
  `scripts/README.md`; orphan status is correct and should be recorded, not fixed.
- **Unreachable test and audit tiers**: `test-hurd-system.sh`, `test-docker.sh`,
  `test-run-hurd-qemu.sh`, `TEST-TRAP-HANDLERS.sh`, `smoke-console.sh`,
  `analyze-script-complexity.sh`, `generate-complexity-report.sh`, `audit-documentation.sh`.
  These exist to be run automatically and are not. This is test debt with a concrete fix.
- **Guest-side installers invoked inside the VM**: `install-*-hurd.sh`,
  `bootstrap-workstation-hurd.sh`, `minty-hurd-install.sh`. Their caller is the guest, not
  the host graph, so host-side edge extraction cannot see it. Orphan status is a false
  positive here and the inventory should mark them as guest-scoped.

`scripts/INVENTORY.md` and `scripts/inventory.tsv` already exist and should absorb this
three-way classification rather than being superseded by it.

### Duplicated script paths

Five scripts exist at two paths each:

```
scripts/qemu-auto-verify.sh              scripts/automation/qemu/qemu-auto-verify.sh
scripts/qemu-install-serial-fsm.sh       scripts/automation/qemu/qemu-install-serial-fsm.sh
scripts/qemu-matrix-runner.sh            scripts/automation/qemu/qemu-matrix-runner.sh
scripts/qemu-stall-probe.sh              scripts/automation/qemu/qemu-stall-probe.sh
scripts/rebuild-hurd-unattended-iso.sh   scripts/automation/qemu/rebuild-hurd-unattended-iso.sh
```

Three more are duplicated between `scripts/` and `share/`: `install-essentials-hurd.sh`,
`install-nodejs-hurd.sh`, `install-claude-code-hurd.sh`. The `share/` copies are mounted into
the guest at `/share`, so that pair may be intentional delivery rather than duplication;
the `scripts/automation/qemu/` pair is not, because `validate-config.sh` shellchecks both
copies as if they were distinct programs.

Disposition requires a diff per pair: identical content means delete one and add a symlink
or a single canonical path; divergent content means a fork that has to be merged before
either copy is trusted.

## Compose topology

Eight compose files, all parsing clean under `docker compose config -q`. The base service is
`gnu-hurd-dev`; overlays compose onto it by name.

| File | Service | Role |
| --- | --- | --- |
| `compose.yaml` | `gnu-hurd-dev` | base, GHCR image, TCG-safe |
| `compose.override.yaml` | `gnu-hurd-dev` | auto-loaded, local build, binds one qcow2 |
| `compose.kvm.yaml` | `gnu-hurd-dev` | KVM device passthrough |
| `compose.vnc.yaml` | `gnu-hurd-dev`, `novnc`, `vnc-recorder` | VNC overlay plus two sidecars |
| `compose.bind.yaml` | `gnu-hurd-dev` | binds `./images` instead of the named volume |
| `compose.podman.yaml` | `gnu-hurd-dev` | shifted host ports, avoids Docker collision |
| `compose.libvirt.yaml` | `hurd-manager` | standalone stack, not an overlay |
| `compose.minty.yaml` | `hurd` | standalone stack, not an overlay |

Structural note: `compose.libvirt.yaml` and `compose.minty.yaml` declare service names that
do not exist in the base (`hurd-manager`, `hurd`). Composing either onto `compose.yaml`
yields two unrelated services rather than a configured one. They are alternative stacks
wearing overlay-shaped filenames, and the naming invites `-f compose.yaml -f compose.minty.yaml`,
which silently starts both. Renaming them to `stack.libvirt.yaml` and `stack.minty.yaml`
would encode the distinction the filenames currently hide.

Defects:

- `compose.yaml` declares duplicate `security_opt` entries. Self-merging the file
  (`-f compose.yaml -f compose.yaml`) errors with
  `services.gnu-hurd-dev.security_opt items at 0 and 1 are equal`. Single-file parse is
  unaffected, so this is latent rather than active, but it makes the file non-idempotent
  under merge.
- `compose.libvirt.yaml` retains an obsolete top-level `version:` key. Compose v2 warns and
  ignores it. `CONTRIBUTING.md:173` already states the rule this file breaks.
- `compose.minty.yaml` sets `QEMU_DISK_CACHE`, which `entrypoint.sh` never reads. The value
  has no effect.

The compose-v2 policy holds in live files. Across all non-archive sources there are 102
occurrences of the hyphenated string `docker-compose`, and zero of them are v1 command
invocations: they are filenames (`docker-compose.yml`), prose, or `podman-compose`. ROADMAP
item 17 reads "`docker compose` vs `docker compose` vs `podman-compose`", where one term was
meant to be the v1 spelling; the item text needs the correction, and the underlying work is
already done for command invocations.

## Deferred-work census

Markers across all tracked files excluding `ARCHIVE/`, `docs/archive/`, `scripts/archive/`,
and binaries.

| Class | Count | Note |
| --- | --- | --- |
| `- [ ]` unchecked checklist items | 287 | dominated by templates and per-run checklists |
| `workaround` | 61 | highest-signal class, see below |
| `experimental` | 54 | mostly accurate SMP and VirtIO caveats |
| `deprecated` | 52 | mostly i386 retirement notes, correct |
| `broken` | 44 | mixed: real defects and prose about fixed defects |
| `known issue` / `known limitation` | 27 | concentrated in `known-issues-research.md` |
| `not yet` / `in progress` | 21 | status text, several stale |
| `TODO` / `FIXME` / `XXX` / `HACK` | 8 | six are the CI scanner's own pattern strings |
| `STUB` | 4 | all in `scripts/automation/stubs/vbox-conceptual-stub.sh`, honest |

The `TODO` count deserves emphasis: only two are real markers, and the other six are the
literal grep patterns inside `.github/workflows/quality-and-security.yml:486`. This
repository does not carry TODO debt in the ordinary sense. Its deferred work is expressed as
prose in documentation, which is why the marker scan understates it and the dead-reference
scan overstates it.

The `workaround` class is the one worth mining. These are real, root-caused, and mostly
documented against upstream bugs in `upstream-bug-reports/`, which contains four
well-formed reports (OpenSSL SIMD sshd crash, dbus default config, pflocal `SO_PEERCRED`,
dropbear password auth). That directory is the strongest engineering artifact in the
repository and is referenced from almost nowhere.

### Shell robustness

Eleven scripts lack `set -e` or `set -eu` in their first 20 lines:

```
scripts/SCRIPT-HEADER-TEMPLATE.sh   scripts/hurd-desktop-autostart.sh
scripts/install-hurd-dbus-fix.sh    scripts/lib/colors.sh
scripts/lib/package-helpers.sh      scripts/lib/package-lists.sh
scripts/lib/ssh-helpers.sh          scripts/minty-hurd-install.sh
scripts/oobe-first-login.sh         scripts/run-hurd-qemu.sh
share/run-all-installations.sh
```

Five of these are `scripts/lib/*.sh`. Sourced libraries should not set shell options for
their caller, so their absence is correct and should be recorded as intentional rather than
fixed. The remaining six are executable entry points where the omission is real:
`run-hurd-qemu.sh` in particular is a documented user-facing launcher referenced by
`.github/workflows/release-artifacts.yml`.

## Documentation truth

Dead references verified against the filesystem, split by whether the containing document is
live or archived. The split matters: an archived document describing a deleted script is a
correct historical record, while a live document doing so is a false instruction.

| Class | Total | In live docs | In archive |
| --- | --- | --- | --- |
| A: referenced script does not exist | 73 | 12 | 61 |
| B: `make <target>` absent from Makefile | 14 | 14 | 0 |
| C: referenced compose file missing | 0 | 0 | 0 |
| D: env var documented but never read | 70 | 41 | 29 |
| E: internal link does not resolve | 18 | 4 | 14 |
| F: hyphenated `docker-compose` mention | 88 | 61 | 27 |

The live-document subsets are the actionable ones:

- **Class B, all 14 live.** `docs/09-TESTING-ROADMAP.md:472-491` documents twelve make
  targets (`make docker-up`, `make podman-up`, `make libvirt-define`, and siblings) that the
  Makefile does not define. `docs/reports/AUDIT-2026-05-12.md:172` names `make vnc-up` and
  `make latest-image`; the real targets are `up-vnc` and `setup-latest`. A reader following
  this document types commands that do not exist.
- **Class D, 41 live.** The largest cluster is `QEMU_STORAGE`, `QEMU_EXTRA_ARGS`, `QEMU_CPU`,
  `QEMU_VIDEO`, and `QEMU_ACCEL`, documented across `docs/06-TROUBLESHOOTING/`,
  `docs/03-CONFIGURATION/`, and `docs/07-RESEARCH-AND-LESSONS/`. `entrypoint.sh` reads none
  of them; it uses `QEMU_DISK_BUS`, `QEMU_VGA_DEVICE`, `DISABLE_KVM`, and `QEMU_MACHINE`.
  Troubleshooting guides therefore instruct users to set variables that do nothing, which is
  worse than silence because the user concludes the fix was tried and failed.
- **Class A, 12 live.** Beyond `docker-orchestration.sh`, live docs reference
  `scripts/wait-for-boot.sh`, `scripts/benchmark.sh`, and `scripts/install-gui-lxde.sh`.

The reciprocal check also matters and is clean: `entrypoint.sh` reads no externally-supplied
variable that lacks either a `:-` default or a `compose.yaml` assignment. The runtime is
robust against missing configuration; the documentation is the drifted surface.

## Boot evidence

Two-arm instrumented capture, KVM and TCG, same image, same disk bus, same machine type.
Base image untouched: each arm writes to a fresh qcow2 overlay whose backing file is the
canonical image, verified by `stat` before and after.

The capture ran twice. The first pass started both arms concurrently, which co-schedules a
CPU-bound TCG guest against a KVM guest and inflates the TCG figure by an unknown amount.
The second pass ran each arm alone. The numbers below are from the uncontended serial pass;
the concurrent pass is reported alongside it because the small gap between them bounds the
contention effect.

Reproduce:

```sh
SCRATCH=$(mktemp -d)
qemu-img create -f qcow2 -F qcow2 \
  -b "$PWD/images/debian-hurd-amd64.qcow2" "$SCRATCH/arm.qcow2"
qemu-system-x86_64 -machine pc -accel kvm -m 2048 -smp 2 \
  -drive file="$SCRATCH/arm.qcow2",format=qcow2,if=ide,cache=writeback,rerror=report,werror=report \
  -netdev user,id=n0 -device rtl8139,netdev=n0 \
  -monitor unix:/tmp/hm.mon,server,nowait -display none -no-reboot &
sleep 60
printf 'info status\nscreendump /tmp/arm.ppm\n' | socat - UNIX-CONNECT:/tmp/hm.mon
```

Results:

| Observation | KVM arm | TCG arm |
| --- | --- | --- |
| `info status` | `VM status: running` | `VM status: running` |
| QEMU stderr | empty | empty |
| Guest timestamp at `fsck` failure, serial pass | 8.26 s | 37.23 s |
| Guest timestamp at `fsck` failure, concurrent pass | 8.05 s | 37.95 s |
| Console content | maintenance shell prompt | same text, differing only in the kernel timestamp column |
| Overlay bytes written | 393216 | 393216 |
| Base image mtime and size | unchanged | unchanged |

Three conclusions follow, and one non-conclusion.

**The failure is accelerator-independent.** The two arms produce the same console text,
differing only in the kernel timestamp column, which rules out the accelerator as the cause.
The dirty filesystem is a property of the image.

**KVM delivers a measured 4.5x speedup to the same failure point.** 37.23 s / 8.26 s = 4.51,
measured uncontended as guest-reported time to an identical boot milestone. The concurrent
pass gave 4.71, so contention accounted for roughly four percent and the serial figure is the
one to cite. This is a same-endpoint comparison and the first quantitative KVM-versus-TCG
datum in the repository. `docs/07-RESEARCH-AND-LESSONS/LESSONS-LEARNED.md` and `README.md`
cite a 30-60 s boot expectation without a measurement behind it.

**Serial capture is inert on this image.** `-serial file:` produced zero bytes across a
180-second run on both arms while the VGA console carried the full boot log. The guest
console is not directed to a serial port. This is why `smoke-console.sh` uses screendumps and
why `guestfish-bootstrap-hurd-console.sh` exists, and it means any automation that waits on
serial output against this image waits forever.

**Not concluded: ROADMAP item 33.** The KVM plus IDE DMA error is neither reproduced nor
refuted by this capture. Neither arm emitted a DMA error, and `rerror=report,werror=report`
was set so one would have surfaced. But the guest halts in `fsck` before mounting the root
filesystem read-write, so it never reaches the sustained write workload under which the
reported errors occur. The correct reading is that this capture does not exercise the
condition. Item 33 stays open, and testing it requires a clean image first, which makes
finding 1 a blocking prerequisite.

Nothing in this section speaks to guest SSH, package state, or translator behavior. No
capture reached multi-user state, so every runtime claim in that territory remains
`unverified`.

## Remediation roadmap

Ordered by dependency. Each item carries a reproduce command and an acceptance check.

### Restore a bootable canonical image

Blocking prerequisite for all runtime verification.

1. **Repair the guest filesystem offline.**
   Do: `guestfish -a images/debian-hurd-amd64.qcow2 -i` then `e2fsck -fy /dev/sda5`, or
   `virt-rescue -a images/debian-hurd-amd64.qcow2`. Work on a copy first.
   Accept: a fresh overlay boot reaches a login prompt rather than a maintenance shell,
   confirmed by screendump.
2. **Add a guest-filesystem gate.**
   Do: extend `scripts/validate-config.sh` with an offline `e2fsck -fn` against the image
   root partition, gated on `guestfish` being installed and skipped with a recorded message
   when absent.
   Accept: the gate fails against the current dirty image and passes after item 1.
   Rationale: `qemu-img check` passes on an unbootable image, so container-level checking is
   not sufficient evidence of a usable image.
3. **Record image provenance.**
   Do: record SHA256 and upstream URL for each file in `images/` in a tracked manifest;
   `images/` holds seven qcow2 files and two symlinks with no recorded origin.
   Accept: every image in `images/` resolves to a documented source or is marked local-build.
4. **Re-test ROADMAP item 33 against the repaired image.**
   Do: rerun the two-arm capture, driving past `fsck` to multi-user, with
   `rerror=report,werror=report` retained.
   Accept: DMA errors either reproduce with a captured console log or the item closes as
   not-reproducible against a named image build.

### Repair the release pipeline

5. **Remove `docker-orchestration.sh` from the required-script gate.**
   Do: edit `.github/workflows/release-artifacts.yml:64` to drop the deleted script.
   Accept: `act` or a throwaway `v0.0.0-test` tag completes the packaging job.
6. **Replace the stale orchestration instructions.**
   Do: rewrite `push-ghcr.yml:165` and `release-qemu-image.yml:113` to use `make up`.
   Accept: `git grep -n docker-orchestration -- .github/` returns nothing.
7. **Derive the required-script list instead of hardcoding it.**
   Do: gate on the scripts the Makefile and compose files actually reference, extracted at
   job time.
   Accept: deleting any referenced script fails CI at the reference, not at a stale literal.

### Close the gate coverage gap

8. **Glob the shellcheck targets.**
   Do: replace the 29 enumerated `shellcheck -S error <path>` lines in
   `scripts/validate-config.sh` with a `find`-driven loop over all live scripts.
   Accept: adding a new script under `scripts/` is covered without editing the gate.
9. **Reconcile the two severity thresholds.**
   Do: choose one threshold across `validate-config.sh`, `validate-config.yml`, and
   `quality-and-security.yml`. The 15 warnings are tractable; `-S warning` is reachable now,
   and the 78 notes are dominated by `SC1091` (28, sourced-file resolution) which
   `-x` or an exclusion resolves rather than a code change.
   Accept: all three gates report the same finding count on the same tree.
10. **Fix the yamllint error.**
    Do: `.github/workflows/release.yml:83` contains a literal tab. Replace with spaces.
    Accept: `yamllint -c .yamllint .github/` reports zero errors.
11. **Deduplicate the Makefile targets.**
    Do: `up-podman`, `up-podman-kvm`, `up-podman-vnc`, `up-podman-latest`, and
    `up-podman-installer` are each defined twice, at adjacent line pairs 186/187, 190/191,
    194/195, 198/199, 202/203. Make silently takes the last.
    Accept: `grep -oP '^[a-zA-Z][\w-]*(?=:)' Makefile | sort | uniq -d` is empty.

### Reconcile the script inventory

12. **Classify the 41 orphans three ways.**
    Do: mark each as operator-tool, guest-scoped, or unreachable-automation in
    `scripts/INVENTORY.md` and `scripts/inventory.tsv`.
    Accept: every orphan carries a disposition; the count of unexplained orphans is zero.
13. **Reconnect the integration test tier.**
    Do: add a Makefile target invoking `scripts/test-hurd-system.sh`, which reaches all
    seven `test-phases/*.sh`. It is currently unreachable from any entry point.
    Accept: `make test-guest` exists and the phase scripts appear as graph callees.
14. **Resolve the five duplicated `automation/qemu` script pairs.**
    Do: `diff` each pair. Identical means keep one canonical path; divergent means merge.
    Accept: no script content exists at two paths, or each surviving pair is documented as
    intentional guest delivery, as with the `share/` copies.
15. **Add `set -eu` to the six executable entry points that lack it.**
    Do: exclude the five `scripts/lib/*.sh`, where the omission is correct for sourced
    libraries, and record that exclusion as intentional.
    Accept: every executable script under `scripts/` sets `-eu`; libraries documented as
    deliberately not doing so.

### Correct the documentation surface

16. **Fix the 14 dead make targets.**
    Do: `docs/09-TESTING-ROADMAP.md:472-491` and `docs/reports/AUDIT-2026-05-12.md:172`.
    Map `make vnc-up` to `up-vnc`, `make latest-image` to `setup-latest`, and either
    implement or remove the twelve backend targets.
    Accept: every `make <target>` in live docs resolves in the Makefile.
17. **Retire the 41 phantom environment variables from live docs.**
    Do: `QEMU_STORAGE`, `QEMU_EXTRA_ARGS`, `QEMU_CPU`, `QEMU_VIDEO`, `QEMU_ACCEL`,
    `QEMU_FSCK`, `QEMU_NIC` are documented and unread. Replace with the variables
    `entrypoint.sh` reads, or implement the documented ones.
    Accept: every env var in a live troubleshooting doc appears in `entrypoint.sh`.
18. **Generate the environment-variable reference from the source.**
    Do: derive `docs/03-CONFIGURATION/environment-variables.md` from `entrypoint.sh` reads
    and verify it in CI.
    Accept: the drift that produced item 17 cannot recur silently.
19. **Adopt one archive convention.**
    Do: three coexist (`ARCHIVE/`, `docs/archive/`, `scripts/archive/`) alongside nested
    `docs/*/archive/` and `-LEGACY.md` suffixes. Pick one and state it in `CONTRIBUTING.md`.
    Accept: the audit scan needs one exclusion rule rather than five.
20. **Surface the upstream bug reports.**
    Do: `upstream-bug-reports/` holds four well-formed reports that the docs index does not
    reference. Link them from `docs/INDEX.md` and the troubleshooting entry points, and
    record filing status per report.
    Accept: each report is reachable from `docs/INDEX.md` and states whether it is filed
    upstream.

### Repair the documentation site

21. **Rebuild the `mkdocs.yml` nav against the current tree.**
    Do: all 26 entries name files from the pre-consolidation flat layout. Regenerate the nav
    from the `01-08` hierarchy, or adopt `mkdocs-awesome-pages` / literate-nav so the nav
    derives from the directory structure and cannot drift again.
    Accept: `mkdocs build --strict` exits 0.
22. **Decide the fate of the 260-plus unlisted documents.**
    Do: the nav omits nearly the entire corpus. Either include the `01-08` sections and
    exclude `archive/` and `reports/` explicitly, or set `not_in_nav` so `--strict` stays
    meaningful rather than noisy.
    Accept: every live document is either in the nav or explicitly excluded.

### ROADMAP.md reconciliation applied in this pass

These four corrections are already committed to the working tree and are recorded here for
traceability rather than as pending work:

- The Milestone 5 / Milestone 6 numbering collision is resolved. Milestone 6 renumbers to
  items 39-41.
- Item 17 no longer reads "`docker compose` vs `docker compose`"; it names v2 against
  `podman-compose` and records the zero-live-v1-invocation measurement.
- Items 33 and 34 are annotated as blocked on the image repair, with the reason stated.
- Milestone 5b (items 35-38, bootable image integrity) and Milestone 7 (items 42-49, gate
  coverage and reference integrity) are added, carrying the findings above.

The `mkdocs` items 21 and 22 in this section are not yet reflected in ROADMAP.md.

## What this audit does not establish

Stated plainly so that no downstream reader mistakes static findings for runtime evidence.

- No guest reached multi-user state, so SSH behavior, package availability, translator
  function, and the sshd crash of ROADMAP item 34 are all `unverified` here.
- Podman, libvirt, VirtualBox, macOS, and Windows paths were not exercised. ROADMAP items
  15, 17, and 18 remain open on their original terms.
- The GitHub Actions findings are read from workflow source, not from observed runs. The
  `exit 1` in `release-artifacts.yml` is proven by reading the gate and confirming the file
  is absent; it is not proven by a failed run log.
- The 4.7x KVM speedup measures time to a `fsck` failure, not time to a usable system. It is
  a valid same-endpoint comparison and not a boot-time benchmark.
