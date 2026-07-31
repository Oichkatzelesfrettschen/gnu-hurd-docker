#!/bin/bash
set -euo pipefail

# GNU/Hurd Docker - Configuration Validation Script
# Validates Dockerfile, entrypoint.sh, and Compose files for internal consistency.

echo "=========================================="
echo "GNU/Hurd Docker Configuration Validator"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

pass() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; ERRORS=$((ERRORS + 1)); }

require_file() {
    local path="$1"
    if [[ -f "$path" ]]; then
        pass "Found $path"
    else
        fail "Missing $path"
    fi
}

require_executable() {
    local path="$1"
    if [[ -x "$path" ]]; then
        pass "Found executable $path"
    elif [[ -f "$path" ]]; then
        fail "$path is present but not executable"
    else
        fail "Missing $path"
    fi
}

echo "1. Checking required files..."
echo ""

require_file Dockerfile
require_file entrypoint.sh
require_file compose.yaml
require_file compose.bind.yaml
require_file compose.kvm.yaml
require_file compose.vnc.yaml
require_file compose.podman.yaml
require_file docker-bake.hcl
# The gate's own mechanism is an invariant of the tree: a missing or
# non-executable enumerator or runner makes every ShellCheck surface report
# success over zero files.
require_executable scripts/list-maintained-shell.sh
require_executable scripts/check-maintained-shell.sh
require_file scripts/plan-builder-batches.py
require_file scripts/check-builder-batch-evidence.py
require_file scripts/write-builder-batch-journal.py
require_executable scripts/execute-builder-batches.sh
require_file scripts/health-check.sh
require_file scripts/download-image.sh
require_file scripts/setup-hurd-amd64.sh
require_file scripts/resolve-latest-hurd-amd64.sh
require_file scripts/resolve-latest-hurd-amd64-daily-installer.sh
require_file scripts/setup-hurd-amd64-latest.sh
require_file scripts/setup-hurd-amd64-daily-installer.sh
require_file scripts/build-hurd-unattended-iso.sh
require_file scripts/rebuild-hurd-unattended-iso.sh
require_file scripts/wait-for-guest-ssh.sh
require_file scripts/provision-hurd-x11.sh
require_file scripts/vboxmanage-hurd.sh
require_file scripts/install-hurd-unattended.sh
require_file scripts/qemu-auto-verify.sh
require_file scripts/qemu-matrix-runner.sh
require_file scripts/qemu-install-fsm.expect
require_file scripts/qemu-install-serial-fsm.sh
require_file scripts/qemu-stall-probe.sh
require_file scripts/scripts-inventory-audit.sh
require_file scripts/sudo-askpass.sh
require_file scripts/bootstrap-latest-hurd.sh
require_file scripts/validate-security-config.sh
require_file scripts/smoke-host.sh
require_file scripts/smoke-container.sh
require_file scripts/smoke-guest.sh
require_file scripts/capture-telnet-log.sh
require_file scripts/lib/installer/serial-log-utils.sh
require_file scripts/automation/qemu/qemu-auto-verify.sh
require_file scripts/automation/qemu/qemu-matrix-runner.sh
require_file scripts/automation/qemu/qemu-install-serial-fsm.sh
require_file scripts/automation/qemu/qemu-stall-probe.sh
require_file scripts/automation/qemu/rebuild-hurd-unattended-iso.sh
require_file scripts/automation/stubs/vbox-conceptual-stub.sh
require_file scripts/automation/audit/audit-scripts-inventory.sh
require_file infrastructure/unattended/preseed.cfg
require_file config/virtualbox/hurd-amd64.env
require_file Makefile

echo ""

echo "2. Validating shell scripts (ShellCheck)..."
echo ""

if command -v shellcheck >/dev/null 2>&1; then
    # scripts/check-maintained-shell.sh is the single enforcement mechanism for
    # every gate in the repository, so this check, `make lint`, and the workflows
    # that call it agree by construction and fail together.  Running the check
    # here rather than reimplementing the loop is what keeps this validator from
    # passing over an empty file set when the enumerator breaks.
    #
    # SHELLCHECK_SEVERITY selects the enforced level here exactly as it does for
    # `make lint`, so one variable moves every gate together.  Pinning error here
    # would leave `SHELLCHECK_SEVERITY=warning make validate` silently enforcing
    # error, and would split this check from `make lint` the moment roadmap item
    # 43 raises the default.  error is that default, and every maintained script
    # passes it.  Findings at warning and below are reported without failing.
    shellcheck_severity="${SHELLCHECK_SEVERITY:-error}"
    shellcheck_checked="$(./scripts/list-maintained-shell.sh | grep -c '' || true)"
    if ./scripts/check-maintained-shell.sh; then
        pass "$shellcheck_checked shell scripts pass shellcheck ($shellcheck_severity)"
    else
        fail "the maintained shell surface fails shellcheck ($shellcheck_severity)"
    fi

    # Reported, not counted: warn() increments the error total and would fail the
    # run, while clearing these findings is separate work tracked as roadmap item 43.
    # A non-zero exit means findings were reported, and under `set -e` with
    # pipefail that would abort the run.  Findings here are the expected case, so
    # the substitution absorbs that status.
    # (A comment opening with the tool's own name parses as a directive, so this
    # one deliberately does not.)
    advisory_output="$( { SHELLCHECK_SEVERITY=warning \
        ./scripts/check-maintained-shell.sh -f gcc 2>/dev/null || true; } )"
    if [ -n "$advisory_output" ]; then
        shellcheck_advisory=$(printf '%s\n' "$advisory_output" | wc -l)
        echo "[INFO] $shellcheck_advisory findings at warning level (advisory, not enforced):"
        printf '%s\n' "$advisory_output"
    fi
else
    warn "shellcheck not installed"
fi

echo ""

echo "2a. Validating builder batch-plan inputs..."
echo ""

if python3 scripts/plan-builder-batches.py --check; then
    pass "The stock-kernel builder batch plan binds to the committed lock and closure"
else
    fail "The stock-kernel builder batch plan does not bind to the committed lock and closure"
fi

echo ""

echo "3. Validating Dockerfile invariants..."
echo ""

if grep -qF 'FROM ubuntu:24.04' Dockerfile; then
    pass "Base image is ubuntu:24.04"
else
    warn "Base image is not ubuntu:24.04"
fi

if grep -qE '^[[:space:]]*qemu-system-x86[[:space:]]*\\\\?$' Dockerfile; then
    pass "Installs qemu-system-x86"
else
    fail "Dockerfile does not appear to install qemu-system-x86"
fi

if grep -qE '^[[:space:]]*gosu[[:space:]]*\\\\?$' Dockerfile; then
    pass "Installs gosu (optional privilege drop)"
else
    warn "Dockerfile does not appear to install gosu"
fi

if grep -q "dpkg --print-foreign-architectures" Dockerfile; then
    pass "Enforces no foreign dpkg architectures"
else
    warn "Dockerfile does not enforce dpkg foreign-architecture cleanliness"
fi

if grep -q '^USER hurd' Dockerfile; then
    pass "Runs as non-root user (USER hurd)"
elif grep -qE '^[[:space:]]*gosu[[:space:]]*\\\\?$' Dockerfile && grep -q "gosu hurd" entrypoint.sh; then
    pass "Runs as root but drops privileges to hurd when possible (gosu)"
else
    warn "Dockerfile does not switch to USER hurd (and no gosu privilege drop detected)"
fi

if grep -qF 'ENTRYPOINT ["/entrypoint.sh"]' Dockerfile; then
    pass "ENTRYPOINT points to /entrypoint.sh"
else
    fail "Dockerfile ENTRYPOINT does not point to /entrypoint.sh"
fi

echo ""

echo "4. Validating Compose files (YAML + semantics)..."
echo ""

if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not installed (cannot validate YAML)"
else
    python3 - <<'PY' || exit 1
import sys, yaml

def load(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)

base = load("compose.yaml")
bind = load("compose.bind.yaml")
kvm = load("compose.kvm.yaml")
vnc = load("compose.vnc.yaml")
podman = load("compose.podman.yaml")

errors = []

def expect_service(doc, path, name="gnu-hurd-dev"):
    services = (doc or {}).get("services") or {}
    if name not in services:
        errors.append(f"{path}: missing services.{name}")
        return None
    return services[name]

base_svc = expect_service(base, "compose.yaml")
bind_svc = expect_service(bind, "compose.bind.yaml")
kvm_svc = expect_service(kvm, "compose.kvm.yaml")
vnc_svc = expect_service(vnc, "compose.vnc.yaml")
novnc_svc = expect_service(vnc, "compose.vnc.yaml", name="novnc")
podman_svc = expect_service(podman, "compose.podman.yaml")

if base_svc is not None:
    vols = base_svc.get("volumes") or []
    if not any(isinstance(v, str) and v.startswith("hurd-disk:/opt/hurd-image") for v in vols):
        errors.append("compose.yaml: expected hurd-disk volume mounted to /opt/hurd-image")
    if not any(isinstance(v, str) and v.startswith("./infrastructure/cache/images/installers:/opt/hurd-installer") for v in vols):
        errors.append("compose.yaml: expected installer cache mount ./infrastructure/cache/images/installers:/opt/hurd-installer")
    env = base_svc.get("environment") or {}
    qemu_drive = env.get("QEMU_DRIVE", "")
    expected_qemu_drive = "/opt/hurd-image/${HURD_IMAGE_BASENAME:-debian-hurd-amd64.qcow2}"
    if qemu_drive not in ("/opt/hurd-image/debian-hurd-amd64.qcow2", expected_qemu_drive):
        errors.append("compose.yaml: environment.QEMU_DRIVE must support /opt/hurd-image/${HURD_IMAGE_BASENAME:-debian-hurd-amd64.qcow2}")
    if "QEMU_CDROM" not in env:
        errors.append("compose.yaml: expected environment.QEMU_CDROM for optional installer media")
    if "QEMU_BOOT_ORDER" not in env:
        errors.append("compose.yaml: expected environment.QEMU_BOOT_ORDER for installer boot control")
    ports = base_svc.get("ports") or []
    if not ports:
        errors.append("compose.yaml: expected ports to be configured (SSH/HTTP/serial/monitor)")
    else:
        bad = [p for p in ports if not (isinstance(p, str) and p.startswith("127.0.0.1:"))]
        if bad:
            errors.append("compose.yaml: expected all published ports to be bound to 127.0.0.1 by default")

if bind_svc is not None:
    vols = bind_svc.get("volumes") or []
    if not any(isinstance(v, str) and v.startswith("./images:/opt/hurd-image") for v in vols):
        errors.append("compose.bind.yaml: expected ./images bind mount to /opt/hurd-image")

if kvm_svc is not None:
    devs = kvm_svc.get("devices") or []
    if "/dev/kvm:/dev/kvm:rw" not in devs:
        errors.append("compose.kvm.yaml: expected devices entry /dev/kvm:/dev/kvm:rw")

if vnc_svc is not None:
    env = vnc_svc.get("environment") or {}
    if str(env.get("ENABLE_VNC", "")).strip() not in ("1", "true", "True"):
        errors.append("compose.vnc.yaml: expected services.gnu-hurd-dev.environment.ENABLE_VNC=1")
    ports = vnc_svc.get("ports") or []
    if not any(isinstance(p, str) and p.endswith(":5900") for p in ports):
        errors.append("compose.vnc.yaml: expected services.gnu-hurd-dev.ports to publish :5900")

if novnc_svc is not None:
    ports = novnc_svc.get("ports") or []
    if not any(isinstance(p, str) and p.endswith(":8080") for p in ports):
        errors.append("compose.vnc.yaml: expected services.novnc.ports to publish :8080")

if podman_svc is not None:
    if podman_svc.get("container_name") != "gnu-hurd-dev-podman":
        errors.append("compose.podman.yaml: expected container_name gnu-hurd-dev-podman")
    pvols = podman_svc.get("volumes") or []
    if not any(isinstance(v, str) and v.startswith("./images:/opt/hurd-image") for v in pvols):
        errors.append("compose.podman.yaml: expected ./images bind mount to /opt/hurd-image")
    if not any(isinstance(v, str) and v.startswith("./infrastructure/cache/images/installers:/opt/hurd-installer") for v in pvols):
        errors.append("compose.podman.yaml: expected installer cache mount ./infrastructure/cache/images/installers:/opt/hurd-installer")

if errors:
    print("[FAIL] Compose validation failed:")
    for e in errors:
        print("  -", e)
    sys.exit(1)

print("[OK] Compose files are consistent (service name, volumes, env, overrides)")
PY
    pass "Compose YAML and semantics valid"
fi

echo ""

echo "5. Validating image directory expectations..."
echo ""

if [[ -d images ]]; then
    pass "images/ directory exists"
else
    pass "images/ directory missing (ok for volume mode; required for bind mode)"
fi

echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "Errors: ${RED}${ERRORS}${NC}"
echo ""

if [[ "$ERRORS" -eq 0 ]]; then
    echo -e "${GREEN}Configuration is VALID${NC}"
    exit 0
fi

echo -e "${RED}Configuration has ERRORS${NC}"
exit 1
