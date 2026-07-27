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

Omitting `mate-polkit` from a request does not keep it out of the transaction.
`mate-panel` declares it as a hard `Depends`, so the authorization branch gates
the panel, and an install list that simply leaves the name out is an intent
rather than a transaction apt would accept.

What the archive does accept today is the resolvable subset of `mate-bootstrap`,
which is a panel-less session: `mate-session-manager`, `marco`, `mate-terminal`,
`mate-notification-daemon`, `mate-menus`, `mate-icon-theme`, and `mate-themes`
resolve together on hurd-amd64. That keeps the package manager truthful --
`sudo` for privileged operations, administrative GUI actions recorded as
unavailable -- and it names the panel as a second thing the polkit branch gates,
alongside the settings-administration layer. Adding the panel before polkit
takes a packaging change that makes the authorization agent optional, a
substitute panel recorded as a deviation, or a genuine alternative polkit
service; a `Provides: polkitd` stub is none of those.

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

## The 32-bit port is a reference system, not a package source

The hurd-i386 binaries the sections above name are tempting as payloads: the
64-bit port lacks `mate-settings-daemon` and the 32-bit port has it. Two
independent facts rule that out, and only the second needed measuring here.

Upstream supports 32-on-64 as a whole-userland configuration. 64-bit GNU Mach
runs an entirely 32-bit Hurd userland, or an entirely 64-bit one, and the GNU
Hurd FAQ states that both Debian GNU/Hurd ports are supported but not both at
the same time. A 64-bit Hurd server set alongside arbitrary 32-bit Hurd
applications, with both dependency universes present, is a third configuration
that nothing upstream supports. The `Multi-Arch: same` field on `libc0.3` is
real and it is one necessary layer; it settles file layout for libraries and
says nothing about mixed Hurd processes and servers.

The packaging layer refuses first, before any ABI question is reached.
`--foreign-architecture` enables a second architecture the way
`dpkg --add-architecture` does and qualifies each architecture-specific request
to it, so the question is asked against the real index:

    make hurd-closure-report HURD_ARCH=hurd-amd64 HURD_FOREIGN=hurd-i386 \
        HURD_SET=mate-bootstrap

An `Architecture: all` request stays unqualified. Such a package is realized
once, under the native architecture, so `pkg:hurd-i386` names a binary the
archive never publishes; qualifying one manufactures an impossible request and
reports it as a missing foreign variant, which reads as a multiarch limitation
and is an artifact of the question.

What the archive answers, from
`evidence/hurd-archive/hurd-amd64-foreign-hurd-i386-*.json`:

| set, foreign hurd-i386 into hurd-amd64 | resolvable | foreign-qualified members |
|---|---|---|
| mate-bootstrap | 3 of 10, all Architecture: all | 0 |
| mate-control | 2 of 3 | 13 of 32 |
| mate-meta-validation | 0 of 2 | 0 |
| mint-mate-integration | 2 of 3, both Architecture: all | 0 |

`dconf-gsettings-backend` and `dconf-cli` coinstall as `:hurd-i386` and pull 13
foreign-qualified packages, so the mechanism works where the packaging is
multiarch-aware. Every architecture-specific MATE component fails, seven of
seven in the bootstrap set, and one failure shape carries the finding:

    mate-session-manager:hurd-i386 : Depends: mate-desktop-common:hurd-i386 (>= 1.24)
    mate-notification-daemon:hurd-i386 : Depends: mate-notification-daemon-common:hurd-i386
    marco:hurd-i386 : Depends: libmarco-private2:hurd-i386 (= 1.26.2-4.1+b2)

MATE splits nearly every component's data into an `Architecture: all` companion,
and an `Architecture: all` package without `Multi-Arch: foreign` cannot satisfy a
foreign package's dependency, so the foreign build of each component depends on a
name that cannot be architecture-qualified. The metapackages resolve to the same
place through `marco`. `mate-settings-daemon` carries no `Multi-Arch` field at
all, which places its executables in shared paths where two architectures cannot
coexist. The barrier is in the packaging layer, ahead of any ABI question.

Whether such a transaction would displace an installed native userland is **not
measured** in the committed reports. The resolver's tree carries an empty dpkg
status file, recorded as `provenance.installed_baseline`, so
`native_packages_removed` is empty by construction rather than by observation.
What the reports establish is that the architecture-qualified requests do not
resolve.

The mechanism that settles it now exists and has not been run against a guest.
apt reads installed state as RFC822 paragraphs, so the export renders paragraphs
through `dpkg-query` rather than a table, and spells `Status` from its three
parts because apt parses `install ok installed` and not the abbreviated `ii`.
`--installed-status` copies that file into `Dir::State::status`, refuses a file
naming no package, and refuses one carrying the other port's architecture, which
would otherwise make every native verdict wrong while still parsing. A fixture
shows what the seed changes: one transaction reports removing an installed
package against a seeded baseline and reports nothing against an empty one. The
remaining step is the boot that produces the file.

The guest half of the experiment stays in a disposable clone, and its outcomes
are graded before it runs so a partial success is not read as a route:

| outcome | what it establishes |
|---|---|
| foreign architecture rejected | no dpkg-level route; the question closes here |
| packages conflict before installation | the packaging layer refuses, matching the archive |
| loader fails | the foreign libc does not load under 64-bit GNU Mach |
| a simple process runs, IPC fails | 32-bit computation works and Mach-mediated services do not |
| the full probe ladder succeeds | mixed processes are technically possible, and nothing about the desktop |
| a MATE process later succeeds | still short of product acceptance without full closure and session testing |

The i386 binaries stay valuable as evidence: they prove the source has one
working Hurd port, they identify the source version and Debian patch set to
reproduce, and their contents and `.buildinfo` are the comparison for a new
amd64 build. They narrow a failure to 64-bit assumptions, dependency skew, or
buildd state rather than generic Linux-only code. They do not prove the source
builds unchanged for `hurd-amd64`, and the native build stays the acceptance
test.

## Whether a rebuild can start is its own archive question

A missing binary is a rebuild candidate only if a build can begin, and that is
not settled by the binary index. `--build-dependencies` adds a `deb-src` line
for the main archive and resolves each source package's build closure against
the target port's binaries:

    make hurd-build-closure-report
    make hurd-build-closure-report HURD_ARCH=hurd-i386

The simulation names `source=version`. Given a bare name apt resolves the source
through the binary of that name in the port index and then demands the source at
that binary's version, so a port carrying a stale binary sends apt looking for a
source version the main archive stopped publishing. That is what made hurd-i386
report `python3-setproctitle` blocked against a version constraint: the port
holds the 1.1.8-1 binary while the archive publishes 1.3.7-2 source, and pinning
the reported version resolves 156 build dependencies. A source package is also
its own namespace, so the report names the source that runs the build beside the
requested name: `polkitd` is built by `policykit-1` and `python3-setproctitle` by
`python-setproctitle`.

The answer reorders the work. From
`evidence/hurd-archive/hurd-amd64-build-closure-rebuild-candidates.json`, six
sources tested, two buildable and four blocked:

    libmatemixer          buildable   206 build dependencies resolve
    python3-setproctitle  buildable   156 build dependencies resolve
    mate-settings-daemon  blocked     libmatemixer-dev (>= 1.24)
    mate-control-center   blocked     libaccountsservice-dev (>= 0.6.21),
                                      mate-settings-daemon-dev (>= 1.24)
    accountsservice       blocked     polkitd
    polkitd               blocked     libselinux-dev

Every unsatisfied build dependency is recorded, not only the first apt names, so
`mate-control-center` shows both of its prerequisites. A scheduler reading one
blocker per source would start that build after supplying `libaccountsservice-dev`
alone.

Two dependency views are recorded, because neither contains the other. The
declared scan reads the selected source paragraph's own clauses and resolves
each the way a build daemon would: an alternative group is satisfied by any
member, an architecture restriction that excludes the target removes the clause,
and a virtual name is satisfied by a provider. It therefore names a build
dependency the port lacks outright. apt resolves transitively, so it names a
package that exists whose own dependencies do not close. A name only the scan
reports means apt stopped earlier; a name only apt reports means the chain runs
deeper than the source text shows.

The distinction is not hypothetical. On hurd-amd64 the two views agree on every
candidate, which is what establishes that the build order above is the full set
rather than apt's first look. On hurd-i386 they disagree once: every build
dependency `mate-control-center` declares exists on that port, and apt still
reports `polkitd`, because `mate-polkit` is a build dependency that exists and
its own dependency does not. Read from the source text alone that build looks
ready; read from the simulation alone the blocker looks declared. It is neither.

The provider case is equally concrete. `mount` is a build dependency polkit
declares and the `hurd` package provides, and `debhelper-compat`,
`dpkg-build-api`, and `dh-sequence-gir` are supplied by `debhelper`, `dpkg-dev`,
and `gobject-introspection`. A scan that read names rather than resolving them
would report six extra blockers for polkit and send someone porting packages the
port already has.

`accountsservice` needs `polkitd` at build time, not only at run time, and
polkit's own build stops at `libselinux-dev`. SELinux is a Linux kernel
interface, so that build dependency cannot be satisfied on the Hurd at all. The
remedy there is a packaging change that qualifies the build dependency to Linux
architectures and builds without it, which is a patch to Debian's polkit
packaging rather than a port of polkit's logic.

The work is three partly independent branches rather than one chain:

    libmatemixer ------------------> mate-settings-daemon ----+
                                                              |
    python3-setproctitle ----------> Mint Menu                |
                                                              |
    libselinux-dev qualification --> polkitd                  |
                                        |                     |
                                        v                     v
                                   accountsservice ----> mate-control-center

The settings branch and the authorization branch both have to close before the
control center can build. Both buildable sources resolve together in one
simulation, pulling 240 packages, so one builder tree serves the batch rather
than two.

So polkit is not only the run-time blocker of `mate-polkit`; it is a build-time
blocker of `accountsservice` and therefore of `mate-control-center`. Bringing up
a session without polkit-dependent integration is still the right first step,
and polkit still has to come before the settings-administration layer can be
built at all.

`libselinux-dev` is the first barrier polkit presents, and clearing it is not
the same as establishing that polkit needs no portability work. Linux-specific
headers elsewhere in the source, process-credential introspection, session
tracking, and local-socket peer credentials are all unmeasured until the build
runs, and a produced `.deb` still says nothing about `polkitd` answering on the
Hurd system bus. The qualification, the build, and the runtime contract are
three separate results.

The 32-bit port is further along here too, which is what makes it a useful
reference system: `mate-settings-daemon` is already buildable there, pulling 450
build dependencies, because `libmatemixer-dev` exists. `python3-setproctitle` is
buildable on both ports. `polkitd` stops at `libselinux-dev` on both, and
`mate-control-center` is blocked on both -- on hurd-i386 through `mate-polkit`,
which its build dependencies pull, so the authorization branch gates the control
center on the 32-bit port as well.

One claim above needs narrowing with this evidence. The main archive carries
`mate-control-center` source at 1.26.1-1.1 while the hurd-i386 binary is
1.26.0-2, so the same-source-version argument holds for `mate-settings-daemon`
alone. For `mate-control-center` the i386 binary was built from an older source
than the one a rebuild would use.

## The development profile resolves before any guest boots

The product promises a native compiler and Hurd development environment, and a
package list taken from a running image reports what happens to be installed
rather than what the port can supply. That is an archive question:

    make hurd-closure-report HURD_SET=dev-profile

All 31 members resolve for hurd-amd64 -- 23 native, 8 architecture-independent,
pulling 261 packages recursively. The Hurd-specific members are present:
`mig-x86-64-gnu` at 1.8+git20231217-11, `gnumach-dev` at 2:1.8+git20260224-11,
and `hurd-dev` at 1:0.9.git20260527-3+b1. `git` carries a Hurd-specific revision
at 1:2.53.0-1+hurd.1, which is evidence the port receives downstream patching
rather than rebuilds alone.

hurd-i386 resolves 30 of 31, missing `mig-x86-64-gnu` alone, which is the
amd64 cross-generator and correctly absent from a 32-bit port.

This settles availability. Whether each compiler compiles, links, and runs on
GNU Mach, whether MIG generates stubs that build, and whether a Hurd server
probe compiles are guest facts that no archive answers.

## Closing the gaps

Three kinds of failure appear above, and each takes a different mechanism.
Treating them alike is how a rebuild gets manufactured for a problem no rebuild
addresses.

**Rebuild from source, for a missing native binary.**
`mate-settings-daemon`, `mate-control-center`, and `python3-setproctitle` have
source in the main Debian archive, and the first two have a hurd-i386 binary at
the same source version. The builder belongs in a disposable overlay rather than
in the product image: an immutable hurd-amd64 builder base, a fresh external
qcow2 overlay per build, authenticated source and exact build dependencies
inside it, `dpkg-buildpackage`, whatever package tests run on the Hurd, export
of the `.deb`, `.ddeb`, `.changes`, `.buildinfo`, `.dsc` and source checksums,
build and test logs, toolchain versions, and the source index identities; then a
clean shutdown, an offline filesystem check, and the overlay discarded. The
tested binaries install into a separate product overlay. That removes any need
to trust an internal snapshot as the routine rollback, and it keeps a failed
build away from the image the product boots.

The overlay half of that is in place and measured. `QEMU_BACKING_DRIVE` names an
immutable image and `QEMU_DRIVE` an overlay path that must not already exist;
the entrypoint records the backing digest, refuses a declared
`QEMU_BACKING_SHA256` that disagrees, refuses to reuse an overlay because the
previous run's writes would carry forward, and states the backing format rather
than letting `qemu-img` probe it, which would read a raw backing file as
whatever its first bytes resemble. A probe booted QEMU against a fresh overlay
and compared the backing image's SHA-256 across the run: unchanged. The two
refusals were exercised, and the refused run created no overlay.

Which rollback applies follows from intent rather than from preference.
Provisioning mutates the canonical image on purpose and wants the change kept,
so it snapshots first. A build mutates a filesystem on purpose and must leave
nothing behind, so it runs on an overlay that is discarded. Discarding a file
cannot half-apply, and it holds when the guest never shuts down cleanly, which
is exactly the case an internal snapshot handles worst.

**Pin the archive, so the closure and the build answer the same question.** sid
and unreleased move, so a closure resolved one day and the build it schedules
the next can resolve against different archives, and the report then carries a
verdict the build cannot reproduce. `--archive-snapshot` points both the ports
mirror and the source archive at one `snapshot.debian.org` timestamp;
snapshot.debian.org carries dated dists for debian-ports as well as the main
archive, so the lock is a timestamp rather than a local cache of every fetched
artifact. Timestamp 20260726T003219Z reproduces the committed hurd-amd64 build
closure exactly, including the 240-package shared builder tree.

A timestamp alone does not make the lock durable, and two mechanisms bound it.

The first is expiry. A snapshot Release carries the `Valid-Until` it was
published with, so the archive state a timestamp pins stops being acceptable to
apt some weeks later while the bytes and the signature stay exactly what they
were. Against a January 2026 snapshot apt reports `Release file ... is expired
(invalid since 200d 2h 55min 3s)`. Expiry checking is therefore disabled for
snapshot sources and left enabled for live mirrors, where a stale Release is a
genuine freshness failure rather than the point; disabling it everywhere would
trade the lock for the freshness check.

The second is the keyring, and it is the harder bound. That same January 2026
debian-ports snapshot also fails verification with `Missing key
519759FBC670BF...`, because debian-ports rotates its archive signing key and the
keyring shipped in the resolver image carries the current one. Expiry is
configuration; a key the verifier does not hold is not. A timestamp is therefore
usable only together with a keyring vintage that can verify it, and pinning far
into the past means vendoring the historical keyring as well. The build lock
records the timestamp beside the resolver image that verified it.

**Wait or pin, for an archive inconsistency.** The `caja` failure is a skew
between `gvfs` and its own split-out packages inside `sid`, and both ports carry
`caja` natively. Rebuilding `caja` addresses no mechanism; it manufactures a
local build because `caja` is the name at the top of a failing transaction. The
remedies are convergence in the archive, a coherent snapshot where every
candidate matches, or rebuilding the mismatched dependency set together against
one source state.

**Port or make optional, for an absent subsystem.** `polkitd` and, for
hurd-amd64, `accountsservice` are real work. The final product needs a
Hurd-compatible polkit service, a deliberately designed Hurd-native
authorization replacement, or packaging that makes the affected MATE
functionality optional. Nothing above substitutes, and the 32-bit port supplies
no escape because `polkitd` is absent there too.

## What this changes

Roadmap 55 assumed the package closure had to be read from a live guest. It does
not: availability and dependency facts are archive facts. What still requires
the guest is runtime behavior -- whether a component starts, whether GSettings
persists, whether the session survives logout -- whether a package installs at
all, and whether a rebuild succeeds.

These are index facts read on one date against an unpinned archive. The reports
name their suites, mirrors, digests, and resolver so a rerun is comparable.
