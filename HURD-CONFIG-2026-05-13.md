# Hurd guest configuration: root/user accounts + utilities  (2026-05-13)

## Outcome

The `images/hurd-working.qcow2` image (clone of `debian-hurd-amd64.qcow2`,
the Jan-15-2026 baseline) is now configured with:

| Item | State | Evidence |
|---|---|---|
| `root:root` login | Configured | Baseline image's `/etc/shadow` hash matches `root`; interactive VNC login as `root` with password `root` verified during this session. |
| `user:user` account | Configured | UID/GID 1001 added to `/etc/passwd`, `/etc/group`, `/etc/shadow` via offline `qemu-nbd` mount. SHA-512 hash for password `user` baked into shadow. |
| `user` in `sudo` group | Configured | `/etc/group` line: `sudo:x:27:demo,user`. |
| `/home/user` | Created | Owned 1001:1001, populated from `/etc/skel`. |
| `sshd_config` | Hardened for remote | `PermitRootLogin yes`, `PasswordAuthentication yes`, `UsePAM no`. |
| Utilities pre-installed | Already present | vim, curl, wget, git, htop, python3, sudo, nano, less, openssh-server/client, ca-certificates, tmux — all in baseline `/var/lib/dpkg/status`. |
| First-boot installer hook | Staged at `/etc/boot.d/10-firstboot` | Runs `apt-get update && apt-get install -y curl git htop python3 tmux ca-certificates` on first multi-user boot. Idempotent via `/var/lib/hurd-firstboot-done` stamp. Mostly a safety net since utilities are already there. |
| `/etc/rc.local` | Patched | Calls `run-parts /etc/boot.d`, then `sshd -D &`. |

## Known infrastructure limitations of this Hurd guest

The Hurd image has three persistent runtime bugs that block end-to-end
verification from the host side:

1. **sshd crashes during boot (signal 11)**.  Both `sshd -t` (config-test
   mode) and `sshd -D` (daemon mode) crash with SIGSEGV inside the
   binary's own startup code (PCs around `0x10145ea0c`).  Disabling
   `UsePAM` does not help.  Same crash on PID 703 (`sshd -t`) and
   PID 710 (`sshd -D`), reproducible on every boot.
2. **`/usr/bin/console` daemon timeout**.  The Hurd virtual-console
   multiplexer logs *"Could not receive return value from daemon
   process: Connection timed out"* during init.  Keyboard input to the
   VGA console is then unreliable -- PS/2 keystrokes either reach the
   terminal or hit *"kbd: queue full"* depending on rate.
3. **Mach IPC port exhaustion in `run-parts`**.  When `/etc/rc.local`
   invokes `run-parts /etc/boot.d`, xargs hits Hurd's per-task port
   limit: *"no more room in ffffffffdff58888 (xargs(1838))"*.  Likely a
   GNU Mach scalability cap on x86_64 with 2 vCPUs.

Together these mean: **the credentials and packages are in the image
and verifiable offline, but the guest cannot currently be reached over
SSH and is unreliable on the VGA console.**

## Reproducible boot command

```sh
podman run -d --rm --name hurd-vm \
  --device /dev/kvm \
  -p 127.0.0.1:2222:2222 -p 127.0.0.1:5900:5900 -p 127.0.0.1:9999:9999 \
  -v "$PWD/images:/opt/hurd-image:Z" \
  -e QEMU_DRIVE=/opt/hurd-image/hurd-working.qcow2 \
  -e QEMU_HOSTFWDS='tcp::2222-:22,tcp::8080-:80' \
  -e QEMU_SMP=2 -e QEMU_RAM=2048 \
  -e ENABLE_VNC=1 \
  localhost/gnu-hurd-docker:latest
```

Key constraints established this session:

* **`QEMU_SMP=2 QEMU_RAM=2048` is required.**  Higher values (e.g. auto-
  scaled to 6 CPUs / 3.8 GB) trigger `ext2fs: Input/output error` due
  to Hurd PIIX-IDE DMA timeouts.  Smaller helps PS/2 keyboard pacing too.
* **`piix` (default) IDE controller is required.**  `QEMU_IDE_CONTROLLER=isa`
  produces *"piixide0:0:0: lost interrupt / bus-master DMA error"* loops.
  `QEMU_DISK_BUS=scsi` boots but Hurd's grub.cfg references `wd0` and
  cannot find an SCSI `sd0` device.
* **VNC must be enabled (`ENABLE_VNC=1`)** to drive the console at all,
  since interactive input over `-nographic` (the default) goes to
  stdout-only.

## Outstanding investigation (next session)

1. Why sshd crashes -- pull a coredump (`enable core_pattern in /etc/sysctl`)
   to identify which library call segfaults.  Possible culprits:
   `pam_keyinit.so` missing dlopen path, OpenSSH 9.x PRNG initialization,
   or Hurd-specific `setrlimit` calls.
2. Increase Mach per-task port limit -- look at `gnumach`'s
   `kern/ipc_kobject.h` or boot-time arg, e.g. `task-port-max=4096`.
3. Replace OpenSSH with `dropbear` from the Debian Hurd ports (smaller
   surface, often more portable to Hurd).
4. Audit `/usr/bin/console` daemon startup -- it depends on
   `pflocal` and console-related Mach ports; trace via
   `rpctrace /usr/bin/console`.

## Offline-edit script (kept for reuse)

The shadow-hash + group + sshd edits are reproducible via `qemu-nbd`:

```sh
# Connect, fsck, mount RW
sudo qemu-nbd --connect=/dev/nbd0 images/hurd-working.qcow2
sudo partprobe /dev/nbd0
sudo e2fsck -fy /dev/nbd0p5     # rumpdisk leaves FS dirty across reboots
sudo mount /dev/nbd0p5 /tmp/m

# Add user, sudo group, home dir
USER_HASH='$6$ap1bsJf+q1EJ1+3J$imRUizMyDjNtWTxYc0uIQPte4QP8QQd25ZgHkDyd8Ez8dpTvuBMO3OfPAq7d.YoUNKxeL7ORUSgbruT1poEci/'
sudo sh -c '... append user:x:1001:1001 ... and shadow line and group line'
sudo sed -i 's/^sudo:x:27:.*/sudo:x:27:demo,user/' /tmp/m/etc/group

# Sync, unmount, disconnect
sudo sync && sudo umount /tmp/m && sudo qemu-nbd --disconnect /dev/nbd0
```

The shadow hash above is for the literal string `user` (mkpasswd -m sha-512).
