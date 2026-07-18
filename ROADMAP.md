# Roadmap — gnu-hurd-docker

This roadmap focuses on making the project **portable**, **truthful**, and **reproducible** across Docker/Podman and amd64/arm64 hosts.

## Milestone 0 — Baseline integrity (now)

1. [x] Standardize canonical service/container name to `gnu-hurd-dev` (legacy/long-form docs preserved under `docs/**/archive/`)
2. [x] Standardize image reference to `ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest`
3. [x] Ensure `compose.yaml` is TCG-safe by default (no mandatory `/dev/kvm`)
4. [x] Provide explicit `compose.kvm.yaml` for Linux x86_64 acceleration
5. [x] Ensure secrets are optional (no mandatory local secret files for first boot)
6. [x] Keep `./images` as the canonical dev image directory (tracked via `images/.gitkeep`)
7. [x] Make `./scripts/validate-config.sh` the source of truth for internal consistency
8. [x] Add/maintain `./scripts/smoke-host.sh` as the minimal “can I start?” check

## Milestone 1 — Documentation truth + link hygiene

9. [x] Run a link scanner across `docs/` and fix broken internal links (nested `**/archive/**` excluded)
10. [x] Remove/qualify claims not backed by primary sources (notably hardcoded image dates)
11. [x] Update entry docs (README + docs index + canonical guides) to match current Compose files and scripts
12. [x] Document host/guest architecture clearly (amd64/arm64 host vs x86_64 guest)
13. [x] Document KVM constraints clearly (Linux x86_64-only for x86_64 guests)
14. [x] Document `AUTO_DOWNLOAD_IMAGE=1` (opt-in self-heal)

## Milestone 2 — Runtime portability (Docker + Podman)

15. [ ] Verify rootless Podman behavior on Linux and document required flags/limitations
16. [x] Add a Docker/Podman invocation path using Compose-native `make` targets + `scripts/lib/container-runtime.sh`
17. [ ] Ensure `docker compose` vs `docker compose` vs `podman-compose` differences are documented and tested end-to-end
18. [ ] Validate bind mounts and file paths on macOS/Windows via Docker Desktop/Podman Machine (document caveats)

## Milestone 3 — Reproducible image acquisition

19. [x] Pin Debian image URL to ports/13.0 and verify `SHA256SUMS` (do not hardcode build IDs; example `20250807`)
20. [x] Add checksum verification to `scripts/download-image.sh`
21. [x] Cleanup deterministically on failure and avoid assuming a fixed extracted `.img` filename
22. [x] Document upstream source and verification commands in `docs/audits/`

## Milestone 4 — CI confidence (without pretending)

23. [x] CI: validate YAML + shell scripts + internal invariants (fast, no VM boot)
24. [ ] CI: optional, scheduled “boot smoke” job (best-effort; clearly marked flaky/slow if needed)
25. [ ] CI: publish artifacts for troubleshooting (logs, config dumps)

## Milestone 5 — Operational ergonomics

26. [x] Add `make` targets (or a small CLI) for: `setup`, `validate`, `up`, `up-kvm`, `up-vnc`, `logs`, `down`
27. [x] Add orchestration commands for VNC/noVNC overlays (`up-vnc`, `up-kvm-vnc`, `up-volume-vnc`)
28. [ ] Add explicit “resource sizing” guidance (RAM/CPU/disk) and sane defaults per host class
29. [ ] Add “known good” troubleshooting playbook for common failures (boot, ssh, disk/fsck, perf)
30. [x] Add a console smoke check (noVNC reachable + monitor “running” + screenshot works)
31. [x] Add an offline GRUB root device patcher (guestfish) so SCSI boots can be tested reproducibly
32. [x] Add disk bus switch docs (`QEMU_DISK_BUS=ide|scsi`) and root device implications (`wd0` vs `sd0`) (SCSI remains experimental for the current image)
33. [ ] Investigate/mitigate KVM+IDE DMA I/O errors; default to TCG for IDE (`AUTO_DISABLE_KVM_FOR_IDE=1`) with `FORCE_KVM=1` override
34. [ ] Investigate guest `sshd` crash on some images; document a known-good image version and/or mitigation steps

## Milestone 6 — Packaging coherence

33. [x] Align `PKGBUILD` with runtime realities (host QEMU optional; scripts are arch-independent)
34. [ ] Add a `podman` optional dependency path in packaging docs (where applicable)
35. [ ] Ensure package-installed launcher supports `up-kvm` via `compose.kvm.yaml`

## Definition of done (per change)

- The change is reflected in:
  - `README.md` (if user-facing)
  - `docs/` (if it alters behavior or requirements)
  - `scripts/validate-config.sh` (if it alters invariants)
- `./scripts/smoke-host.sh` passes on a clean checkout.
