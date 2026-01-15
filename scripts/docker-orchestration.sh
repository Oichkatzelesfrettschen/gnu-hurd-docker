#!/bin/bash
# GNU/Hurd container orchestration helper (Docker or Podman).
#
# This script intentionally prefers Compose to keep configuration in one place.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/container-runtime.sh
source "${SCRIPT_DIR}/lib/container-runtime.sh"

SERVICE_NAME="${SERVICE_NAME:-gnu-hurd-dev}"

compose_files_override=()
if [[ -f "${REPO_ROOT}/docker-compose.override.yml" ]]; then
    compose_files_override=(-f "${REPO_ROOT}/docker-compose.override.yml")
fi

compose_files_base=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}")
compose_files_bind=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}" -f "${REPO_ROOT}/docker-compose.bind.yml")
compose_files_bind_kvm=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}" -f "${REPO_ROOT}/docker-compose.bind.yml" -f "${REPO_ROOT}/docker-compose.kvm.yml")
compose_files_bind_vnc=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}" -f "${REPO_ROOT}/docker-compose.bind.yml" -f "${REPO_ROOT}/docker-compose.vnc.yml")
compose_files_bind_kvm_vnc=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}" -f "${REPO_ROOT}/docker-compose.bind.yml" -f "${REPO_ROOT}/docker-compose.kvm.yml" -f "${REPO_ROOT}/docker-compose.vnc.yml")
compose_files_volume=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}")
compose_files_volume_kvm=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}" -f "${REPO_ROOT}/docker-compose.kvm.yml")
compose_files_volume_vnc=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}" -f "${REPO_ROOT}/docker-compose.vnc.yml")
compose_files_volume_kvm_vnc=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}" -f "${REPO_ROOT}/docker-compose.kvm.yml" -f "${REPO_ROOT}/docker-compose.vnc.yml")
compose_files_all=(-f "${REPO_ROOT}/docker-compose.yml" "${compose_files_override[@]}" -f "${REPO_ROOT}/docker-compose.bind.yml" -f "${REPO_ROOT}/docker-compose.kvm.yml" -f "${REPO_ROOT}/docker-compose.vnc.yml")

usage() {
    cat <<'EOF'
GNU/Hurd Orchestration Utility

Usage:
  ./scripts/docker-orchestration.sh <command> [args...]

Commands:
  check                 - Show detected runtime + platform notes
  up                    - Start using ./images bind mount (dev default)
  up-kvm                - Start dev default + KVM (Linux x86_64 only)
  up-vnc                - Start dev default + VNC/noVNC overlay
  up-kvm-vnc            - Start dev default + KVM + VNC/noVNC overlay
  up-volume             - Start using engine volume (portable default)
  up-volume-kvm         - Start volume mode + KVM (Linux x86_64 only)
  up-volume-vnc         - Start volume mode + VNC/noVNC overlay
  up-volume-kvm-vnc     - Start volume mode + KVM + VNC/noVNC overlay
  up-bind               - Start using ./images bind mount (host-managed QCOW2)
  up-bind-kvm           - Start bind mount + KVM (Linux x86_64 only)
  down                  - Stop and remove
  logs                  - Follow logs
  ps                    - Show container status
  shell                 - Open shell inside container
  exec <cmd...>         - Run a command inside container

Notes:
  - Default (volume) mode: use AUTO_DOWNLOAD_IMAGE=1 for first run, or copy in an image.
  - Bind mode: run ./scripts/setup-hurd-amd64.sh first to populate ./images/.
  - For KVM acceleration on Linux x86_64: use up-kvm and ensure /dev/kvm exists.
EOF
    exit 2
}

cd "$REPO_ROOT"

case "${1:-}" in
    check)
        check_runtime_compatibility
        ;;
    up)
        container_compose "${compose_files_bind[@]}" up -d
        ;;
    up-kvm)
        container_compose "${compose_files_bind_kvm[@]}" up -d
        ;;
    up-vnc)
        container_compose "${compose_files_bind_vnc[@]}" up -d
        ;;
    up-kvm-vnc)
        container_compose "${compose_files_bind_kvm_vnc[@]}" up -d
        ;;
    up-volume)
        container_compose "${compose_files_volume[@]}" up -d
        ;;
    up-volume-kvm)
        container_compose "${compose_files_volume_kvm[@]}" up -d
        ;;
    up-volume-vnc)
        container_compose "${compose_files_volume_vnc[@]}" up -d
        ;;
    up-volume-kvm-vnc)
        container_compose "${compose_files_volume_kvm_vnc[@]}" up -d
        ;;
    up-bind)
        container_compose "${compose_files_bind[@]}" up -d
        ;;
    up-bind-kvm)
        container_compose "${compose_files_bind_kvm[@]}" up -d
        ;;
    down)
        container_compose "${compose_files_all[@]}" down --remove-orphans
        ;;
    logs)
        container_compose "${compose_files_base[@]}" logs -f "$SERVICE_NAME"
        ;;
    ps|status)
        container_compose "${compose_files_base[@]}" ps
        ;;
    shell)
        runtime="$(get_container_runtime)"
        case "$runtime" in
            docker)
                docker exec -it "$SERVICE_NAME" bash
                ;;
            podman)
                podman exec -it "$SERVICE_NAME" bash
                ;;
        esac
        ;;
    exec)
        shift
        if [[ $# -lt 1 ]]; then
            usage
        fi
        runtime="$(get_container_runtime)"
        case "$runtime" in
            docker)
                docker exec "$SERVICE_NAME" "$@"
                ;;
            podman)
                podman exec "$SERVICE_NAME" "$@"
                ;;
        esac
        ;;
    ""|-h|--help|help)
        usage
        ;;
    *)
        echo "[ERROR] Unknown command: $1" >&2
        usage
        ;;
esac
