# The Hurd execution boundary, and the archive layer that crosses it

Two layers were proposed: the QEMU virtual machine inside a container, which
exists, and Hurd running on Docker directly, which does not. This records the
probe that separates them, the layer that is buildable in place of the second,
and what that layer says about putting MATE on each Hurd port.

## Hurd userland does not execute in an ordinary Linux container

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
before it loads any program. What that establishes is bounded: supplying files
does not move the barrier, so the barrier is the kernel interface. The signal
alone does not name the first Mach trap that failed, which would take a debugger
attached to the loader or an instruction trace, and neither was run.

Emulation as configured here does not close it either. `qemu-user` translates
Linux system calls for a foreign architecture; here the architecture already
matches and the missing element is Mach, which `qemu-user` does not provide.
Running a Hurd userland on a Linux kernel would take a Mach ABI compatibility
layer in the shape of Wine, which nothing in this repository supplies. Full
system QEMU supplies GNU Mach itself, and that is the layer this repository
already runs.

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
The tree is built under a temporary directory per invocation and removed
afterwards, because a retained index decides a later verdict silently.

    make hurd-closure-selftest
    make hurd-closure HURD_SET=mate-bootstrap
    make hurd-closure HURD_ARCH=hurd-i386 HURD_SET=mate-privileged-integration
    make hurd-closure-report HURD_SET=mint-visual

What this layer settles is availability, candidate version, declared
dependencies, and whether apt's solver closes the graph. What it leaves open is
everything the guest decides: maintainer scripts that call Linux-only commands,
runtime startup, D-Bus and GSettings behavior, and whether a session survives
logout. A resolved set is a prediction about installation rather than a
measurement of it, so the verdicts below say `resolves` and the sets are named
for the question each answers rather than for a product.

Mint supplies no Hurd binaries. LMDE 7 `gigi` advertises `i386` and `amd64` and
publishes no `binary-all` directory, so its `Architecture: all` payloads sit
inside the per-architecture indices. Taking a Mint index wholesale would offer
amd64 binaries to a Hurd architecture. The overlay keeps only the
`Architecture: all` stanzas and republishes them per source component under the
target architecture, and a pin on the overlay's own origin keeps Debian Ports
authoritative for any name both carry. Every version and every component copy
is kept, so apt performs the selection rather than the import order. The overlay
contributes 152 architecture-independent Mint packages.

Mint metadata is authenticated before any of it is read. The suite `Release` is
fetched over HTTPS and verified with `gpgv` against the Linux Mint repository
signing key vendored at `config/keys/linuxmint-archive-keyring.asc`, pinned to
primary fingerprint `302F0738F465C1535761F965A6616109451BBBF2`; each component
index is accepted only when its SHA-256 matches the entry in that verified
`Release`. A signature failure, an index the `Release` does not name, and a hash
mismatch each abort the run, because an overlay that silently shrinks reports a
smaller closure as though the archive were smaller. Debian Ports is verified by
apt itself against `debian-ports-archive-keyring`.

The resolver's solver is not the guest's. The image is `debian:trixie-slim`
pinned by digest, and the guest runs `sid`, so `uninstallable` is a verdict from
`apt 3.0.3` rather than from the apt the guest would run. Availability and
candidate version are independent of solver version; whether a graph closes is
partly a statement about the solver, so the apt and dpkg versions are recorded
with every report and a sid-matched resolver stays open work.

`evidence/hurd-archive/` holds the generated reports. Each carries its
collection time, the resolver base image digest, the apt and dpkg versions that
produced the verdicts, the verified `Release` digest and date, every source
index digest, the generated overlay digest, the signing key fingerprint, the
candidate origin per package, and the full recursive transaction rather than
only its size.

## What the archive says

Counts below are read from the committed reports and move with the archive.

### The first session, before authorization

`mate-bootstrap` asks whether a MATE session can start at all. It excludes the
metapackages and the privileged-session layer, whose failure answers a different
question and would otherwise mask this one.

| | hurd-amd64 | hurd-i386 |
|---|---|---|
| native | 4 | 4 |
| architecture-all | 3 | 3 |
| uninstallable | 2 | 3 |
| missing | 1 | 0 |

`marco`, `mate-terminal`, `mate-notification-daemon`, and `dconf` are native on
both, and `mate-menus`, `mate-icon-theme`, and `mate-themes` are
architecture-independent.

**`mate-settings-daemon` and `mate-control-center` have no hurd-amd64 record at
all, and both exist for hurd-i386** at 1.26.1-1.2 and 1.26.0-2. Both are named
in the MATE acceptance gate, and a session without a settings daemon has no
mechanism to apply the theme, icon, and cursor selections the product is defined
by.

The main archive carries `mate-settings-daemon` source at **1.26.1-1.2**, the
same version the hurd-i386 binary was built from. That makes both packages
high-confidence native-rebuild candidates rather than greenfield ports: the
source is known to build for one Hurd port at that version. It does not
establish that the source builds for `hurd-amd64`, where 64-bit assumptions,
dependency skew, or new compiler diagnostics can still block it. An actual
`hurd-amd64` build is the acceptance test, and it has not run.

Two blockers are distinct and are often conflated:

    hurd-amd64  mate-panel  mate-polkit : Depends: accountsservice but it is not installable
    hurd-i386   mate-panel  mate-polkit : Depends: polkitd but it is not installable

`mate-panel` pulls `mate-polkit`, so the authorization layer reaches into the
first session rather than staying in the administrative one. `accountsservice`
is native on hurd-i386 at 0.6.55-3 and absent for hurd-amd64, so the 64-bit port
carries one blocker the 32-bit port does not.

`caja` fails on both ports for a different reason:

    caja  gvfs : Depends: gvfs-common (= 1.58.0-2) but it is not going to be installed

That is a version skew inside `sid` between `gvfs` and its own split-out
packages, not a port gap. Both ports carry `caja` natively, and the skew clears
itself when the archive catches up. Naming it separately matters: a rebuild
closes a port gap and does nothing for a skew.

### Authorization

`polkitd` has no record for either port, and neither does the layer around it:

    accountsservice (hurd-amd64 only)  libaccountsservice0  systemd
    libsystemd0                        libelogind0          policykit-1

This is the boundary the architecture notes predicted, and it is session and
seat integration rather than the file manager or the window manager.

A stub that `Provides: polkitd` while supplying no daemon persuades apt and
authorizes nothing. Even on a single-user VM the system still distinguishes the
unprivileged desktop account, root, system daemons, operations that require
authentication, and operations that should always be denied; `mate-polkit` and
every other client then fails over D-Bus at run time, later and less legibly
than a refused install, and any unrelated package accepts the same false
provider. A stub may demonstrate what lies past the blocker in an experiment. It
counts toward no acceptance profile, and porting polkit stays the work.

The clean bootstrap route keeps the package manager truthful: install the
explicit MATE components, leave `mate-polkit` and the metapackages out, use
`sudo` for privileged operations, and record the administrative GUI actions as
unavailable until polkit is ported.

### Metapackages

`mate-desktop-environment-core` and `mate-desktop-environment` are
uninstallable on both ports. On hurd-amd64 they stop at `caja`, and on hurd-i386
they stop at the same `gvfs` skew. The metapackages are `Architecture: all`, so
they state a component list and nothing about native dependency closure; they
are asked here as their own question rather than used as a readiness signal.

### Mint presentation assets

35 of 35 packages in `mint-visual` are `architecture-all` and **dependency
resolve** for both ports, pulling 60 packages recursively. That is a resolver
verdict, not an installation: an `Architecture: all` package can still carry a
maintainer script that calls a Linux-only command, Python that reads `/proc`, or
systemd activation. Whether the Mint visual set installs is settled by a
disposable guest installation that ends with `dpkg -C` clean, which has not run.

`mint-backgrounds` is published per release codename rather than per suite, so
the tool discovers those names from the archive rather than guessing one, which
is why an earlier hardcoded `mint-backgrounds-gigi` read as missing when it
never existed.

`mint-mate-integration` is code rather than artwork and fails on its own terms.
`xapps-common` and `xapp-symbolic-icons` resolve on both ports; `mintmenu` stops
at `python3-setproctitle`, which neither port publishes. Source availability
alone does not say whether that is a buildd omission or a porting problem, and
the rebuild attempt is what distinguishes them.

## Closing the gaps

Two tiers, in order of preference, and both are separate work from this layer.

**Rebuild from source.** `mate-settings-daemon`, `mate-control-center`, and
`python3-setproctitle` have source in the main Debian archive, and the first two
have a hurd-i386 binary at the same source version. A builder that produces
those binaries belongs in a disposable overlay rather than in the product image:
an immutable Hurd builder base, a fresh external qcow2 overlay per build,
build-dependency installation and an unprivileged source build inside it, export
of the `.deb`, `.changes`, `.buildinfo`, and logs, and then installation of the
tested binaries into a separate product overlay. That removes any need to trust
an internal snapshot as the routine rollback, and it keeps a failed build from
touching the image the product boots.

**Port.** `polkitd` and `accountsservice` are real work, and nothing above
substitutes for them.

## What this changes

Roadmap 55 assumed the package closure had to be read from a live guest. It does
not: availability and dependency facts are archive facts. What still requires
the guest is runtime behavior -- whether a component starts, whether GSettings
persists, whether the session survives logout -- whether a package installs at
all, and whether a rebuild succeeds.

These are index facts read on one date against an unpinned archive. The reports
name their suites, mirrors, digests, and resolver so a rerun is comparable.
