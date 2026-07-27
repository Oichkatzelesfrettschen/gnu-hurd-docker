# Guest baseline, collected from one boot

Every closure verdict in `evidence/hurd-archive/` was resolved against an empty
dpkg status file, so it states what the archive permits on an empty system. A
transaction there has no installed package to displace, which makes an empty
removal list a property of the tree rather than a measurement of the image.

These artifacts come from one TCG boot of a disposable external overlay over
`images/hurd-working.qcow2`. The canonical image was never opened for writing:
its SHA-256 is recorded before and after in `run.json`, and the overlay was
discarded afterwards. The overlay carried two offline edits that therefore
reached no published image -- an ephemeral public key in `/root/.ssh`, and the
`/etc/shadow` last-change field moved off zero for `root` and `user`, because
those accounts sit at `chage -d 0` and refuse key-based SSH after authenticating
it.

`chage` could not perform that edit. libguestfs runs a Linux appliance and the
guest binaries are `hurd-amd64`, so a guest command cannot execute there. The
field was rewritten as text. That is the same execution boundary
`docs/audits/hurd-execution-boundary-and-archive-layer.md` records, met from the
offline-tooling side rather than the container side.

## How to read a probe

`probes.json` carries one record per query: the command, its exit status, the
transport status, both streams, and the digest of each. The class says which of
five outcomes occurred, and they are different facts:

    observed          the query answered
    observed-absent   the query answered that the thing it reads is absent
    partial           the query emitted output and then failed
    failed            the query failed with nothing to show
    unreachable       the transport was gone, so the guest said nothing

A probe body exits 66 to state an absence. `run.json` carries the digest of
every artifact the run produced, so a file edited afterwards no longer matches
the package that advertises it. Files in this directory that the index does not
name are resolver reports, and each one names in its provenance the status file
it was resolved against. `make guest-baseline-check` asserts all of that.

## How the package is produced

    make minty-collect-baseline MINTY_SSH_PORT=<port>
    make minty-baseline-run-manifest MINTY_BASELINE_BEFORE=<digest> \
        MINTY_BASELINE_FSCK=clean MINTY_BASELINE_CONTAINER=<name>

The collector reads the guest; the run manifest carries what sits outside it,
and `scripts/write-guest-baseline-run.py` derives the artifact index from the
directory rather than taking it by hand. The container has to still be running
for its image ID and QEMU version to be readable, because those are properties
of the process that produced the evidence.

Two independent boots of the same image produced byte-identical artifacts for
every probe except `free.txt`, whose numbers are a property of the running
kernel, and byte-identical package state at 740 entries. A third boot from the
same clean backing image stalled before reaching `sshd`: QEMU held at 2% CPU
with the overlay static at 964 KiB for thirty minutes, and a fresh overlay
prepared identically answered in 165 seconds. That is roadmap items 33 and 34
observed on this image rather than a new defect, and it is why a collection
bounds its wait rather than assuming a boot.

## What the guest reports

    uname            GNU debian 0.9 GNU-Mach 1.8+git20260224-up-amd64/Hurd-0.9 x86_64 GNU
    nproc            1
    debian_version   forky/sid
    architecture     hurd-amd64
    packages         740
    desktop mode     vnc
    desktop session  absent

The kernel is the uniprocessor Mach build and `nproc` returns 1 while QEMU was
asked for one vCPU, which is the measurement behind the `QEMU_SMP` default. The
suite is `forky/sid`, not Trixie. Two `gnumach-image` packages are installed at
`2:1.8+git20260224-11`, the generic `-amd64` name and the `-amd64-up` build, and
`uname` reports the uniprocessor one.

## The toolchain the image carries, and what it lacks

`toolchain-packages.txt` asks after each build tool by name and prints its
version or `absent`, so a package that is not installed is an observation rather
than a failed query:

    gcc 4:15.2.0-5+b1        make 4.4.1-3         binutils 2.46.90.20260712-1
    g++ 4:15.2.0-5+b1        dpkg-dev 1.23.7      libc0.3-dev 2.42-17
    build-essential 12.12    python3 3.14.6-1
    mig absent               pkg-config absent

`mig` is the Mach Interface Generator, and no Hurd server, translator, or RPC
stub is built without it. The archive carries it -- the seeded development
profile resolves `mig` and `mig-x86-64-gnu` at `1.8+git20231217-11` -- so this is
a gap in the image rather than in the port.

## What the baseline changes

`hurd-amd64-mate-bootstrap.json` here and in `evidence/hurd-archive/` resolve the
same set against the same archive snapshot `20260726T003219Z`, the same resolver
image, and the same generator. Only the installed state differs, so the
difference between them is attributable.

Every per-package class is identical, which is evidence that the archive-only
reports were sound about availability. The transaction is not identical: against
an empty system it installs 214 packages, and against this image it carries 228
changes, of which 34 name packages absent from the empty-system transaction
because they are already installed and would be upgraded -- among them
`libc0.3`, `dbus`, `e2fsprogs`, and `curl`. Twenty packages the empty-system
transaction installs do not appear here, because the image already carries an
acceptable version. Installing the bootstrap set on this guest therefore
upgrades the C library, which is a different operation from installing 214 fresh
packages, and no report resolved against an empty tree could say so.

The other seeded reports answer against the same 740-package state:

    hurd-amd64-build-closure-rebuild-candidates.json   225 packages
    hurd-amd64-dev-profile.json                        31 of 31, 260 packages
    hurd-amd64-mint-visual.json                        35 of 35, 35 packages

The Mint visual set pulls exactly its own 35 members against this image, so the
visual freeze is those 35 `.deb` files with no native dependency behind them.

No transaction removes an installed package. Each report carries
`transaction_removals` and names the baseline it was measured against, so an
empty list here is a measurement where the same field against an empty tree is
empty by construction.

## The LMDE keyring is globally trusted

`apt-sources.txt` holds `/etc/apt/sources.list`, whose two `debian-ports` lines
carry no `signed-by`. `apt-sources-d.txt` holds the Mint line, which does scope
itself to `signed-by=/etc/apt/trusted.gpg.d/linuxmint-keyring.gpg`.
`apt-trusted-keys.txt` shows that file present in the global directory alongside
`debian-ports-archive-2026.asc` and `debian-ports-archive-2027.asc`.

A key in `/etc/apt/trusted.gpg.d/` authenticates every source that does not
scope itself, so the Mint archive key is a valid signer for the Debian Ports
archive on this guest. Roadmap item 72 carries the repair.

## The pins the image already carries

`apt-preferences-d.txt` shows two pin files, neither of which any repository
document described:

`lmde7` holds the whole `linuxmint` origin at priority 100 and raises a
whitelist of 39 Mint package names to 500. That whitelist, rather than the
resolver's `mint-visual` set, is what the running image accepts from LMDE, and
reconciling the two is roadmap item 74.

`openssh-hurd` pins `openssh-server`, `openssh-client`, and
`openssh-sftp-server` to `a=sid` at 990 and drives version `1:10.2p1-*` to -1,
because that version does not build on the Hurd without a libcrypt link. SSH is
how every artifact here was collected, so an upgrade that lifts this pin removes
the transport this baseline depends on.
