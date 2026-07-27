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

## What the guest reports

    uname            GNU debian 0.9 GNU-Mach 1.8+git20260224-up-amd64/Hurd-0.9 x86_64 GNU
    nproc            1
    debian_version   forky/sid
    architecture     hurd-amd64
    packages         740

The kernel is the uniprocessor Mach build and `nproc` returns 1 while QEMU was
asked for one vCPU, which is the measurement behind the `QEMU_SMP` default. The
suite is `forky/sid`, not Trixie.

## What the baseline changes

`hurd-amd64-mate-bootstrap.json` resolves the same set as
`evidence/hurd-archive/hurd-amd64-mate-bootstrap.json` and differs in the
transaction rather than the verdicts. Every per-package class is identical,
which is evidence that the archive-only reports were sound about availability.

The transaction is not identical. Against an empty system it installs 214
packages; against this image it carries 228 changes, of which 34 name packages
absent from the empty-system transaction because they are already installed and
would be upgraded -- among them `libc0.3`, `dbus`, `e2fsprogs`, and `curl`.
Twenty packages the empty-system transaction installs do not appear here,
because the image already carries an acceptable version. Installing the
bootstrap set on this guest therefore upgrades the C library, which is a
different operation from installing 214 fresh packages, and no report resolved
against an empty tree could say so.

No transaction removed an installed package. That claim is now measured, where
`native_packages_removed` in the archive-only reports is empty by construction.

## The LMDE keyring is globally trusted

`apt-sources.txt` shows the Mint repository line carrying
`signed-by=/etc/apt/trusted.gpg.d/linuxmint-keyring.gpg`, and the two
`debian-ports` lines above it carry no `signed-by` at all. A key in
`/etc/apt/trusted.gpg.d/` is trusted for every source that does not scope
itself, so the Mint archive key is currently a valid signer for the Debian Ports
archive on this guest. Roadmap item 72 carries the repair.
