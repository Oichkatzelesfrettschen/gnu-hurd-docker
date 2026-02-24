# Workstation bootstrap (XFCE)

This repo can boot Debian GNU/Hurd under QEMU and expose the VGA console via VNC/noVNC. Turning the guest into a full workstation is **best-effort**: package availability and stability vary by the upstream Hurd image.

## Recommended path (reliable boot first)

1. Start with VNC/noVNC (TCG, no KVM):

```bash
make up-vnc
```

2. Open noVNC locally:

- `http://127.0.0.1:6080/vnc.html`

3. Log in on the guest console as `root`.

Notes:
- Serial login is often blank on upstream images. Use noVNC for first boot.
- Some images hit IDE DMA I/O errors under KVM. This repo defaults to `AUTO_DISABLE_KVM_FOR_IDE=1`.
- On some images `sshd` can crash at boot; plan to do initial setup interactively via noVNC.

## Bootstrap steps (inside the guest)

Run these as `root` from the guest console.

1. Ensure networking works (DHCP should already run on many images):

```sh
ping -c 1 8.8.8.8 || true
```

2. Update apt metadata:

```sh
apt-get update
```

3. Install entropy helper + SSH server (optional but recommended to enable automation):

```sh
apt-get install -y random-egd openssh-server
```

4. Install desktop packages (best-effort):

```sh
apt-get install -y xorg xfce4 xfce4-goodies dbus-x11 xterm
```

If `lightdm` is available on your image, you can try it; otherwise plan to start X manually.

5. Start a graphical session (varies by image):

- If you have a working login manager, reboot and use it via VNC/noVNC.
- Otherwise, try running `startxfce4` under an X session (`startx`), after starting/attaching a console server if your image requires it.

## Automation (after SSH works)

Once you can SSH to the guest, use:

```bash
ROOT_PASS=root SSH_PORT=2222 ./scripts/bootstrap-workstation-hurd.sh
```

If SSH does not come up, see:
- `docs/06-TROUBLESHOOTING/SSH-ISSUES.md`
