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

42. [x] Discover the maintained shell surface dynamically in `scripts/validate-config.sh` -- `entrypoint.sh`, `scripts/**`, and `share/**`, excluding archives, which replaces 29 enumerated paths with the whole maintained tree. Item 43 names the enumerator that now defines that set and carries its current size
43. [ ] Clear the 15 warning-level ShellCheck findings, then raise the enforced severity. `scripts/list-maintained-shell.sh` defines the file set (109 scripts) and `scripts/check-maintained-shell.sh` is the single enforcement mechanism, failing closed on an empty surface; `make lint`, `scripts/validate-config.sh`, `validate.yml`, `validate-config.yml`, and `quality-and-security.yml` all run it, with `SHELLCHECK_SEVERITY` selecting the level and `error` enforced. Raising the default to `warning` waits on the findings, because `make lint` has to pass on a clean tree
44. [x] Remove the stale required-script gate from `release-artifacts.yml` and move release acceptance onto the extracted archive rather than repository-source paths, so the gate reads the product it publishes
45. [x] Replace the tab in `.github/workflows/release.yml` (sole yamllint error)
46. [ ] Count recipe blocks, not target lines, in any Makefile duplicate-target check (the five `up-podman*` pairs are the GNU make target-specific variable idiom and are correct)
47. [ ] Reconnect `scripts/test-hurd-system.sh` (and the seven `test-phases/` scripts it reaches) to a Makefile target
48. [ ] Classify the 36 live host-side orphan scripts (41 raw zero-inbound graph nodes, five of which fall outside the live-shell denominator) as operator-tool, guest-scoped, or unreachable-automation in `scripts/INVENTORY.md`
49. [ ] Correct the phantom `QEMU_*` env vars cited in live docs -- the dead `make` targets are corrected and `docs/03-CONFIGURATION/environment-variables.md` names the variables the entrypoint ignores; classifying the remaining live references needs a schema-backed variable inventory rather than a grep
50. [x] Rebuild the `mkdocs.yml` nav against the `01-08` tree, so `mkdocs build --strict` produces `site/index.html`
51. [x] Classify every document as nav, `not_in_nav`, or `exclude_docs`, so adding a report or an audit cannot break the strict build

52. [ ] Make the runtime self-identifying, so operators read the accelerator QEMU selected rather than infer it from a target name. `compose.kvm.yaml` exposes `/dev/kvm`, and the entrypoint then chooses between `-accel kvm` and `-accel tcg` -- under the default `QEMU_MACHINE=pc` plus `QEMU_DISK_BUS=ide` with `AUTO_DISABLE_KVM_FOR_IDE=1` it chooses TCG. A `make runtime-info` target should report the observed container runtime, QEMU binary, accelerator (from the monitor, not from `/dev/kvm`), machine, disk bus, image path, and image SHA256, and the `up-kvm` target name should say that it exposes KVM rather than that it uses it

## Definition of done (per change)

- The change is reflected in:
  - `README.md` (if user-facing)
  - `docs/` (if it alters behavior or requirements)
  - `scripts/validate-config.sh` (if it alters invariants)
- `./scripts/smoke-host.sh` passes on a clean checkout.
