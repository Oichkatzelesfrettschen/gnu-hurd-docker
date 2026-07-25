# Minty image provenance: sid drift, UP Mach, and the published artifact

The published `minty-20260718` release is a genuine 16 GiB Debian GNU/Hurd desktop
image, and the repository's Minty source artifacts are already identical to `main`.
The reconciliation gap is not source-to-source: it is image-to-source.  The guest
tracks `sid` plus `unreleased`, and the kernel it boots is the uniprocessor Mach
build, which invalidates the SMP tuning constraint the compose profiles encode.

Every claim below is grounded in the qcow2 header bytes, the guest's
`/var/lib/dpkg/status`, `/boot/grub/grub.cfg`, and `/etc/apt/sources.list`, read
read-only from `images/hurd-working.qcow2`.

## There is no forward-port delta at the git level

`git merge-base main minty-20260718` returns the tag commit `8f6c08a` itself, so the
tag is an ancestor of `main`.  The seven Minty artifacts -- `MINTY-HURD-README.md`,
`compose.minty.yaml`, `docs/04-OPERATION/WORKSTATION-XFCE.md`,
`scripts/minty-hurd-install.sh`, `scripts/lmde7-apt-setup.sh`,
`scripts/fetch-mint-sources.sh`, `scripts/hurd-desktop-autostart.sh` -- diff empty
between the tag and `main`.  The eight commits since the tag touch documentation,
`mkdocs.yml`, `scripts/validate-config.sh`, and add
`scripts/guestfish-check-guest-filesystem.sh`.

The Minty source tree therefore needs no forward port.  What is undescribed is the
binary.

## The published artifact is the desktop image, flattened

Both release assets carry sha256 `5b4bd3ea...`, so `debian-hurd-amd64-latest.qcow2.xz`
and `debian-hurd-amd64-minty-20260718.qcow2.xz` are one blob under two names.  A
ranged fetch of the first 4 MB, decompressed, yields the qcow2 header:

| Field (offset) | Published | `images/hurd-working.qcow2` |
| --- | --- | --- |
| virtual size (0x18) | `0x400000000` = 16 GiB | 16 GiB |
| `l1_size` (0x24) | 32 | 32 |
| `l1_table_offset` (0x28) | `0x30000` | `0xc51a0000` |
| `nb_snapshots` (0x3c) | 0 | 1 |
| `snapshots_offset` (0x40) | 0 | `0x190860000` |

`l1_size` 32 is arithmetically consistent with 16 GiB at a 64 KiB cluster size, since
one L2 cluster maps 512 MiB.  The three base images in `images/` are all 3.91 GiB
virtual, so the release is not a mislabeled base image.

The prefixes differ bytewise because the release is a `qemu-img convert` flattening:
same geometry, compacted L1 table, snapshots dropped.  The working image retains one
internal snapshot the release does not:

    ID  TAG                        DATE
    1   pre-fullupgrade-20260716   2026-07-16 17:48:46

That snapshot is the only surviving record of the upgrade boundary, and it exists
only in an untracked local file.

## The guest is sid, not Trixie

`/etc/debian_version` reads `forky/sid`, and `/etc/apt/sources.list` is:

    deb http://deb.debian.org/debian-ports sid main
    deb http://deb.debian.org/debian-ports unreleased main
    deb-src http://deb.debian.org/debian sid main

`MINTY-HURD-README.md` line 219 already says "Debian-ports/sid hurd-amd64", so the
repository is accurate here.  The `trixie` references belong to
`scripts/lmde7-apt-setup.sh`, which describes LMDE 7 `gigi` as trixie-based -- that is
the theme source's Debian base, not the Hurd guest's suite.  Conflating the two
misreads the reproducibility problem.

The installed versions confirm the suite: glibc `2.42-17` as `libc0.3`, GCC
`4:15.2.0-5+b1` over `gcc-15` `15.3.0-1`, binutils `2.46.90.20260712-1`, Python
`3.14.6-1`, Xorg server `2:21.1.23-1`, XFCE 4.20.  A Trixie guest would carry GCC 14
and glibc 2.41.

Two consequences follow.  Re-running the provisioning scripts today cannot reproduce
this image, because `sid` and `unreleased` are rolling and neither is pinned to
`snapshot.debian.org`; reproducibility needs a snapshot pin, not a re-run.  And the source configuration is
partial: `deb-src` names `deb.debian.org/debian sid main`, which is the normal
arrangement for an unofficial port, since `debian-ports` carries port binaries while
the shared source lives in the main archive.  What has no `deb-src` line is
`unreleased`, the one component that does hold port-specific sources, so the
port-local packages cannot be fetched as source from this configuration.

## The kernel is the uniprocessor Mach, so the SMP constraint measures nothing

`/boot` contains exactly one kernel, `gnumach-1.8-amd64-up.gz`, and every
`menuentry` in `/boot/grub/grub.cfg` multiboots it:

    multiboot /boot/gnumach-1.8-amd64-up.gz root=part:5:device:wd0

The package says so itself.  The `Description` field of
`gnumach-image-1.8-amd64-up` (`2:1.8+git20260224-11`) closes with "This kernel is for
use with uniprocessor support."  The metapackage `gnumach-image-1-amd64` depends on
that variant, so the archive's current default for `hurd-amd64` is the uniprocessor
build, and no SMP-capable image is installed.

The compose profiles and the README encode an SMP constraint against this guest:

* `compose.yaml:74` comments "CPU cores (Hurd 2025 has SMP support)" with
  `QEMU_SMP` defaulting to 2.
* `compose.minty.yaml:39` pins `QEMU_SMP: "2"`.
* `MINTY-HURD-README.md:163` records `-smp 2` because ">2 triggers IDE DMA
  'bus-master missing interrupt'".

Two statements follow, at different confidence.  Established: a uniprocessor Mach
does not schedule across additional processors, so the vCPUs beyond the first are
host-side QEMU threads this guest kernel never uses, and the recorded IDE DMA failure
cannot be explained by guest SMP because the guest has no SMP to implicate.
Hypothesis, not traced: that the residual coupling between vCPU count and
"bus-master missing interrupt" lies in QEMU's IDE emulation timing under added vCPU
threads.  That mechanism needs its own instrumented run before it is asserted.

The comment "Hurd 2025 has SMP support" at `compose.yaml:74` is true of Mach upstream
and false of this image.

The guest confirms it.  Booted through `compose.yaml -f compose.minty.yaml` with the
profile's `QEMU_SMP: "2"`, and with QEMU's own argv reading `-machine pc -accel kvm
-smp 2` and its monitor reporting `kvm support: enabled` alongside two vCPU threads
(`CPU #0`, `CPU #1`), the guest reports:

    # uname -a
    GNU debian 0.9 GNU-Mach 1.8+git20260224-up-amd64/Hurd-0.9 x86_64 GNU
    # nproc
    1

The kernel release string carries `-up-` itself, and `nproc` returns 1 while QEMU
presents two vCPUs.  Guest parallelism is one processor regardless of `QEMU_SMP`.

This reframes what a backend matrix arm can measure.  Varying `QEMU_SMP` measures
host-side QEMU behaviour, not guest scaling, because guest parallelism is fixed at one
processor whatever the arm sets.  Whether an SMP Mach changes that is untestable until
`gnumach-image-1.8-amd64` proper is installed alongside the `-up` image and selected
from GRUB.

The configuration itself is not implicated.  At the profile's `QEMU_SMP: "2"` the
guest booted to a stable login in 64 seconds and carried a 44-package upgrade to
completion with the filesystem clean afterwards.  The README's report that more than
two vCPUs triggers "bus-master DMA error: missing interrupt" was neither reproduced
nor tested here, since no arm above two was run.

## What the image contains

738 packages are installed: 604 native `hurd-amd64` and 134 `all`, which confirms the
documented "700+" and locates the Mint contribution in the architecture-independent
set.  `libxapp1` and `gir1.2-xapp-1.0` are `hurd-amd64` native builds, so XApp was
compiled for Hurd rather than pulled in as data.

| Component | Version |
| --- | --- |
| GNU Mach | `2:1.8+git20260224-11` (`-up` image) |
| Hurd | `1:0.9.git20260527-3+b1` |
| glibc (`libc0.3`) | `2.42-17` |
| Xorg server | `2:21.1.23-1` |
| `xserver-xorg-video-vesa` | `1:2.6.0-2` |
| XFCE | session 4.20.4, panel 4.20.7, xfwm4 4.20.0, xfdesktop 4.20.2 |
| GCC | `4:15.2.0-5+b1` (gcc-15 `15.3.0-1`) |
| binutils | `2.46.90.20260712-1` |
| Python | `3.14.6-1` |
| OpenSSH server | `1:10.4p1-1` |
| x11vnc / Xvfb | `0.9.17-3` / `2:21.1.23-1` |

`/etc/hurd-desktop.mode` is `vnc`, so the shipped image boots the Xvfb + x11vnc path;
the Xorg/VESA path is installed and selectable but is not the default state.

Disk geometry from `statvfs`: 3916928 blocks of 4096 bytes with 2810292 available,
which is the documented 16 GiB disk with roughly 11 GiB free.  Partitioning is
`sda1` swap (999 MB) and `sda5` ext2 (16.2 GB), matching the guest's `wd0s5`.

Mint presentation packages present: `mint-themes` 2.3.8, `mint-l-theme` 2.0.6,
`mint-y-icons` 1.9.2-1, `mint-x-icons` 1.7.5, `mint-l-icons` 1.8.0,
`mint-cursor-themes` 1.0.2, `mint-artwork` 1.9.3, `mint-backgrounds-wilma` 1.1,
`linuxmint-keyring` 2022.06.21, and the XApp stack at 3.2.2-1.  This matches the
whitelist in `MINTY-HURD-README.md:220`.

## Three defects block the documented Minty boot

`compose.minty.yaml` set `QEMU_HOSTFWDS` as a YAML folded scalar (`>-`), which turns
each newline into a space.  QEMU received `hostfwd= udp::60002-:60002` and refused to
start: `Invalid host forwarding rule ' udp::60002-:60002' (Bad protocol name)`.  The
container then crash-looped.  The value has to be one unbroken line, because the
entrypoint splits it on commas and appends each element to `hostfwd=`.

`compose.minty.yaml` declares a service named `hurd`, while `compose.yaml` declares
`gnu-hurd-dev`.  The second file therefore adds a service rather than overriding the
first, so the documented `docker compose -f compose.yaml -f compose.minty.yaml up -d`
and `make minty-up` (`Makefile:314`) both start two containers.  The extra one pulls
`ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest`, which no workflow publishes,
and would otherwise boot `debian-hurd-amd64.qcow2` with `FORCE_KVM: "0"`.  Booting
only the intended guest requires naming it: `up -d hurd`.

The root filesystem was dirty.  On first boot `fsck` reported deleted inodes with
zero dtime, exited status 3, and the boot script asked for a restart that failed, so
the guest never reached `sshd`.  Preen mode could not finish the repair --
`e2fsck: /dev/sda5: Missing '.' in directory inode 578181` -- and a full
non-interactive pass was required.  What is verified is that this working file was
dirty; the published artifact was not itself checked.  Since the release is a
`qemu-img convert` of this file, it carries whatever filesystem state the source held
at convert time, which makes a clean-shutdown-and-fsck gate worth putting in the
release path.

## Guest access is gated by the OOBE flow

`root` and `user` both sit at `chage -d 0` ("password must be changed", account
expiry never).  Key-based SSH authenticates and is then refused: "You are required to
change your password immediately (administrator enforced) ... Password change
required but no TTY available."  Non-interactive automation against a published image
cannot proceed without either an interactive first login or lifting the aging field.
That is correct behaviour for a distributed image and a hard stop for any unattended
gate, so the two intentions need separating rather than one silently defeating the
other.

## LMDE has no suite to pair with sid, and its staging components are empty

Linux Mint publishes release codenames only; `gigi` is the newest and its `Release`
is current.  There is no rolling suite to track alongside `debian-ports sid`.

`gigi` does advertise `Components: main upstream import backport romeo incoming`, and
`romeo` (packages not promoted to main) plus `incoming` (the upload queue) look like
the nearest equivalent.  They are empty.  The `gigi` `Release` file lists
`romeo/binary-amd64/Packages` and `incoming/binary-amd64/Packages` at 0 bytes, with
the empty-input digests `d41d8cd98f00b204e9800998ecf8427e` and
`da39a3ee5e6b4b0d3255bfef95601890afd80709`, against 60923 bytes for
`main/binary-amd64/Packages`.  Adding them to the sources line changes nothing: apt
loads `c=main`, `c=upstream`, `c=import`, `c=backport` and no `c=romeo` or
`c=incoming` entry appears in `apt-cache policy`.

deb-multimedia.org does publish a `sid` suite, but its architectures are `all`,
`amd64`, `arm64`, `armhf`, `i386`, `powerpc`, and `riscv64`.  It builds no
`hurd-amd64`, so it can offer this guest only `Architecture: all` packages whose
companion binaries never resolve.

## The upgrade

Run against `debian-ports sid` + `unreleased` with the guest booted under
`-accel kvm -smp 2`: 44 packages installed or upgraded, zero removals, and
`apt-get full-upgrade` exited 0 with `dpkg -C` reporting nothing broken.  The
installed count moved from 738 to 740.

`gnumach-image-1.8-amd64-up`, `hurd`, `libc0.3`, `xserver-xorg-core`, and
`xserver-xorg-video-vesa` all held their versions, so the `Breaks:` relationships on
the kernel package were never engaged.  The upgrade covered perl 5.40.1 to 5.42.2-3,
the gcc-15 toolchain to 15.3.0-2, `openssh-server` to 1:10.4p1-2, XApp to 3.2.2-2,
thunar, and `python3-pil`.  XFCE 4.20.4 and the Mint presentation packages
(`mint-themes` 2.3.8, `mint-l-theme` 2.0.6) are unchanged.

The guest was halted rather than killed, and an offline preen pass afterwards
reported the filesystem clean.

## Reproducibility gaps this leaves open

The 10.2 GB `images/hurd-working.qcow2` is untracked, no manifest ties any of the six
files in `images/` to a commit, and the release asset is a flattening of a local file
whose snapshot history lives nowhere else.  Pinning `snapshot.debian.org` in
`scripts/lmde7-apt-setup.sh` and recording the archive timestamp alongside the image
digest would make the rebuild reproducible; nothing short of a pin will, because the
guest tracks `sid` and `unreleased`.
