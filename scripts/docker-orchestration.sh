#!/bin/bash
# GNU/Hurd Docker - Docker CLI Orchestration Script
# Demonstrates comprehensive Docker CLI control and best practices
# WHY: Enable programmatic Docker container management
# WHAT: Container lifecycle, exec, logs, inspect, networking
# HOW: Docker CLI commands with best practices

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONTAINER_NAME="${CONTAINER_NAME:-hurd-x86_64}"
IMAGE_NAME="${IMAGE_NAME:-hurd-x86_64:latest}"

show_usage() {
    cat <<EOF
GNU/Hurd Docker Orchestration Utility

Usage: $0 <command> [arguments]

Container Lifecycle:
  build           - Build the Docker image
  start           - Start the container (detached)
  stop            - Stop the container
  restart         - Restart the container
  remove          - Remove the container
  logs            - View container logs
  follow-logs     - Follow container logs in real-time

Interaction:
  exec CMD        - Execute command in container
  shell           - Open interactive shell in container
  attach          - Attach to container's main process
  inspect         - Inspect container details

QEMU Control (inside container):
  qemu-monitor    - Access QEMU monitor via docker exec
  qemu-serial     - Access QEMU serial console via docker exec
  qemu-ssh        - SSH into Hurd instance

Debugging:
  stats           - Show container resource usage
  top             - Show container processes
  network         - Show container network details
  ports           - Show port mappings

Examples:
  $0 start
  $0 exec "ps aux"
  $0 shell
  $0 qemu-monitor
  $0 logs
  $0 stats

EOF
    exit 1
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
}

case "${1:-}" in
    build)
        check_docker
        log_info "Building Docker image: $IMAGE_NAME"
        docker build -t "$IMAGE_NAME" .
        log_success "Image built successfully"
        ;;

    start)
        check_docker
        log_info "Starting container: $CONTAINER_NAME"
        # Start detached with full debugging enabled
        docker run -d \
            --name "$CONTAINER_NAME" \
            --privileged \
            -p 2222:22 \
            -p 5900:5900 \
            -p 9999:9999 \
            -p 5555:5555 \
            -v "$(pwd)/images:/home/user/images:rw" \
            -v "$(pwd)/share:/home/user/share:rw" \
            -e "ENABLE_VNC=1" \
            -e "DEBUG=1" \
            "$IMAGE_NAME"
        log_success "Container started"
        log_info "View logs: docker logs -f $CONTAINER_NAME"
        ;;

    stop)
        check_docker
        log_info "Stopping container: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME"
        log_success "Container stopped"
        ;;

    restart)
        check_docker
        log_info "Restarting container: $CONTAINER_NAME"
        docker restart "$CONTAINER_NAME"
        log_success "Container restarted"
        ;;

    remove|rm)
        check_docker
        log_warning "Removing container: $CONTAINER_NAME"
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
        log_success "Container removed"
        ;;

    logs)
        check_docker
        docker logs "$CONTAINER_NAME"
        ;;

    follow-logs)
        check_docker
        log_info "Following logs for: $CONTAINER_NAME"
        log_info "Press Ctrl+C to stop"
        docker logs -f "$CONTAINER_NAME"
        ;;

    exec)
        check_docker
        if [ -z "${2:-}" ]; then
            log_error "Command required"
            echo "Usage: $0 exec \"COMMAND\""
            exit 1
        fi
        log_info "Executing in container: $2"
        docker exec "$CONTAINER_NAME" bash -c "$2"
        ;;

    shell)
        check_docker
        log_info "Opening interactive shell in container"
        log_info "Type 'exit' to return"
        docker exec -it "$CONTAINER_NAME" /bin/bash
        ;;

    attach)
        check_docker
        log_warning "Attaching to container (Ctrl+P, Ctrl+Q to detach)"
        docker attach "$CONTAINER_NAME"
        ;;

    inspect)
        check_docker
        docker inspect "$CONTAINER_NAME"
        ;;

    qemu-monitor)
        check_docker
        log_info "Accessing QEMU monitor via container"
        log_info "Type QEMU commands (e.g., 'info status', 'help')"
        log_info "Press Ctrl+] then type 'quit' to exit"
        docker exec -it "$CONTAINER_NAME" telnet localhost 9999
        ;;

    qemu-serial)
        check_docker
        log_info "Accessing QEMU serial console via container"
        log_info "Press Ctrl+] then type 'quit' to exit"
        docker exec -it "$CONTAINER_NAME" telnet localhost 5555
        ;;

    qemu-ssh)
        check_docker
        log_info "SSH into Hurd instance (password: root)"
        ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost
        ;;

    stats)
        check_docker
        log_info "Container resource usage (Ctrl+C to stop)"
        docker stats "$CONTAINER_NAME"
        ;;

    top)
        check_docker
        log_info "Container processes:"
        docker top "$CONTAINER_NAME"
        ;;

    network)
        check_docker
        log_info "Container network details:"
        docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME"
        docker port "$CONTAINER_NAME"
        ;;

    ports)
        check_docker
        log_info "Port mappings for: $CONTAINER_NAME"
        docker port "$CONTAINER_NAME"
        ;;

    *)
        show_usage
        ;;
esac
