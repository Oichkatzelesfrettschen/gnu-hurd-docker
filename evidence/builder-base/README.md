# Builder base, exported from one boot of the flattened image

`images/minty-hurd-builder-base.qcow2` is the immutable base every package
build boots a disposable overlay over. It was produced from one TCG boot of an
external overlay over `images/hurd-working.qcow2` -- the canonical image was
never opened for writing and still hashes to its certified digest -- and then
flattened with `qemu-img convert`, so the base has no backing file and one
SHA-256 identifies it. `config/minty/builder.lock.json` records that digest
beside the digests of the two files here.

The overlay boot made four changes before the flatten:

- `/etc/apt/sources.list` binds both debian-ports suites and the deb-src line
  to `snapshot.debian.org` at the lock's `archive_snapshot`, each scoped with
  `signed-by` to the keyring that signs it, with `check-valid-until` off
  because a snapshot Release keeps the Valid-Until of the day it was frozen.
  The Mint keyring moved from `/etc/apt/trusted.gpg.d/` to
  `/usr/share/keyrings/`, so every source is authenticated by exactly the key
  it names and the global trust directory holds Debian keys only. The
  `openssh-hurd` pin is preserved unchanged: SSH is the transport every build
  artifact leaves through, and that pin is what keeps it installable.
- The 31-member development profile from
  `evidence/guest-state/hurd-amd64-dev-profile.json` was installed with
  `--no-install-recommends`, the semantics the resolver derives with. The
  guest's own apt computed 105 new packages, 0 upgrades, 0 removals, and dpkg
  reports 845 packages with a clean audit. `mig` and `pkg-config` resolve as
  commands.
- An unprivileged `builder` account exists for source builds.
- The `root` and `builder` accounts accept the repository's test key, and the
  `/etc/shadow` last-change fields sit off zero, so build automation
  authenticates and is not prompted for a password change. The base is build
  infrastructure that never leaves the host, which is why an ephemeral-key
  edit that the baseline collection discards is kept here.

The guest halted on its own `halt`, the overlay passed `qemu-img check` and a
silent offline `e2fsck` at exit 0, and the flatten read from that checked
overlay.

## What the files here are

`hurd-amd64-dpkg-status` is the base's installed-package state, exported over
SSH from one boot of the flattened image itself through a disposable overlay,
so `source_image_sha256` in `hurd-amd64-dpkg-status.json` names the base and
the export describes the file that exists rather than the overlay it was built
in. That boot also observed the `builder` login and the toolchain commands.

`scripts/write-builder-lock.py` reads all three files and holds the chain they
state. The status metadata names the manifest it sits beside and the digest that
manifest hashes to, and its `source_image_sha256` is held against the base digest
the lock records, which is the one link that says the package state was exported
from the locked image rather than from some other guest. The seeded closure names
the status it answered against, the archive it resolved at, and the resolver
revision and image that produced it, and each is held against the tree. An absent
field refuses rather than comparing equal to another absent field, and a missing
input refuses rather than leaving the previous run's value in the lock.
`make builder-lock-selftest` breaks one link per case and requires a refusal that
writes no lock, because the drift gate runs against a tree whose links already
hold and so shows only that a correct chain is accepted.

`hurd-amd64-build-closure-rebuild-candidates.json` is the rebuild-candidate
closure seeded with that status at the lock's snapshot. Against the base the
shared build-dependency transaction is 171 packages and removes nothing, where
the same set against the pre-profile 740-package image was 225 and against an
empty tree 240. The per-package classes are identical across all three
resolutions -- `libmatemixer` and `python3-setproctitle` buildable,
`mate-settings-daemon`, `mate-control-center`, `accountsservice`, and
`polkitd` blocked -- so the installed state changes the transaction size and
not the verdicts. The batch planner consumes this report's transaction; the
earlier counts are superseded sizings of the same set.

## A resolver-fidelity boundary this run measured

The resolver predicts transactions with apt 3.0.3 on amd64; the guest executes
them with apt 3.3.1 on hurd-amd64. For the development profile the resolver's
seeded transaction listed 260 entries, 59 of them carrying an
installed-version bracket, while the guest's own apt computed 105 new packages
and nothing else. The requested set resolved either way and the base carries
what the guest installed, but a transaction size predicted by the resolver and
the transaction a guest executes are two solvers' answers to one question, so
the planner treats the resolver's figure as a bound to derive batches from and
the guest's simulation as the authority immediately before each batch runs.

`scripts/plan-builder-batches.py` consumes this closure. It refuses any
disagreement among the lock's digests, the exported status, and the report's own
provenance, then partitions the 171-member transaction in resolver order into
rounds of at most 40 requested members. `scripts/run-hurd-build.sh` writes the
checked plan into a disposable run directory only after proving the local base
image hashes to the lock, and `scripts/execute-builder-batches.sh` runs it.

That boundary is what makes the round bound a bound on the request rather than
on the installation: a round names up to 40 members and the guest's own
simulation decides how many of them are missing.
`evidence/builder-batches/README.md` carries the run where five rounds of 40,
40, 40, 40, and 11 members installed 44 packages.
