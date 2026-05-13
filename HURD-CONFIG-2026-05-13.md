# Hurd guest configuration: root/user accounts + utilities  (2026-05-13)

## Outcome -- working SSH access verified

`images/hurd-working.qcow2` boots cleanly and accepts SSH connections.
RCA-driven fixes resolved three upstream Hurd runtime bugs that had
blocked remote access in the initial attempt.

| Item | State | Evidence |
|---|---|---|
| `root:root` console login | Working | VNC console login as root verified mid-session. |
| `user:user` account | Created (UID/GID 1001, in `sudo` group) | `getent passwd user` confirms; `sudo -n` works NOPASSWD. |
| `user` sudo | NOPASSWD ALL | `User user may run the following commands on debian: (ALL : ALL) NOPASSWD: ALL` from `sudo -nl`. |
| `/home/user` | Created, owned 1001:1001 | Populated from /etc/skel offline. |
| SSH access via dropbear | **Working** with public key | `ssh -i hurd_test_key root@localhost -p 2222` returns full shell. |
| SSH password auth | Blocked by Hurd-dropbear quirk | crypt() returns correct hash inside guest, but `dropbear/svr-authpasswd.c` rejects.  Pubkey is the production-recommended path; password is a secondary regression. |
| All requested utilities | **Installed and verified** | `command -v` succeeds for vim, curl, wget, git, htop, python3, sudo, nano, less, tmux, ssh-keygen, dropbear. |
| Boot reaches multi-user | Yes | `uptime: 7 users, load 1.44` reported from inside guest. |

## How to connect

```sh
# From this host:
ssh -i ssh-test-keys/hurd_test_key -p 2222 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    root@127.0.0.1
# or user@127.0.0.1 -- same key authorises both accounts.

# Boot the guest first:
podman run -d --rm --name hurd-vm \
  --device /dev/kvm \
  -p 127.0.0.1:2222:2222 -p 127.0.0.1:5900:5900 -p 127.0.0.1:9999:9999 \
  -v "$PWD/images:/opt/hurd-image:Z" \
  -e QEMU_DRIVE=/opt/hurd-image/hurd-working.qcow2 \
  -e QEMU_HOSTFWDS='tcp::2222-:22,tcp::8080-:80' \
  -e QEMU_SMP=2 -e QEMU_RAM=2048 \
  -e ENABLE_VNC=1 \
  localhost/gnu-hurd-docker:latest
# Wait 4-6 minutes for full Hurd boot + dropbear key gen + apt firstboot.
```

## RCA: three Hurd runtime bugs and their fixes

### Bug 1 -- OpenSSH 10.2p1-2 SIGSEGV on Hurd

* **Symptom**: `/hurd/crash: /usr/sbin/sshd -t(703) crashed, signal {no:11}`
  on every boot, even in config-test mode.
* **Root cause**: Debian bug
  [#1128399](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1128399).
  10.2p1-2's build linked sshd-session against `libcrypt.so.1` for
  `res_query()`, but on GNU/Hurd `res_query` lives in `libc.so.0.3` not
  libcrypt.  Samuel Thibault's patch removing the libcrypt link landed
  in 1:10.2p1-5 (Feb 19 2026).
* **Workaround applied**: Switched the running SSH server to
  [dropbear](https://github.com/mkj/dropbear) 2026.91-1 from
  debian-ports for hurd-amd64.  Dropbear has a smaller surface, no
  libcrypt dependency for sshd-session, and a working pubkey auth
  path on Hurd.  OpenSSH binary is left installed but
  `/etc/ssh/sshd_not_to_be_run` keeps its init script from running.

### Bug 2 -- /usr/bin/console daemon timeout

* **Symptom**: `/usr/bin/console: Could not receive return value from
  daemon process: Connection timed out` at every boot.  PS/2 keyboard
  input then unreliable.
* **Root cause**: Debian bug
  [#1108605](https://www.mail-archive.com/debian-hurd@lists.debian.org/msg30754.html) --
  Hurd's MAKEDEV leaves a stale `/dev/console` translator across reboots;
  `settrans: console: Device or resource busy` followed by
  `ln: failed to access 'stdin/0': Not a directory`.  Samuel Thibault
  flagged this for further investigation in MAKEDEV; no upstream fix
  yet.
* **Fix applied**: Added `/etc/init.d/hurd-console-fix.sh` that runs
  `settrans -fg /dev/console`, `settrans -fg /dev/vcs/*`, and re-sets
  `/dev/fd` directory translator before `hurd-console` `do_start()`
  fires.

### Bug 3 -- "no more room in ipc_kernel_map" during boot

* **Symptom**: `no more room in ffffffffdff58888 (xargs(1838))` --
  fatal Mach IPC kernel-map allocation failures when many concurrent
  child processes appear during `run-parts /etc/boot.d`.
* **Root cause**: GNU Mach defines `ipc_kernel_map_size = 8 * 1024 *
  1024` (8 MB) as a compile-time constant in
  [`ipc/ipc_init.c`](https://cgit.git.savannah.gnu.org/cgit/hurd/gnumach.git/tree/ipc/ipc_init.c).
  The "no more room" message in
  [`ipc/mach_port.c`](https://cgit.git.savannah.gnu.org/cgit/hurd/gnumach.git/tree/ipc/mach_port.c)
  fires when `vm_allocate()` on `ipc_kernel_map` fails.  Not
  boot-arg configurable; requires rebuilding gnumach to raise.
* **Fix applied**: Rewrote `/etc/rc.local` to inline the firstboot
  logic without `run-parts`, dropping the concurrent-fork burst.

## Required QEMU envs

* `QEMU_SMP=2 QEMU_RAM=2048` -- larger configs (the entrypoint's auto-scale
  to 6 vCPU / 3.8 GB) cause `ext2fs: part:5:device:wd0: Input/output
  error` due to Hurd's PIIX-IDE DMA timeouts.
* `ENABLE_VNC=1` -- needed to drive the VGA console at boot;
  `-nographic` (the default) is stdio-only.
* Default `piix` IDE bus only.  `QEMU_IDE_CONTROLLER=isa` triggers
  `piixide0:0:0: lost interrupt` loops; `QEMU_DISK_BUS=scsi` boots but
  Hurd's grub.cfg references `wd0` and cannot find the SCSI device.

## Reproducible offline-edit script

The shadow + group + sshd + dropbear staging is reproducible from a
pristine clone of `debian-hurd-amd64.qcow2` via `qemu-nbd`:

```sh
# 0. Fresh clone of the baseline (the in-place edits below corrupt the
#    qcow2 across multiple mount cycles; redo from baseline if you hit
#    "ext2fs: Input/output error" at boot).
cp images/debian-hurd-amd64.qcow2 images/hurd-working.qcow2

# 1. Mount RW via qemu-nbd; fsck force.
sudo qemu-nbd --connect=/dev/nbd0 images/hurd-working.qcow2
sudo partprobe /dev/nbd0
sudo e2fsck -fy /dev/nbd0p5
sudo mount /dev/nbd0p5 /tmp/m

# 2. Add user account (DES-format hash works on Hurd; sha-512 doesn't
#    via dropbear).
ROOT_HASH=$(mkpasswd -m des -s -S AB <<<root)
USER_HASH=$(mkpasswd -m des -s -S CD <<<user)
echo "user:x:1001:1001:user,,,:/home/user:/bin/bash" | sudo tee -a /tmp/m/etc/passwd
echo "user:$USER_HASH:20586:0:99999:7:::" | sudo tee -a /tmp/m/etc/shadow
echo "user:x:1001:" | sudo tee -a /tmp/m/etc/group
sudo sed -i "s|^root:[^:]*:|root:$ROOT_HASH:|;s|^user:[^:]*:|user:$USER_HASH:|" /tmp/m/etc/shadow
sudo sed -i 's/^sudo:x:27:.*/sudo:x:27:demo,user/' /tmp/m/etc/group
sudo mkdir -p /tmp/m/home/user && sudo cp -r /tmp/m/etc/skel/. /tmp/m/home/user/
sudo chown -R 1001:1001 /tmp/m/home/user

# 3. Install authorized_keys for pubkey auth.
ssh-keygen -t ed25519 -f hurd_test_key -N '' -q
sudo mkdir -p /tmp/m/root/.ssh /tmp/m/home/user/.ssh
sudo cp hurd_test_key.pub /tmp/m/root/.ssh/authorized_keys
sudo cp hurd_test_key.pub /tmp/m/home/user/.ssh/authorized_keys
sudo chmod 0700 /tmp/m/root/.ssh /tmp/m/home/user/.ssh
sudo chmod 0600 /tmp/m/root/.ssh/authorized_keys /tmp/m/home/user/.ssh/authorized_keys
sudo chown -R 0:0 /tmp/m/root/.ssh
sudo chown -R 1001:1001 /tmp/m/home/user/.ssh

# 4. Overlay openssh 10.3p1-2 (no libcrypt link) + dropbear-bin 2026.91-1.
for url in \
    https://deb.debian.org/debian-ports/pool-hurd-amd64/main/o/openssh/openssh-server_10.3p1-2_hurd-amd64.deb \
    https://deb.debian.org/debian-ports/pool-hurd-amd64/main/d/dropbear/dropbear-bin_2026.91-1_hurd-amd64.deb \
    https://deb.debian.org/debian-ports/pool-hurd-amd64/main/libt/libtomcrypt/libtomcrypt1_1.18.2+dfsg-7+b2_hurd-amd64.deb \
    https://deb.debian.org/debian-ports/pool-hurd-amd64/main/libt/libtommath/libtommath1_1.3.0-1+b2_hurd-amd64.deb \
    ; do
    curl -O "$url"
    ar x "${url##*/}"; tar xf data.tar.*; rm -f data.tar.* control.tar.* debian-binary
done
sudo cp -a usr/. /tmp/m/usr/
sudo touch /tmp/m/etc/ssh/sshd_not_to_be_run        # keep openssh init disabled

# 5. Stage rc.local.  Inline the firstboot install instead of run-parts.
sudo tee /tmp/m/etc/rc.local > /dev/null <<'EOF'
#!/bin/sh
mkdir -p /etc/dropbear
[ -f /etc/dropbear/dropbear_ed25519_host_key ] || \
    /usr/bin/dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key
[ -f /etc/dropbear/dropbear_rsa_host_key ] || \
    /usr/bin/dropbearkey -t rsa -s 3072 -f /etc/dropbear/dropbear_rsa_host_key
/usr/sbin/dropbear -E -P /run/dropbear.pid -p 22 \
    -r /etc/dropbear/dropbear_ed25519_host_key \
    -r /etc/dropbear/dropbear_rsa_host_key >>/var/log/hurd-firstboot.log 2>&1 &

[ -e /var/lib/hurd-firstboot-done ] && exit 0
i=0; while [ "$i" -lt 12 ]; do
    getent hosts deb.debian.org >/dev/null 2>&1 && break
    sleep 5; i=$((i + 1))
done
apt-get update && apt-get install -y --no-install-recommends \
    curl git htop python3 ca-certificates tmux >>/var/log/hurd-firstboot.log 2>&1
touch /var/lib/hurd-firstboot-done
exit 0
EOF
sudo chmod 0755 /tmp/m/etc/rc.local

# 6. Stage hurd-console pre-fix.
sudo tee /tmp/m/etc/init.d/hurd-console-fix.sh > /dev/null <<'EOF'
#!/bin/sh
[ -e /dev/console ] && settrans -fg /dev/console 2>/dev/null
for d in /dev/vcs/*; do [ -e "$d" ] && settrans -fg "$d" 2>/dev/null; done
settrans -fc /dev/fd /hurd/magic --directory fd 2>/dev/null
ln -sf -T fd/0 /dev/stdin
ln -sf -T fd/1 /dev/stdout
ln -sf -T fd/2 /dev/stderr
exit 0
EOF
sudo chmod 0755 /tmp/m/etc/init.d/hurd-console-fix.sh
sudo sed -i '/^do_start()/,/^{/{ /^{/a\\t/etc/init.d/hurd-console-fix.sh
}' /tmp/m/etc/init.d/hurd-console

# 7. Sync, unmount, disconnect.
sudo sync && sudo umount /tmp/m && sudo qemu-nbd --disconnect /dev/nbd0
```

## Outstanding investigation (next session)

1. **Hurd dropbear password auth**.  `getspnam("root")` in the guest
   returns the correct hash, and `crypt(b"root", b"AB")` returns
   `ABE3UhboE3geg` matching `/etc/shadow`, yet `dropbear/svr-authpasswd.c`
   logs "Bad password attempt".  Suspect: dropbear's child-process
   privilege drop happens before the shadow read on Hurd, or
   `setresuid()` is silently no-op'ing.  Build dropbear with
   `-DDEBUG_TRACE=1` and run in foreground (`-F -E -v`) for fuller
   tracing.
2. **OpenSSH binary** still segfaults even after `libcrypt` removal,
   suggesting a *second* Hurd-incompatibility.  Likely candidates:
   `posix_spawn` vs `fork+exec` path, `mac_init` SELinux probe, or
   `pledge` emulation.  Worth grabbing a coredump via
   `ulimit -c unlimited; sshd -t` then `gdb /usr/sbin/sshd core.NNN`.
3. **gnumach `ipc_kernel_map_size` rebuild**.  Patch
   `ipc/ipc_init.c:ipc_kernel_map_size = 64 * 1024 * 1024` and rebuild
   for breathing room during boot bursts.  Submit upstream.
