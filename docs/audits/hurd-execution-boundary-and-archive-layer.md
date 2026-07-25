# The Hurd execution boundary, and the archive layer that crosses it

Two layers were proposed: the QEMU virtual machine inside a container, which
exists, and Hurd running on Docker directly, which does not. This records the
probe that separates them, the layer that is buildable in place of the second,
and what that layer says about putting MATE on each Hurd port.

## Hurd userland cannot execute on a Linux host

A container shares the host kernel. Debian GNU/Hurd userland needs GNU Mach and
the Hurd servers, so the question is whether a Hurd binary can run against a
Linux kernel. The architecture is not the obstacle:

    $ file hurd/ext2fs
    ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked,
    interpreter /lib/ld-x86-64.so.1, ... for GNU/Hurd 0.0.0, stripped

The machine matches this host exactly. Two things differ. The interpreter is
`/lib/ld-x86-64.so.1`, which Debian GNU/Linux does not carry; it installs
`/lib64/ld-linux-x86-64.so.2`. And the shared libraries are `libdiskfs`,
`libports`, `libpager`, and `libstore`, whose operations are Mach RPC.

Running the binary gives the shallow failure:

    $ ./hurd/ext2fs --version
    cannot execute: required file not found

The decisive probe supplies the missing loader from the hurd-amd64 `libc0.3`
package, which separates the loader from the kernel interface:

    $ ./ld-x86-64.so.1 --version                            # rc=139
    $ ./ld-x86-64.so.1 --library-path . hurd/ext2fs         # rc=139

Status 139 is 128+11: SIGSEGV. The Hurd dynamic loader crashes on this kernel
before it loads any program, because its own startup issues Mach traps Linux
does not implement. The barrier is the kernel interface; installing files does
not move it.

Emulation does not close it either. `qemu-user` translates Linux system calls
for a foreign architecture; here the architecture already matches and the
missing element is Mach, which `qemu-user` does not provide. Full-system QEMU
does provide it, and that is the layer this repository already runs.

The falsifier is explicit: a Hurd binary that completes useful work in a
container with no `qemu-system-*` process refutes this. None did.

## The two ports

`hurd-i386` is the mature 32-bit port that the published Debian GNU/Hurd
releases are cut from. `hurd-amd64` is the newer 64-bit port and the one this
repository's guest runs. Both live on debian-ports, and neither has a `stable`
suite there: probing `stable`, `bookworm`, and `trixie` on both
`ftp.ports.debian.org` and `deb.debian.org` returns no index for either
architecture. The archive publishes `sid` and `unreleased` only, so every
closure below is resolved against a rolling target and a rerun after an upload
reports different numbers.

Binaries come from debian-ports. Source comes from the main Debian archive,
which is architecture-independent and serves both ports.

## The archive is data, and data crosses

`apt` and `dpkg` are ordinary Linux programs. `Dockerfile.hurd-archive` sets
`APT::Architecture` to the target port over a private apt state tree, so
dependency resolution runs against the real index without executing anything.

    make hurd-closure                                   # hurd-amd64, MATE core
    make hurd-closure HURD_ARCH=hurd-i386 HURD_SET=mate-full
    make hurd-closure HURD_SET=mint-visual

Mint supplies no Hurd binaries. LMDE 7 `gigi` advertises `i386` and `amd64` and
publishes no `binary-all` directory, so its `Architecture: all` payloads sit
inside the per-architecture indices. Taking a Mint index wholesale would offer
amd64 binaries to a Hurd architecture. The overlay keeps only the
`Architecture: all` stanzas and republishes them under the target architecture,
and a pin keeps Debian Ports authoritative for any name both carry. The overlay
contributes 152 architecture-independent Mint packages.

## What the archive says

### MATE session core

| Class | hurd-amd64 | hurd-i386 |
|---|---|---|
| native | 4 | 4 |
| architecture-all | 3 | 3 |
| uninstallable | 4 | 6 |
| missing | 2 | 0 |

`mate-session-manager`, `marco`, `mate-terminal`, and `mate-notification-daemon`
are native on both. The difference is the finding:

**`mate-settings-daemon` and `mate-control-center` have no hurd-amd64 binary at
all, and both exist for hurd-i386** at 1.26.1-1.2 and 1.26.0-2. Both are named
in the MATE acceptance gate, and `mate-desktop-environment-core` depends on
`mate-control-center (>= 1.26)`, so the metapackage is uninstallable for that
reason alone. A session without a settings daemon has no mechanism to apply the
theme, icon, and cursor selections the product is defined by.

The main archive carries `mate-settings-daemon` source at **1.26.1-1.2**, the
same version the hurd-i386 binary was built from. The hurd-amd64 gap is
therefore a build gap, not a porting gap: the source already builds on the Hurd,
and 64-bit simply has no upload.

On hurd-i386 the whole cascade reduces to one root cause. Every uninstallable
package there reports the same blocker:

    mate-polkit : Depends: polkitd but it is not installable

`polkitd` is absent for both ports, and so is the layer around it:

    accountsservice  libaccountsservice0  systemd  libsystemd0
    libelogind0      policykit-1          polkitd

This confirms by archive evidence what the architecture notes predicted: the
difficult boundary is session integration, not Caja or Marco, which are present
and native on both ports.

### Mint visual family

37 of 38 packages are `architecture-all` and install on hurd-amd64, pulling 105
packages recursively. The strategy works: Mint artwork reaches a Hurd desktop
unmodified.

`mintmenu` is the exception; it needs `python3-setproctitle`, which no Hurd port
builds. `mint-backgrounds` is published per release codename rather than per
suite, so the tool discovers those names from the archive rather than guessing
one, which is why an earlier hardcoded `mint-backgrounds-gigi` read as missing
when it never existed.

## Closing the gaps

Three tiers, in order of preference.

**Rebuild from source, when the source already builds for the other port.**
`scripts/build-hurd-package-in-guest.sh` adds a `deb-src` line for the main
archive, installs build dependencies, and runs `dpkg-buildpackage` on the guest.
This is the honest fix for `mate-settings-daemon`, `mate-control-center`, and
`python3-setproctitle`, whose sources are all present. It requires a snapshot
name and refuses to run without one, because the guest writes straight through
to the qcow2 and a failed build is exactly what a rollback is for.

    scripts/build-hurd-package-in-guest.sh \
        --snapshot pre-mate-rebuild-20260725 \
        mate-settings-daemon mate-control-center

**Stub the dependency, when it is genuinely unavailable and the VM does not need
it.** `scripts/make-hurd-dependency-stub.sh` builds an equivs package that
provides a name and none of its behavior. `polkitd` is the case: upstream polkit
tracks sessions through logind, the Hurd has no logind and no elogind build, and
on a single-user VM the authority polkit would arbitrate has one answer. The
stub records its reason in the package description, so `dpkg -s` on the guest
reports why it is there and what is missing.

    scripts/make-hurd-dependency-stub.sh --provides polkitd \
        --reason "polkit tracks sessions through logind; the Hurd has neither"

A stub supplies no behavior, and anything that calls the service fails at run
time -- later and less legibly than an install that refused. It is a claim about
the system, not a fix, and the roadmap entry stays the real work.

**Port it.** `accountsservice` and polkit proper are real work, and nothing above
substitutes for them if a multi-user session is wanted.

The repeatable order for a desktop in a pinch: rebuild the two MATE components
from source, stub `polkitd`, install the 37 Mint packages that already resolve,
and leave `mintmenu` behind the `python3-setproctitle` rebuild.

## What this changes

Roadmap 55 assumed the package closure had to be read from a live guest. It does
not: availability and dependency facts are archive facts. What still requires the
guest is runtime behavior -- whether a component starts, whether GSettings
persists, whether the session survives logout -- and whether a rebuild succeeds.

These are index facts read on one date against an unpinned archive. The report
names its suites, mirror, and source so a rerun is comparable.
