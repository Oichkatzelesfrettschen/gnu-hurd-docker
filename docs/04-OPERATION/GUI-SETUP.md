# GUI setup (Canonical)

GUI support inside Debian GNU/Hurd varies significantly by upstream image, package availability, and driver support. This repo’s default runtime is headless (serial + SSH), with optional VNC/noVNC output from QEMU.

## Recommended workflow

- Prefer headless workflows unless you specifically need a GUI.
- Use VNC/noVNC for display output:
  - Start the overlay: `./scripts/docker-orchestration.sh up-vnc`
  - Connect with: `vncviewer localhost:5900` or open `http://localhost:6080/vnc.html`
- If you want to install a desktop environment (XFCE), follow: `docs/04-OPERATION/WORKSTATION-XFCE.md`.

## Legacy

An older GUI walkthrough (including unverified snapshot-pinning advice) is preserved at `docs/04-OPERATION/archive/GUI-SETUP-LEGACY.md`.
