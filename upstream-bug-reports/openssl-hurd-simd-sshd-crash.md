# Upstream bug report: OpenSSL 3.5.4 SHA512_Update SIGSEGV on GNU/Hurd

**To file:** Debian BTS against `src:openssl` with usertag `hurd`, and
upstream at https://github.com/openssl/openssl/issues, plus cc to
bug-hurd@gnu.org.

## Summary

OpenSSH 10.3p1-2 and other OpenSSL-linked daemons crash with SIGSEGV
inside `libcrypto.so.3:SHA512_Update` on Debian GNU/Hurd 0.9 (gnumach
1.8 amd64) when started via `/etc/init.d/ssh` or any process tree that
goes through `start-stop-daemon`.  Direct invocation of the same binary
in an interactive shell does NOT crash.

Setting the environment variable `OPENSSL_ia32cap="~0:0"` disables
all CPU-feature-driven optimizations in libcrypto and makes the crash
disappear.  This points to a buggy SIMD/SHA-NI/AVX code path in
libcrypto interacting with how GNU Mach saves/restores extended
register state across process forks initiated by `start-stop-daemon`'s
double-fork daemonization.

## Reproduction

Debian GNU/Hurd 0.9 / gnumach 1.8 / glibc 2.41+hurd.X / openssl 3.5.4-1
(libssl3t64), QEMU x86_64 TCG.  Image:
`gnu-hurd-docker/images/hurd-working.qcow2` (clone of the Jan-2026
baseline) with openssh-server 1:10.3p1-2 from debian-ports.

1. `apt-get install openssh-server` (or use the in-image package).
2. `/etc/init.d/ssh start`

Result:
```
Starting OpenBSD Secure Shell server: sshd Segmentation fault
 failed!
```

QEMU monitor screendump shows the kernel-level crash message:
```
/hurd/crash: /usr/sbin/sshd -D(725) crashed, signal {no:11, code:1, error:1},
    exception {1, code:1, subcode:36388864}, PCs: {
        0x101442a0c 0x12835b0145706fbe,
        0x1016eec2c
    }, killing task.
```

GDB attached to a manual `sshd -t` invocation captures the same
crash:
```
Thread 2 received signal SIGSEGV, Segmentation fault.
0x0000000101442a0c in ?? () from /usr/lib/x86_64-gnu/libcrypto.so.3
#0  0x0000000101442a0c in ?? () from /usr/lib/x86_64-gnu/libcrypto.so.3
#1  0x00000001014447f8 in SHA512_Update () from /usr/lib/x86_64-gnu/libcrypto.so.3
#2  0x00000001012c47a6 in EVP_Digest () from /usr/lib/x86_64-gnu/libcrypto.so.3
#3  0x00000001000420c0 in ?? ()
#4  0x000000010002a3a2 in ?? ()
#5  0x000000010000a214 in ?? ()
#6  0x000000010173960b in __libc_start_main () from /usr/lib/x86_64-gnu/libc.so.0.3
#7  0x000000010000d1f1 in ?? ()
```

Registers at crash:
```
rax=0x1462e1e21c29dfed  rbx=0xfc40fc58d83da3cd  rcx=0xc9640911dc78a0b
rdx=0x2f97795f1e653863  rsi=0x1022b3f80         rdi=0x200000058810
rbp=0x1015a71c0         rsp=0x1010a8c80         r8=0xafb6f4aa9a7da070
r9=0xd7860efe5d4ddaed   r10=0xba04b0a777cce13c  r11=0x1d706f2c4d2ba335
r12=0x1022b3f80         r13=0x980ba0a552841c72  r14=0xdc388f53d3645c80
r15=0x712c0d6628829ec2  rip=0x101442a0c
```

The general-purpose registers contain wild high-entropy values
suggesting a state machine has been fed corrupt input.  This is
consistent with the SHA-512 SIMD inner loop reading from an
unaligned/garbage pointer (the value of `rdi` is in a high address
range that's canonical on x86_64 but unusual).

## Workaround (confirmed working)

Add to `/etc/default/ssh`:
```sh
export OPENSSL_ia32cap="~0:0"
```

This makes libcrypto fall back to the pure-C SHA-512 implementation
and the crash disappears.  Same workaround should help any
OpenSSL-linked daemon launched via `start-stop-daemon` (or similar
double-fork daemonizers) on Hurd.

```
$ /etc/init.d/ssh start
Starting OpenBSD Secure Shell server: sshd.
$ ssh -p 22 root@hurd-vm
[publickey auth succeeds]
$
```

## Hypothesis

GNU Mach's user-thread context save (saved on Mach `thread_get_state`
or implicit during fork) does not include the full x86_64 XSAVE
state.  Specifically, the YMM/ZMM high-halves and any SHA-NI or
PCLMUL state may not survive a daemonizing double-fork.  OpenSSL's
SHA-512 picks up that the host CPU supports `aes`, `xsave`, `avx`,
`pclmulqdq` (visible in `/proc/cpuinfo`) and selects a hand-coded
assembly path that uses those registers; when run from a daemonized
child whose extended state is clobbered, the path reads invalid data
and faults.

The `OPENSSL_ia32cap` workaround forces OpenSSL to use the pure-C path
which only touches the integer GPRs that Mach DOES save correctly.

Worth investigating in gnumach:
* `i386/i386/fpu.c` -- check FXSAVE/XSAVE in
  `fpinherit()` (called during fork) and `fpu_module_init()`.
* `kern/thread.c:thread_create` -- ensure inherited FP state covers
  YMM_HI, BNDREGS, BNDCSR, OPMASK, ZMM_HI256, HI16_ZMM,
  PT_STATE, PASID (i.e. the full XSAVE area for any CPU feature the
  host CPU advertises).

## Why the manual invocation works but init.d/ssh doesn't

When `sshd -t` is run from an interactive shell, the parent process
(the shell) preserves all extended state -- the child inherits a
properly-initialized FPU/XMM context.  When `start-stop-daemon`
double-forks and execs sshd, the extended state has been
"reinitialized" (or zeroed) for the orphan child, and libcrypto's
runtime CPUID detection then assumes the host's SIMD features are
usable in a context where the actual register state is corrupt.

The kernel-level fix is to ensure GNU Mach inherits XSAVE state
across all fork/exec paths; the OpenSSL-level workaround is the
environment variable.

## Affected components

* `libssl3t64` 3.5.4-1 (openssl 3.5.4 in debian-ports/sid for hurd-amd64)
* `openssh-server` 1:10.3p1-2 and earlier
* GNU Mach 1.8+git20250731 amd64
* `start-stop-daemon` (dpkg 1.22+)
* QEMU x86_64 TCG with `-cpu max` exposing AES-NI, AVX, F16C, PCLMUL

## Not affected

* Same binaries on Linux amd64
* OpenSSH started directly from interactive shell on Hurd
* Daemons that do not link libcrypto (e.g. dropbear linked against
  libtomcrypt instead)
