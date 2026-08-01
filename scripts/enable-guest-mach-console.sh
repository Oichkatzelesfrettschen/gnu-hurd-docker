#!/bin/bash
# Give a disposable overlay a serial GNU Mach console and prove it carries one.
#
# GNU Mach writes to the console its multiboot command line names. The builder
# base boots `root=part:5:device:wd0` with no `console=com0`, so the kernel
# writes to VGA and the serial port carries only firmware and GRUB. The Mach IPC
# allocation failure a build round is rejected for is a kernel message, so a run
# that does not fix this cannot observe its own falsifier.
#
# The edit belongs to the overlay rather than to the base. `update-grub` inside
# the guest rewrites the generated multiboot lines, the change lives in the
# disposable qcow2, and the immutable base keeps the digest the lock pins, so no
# run re-cuts the base or rebinds the lock, its exported status, or the closure
# seeded with it.
#
# What proves it worked is kernel output. The version string is not the test: a
# measured transcript carries it exactly once, in the /etc/issue login banner a
# getty writes, so matching it accepts a serial port that reaches a getty while
# the kernel still writes to VGA.

set -euo pipefail

run_dir=""
require=0
while [ $# -gt 0 ]; do
    case "$1" in
        --run-dir) run_dir="$2"; shift 2 ;;
        --require) require=1; shift ;;
        *) printf 'mach console: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done
[ -n "$run_dir" ] && [ -d "$run_dir" ] || {
    printf 'mach console: --run-dir naming an existing directory is required\n' >&2
    exit 2
}

script_dir="$(cd "$(dirname "$0")" && pwd)"
export GUEST_SSH_HOST="${GUEST_SSH_HOST:-127.0.0.1}"
export GUEST_SSH_PORT="${GUEST_SSH_PORT:-${BUILDER_SSH_PORT:-2223}}"
export GUEST_SSH_USER="${GUEST_SSH_USER:-root}"
export GUEST_SSH_KEY="${GUEST_SSH_KEY:-ssh-test-keys/hurd_test_key}"
export GUEST_KNOWN_HOSTS="${GUEST_KNOWN_HOSTS:-${run_dir}/known_hosts}"
# shellcheck source=scripts/lib/guest-ssh.sh
source "${script_dir}/lib/guest-ssh.sh"

evidence="${run_dir}/artifacts"
mkdir -p "$evidence"
serial="${run_dir}/serial.log"
ready_timeout="${BUILDER_SSH_READY_TIMEOUT:-600}"

# The same definition the executor reads the transcript with. Lines only the
# kernel writes, anchored past the carriage return a CRLF console leaves at the
# start of every line after the first.
MACH_KERNEL_OUTPUT='^[[:space:]]*(module [0-9]+:|timer calibration|IOAPIC .* configured with GSI|APIC entry=|IRQ override:|RTC time is)'

log() { printf 'mach console: %s\n' "$*" >&2; }

wait_for_guest() {
    local limit="$1" waited=0
    while [ "$waited" -lt "$limit" ]; do
        if guest_ssh_alive; then return 0; fi
        sleep 10
        waited=$((waited + 10))
    done
    return 1
}

guest_ssh_alive || wait_for_guest "$ready_timeout" || {
    log "the guest never answered SSH, so the console cannot be configured"
    exit 1
}

guest_ssh_exec "${evidence}/grub-default-before.txt" \
    "${evidence}/grub-read.stderr" "cat /etc/default/grub" || true
guest_ssh_exec "${evidence}/grub-cfg-before.txt" \
    "${evidence}/grub-read.stderr" "grep -n gnumach /boot/grub/grub.cfg" || true

# A key already carrying console=com0 is replaced rather than appended to, so a
# rerun cannot accumulate duplicates that GRUB would pass through verbatim.
if ! guest_ssh_exec "${evidence}/update-grub.stdout" \
        "${evidence}/update-grub.stderr" \
        "sed -i '/^GRUB_CMDLINE_GNUMACH=/d' /etc/default/grub && printf 'GRUB_CMDLINE_GNUMACH=\"console=com0\"\n' >> /etc/default/grub && update-grub"; then
    log "update-grub failed; see ${evidence}/update-grub.stderr"
    exit 1
fi

guest_ssh_exec "${evidence}/grub-cfg-after.txt" \
    "${evidence}/grub-read.stderr" "grep -n gnumach /boot/grub/grub.cfg" || true
if ! grep -q 'console=com0' "${evidence}/grub-cfg-after.txt"; then
    log "the regenerated grub.cfg names no console=com0"
    exit 1
fi
log "grub.cfg carries console=com0 on $(grep -c 'console=com0' "${evidence}/grub-cfg-after.txt") multiboot line(s)"

offset_before=0
[ -f "$serial" ] && offset_before="$(wc -c <"$serial" | tr -d ' ')"

guest_ssh_exec "${evidence}/console-reboot.stdout" \
    "${evidence}/console-reboot.stderr" "sync; (sleep 1; /sbin/reboot) >/dev/null 2>&1 &" || true
sleep 30
if ! wait_for_guest "$ready_timeout"; then
    log "the guest did not return on SSH after enabling the serial console"
    exit 1
fi
log "guest answered SSH after the console reboot"

matches=0
if [ -f "$serial" ]; then
    matches="$(tail -c "+$((offset_before + 1))" "$serial" \
        | grep -cE "$MACH_KERNEL_OUTPUT" || true)"
    tail -c "+$((offset_before + 1))" "$serial" \
        >"${evidence}/console-after-enable.log" || true
fi

cat > "${run_dir}/mach-console.json" <<EOF
{
  "schema_version": 1,
  "kind": "guest-mach-console",
  "multiboot_console": "com0",
  "serial_offset_before_reboot": ${offset_before},
  "kernel_output_lines": ${matches},
  "kernel_output_observed": $([ "$matches" -gt 0 ] && echo true || echo false),
  "required": $([ "$require" -eq 1 ] && echo true || echo false),
  "transcript": "serial.log",
  "grub_config_after": "artifacts/grub-cfg-after.txt"
}
EOF

if [ "$matches" -gt 0 ]; then
    log "the transcript carries ${matches} GNU Mach kernel line(s)"
    exit 0
fi
log "the transcript carries no GNU Mach kernel output after enabling console=com0"
[ "$require" -eq 1 ] && exit 1
exit 0
