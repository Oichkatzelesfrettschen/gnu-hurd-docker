# umm so I think there's something weird going on with openssl/libcrypto sha512 on hurd?

**I wanna file this against debian's openssl (with usertag hurd) and
maybe poke `bug-hurd@gnu.org` too?  apologies in advance if I'm
missing something obvious, this is my first real hurd bug report and
I'm not super confident.**

## what I think is happening

so I was just trying to get openssh-server running in a debian
gnu/hurd guest under podman+qemu (no special reason, just thought it
would be cool to be able to ssh into hurd from my linux host).  pubkey
auth works fine when I start sshd by hand from a terminal, BUT
`/etc/init.d/ssh start` always crashes it like this:

```
Starting OpenBSD Secure Shell server: sshd Segmentation fault
 failed!
```

and the qemu console scrolls something like
```
/hurd/crash: /usr/sbin/sshd -D(725) crashed, signal {no:11, code:1, error:1},
    exception {1, code:1, subcode:36388864}, PCs: {
        0x101442a0c 0x12835b0145706fbe,
        0x1016eec2c
    }, killing task.
```

I tried 10.2p1-2 and 10.3p1-2 (both from debian-ports for hurd-amd64),
same crash.

## what gdb shows

with `gdb -ex "run -t"` against `/usr/sbin/sshd` plus the dbgsym
package for symbols:

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
```

registers at the crash are full of high-entropy garbage:
```
rax=0x1462e1e21c29dfed  rbx=0xfc40fc58d83da3cd
rcx=0xc9640911dc78a0b   rdx=0x2f97795f1e653863
```

so... it's not in sshd at all, it's in libcrypto's sha-512 inner
loop?  which is weird because sshd parses its config and validates
hostkeys via sha-512 during `-t` mode.

## the thing that makes the crash go away

setting `OPENSSL_ia32cap="~0:0"` (which kinda means "pretend the cpu
has no fancy features") before launching sshd makes it run fine:

```
$ OPENSSL_ia32cap="~0:0" /etc/init.d/ssh start
Starting OpenBSD Secure Shell server: sshd.
```

I've made it permanent by putting
```
export OPENSSL_ia32cap="~0:0"
```
at the top of `/etc/default/ssh`.

## why this maybe points at something deeper

this only happens when sshd is launched through `start-stop-daemon`
(double-fork daemonize).  if I just run `sshd -D` directly in my
terminal, no crash, even WITHOUT the env var.  so it's something
about the daemonized-child state.

my admittedly-uneducated guess: gnu mach's user-thread context save
might not be copying the full xsave state (ymm high-halves, sha-ni
state, etc) across fork into the orphan daemon child.  then
libcrypto's runtime cpuid detection at *load* time (in the parent)
decided "hey we have aes-ni / avx, let's use the fast path", but the
daemon child no longer has the xmm/ymm state it needs and reads from
garbage register content.

things in gnumach that might be worth a look:
* `i386/i386/fpu.c` -- check `fpinherit()`'s XSAVE_AREA handling
* `kern/thread.c:thread_create` -- whether `pcb->ims.ifps` (the FP
  state pointer) is cloned for daemon children

I didn't have time/skill to actually trace into gnumach to prove
this, sorry.  if a real hurd kernel dev wants to take it from here
I'd super appreciate it.

## reproducer

* `debian-hurd-amd64.qcow2` baseline (Jan 2026)
* qemu-system-x86_64 `-machine pc -cpu max -smp 2 -m 2048`
* openssh-server 1:10.2p1-2 or 1:10.3p1-2 from debian-ports/hurd-amd64
* `apt-get install openssh-server && /etc/init.d/ssh start`

cpu flags from `/proc/cpuinfo` in the guest:
```
fpu de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36
clflush acpi mmx fxsr sse sse2 ss ht sse3 pclmulqdq monitor ssse3
fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave osxsave avx f16c rdrand
hypervisor
```
(no sha-ni in this list which is interesting -- maybe libcrypto's
sha-512 picks the avx path?)

## also worth mentioning

I did separately test that crypt/getpwnam work fine inside the same
hurd guest (with a tiny C program that calls crypt + getpwnam --
the hash compares cleanly).  so it's not "everything's broken on
hurd", just this specific libcrypto code path under daemonized fork.

## affected

* libssl3t64 3.5.4-1 (from debian-ports unstable)
* openssh-server 1:10.2p1-2 and 1:10.3p1-2
* gnumach 1.8+git20250731 amd64
* glibc 2.41+hurd.X
* start-stop-daemon (dpkg 1.22+)
* qemu x86_64 tcg `-cpu max`

## not affected

* same openssh binaries on linux amd64
* dropbear from debian-ports (uses libtomcrypt, not libcrypto)
* sshd started directly from interactive shell on hurd

---

**disclaimer**: I used a large language model (claude) to help me
chase this down, including running gdb in the guest, comparing
binaries before/after the libcrypt link removal, and reading gnumach
ipc code.  the conclusions are based on what we observed and what I
think is happening, but a real hurd dev would be way better at
confirming the gnumach side of things.  the goal here was just to get
ssh working into my hurd-under-podman setup on my own linux machine,
and once I found the `OPENSSL_ia32cap` workaround I figured I should
write this up since searching didn't turn up an existing bug.  if
something's wrong or I'm misreading the trace please just say so,
no offense taken.  thanks!
