# Guest full-upgrade campaign: ipc_kernel_map exhaustion and the reboot-batched workaround (2026-07-16)

`images/hurd-working.qcow2` now carries a fully updated Debian sid
(hurd-amd64) userland: 243 of 250 upgradable packages installed, with
`gnumach 1.8+git20260224`, `openssl 3.6.3-1`, `util-linux 2.42.2-2`
among them. The seven held-back packages (`vim`, `vim-common`,
`vim-runtime`, `vim-tiny`, `emacs-gtk`, `emacs-common`,
`emacs-bin-common`) are debian-ports architecture skew: their arch=all
halves moved ahead of the hurd-amd64 binaries, so apt's solver
correctly keeps the families in lockstep until the port rebuilds.
`apt-get full-upgrade` reports `0 upgraded ... 7 not upgraded`, which
is "fully current" for this port. OOBE credentials were staged after
the upgrade (`scripts/oobe-first-login.sh`) and the guest halted
cleanly.

## Failure mode: one-shot full-upgrade wedges GNU Mach

A single `apt-get full-upgrade` of 250 packages froze the guest twice
with the console streaming:

    no more room in ffffffffc0322650 (xargs(11015))

This is the known GNU Mach limit documented in
`docs/reports/HURD-CONFIG-2026-05-13.md` (Bug 3): `ipc_kernel_map` is a
compile-time 8 MB region (`ipc/ipc_init.c`), and `mach_port.c` prints
"no more room" when `vm_allocate` on it fails. A long dpkg run forks
tens of thousands of processes (maintainer scripts, and especially the
`xargs` storms from man-db trigger processing); the map's port-table
allocations accumulate faster than they are reclaimed, and once the
map fills, every subsequent fork spins in that error. SSH dies with
it. Both wedges hit mid-unpack (the first at the libc 2.42-17 batch
under TCG, the second ~205 packages in under KVM), so the trigger is
cumulative process count, not any specific package.

Two mitigations that were NOT sufficient on their own:

- Diverting `/usr/bin/mandb` to `/bin/true`: the man-db trigger still
  runs `xargs`, which still forks a process per argument batch; only
  the per-process work shrinks.
- KVM instead of TCG (`FORCE_KVM=1`): ~10x faster wall-clock but the
  same number of forks, so the map still exhausts, just later.

## Working procedure: reboot-batched upgrade

A reboot fully resets the kernel map, so the campaign driver upgrades
in 40-package batches with a guest reboot between batches:

1. Boot with `FORCE_KVM=1` (the entrypoint otherwise auto-disables KVM
   for the IDE-on-pc machine type and falls back to TCG).
2. Each round over SSH: `dpkg --configure -a`, `apt-get -f install`,
   then `apt-get install --only-upgrade <next 40 from apt list
   --upgradable>`, then `reboot`.
3. Repeat until `apt list --upgradable` is empty (modulo solver
   holdbacks), then `autoremove --purge`, `apt-get clean`, remove the
   mandb divert.

20 rounds completed the 250-package backlog with zero wedges. Recovery
from the earlier wedges used the offline snapshot taken before the
campaign (`qemu-img snapshot -c pre-fullupgrade-20260716` /
`snapshot -a` to roll back); the snapshot remains in the qcow2 as a
rollback point.

## Repro notes

- Batch driver pattern: see this session's
  `scripts/oobe-first-login.sh` companion flow in the Makefile
  (`make oobe`) for the post-upgrade staging; the batch loop itself is
  four lines of shell around the round-step above and intentionally
  lives in the operator's hands, not CI.
- A proper fix is the gnumach `ipc_kernel_map_size` raise staged in
  `patches/` (64 MB), which needs a kernel rebuild; until that ships
  in debian-ports, treat >100-package apt transactions on stock
  kernels as a wedge risk.
