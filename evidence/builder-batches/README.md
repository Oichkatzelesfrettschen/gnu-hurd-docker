# The stock GNU Mach kernel carries the builder dependency install

`scripts/plan-builder-batches.py` partitions the closure seeded against the
finished builder base into rounds, and `scripts/execute-builder-batches.sh`
runs each round over the guest SSH boundary: simulate, install, sync, reboot,
journal. The files here are one such run, executed against
`images/minty-hurd-builder-base.qcow2` at digest
`7bffe2be3e6fbcd7569d1d274556ea7a234712fa1ffd2df7a66286851ea28072` on a
disposable overlay, with the base unchanged before and after.

Two runs are here, named for the one QEMU setting that separates them: the PIIX
IDE disk presented with `write-cache=off` and with `write-cache=auto`. Each
directory carries `batch-journal.json`, what the guest did; `run.json`, the
manifest the host wrote; and `offline-fsck.log`, the filesystem transcript read
from the overlay after the guest halted. `batch-plan.json` sits under
`write-cache-off/` alone, because both journals name plan digest
`94014c0c8f37402356fb5a932e2c2a3e461f3b69e33597e16fc6cad58d505138` and one
schedule therefore describes both runs.

The planner has since produced a different digest for the same schedule: the
round bound's recorded wording changed when the bound was restated as a bound on
the request. The member partition is byte-identical, so a regenerated plan
differs from the plan here in its own digest and in no batch.

## What the journal records

Five rounds, all with outcome `completed`, in both runs. The plan named 40, 40,
40, 40, and 11 members; the guest's own simulation reported 10, 8, 10, 8, and 8
packages to install in each run, so a run installed 44 packages and found the
remaining 127 members already satisfied by the base's 845. Every round reported
`0 upgraded`, `0 to remove`, and `10 not upgraded`. Each install exited 0, each
`sync` exited 0, each `/sbin/reboot` was accepted, and the guest returned to SSH
before the next round began.

The 40-package figure bounds the size of the request a round names. It is not
the number of packages a round installs, and the journal's
`pre_batch_simulation.simulated_package_count` is the observed quantity. The
transaction is resolved against the base's own installed state and still names
members the base satisfies, because the resolver runs apt 3.0.3 on amd64 while
the guest runs apt 3.3.1 on hurd-amd64; `evidence/builder-base/README.md`
carries that boundary.

## What is settled and what is not

The dependency install is carried by the stock uniprocessor GNU Mach kernel in
reboot-batched rounds. Roadmap item 73 also names the compiler-heavy build
workload, which has not run, so the patched-kernel arm stays open for that
workload and is settled for this one.

Whether every planned member is installed after the final round follows from
each round simulating its own members, installing what was missing, exiting 0,
and removing nothing -- an inference, not an observation. The executor now ends
a run with one simulation over every planned member plus `dpkg -C` and an
installed-package count, and that mechanism had not run when this evidence was
produced.

The plan declares a recorded Mach IPC-map allocation failure as the falsifier
that rejects a batch. The executor greps APT's own streams, and GNU Mach writes
allocation failures to the kernel console, which this run did not capture: the
builder publishes no serial surface and the entrypoint writes no console
transcript. The Mach falsifier is therefore `not run`, and `no Mach IPC
allocation error appeared in APT's output` is the whole of what was observed.

## The Hurd leaves ext2 reporting deleted inodes with zero dtime

Each `offline-fsck.log` is a read-only `e2fsck` over that run's overlay as the
guest left it. Both exit 1 and report deleted inodes with zero dtime, the block
and inode bitmap differences that follow from them, and
`Filesystem still has errors`. Four host-side observations place that signature:

- `images/minty-hurd-builder-base.qcow2` carries an ext2 root, and the same
  read-only pass over it is silent at exit 0. There is no journal whose absent
  replay could explain the report, and the base is clean under the identical
  method.
- The same pass over an overlay that only booted and halted, with no package
  work, reports the same class, and its inode set is a subset of this run's.
  The workload adds deleted inodes because it deletes more files; it does not
  produce the condition.
- A full non-interactive repair (`e2fsck` with `correct:true forceall:false`)
  over a copy of this run's overlay completes at exit 0.
- A read-only pass after that repair produces no output at all.

The Hurd's ext2fs leaves `i_dtime` unset when it unlinks, so a read-only
`e2fsck` over any Hurd-written ext2 root reports this and a repairing pass
clears it. An acceptance gate therefore runs the repairing pass; a read-only
pass is an observation and never a gate, because gating on it refuses every run
this project can produce. `scripts/run-hurd-build.sh` runs both and records
them as `guest_filesystem_as_left` and `guest_filesystem_after_repair`.

Each `run.json` here was written before that split and carries the single
`guest_filesystem` field reading `not run`, which is what the runner recorded
when the read-only pass was still the gate and failed. Both are kept as written,
including the transcript name they index, because evidence describes the run
rather than the code that followed it.

## A remedy these runs falsified

The two runs differ in one QEMU setting, which is why they are both here. Their
journals record the same five completed rounds and the same per-round install
counts, their filesystem transcripts report the same class, and the boot-only
overlay reports it with no package work at all. Disk write caching does not
explain the signature, and the builder composition carries no write-cache
override.
