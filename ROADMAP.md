# Roadmap -- gnu-hurd-docker

This roadmap focuses on making the project **portable**, **truthful**, and **reproducible** across Docker/Podman and amd64/arm64 hosts.

## Milestone 0 -- Baseline integrity (now)

1. [x] Standardize canonical service/container name to `gnu-hurd-dev` (legacy/long-form docs preserved under `docs/**/archive/`)
2. [x] Standardize image reference to `ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest`
3. [x] Ensure `compose.yaml` is TCG-safe by default (no mandatory `/dev/kvm`)
4. [x] Provide explicit `compose.kvm.yaml` for Linux x86_64 acceleration
5. [x] Ensure secrets are optional (no mandatory local secret files for first boot)
6. [x] Keep `./images` as the canonical dev image directory (tracked via `images/.gitkeep`)
7. [x] Make `./scripts/validate-config.sh` the source of truth for internal consistency
8. [x] Add/maintain `./scripts/smoke-host.sh` as the minimal "can I start?" check

## Milestone 1 -- Documentation truth + link hygiene

9. [x] Run a link scanner across `docs/` and fix broken internal links (nested `**/archive/**` excluded)
10. [x] Remove/qualify claims not backed by primary sources (notably hardcoded image dates)
11. [x] Update entry docs (README + docs index + canonical guides) to match current Compose files and scripts
12. [x] Document host/guest architecture clearly (amd64/arm64 host vs x86_64 guest)
13. [x] Document KVM constraints clearly (Linux x86_64-only for x86_64 guests)
14. [x] Document `AUTO_DOWNLOAD_IMAGE=1` (opt-in self-heal)

## Milestone 2 -- Runtime portability (Docker + Podman)

15. [ ] Verify rootless Podman behavior on Linux and document required flags/limitations
16. [x] Add a Docker/Podman invocation path using Compose-native `make` targets + `scripts/lib/container-runtime.sh`
17. [ ] Ensure `docker compose` (v2) vs `podman-compose` differences are documented and tested end-to-end (live sources carry zero v1 `docker-compose` invocations; the remaining 61 live mentions are filenames and prose)
18. [ ] Validate bind mounts and file paths on macOS/Windows via Docker Desktop/Podman Machine (document caveats)

## Milestone 3 -- Reproducible image acquisition

19. [x] Pin Debian image URL to ports/13.0 and verify `SHA256SUMS` (do not hardcode build IDs; example `20250807`)
20. [x] Add checksum verification to `scripts/download-image.sh`
21. [x] Cleanup deterministically on failure and avoid assuming a fixed extracted `.img` filename
22. [x] Document upstream source and verification commands in `docs/audits/`

## Milestone 4 -- CI confidence (without pretending)

23. [ ] CI: validate YAML + shell scripts + internal invariants (fast, no VM boot) -- the workflow definitions exist and `Docs Build Check` runs on pull requests; `validate.yml`, `validate-config.yml`, and `quality-and-security.yml` stay manually disabled until item 43 converges their gates
24. [ ] CI: optional, scheduled "boot smoke" job (best-effort; clearly marked flaky/slow if needed)
25. [ ] CI: publish artifacts for troubleshooting (logs, config dumps)

## Milestone 5 -- Operational ergonomics

26. [x] Add `make` targets (or a small CLI) for: `setup`, `validate`, `up`, `up-kvm`, `up-vnc`, `logs`, `down`
27. [x] Add orchestration commands for VNC/noVNC overlays (`up-vnc`, `up-kvm-vnc`, `up-volume-vnc`)
28. [ ] Add explicit "resource sizing" guidance (RAM/CPU/disk) and sane defaults per host class
29. [ ] Add "known good" troubleshooting playbook for common failures (boot, ssh, disk/fsck, perf)
30. [x] Add a console smoke check (noVNC reachable + monitor "running" + screenshot works)
31. [x] Add an offline GRUB root device patcher (guestfish) so SCSI boots can be tested reproducibly
32. [x] Add disk bus switch docs (`QEMU_DISK_BUS=ide|scsi`) and root device implications (`wd0` vs `sd0`) (SCSI remains experimental for the current image)
33. [ ] Investigate/mitigate KVM+IDE DMA I/O errors; default to TCG for IDE (`AUTO_DISABLE_KVM_FOR_IDE=1`) with `FORCE_KVM=1` override -- blocked on item 35: the 2026-07-24 two-arm capture halts in `fsck` before the guest mounts root read-write, so the condition is not exercised
34. [ ] Investigate guest `sshd` crash on some images; document a known-good image version and/or mitigation steps -- blocked on item 35: no capture has reached multi-user state on the canonical image

## Milestone 5b -- Bootable image integrity

35. [ ] Repair the guest root filesystem in `images/debian-hurd-amd64.qcow2` (`/dev/wd0s5` reports `UNEXPECTED INCONSISTENCY`, `fsck` exits 4, guest stops at a maintenance shell)
36. [ ] Add an offline guest-filesystem gate (`e2fsck -fn` via guestfish) -- `qemu-img check` reports no errors on the same image that fails to boot. `scripts/guestfish-check-guest-filesystem.sh` implements the check with a three-state exit contract (0 clean or repaired, 1 dirty, 2 uncheckable); wiring it into a gate splits by whether an image is present:
    - 36a. [ ] Call the checker from host preflight before QEMU starts, skipping with a recorded reason when the image or guestfish is absent
    - 36b. [ ] Treat exit 1 and exit 2 as failures in any workflow that builds, downloads, repairs, or publishes a qcow2, and install guestfish there. A source-only checkout carries no qcow2, so a green generic run establishes nothing about image integrity
37. [ ] Record SHA256 and upstream provenance for every file in `images/`
38. [ ] Re-run the two-arm KVM/TCG capture past `fsck` once items 35-37 land, and settle items 33 and 34 against evidence

## Milestone 6 -- Packaging coherence

39. [x] Align `PKGBUILD` with runtime realities (host QEMU optional; scripts are arch-independent)
40. [ ] Add a `podman` optional dependency path in packaging docs (where applicable)
41. [ ] Ensure package-installed launcher supports `up-kvm` via `compose.kvm.yaml`

## Milestone 7 -- Gate coverage and reference integrity

42. [x] Discover the maintained shell surface dynamically in `scripts/validate-config.sh` -- `entrypoint.sh`, `scripts/**`, and `share/**`, excluding archives, which replaces 29 enumerated paths with the whole maintained tree. Item 43 names the enumerator that now defines that set; `scripts/list-maintained-shell.sh` is the only authority on its size
43. [ ] Clear the 15 warning-level ShellCheck findings, then raise the enforced severity. `scripts/list-maintained-shell.sh` defines the file set and `scripts/check-maintained-shell.sh` is the single enforcement mechanism, failing closed on an empty surface; `make lint`, `scripts/validate-config.sh`, `validate.yml`, `validate-config.yml`, and `quality-and-security.yml` all run it, with `SHELLCHECK_SEVERITY` selecting the level and `error` enforced. Raising the default to `warning` waits on the findings, because `make lint` has to pass on a clean tree
44. [x] Remove the stale required-script gate from `release-artifacts.yml` and move release acceptance onto the extracted archive rather than repository-source paths, so the gate reads the product it publishes
45. [x] Replace the tab in `.github/workflows/release.yml` (sole yamllint error)
46. [ ] Count recipe blocks, not target lines, in any Makefile duplicate-target check (the five `up-podman*` pairs are the GNU make target-specific variable idiom and are correct)
47. [ ] Reconnect `scripts/test-hurd-system.sh` (and the seven `test-phases/` scripts it reaches) to a Makefile target
48. [ ] Classify the 36 live host-side orphan scripts (41 raw zero-inbound graph nodes, five of which fall outside the live-shell denominator) as operator-tool, guest-scoped, or unreachable-automation in `scripts/INVENTORY.md`
49. [ ] Correct the phantom `QEMU_*` env vars cited in live docs -- the dead `make` targets are corrected and `docs/03-CONFIGURATION/environment-variables.md` names the variables the entrypoint ignores; classifying the remaining live references needs a schema-backed variable inventory rather than a grep
50. [x] Rebuild the `mkdocs.yml` nav against the `01-08` tree, so `mkdocs build --strict` produces `site/index.html`
51. [x] Classify every document as nav, `not_in_nav`, or `exclude_docs`, so adding a report or an audit cannot break the strict build

52a1. [x] Define machine-readable evidence classes and per-probe records. `scripts/capture-runtime-evidence.py` labels every field `observed`, `derived`, `declared`, or `not-captured`, and each probe retains its argv, exit status, and both output streams. `docs/audits/runtime-evidence-capture-protocol.md` carries the contract and `schemas/runtime-evidence-v2.schema.json` the schema
52a2. [ ] Retain both sanitized streams and certify them after redaction. Redaction runs inside `Capture.run` before each stream is written and before its digest is taken, both `stdout_sha256` and `stderr_sha256` are recorded, and JSON is redacted structurally because a regex that consumes a quoted value and writes back an unquoted token produces a document `json_probe` cannot decode. `tests/runtime-evidence/test-capture-producer.py` calibrates the producer against the shapes a real probe returns. A global `core.excludesFile` ignoring `*.out` also kept every retained stdout untracked while its `.err` counterpart committed, so a clone held digests for streams it lacked; `.gitignore` now overrides that rule for the case directories. This closes when a recapture from a clean revision produces the tracked package
52b. [ ] Bind to exactly one QEMU process rather than one container. Container selection by live QEMU process, the Compose service from the `com.docker.compose.service` label, declared configuration read from that service alone, argv from `/proc/<pid>/cmdline`, and image resolution through the container's mount table are in place, and several PIDs in one container exit 2 without `--qemu-pid`. `--image PATH` branches before selection and records the supplied path as declared and the resolved path as observed, so offline image identity no longer depends on a running instance. This closes when a recapture exercises both paths against a live guest
52c1. [x] Execute schema, checker, and producer fixtures in active CI. `make evidence-check` runs both suites and Static Gates runs it. The contract fixtures assert what the document contract rejects: a null value classed `observed`, a null value with a missing or empty reason, a stdout or stderr digest that does not describe its file, a probe advertising an absent stream, a probe recording no stderr digest, a stream path escaping the capture by traversal, an absolute path, a symlink, a directory, a machine-local path, an unredacted credential, a wrong schema version, a missing section, and a directory with no `capture.json`. The producer fixtures assert what the instrument does with a JSON secret member, an environment array, a YAML mapping, a key that merely contains `PASS` or `KEY`, ordinary text, a known and an unknown KVM transcript, and an offline image run that the checker then validates
52c2. [ ] Cover the fixtures that need a live runtime: several QEMU containers, several QEMU processes in one container, named-volume image storage, a custom monitor port, a custom published SSH port, an SSH banner timeout, a missing guest key, and a failed enumerator
52d. [ ] Recapture the matched TCG/KVM pair from a clean identified revision using tracked inputs. `evidence/runtime/cases/SUPERSEDED.md` records why the present pair is not citable: four post-redaction digest mismatches per arm, no stderr digests, a `/tmp` override path that is both machine-local and absent from the tree, and capture from a dirty `b5db85a` that predates the instrument. The pair still shows that changing `FORCE_KVM` from `1` to `0` changed the accelerator with every other captured parameter equal, which is evidence consistent with the `AUTO_DISABLE_KVM_FOR_IDE` branch rather than an observation of it. The recapture follows the single-service Compose topology so the pair is cut once against the topology it describes
52e. [ ] Instrument `entrypoint.sh` to write its accelerator decision as a structured record naming the candidate, each input it tested, the selected accelerator, and a reason code, so a capture reports the reason as an observation of the decision rather than reconstructing it from inputs
52f. [ ] Probe KVM usability rather than device visibility. `test -e/-r/-w /dev/kvm` establishes that the node is visible and its mode bits permit an open, not that `KVM_CREATE_VM` succeeds. `container_kvm_usable` runs a paused diskless `qemu-system-x86_64 -accel kvm` under `timeout`, reads 124 as initialization that survived, a known accelerator diagnostic as failure, and every other outcome as `not-captured` rather than as success. This closes when the probe runs against a live container in both arms of the recapture
53. [x] Define the release source product with `git archive`, so the repository tree and the `.gitattributes` `export-ignore` policy determine its contents, and build it from `scripts/build-release-archive.sh` so the pull-request check and the release job accept the same artifact against the same contract (`make -n up`, `make -n build`, the packaged `scripts/validate-config.sh`, a clean documentation link scan, and the default Compose overlay)
54. [ ] Make `compose.minty.yaml` a single-QEMU-service overlay over `compose.yaml` plus `compose.bind.yaml`, naming the service `gnu-hurd-dev`. The overlay declares a service named `hurd` while the base declares `gnu-hurd-dev`, so Compose adds a service rather than overriding one and the bare invocation starts two QEMU containers. The overlay also carries concerns other overlays own: `/dev/kvm` and `FORCE_KVM` belong to `compose.kvm.yaml` and an explicit KVM target, `./images` binding to `compose.bind.yaml`, browser access to `compose.vnc.yaml` and its noVNC sidecar. `SYS_PTRACE` grants no capability to a process inside the emulated guest, `QEMU_DISK_CACHE` is unread, and the direct `6080:6080` mapping reaches nothing. A static acceptance check asserts one QEMU-running service per composition
55. [x] Resolve the MATE package closure for both Hurd ports from the authenticated archive rather than the guest. `Dockerfile.hurd-archive` pins its base by digest and sets `APT::Architecture` to `hurd-amd64` or `hurd-i386` over a private apt state tree built per invocation, and `make hurd-closure` classifies a set as native, architecture-all, uninstallable, or missing. LMDE 7 `gigi` publishes no `binary-all` directory, so the overlay keeps only its `Architecture: all` stanzas and republishes them per source component under the target architecture, preserving every version, with the overlay origin pinned below Debian Ports. Mint metadata is verified with `gpgv` against a key vendored at `config/keys` and pinned by fingerprint, and each index is accepted only against the SHA-256 in that verified `Release`; a signature failure, an unnamed index, and a hash mismatch each abort. `make hurd-closure-selftest` drives the offline fixture suite in Static Gates, and `evidence/hurd-archive/` holds reports carrying collection time, image digest, apt and dpkg versions, every metadata digest, and the full recursive transaction. The layer settles availability and resolver closure; whether a package installs stays a guest fact
55a. [ ] Build the disposable Hurd package-builder overlay: an immutable builder base, a fresh external qcow2 overlay per build, build dependencies and an unprivileged source build inside it, export of the `.deb`, `.changes`, `.buildinfo`, and logs, and installation of the tested binaries into a separate product overlay. The withdrawn `scripts/build-hurd-package-in-guest.sh` built in the product image behind a `--snapshot` name it neither created nor verified, interpolated package names into a root remote shell, reused one workspace so a later build could select stale source, disabled host-key checking, and fell back from `apt-get install` to `dpkg -i` at the point apt had already called the transaction invalid
55b. [ ] Build `mate-settings-daemon` and `mate-control-center` for `hurd-amd64`, on 55a. Neither has a 64-bit record while both exist for `hurd-i386` at 1.26.1-1.2 and 1.26.0-2, and the main archive carries `mate-settings-daemon` source at the version the i386 binary was built from, which makes them high-confidence native-rebuild candidates rather than greenfield ports. A completed `hurd-amd64` build is the acceptance test: 64-bit assumptions, dependency skew, and new compiler diagnostics can still block a source that builds for the other port
55c. [ ] Port `polkitd`, and `accountsservice` for `hurd-amd64` where it is absent while native on `hurd-i386`. `polkitd` blocks `mate-polkit`, which `mate-panel` pulls, so authorization reaches into the first session rather than staying in the administrative one. A package that `Provides: polkitd` while supplying no daemon persuades apt and authorizes nothing: even on a single-user VM the system distinguishes the desktop account, root, system daemons, operations requiring authentication, and operations that are always denied, and clients then fail over D-Bus at run time. Such a stub counts toward no acceptance profile, which is why `scripts/make-hurd-dependency-stub.sh` was withdrawn rather than kept
55d. [ ] Rebuild `python3-setproctitle` for the Hurd, the one dependency keeping `mintmenu` out of `mint-mate-integration`. Neither port publishes it, and source availability alone does not distinguish a buildd omission from a porting problem; the build attempt is what settles it
55e. [ ] Watch the `sid` skew between `gvfs` and `gvfs-common` that makes `caja` uninstallable on both ports. Both ports carry `caja` natively, so this is an archive state rather than a port gap: the remedies are convergence, a coherent snapshot where every candidate matches, or rebuilding the mismatched dependency set together against one source state. Manufacturing a local `caja` build because `caja` heads a failing transaction addresses no mechanism
55f. [x] Settle whether `hurd-i386` binaries can fill the 64-bit port's gaps, from the archive rather than by argument. `--foreign-architecture` enables a second architecture the way `dpkg --add-architecture` does and qualifies every request to it. Upstream supports 32-on-64 as a whole 32-bit userland over 64-bit GNU Mach, or a whole 64-bit one, and not both at once, so a mixed universe is unsupported before any measurement; the archive then refuses it in the packaging layer first. `dconf` coinstalls as `:hurd-i386` and pulls 13 foreign-qualified packages, so the mechanism works where packaging is multiarch-aware, and 0 of 10 `mate-bootstrap` members resolve because MATE splits each component's data into an `Architecture: all` companion that cannot be architecture-qualified, while `mate-settings-daemon` carries no `Multi-Arch` field at all. No transaction removed a native package, so this is refusal rather than replacement. `hurd-i386` is a build reference and a separate reference system, not a package source for the amd64 desktop
55g. [ ] Run the guest half of the multiarch experiment in a disposable clone or external overlay, never in the canonical image. Simulate before installing and abort on removal of Essential or Important `hurd-amd64` packages, replacement of native Hurd servers, unqualified `/usr/bin` or `/usr/sbin` collisions, unresolved pre-dependencies, mixed-version libc or libpthread constraints, or a large unexpected foreign closure. If a minimal closure is safe, install the foreign libc and one uncomplicated executable rather than MATE, and drive a graded probe: pure computation, standard streams, `getuid` and `uname`, filesystem operations, `fork` and `exec`, Unix-domain sockets, networking, Mach port operations, translator-backed filesystem access, D-Bus session communication, and a GTK window. A working `hello:hurd-i386` establishes that some 32-bit processes run inside the amd64 system and nothing about product acceptance
55h. [ ] Build `minty-hurd-i386.qcow2` as a behavioral reference product beside the amd64 primary, using the more complete 32-bit package set to answer sooner whether MATE starts when the archive carries the missing binaries, which remaining failures are architecture-independent, whether the D-Bus and GSettings session design works, whether the Mint visual family installs and persists, whether `polkitd` is still the blocker, and whether the panel layout and theme configuration work. It is a reference system rather than a shipped desktop, and it keeps those answers out of the amd64 image rather than contaminating it with an unsupported mixed userland
56. [ ] Install the MATE session core and add `minty-hurd-mate`, keeping XFCE as an explicitly selected rescue session. The wrapper resolves the session binary from the installed package rather than assuming a name, and sets the desktop identity MATE components read. `/etc/hurd-desktop.session` selects the session and `/etc/hurd-desktop.mode` the Xorg or VNC route
57. [ ] Narrow the D-Bus session before MATE becomes the default. The current fix permits ANONYMOUS authentication and modifies the system bus; MATE depends on the session bus and GSettings for theme, panel, and window-manager state, so the session moves to a per-user loopback bus with `DBUS_COOKIE_SHA1` and no anonymous system bus
58. [ ] Make MATE the default session in both Xorg and VNC modes, gated on process and settings evidence: `mate-session`, `marco`, `mate-settings-daemon`, and `mate-panel` running, Caja owning the desktop, `mate-terminal` executing a command, GSettings persisting across reboot, the selected Mint themes active, and no XFCE process running
59. [ ] Install every dependency-safe LMDE Mint visual package unchanged under its own name, and fail the installer when the declared theme manifest silently shrinks. The 35 members of `mint-visual` dependency-resolve for both ports, which is a resolver verdict rather than an installation: an `Architecture: all` package can still carry a maintainer script calling a Linux-only command, Python reading `/proc`, or systemd activation, so the claim closes on a disposable guest installation ending `dpkg -C` clean. The set is recorded as a version-locked manifest with each package's component, digests, and reason for inclusion rather than as a hardcoded list. The default theme comes from an ordered probe over the themes actually installed rather than a name asserted before the packages are examined
60. [ ] Integrate Mint Menu when its simulated dependency closure carries only LMDE architecture-independent payloads and native `hurd-amd64` MATE and XApp libraries, falling back to the MATE menu. Whisker Menu stays specific to the XFCE rescue session
61. [ ] Build `minty-emerald-mate-theme` as a separate package deriving its palette from CachyOS-Emerald-KDE and covering GTK, Marco decorations, panel, Caja, control center, terminal, notifications, and wallpapers. It leaves the Mint families installed and selectable rather than overwriting them


## Definition of done (per change)

- The change is reflected in:
  - `README.md` (if user-facing)
  - `docs/` (if it alters behavior or requirements)
  - `scripts/validate-config.sh` (if it alters invariants)
- `./scripts/smoke-host.sh` passes on a clean checkout.
