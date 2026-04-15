# Hidden Clone Mining Report (2026-03-10)

## Scope

This report records what was mined from the legacy hidden checkout at `~/.Github/Docker-Projects/gnu-hurd-docker` before removing it as a duplicate workspace.

Canonical repository:

- `~/Github/gnu-hurd-docker`

Legacy hidden duplicate:

- `~/.Github/Docker-Projects/gnu-hurd-docker`

Summary at audit time:

- Canonical HEAD: `5db55fb905a2cecffe5addb39e1df4c30bb649dc`
- Hidden HEAD: `c76fbe72330c560dd8e463aa9736ed6c79908129`
- Relationship: hidden HEAD was an ancestor of canonical HEAD
- Hidden working tree: dirty (`39` local changes)

## Ported Forward

The following useful ideas were ported into the canonical repository:

1. `scripts/qemu-type.sh`
   - Added optional QMP transport via `QMP_SOCKET` or `--qmp-socket`
   - Added richer control tokens such as `<enter>`, `<ctrl-c>`, arrow keys, and `<delay:N>`
   - Kept the older telnet/HMP path for compatibility

2. `docs/05-CI-CD/GUIDE.md`
   - Added explicit safe automation rules:
     - prefer QMP for key injection and screenshots
     - avoid `xdotool`
     - avoid external screenshot tools
     - keep VNC localhost-bound unless intentionally proxied

3. `docs/01-GETTING-STARTED/STANDALONE-QEMU.md`
   - Added a troubleshooting-only note about `q35` plus AHCI as a fallback when a guest image only behaves correctly with a `wd0` disk path in that configuration

4. `scripts/README.md`
   - Documented the new `qemu-type.sh` QMP mode and control-token grammar

## Reviewed But Not Ported

These hidden-clone items were inspected and intentionally not copied as-is:

- `scripts/qemu-control-unified.sh`
  - Superseded by the canonical split-tool approach (`qemu-type.sh`, `qmp-helper.py`, `qemu-cli-control.sh`, and focused helpers)

- `scripts/download-hurd-image-unified.sh`
  - Superseded by the canonical image acquisition flow

- `launch-hurd.sh`
- `launch-hurd-working.sh`
- `hurd-qemu-max.sh`
  - Too host-specific to become canonical launchers
  - Only the useful `q35` plus AHCI fallback lesson was preserved in docs

- `docs/VNC-ACCESS-GUIDE.md`
- `docs/MATE-ON-HURD-RESEARCH.md`
- `docs/MATE-INSTALLATION-SUMMARY.md`
  - The canonical repository already has a broader and newer structured documentation tree

## Discarded As Local-Only

The following hidden-clone content was treated as non-canonical local residue and intentionally not preserved:

- local Claude/editor settings
- local databases
- generated reports duplicated elsewhere
- large VM image artifacts such as local VMDK and QCOW2 files

## Result

The useful automation behavior from the hidden duplicate was preserved in the canonical repository without importing the older duplicate layout, local-only files, or host-specific launch scripts.
