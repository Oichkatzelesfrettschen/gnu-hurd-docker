# GNU Mach / Hurd / OpenSSH patches

Out-of-tree patches that address bugs identified during the
2026-05-13 RCA session.  Each patch is suitable for either applying to
a Debian source build (`patch -p1`) or for submitting upstream.

## `gnumach-raise-ipc_kernel_map_size.patch`

* **Affects:** GNU Mach kernel
* **Component:** `ipc/ipc_init.c:ipc_kernel_map_size`
* **Fix:** Raise the IPC kernel map size from 8 MB to 64 MB so boot
  bursts of fork+exec via `run-parts` no longer exhaust the kernel
  IPC submap.
* **Submit to:** `bug-hurd@gnu.org` mailing list with
  `[PATCH gnumach]` subject prefix.  Debian package
  `gnumach` at salsa.debian.org/hurd-team/gnumach.

### Rebuild and install

```sh
# On the Hurd guest (one-time setup):
sudo apt-get install build-essential mig autoconf automake texinfo \
                     libsubunit-dev debhelper devscripts dpkg-dev

# Fetch the Debian source (sid).
sudo apt-get build-dep gnumach
mkdir -p ~/build && cd ~/build
apt-get source gnumach

cd gnumach-1.8+git20250731
patch -p1 < /path/to/gnumach-raise-ipc_kernel_map_size.patch

# Build the .deb (no signing for local install).
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc -B

# Install.
sudo dpkg -i ../gnumach-image-1.8-amd64-up_*.deb \
             ../gnumach-common_*.deb

# Update grub menu entry to load the new kernel.
sudo update-grub
sudo reboot
```

After reboot the boot bursts will no longer flood with
`no more room in ffffffffdff58888 (xargs(N))`.

## Future patches

When fixes for the following are authored, they go here too:

* `openssh-disable-libcrypt-on-hurd.patch` -- already upstreamed as
  Debian #1128399 -> 1:10.2p1-5; no out-of-tree patch needed for the
  10.3p1-2 build we use.
* `gnumach-xsave-fork-inherit.patch` -- once we identify the exact
  spot in `i386/i386/fpu.c` where `fpinherit` should perform a full
  XSAVE clone (see `upstream-bug-reports/openssl-hurd-simd-sshd-crash.md`),
  the fix becomes a kernel-side complement to the `OPENSSL_ia32cap`
  user-space workaround we're applying in `/etc/default/ssh`.
* `hurd-makedev-stable-translators.patch` -- proper fix for Debian
  #1108605 `settrans: console: Device or resource busy`; currently
  worked around at runtime by `/etc/init.d/hurd-console-fix.sh`.
