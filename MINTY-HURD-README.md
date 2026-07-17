# Minty Hurd

Linux Mint themes + Whisker Menu + dropbear-or-OpenSSH + tmux/mosh +
fastfetch, all running inside a Debian GNU/Hurd guest under KVM.

## Quick start

```sh
# 0. clone + cd
git clone https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
cd gnu-hurd-docker

# 1. fetch the baseline Hurd image (~600 MB compressed)
IMAGE_TRACK=release ./scripts/download-image.sh
cp images/debian-hurd-amd64.qcow2 images/hurd-working.qcow2

# 2. resize the image to 16 GB so the desktop install has room
qemu-img resize images/hurd-working.qcow2 16G
sudo qemu-nbd --connect=/dev/nbd0 images/hurd-working.qcow2
sudo partprobe /dev/nbd0
sudo parted -s /dev/nbd0 resizepart 2 100%
sudo parted -s /dev/nbd0 resizepart 5 100%
sudo partprobe /dev/nbd0
sudo e2fsck -fy /dev/nbd0p5
sudo resize2fs /dev/nbd0p5
sudo qemu-nbd --disconnect /dev/nbd0

# 3. boot with the Minty profile
docker compose -f compose.yaml -f compose.minty.yaml up -d
# or:  make minty-up

# 4. wait ~60 sec for KVM boot, then SSH in.  Default credentials are
#    root:root and user:user (set offline in the baseline image -- see
#    docs/reports/HURD-CONFIG-2026-05-13.md for how to reproduce).
ssh-keygen -t ed25519 -f hurd_test_key -N ''
# (the install procedure in scripts/minty-hurd-install.sh expects this
#  key to be pre-baked into /home/user/.ssh/authorized_keys; see
#  docs/reports/HURD-CONFIG-2026-05-13.md sec "Offline-edit script".)
ssh -i hurd_test_key -p 2222 user@127.0.0.1

# 5. install the full Minty Hurd stack (XFCE + Mint themes + tmux + mosh + fastfetch)
ssh -i hurd_test_key -p 2222 root@127.0.0.1
sudo /root/scripts/lmde7-apt-setup.sh    # adds LMDE7 (gigi) repo with strict pin
sudo /root/scripts/minty-hurd-install.sh # the resilient installer

# 6. start the XFCE desktop via tightvncserver
ssh -i hurd_test_key -p 2222 user@127.0.0.1
vncpasswd                                          # set VNC password (one-time)
tightvncserver :1 -geometry 1440x900 -depth 24     # binds 127.0.0.1:5901 (guest)
exit
vncviewer 127.0.0.1:5901                            # from host (port forwarded)
```

## What's installed

| Group | Packages |
|---|---|
| Display server | `xserver-xorg-core xserver-xorg-input-kbd xserver-xorg-input-mouse xserver-xorg-video-vesa xserver-xorg-video-fbdev xinit xauth x11-utils x11-xserver-utils dbus dbus-x11` |
| Desktop | `xfce4 xfce4-goodies xfce4-terminal xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin xfce4-notifyd xfce4-screensaver xfce4-screenshooter thunar lightdm lightdm-gtk-greeter` |
| Mint themes (from LMDE7 gigi) | `mint-l-theme mint-l-icons mint-y-icons mint-x-icons mint-cursor-themes mint-backgrounds-wilma linuxmint-keyring` |
| Mint extras (arch=all) | `python3-xapp xapp-thumbnailers-common xapp-mp3-thumbnailer xapp-raw-thumbnailer` |
| Themes (Debian main) | `arc-theme papirus-icon-theme adwaita-icon-theme gnome-themes-extra breeze-icon-theme hicolor-icon-theme` |
| Audio | `pulseaudio pulseaudio-utils pavucontrol` |
| File/utilities | `gvfs gvfs-backends gvfs-daemons upower gnome-keyring file-roller galculator mousepad` |
| Fonts | `fonts-dejavu fonts-liberation fonts-noto` |
| Polkit | `policykit-1 xfce-polkit consolekit libpam-ck-connector` (auth via ConsoleKit since Hurd has no systemd-logind) |
| VNC | `tightvncserver xvfb` (x11vnc / tigervnc-* / novnc not in hurd-amd64 buildd) |
| CLI | `tmux mosh htop ncdu tree jq ripgrep fd-find bat bash-completion zsh mksh rsync openssl ca-certificates` |
| Branding | `fastfetch` (Mint logo + "Minty Hurd" title) |

## Hurd port gaps (skipped by `inst()` in the installer)

These packages don't exist in debian-ports/hurd-amd64 because their
maintainers either explicitly excluded Hurd in `debian/control` or the
buildd never produced a usable binary (Linux-only syscalls):

* `thunar-volman` -- libudev removable-media events.  Thunar still
  works without it; just no auto-mount of USB sticks.
* `xserver-xorg-input-evdev`, `xserver-xorg-input-libinput` -- Hurd
  has no `/dev/input/event*`.  We fall back to `kbd` + `mouse` drivers.
* `gnome-keyring` -- depends on a kernel keyring API absent on Hurd.
  Password storage falls back to `pass` or `keepassxc`.
* `x11vnc`, `tigervnc-standalone-server`, `tigervnc-common`, `websockify`,
  `novnc` -- not built for hurd-amd64.  tightvncserver is the
  alternative; it bundles its own Xtightvnc server (no need for
  separate Xorg + bridge).
* `iotop` -- reads Linux `/proc/diskstats`.  Use `htop` or `gtop`.
* `fish-shell` -- not built for hurd-amd64 (we have bash, dash, zsh,
  mksh, tmux as alternatives).

## The Mint repo (LMDE7 / gigi) -- what it does and doesn't

**Wired via `scripts/lmde7-apt-setup.sh`**:

```sh
deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/linuxmint-keyring.gpg] \
    http://mirrors.kernel.org/linuxmint-packages/ gigi main upstream import backport
```

**`/etc/apt/preferences.d/lmde7`** strict pin:

```
Package: *
Pin: release o=linuxmint
Pin-Priority: 100      # default-deprefer

Package: <named arch=all Mint packages>
Pin: release o=linuxmint
Pin-Priority: 500      # whitelist
```

* `[arch=amd64]` makes apt fetch the amd64 Packages list (LMDE
  doesn't ship hurd-amd64 -- it's a Linux distro).
* Pin priority 100 globally means **nothing** from LMDE wins over
  Debian-ports unless explicitly whitelisted at 500.
* `_all.deb` (arch-independent: themes, Python, configs) installs
  cleanly on hurd-amd64 -- arch=all .debs work on any architecture.
* `_amd64.deb` (Linux-specific binaries) would NOT install on Hurd
  because the dpkg native arch is `hurd-amd64`, and we never
  `dpkg --add-architecture amd64`.  The pin protects against any
  accidental cross-arch pull.

**Whitelisted packages pulled successfully** from LMDE7 gigi (all
`_all.deb`):
* `mint-l-theme` 2.0.6
* `mint-l-icons` 1.8.0
* `mint-y-icons` 1.9.1-1
* `mint-x-icons` 1.7.5
* `mint-cursor-themes` 1.0.2
* `mint-backgrounds-wilma` 1.1
* `linuxmint-keyring` 2022.06.21
* `python3-xapp` 3.0.2-1
* `xapp-thumbnailers-common` 1.2.9
* `xapp-mp3-thumbnailer` 1.2.9
* `xapp-raw-thumbnailer` 1.2.9

**Not pulled (would need arch-specific binaries that don't exist on Hurd)**:
* `mintmenu` -- needs MATE applet runtime (gir1.2-matemenu-2.0,
  gir1.2-matepanelapplet-4.0) which require arch=hurd-amd64 binaries
  that aren't built.  We use `xfce4-whiskermenu-plugin` instead --
  the same XFCE menu Mint ships in their XFCE Edition.
* `mintdesktop`, `mintreport`, `mintsystem`, `mintinstall`,
  `mintwelcome` -- pull in arch-specific deps (libxapp1 et al, gtk
  bindings, etc.) that don't exist for hurd-amd64.

## Shell choice

* **Default login shell: `bash`** (matches Linux Mint default for both
  Mint XFCE and Mint MATE editions).
* `mksh` 59c-43 installed as alt-shell for users who prefer Korn
  shell semantics (registered in `/etc/shells`).
* `zsh` 5.x available too.
* `mosh-server` re-execs in the user's `chsh` shell, so bash is what
  you get on `mosh user@host`.

## QEMU configuration matrix (verified working on the host this was built on)

| Setting | Value | Why |
|---|---|---|
| `-machine pc` | i440fx | Hurd 0.9 + GNU-Mach 1.8 most stable on this chipset |
| `-accel kvm` | KVM (via `FORCE_KVM=1`) | TCG was ~115x slower; KVM works fine if SMP<=2 |
| `-cpu host` | host CPU passthrough | fastfetch shows AMD Ryzen 5 5600X3D inside guest |
| `-smp 2` | 2 vCPU | >2 triggers IDE DMA "bus-master missing interrupt" |
| `-m 2048` | 2 GB RAM | enough headroom; 4GB also OK |
| `-drive cache=writeback,aio=threads,format=qcow2` | safe + fast | unsafe loses data on host crash; writeback is the safe modern default |
| `-device ide-hd` | PIIX IDE | Hurd grub.cfg references `wd0` (the PIIX IDE first-disk name) |
| `-vnc :0` | VNC on :5900 | for the QEMU framebuffer (boot/kernel console) |
| `-nic user,model=e1000` | user-mode NAT | Hurd needs `e1000` not `virtio-net`; user-mode networking works because Hurd has dhclient |
| `-rtc base=utc,clock=host` | host clock | avoids drift |

See `compose.minty.yaml` for the full reproducible spec.

## Outstanding upstream items

* Debian bug filed locally in `upstream-bug-reports/` (not yet
  submitted to the BTS):
    * `openssl-hurd-simd-sshd-crash.md` -- OpenSSL SHA512_Update
      faults on Hurd when sshd is launched via start-stop-daemon;
      workaround `OPENSSL_ia32cap=~0:0`.  Likely root cause:
      GNU Mach `fpinherit` doesn't preserve XSAVE state across the
      daemonizing double-fork.
    * `dropbear-hurd-password-auth.md` -- dropbear rejects all
      passwords on Hurd despite crypt+getpwnam working.  Workaround:
      use pubkey auth.
* `patches/gnumach-raise-ipc_kernel_map_size.patch` -- 8 MB ->
  64 MB in `ipc/ipc_init.c`.  Submitted to nobody yet.

## Remote desktop access -- three paths (recommended order)

1. **X11 forwarding over SSH (recommended)**.  No VNC layer needed.
   The guest's `/etc/ssh/sshd_config` has `X11Forwarding yes`.  From a
   host running an X server:
   ```sh
   ssh -X -i ssh-test-keys/hurd_test_key -p 2222 user@127.0.0.1 xfce4-terminal
   # any X11 program runs on the guest and displays on the host.
   # to run a full XFCE session inside a nested X server:
   Xephyr -screen 1280x800 :2 &
   DISPLAY=:2 ssh -X -i ssh-test-keys/hurd_test_key -p 2222 \
       user@127.0.0.1 dbus-launch startxfce4
   ```

2. **QEMU framebuffer VNC on host port 5900**.  Shows whatever the
   Hurd kernel framebuffer shows (boot messages, login prompt,
   getty).  Useful for kernel-level debugging or watching the
   boot.  Connect via `vncviewer 127.0.0.1:5900` from the host.
   No password (QEMU monitor restricted to 127.0.0.1).

3. **tightvncserver inside guest -- not currently working**.
   `Xtightvnc` reports *"could not open default font 'fixed'"*
   even with explicit `-fp` listing the correct directories and
   verified `fonts.alias` containing the `fixed` alias.  This is
   tracked as a Hurd-specific TightVNC font subsystem bug to file
   upstream.  Workaround: use path 1 (X11-over-SSH).

## Mint package matrix -- what's installed and where it came from

| Source | Packages |
|---|---|
| Debian-ports/sid hurd-amd64 | 700+ packages (Xorg, XFCE, lightdm, fonts, tmux, mosh, mksh, fastfetch, ...) |
| LMDE7 gigi `_all.deb` arch=all (whitelisted) | linuxmint-keyring, mint-artwork, mint-themes (2.3.8), mint-l-theme, mint-y-icons, mint-x-icons, mint-l-icons, mint-cursor-themes, mint-backgrounds-wilma, python3-xapp, xapps-common, xapp-thumbnailers-common, xapp-mp3-thumbnailer, xapp-raw-thumbnailer, xapp-jxl-thumbnailer, xapp-symbolic-icons |
| Mined out of debs directly | Real Mint XFCE whiskermenu-1.rc + xfce4-panel.xml + all panel plugin .rc files from `/usr/share/mint-artwork/xfce/xfce4/` (mint-artwork 1.9.3, gigi).  Deployed to /home/user/.config/xfce4/ and /etc/skel/.config/xfce4/. |
| Curated download (PD/CC) | JWST: weic2208a (Webb's First Deep Field), weic2316a from esawebb.org.  Hubble: Westerlund 2, Cone Nebula, Carina Deep from esahubble.org.  All resized to <=1920x1080.  Staged in /usr/share/backgrounds/minty-hurd/ with attribution README. |

722 packages installed, 16 GB disk with 11 GB free.

## The "_all.deb works for Hurd from LMDE7" mechanism

Architecture-independent `.deb` packages (arch=all) install on any
Debian architecture, including hurd-amd64, because dpkg treats them
as universal.  Architecture-specific binaries are ELF files compiled
for a specific platform -- a binary built for Linux amd64 cannot
satisfy a `Depends:` chain when the dpkg native architecture is
hurd-amd64.

Our setup chains:
1. `/etc/apt/sources.list.d/lmde7.list` with `[arch=amd64]` tells
   apt to fetch LMDE7's `binary-amd64/Packages` list (LMDE has no
   binary-hurd-amd64).
2. `/etc/apt/preferences.d/lmde7` pin file defaults everything from
   LMDE to priority 100 (below Debian-ports' 500), so no package
   wins over Debian by accident.
3. Explicit whitelist at priority 500 for the named arch=all Mint
   packages, allowing them to install.
4. dpkg will refuse to install any `_amd64.deb` (Linux binary)
   because the architecture mismatch is detected by `dpkg --check`
   at unpack time -- `dpkg --add-architecture amd64` was never run,
   so amd64 is foreign and refused.

This gives us the Mint UI/look layer without compromising the Hurd
binary layer.
