#!/bin/bash
set -euo pipefail

# =============================================================================
# GNU/Hurd Performance Benchmark: KVM vs TCG vs Libvirt
# =============================================================================
# PURPOSE:
# - Compare boot performance across different virtualization backends
# - Measure KVM vs TCG acceleration modes
# - Compare Docker/Podman vs Libvirt implementations
# - Generate reproducible benchmark results with timestamps
#
# MODES:
#   docker-kvm    - Docker/Podman with KVM overlay
#   docker-tcg    - Docker/Podman without KVM (TCG emulation)
#   libvirt-kvm   - Libvirt domain with KVM acceleration
#   libvirt-tcg   - Libvirt domain with TCG (KVM disabled)
#   all           - Run all benchmarks sequentially
#
# OUTPUT:
#   Logs to: logs/benchmarks/<timestamp>-<mode>.log
#   Summary to stdout (table format)
#
# REQUIREMENTS:
#   For Docker/Podman modes:
#     - Docker or Podman installed
#     - docker-compose.yml, docker-compose.kvm.yml present
#
#   For Libvirt modes:
#     - libvirt daemon running
#     - domain already defined (./scripts/libvirt-hurd.sh define)
#     - virsh available
#
# USAGE:
#   ./scripts/benchmark-kvm.sh docker-kvm      # Single benchmark
#   ./scripts/benchmark-kvm.sh all              # All benchmarks
#   TIMEOUT=120 ./scripts/benchmark-kvm.sh all  # With custom timeout
#
# ENVIRONMENT VARIABLES:
#   TIMEOUT         - Max boot wait time in seconds (default: 300)
#   DOMAIN_NAME     - Libvirt domain name (default: gnu-hurd-dev)
#   SSH_PORT        - SSH port for health check (default: 2222)
#   OUTPUT_DIR      - Benchmark log directory (default: logs/benchmarks/)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../" && pwd)"
cd "$REPO_ROOT"

# Configuration
TIMEOUT="${TIMEOUT:-300}"
DOMAIN_NAME="${DOMAIN_NAME:-gnu-hurd-dev}"
SSH_PORT="${SSH_PORT:-2222}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/logs/benchmarks}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Color output
echo_info() { echo "[INFO] $*"; }
echo_success() { echo "[SUCCESS] $*"; }
echo_warning() { echo "[WARNING] $*" >&2; }
echo_error() { echo "[ERROR] $*" >&2; }

# Create output directory
mkdir -p "$OUTPUT_DIR"

# =============================================================================
# Utility Functions
# =============================================================================

get_elapsed_time() {
    local start_time=$1
    local end_time=$2
    echo $((end_time - start_time))
}

# Check SSH connectivity
wait_for_ssh() {
    local max_attempts=$1
    local port=$2
    local host="${3:-127.0.0.1}"
    local attempt=0

    while (( attempt < max_attempts )); do
        if timeout 2 bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
            return 0
        fi
        (( attempt++ ))
        sleep 1
    done

    return 1
}

# =============================================================================
# Benchmark: Docker/Podman with KVM
# =============================================================================

benchmark_docker_kvm() {
    local logfile="${OUTPUT_DIR}/${TIMESTAMP}-docker-kvm.log"

    echo_info "Starting Docker/Podman KVM benchmark..."
    {
        echo "=== Docker/Podman KVM Benchmark ==="
        echo "Timestamp: $(date)"
        echo "Timeout: ${TIMEOUT}s"
        echo ""
    } | tee "$logfile"

    local start_epoch=$(date +%s)

    # Bring down any existing containers
    echo_info "Cleaning up existing containers..."
    docker compose down >> "$logfile" 2>&1 || podman-compose down >> "$logfile" 2>&1 || true

    # Start with KVM overlay
    echo_info "Starting container with KVM overlay..."
    echo "[$(date)] Starting container..." >> "$logfile"

    if ! docker compose -f docker-compose.yml -f docker-compose.kvm.yml up -d >> "$logfile" 2>&1; then
        echo "[ERROR] Failed to start container" | tee -a "$logfile"
        return 1
    fi

    # Wait for boot (SSH connectivity)
    echo_info "Waiting for boot (max ${TIMEOUT}s)..."
    echo "[$(date)] Waiting for SSH on port ${SSH_PORT}..." >> "$logfile"

    if wait_for_ssh "$TIMEOUT" "$SSH_PORT"; then
        local end_epoch=$(date +%s)
        local elapsed=$(get_elapsed_time "$start_epoch" "$end_epoch")

        echo_success "Boot complete in ${elapsed}s"
        {
            echo "[SUCCESS] Boot completed"
            echo "Boot time: ${elapsed}s"
            echo "End time: $(date)"
        } >> "$logfile"

        echo "$elapsed"
        return 0
    else
        echo_error "Boot timeout after ${TIMEOUT}s"
        {
            echo "[ERROR] Boot timeout"
            echo "Total time: ${TIMEOUT}s"
        } >> "$logfile"

        return 1
    fi
}

# =============================================================================
# Benchmark: Docker/Podman with TCG (no KVM)
# =============================================================================

benchmark_docker_tcg() {
    local logfile="${OUTPUT_DIR}/${TIMESTAMP}-docker-tcg.log"

    echo_info "Starting Docker/Podman TCG (non-KVM) benchmark..."
    {
        echo "=== Docker/Podman TCG (Non-KVM) Benchmark ==="
        echo "Timestamp: $(date)"
        echo "Timeout: ${TIMEOUT}s"
        echo ""
    } | tee "$logfile"

    local start_epoch=$(date +%s)

    # Bring down any existing containers
    echo_info "Cleaning up existing containers..."
    docker compose down >> "$logfile" 2>&1 || podman-compose down >> "$logfile" 2>&1 || true

    # Start WITHOUT KVM overlay (standard docker-compose.yml only)
    echo_info "Starting container without KVM (TCG mode)..."
    echo "[$(date)] Starting container..." >> "$logfile"

    # Set environment to disable KVM
    if ! AUTO_DISABLE_KVM_FOR_IDE=1 docker compose -f docker-compose.yml up -d >> "$logfile" 2>&1; then
        echo "[ERROR] Failed to start container" | tee -a "$logfile"
        return 1
    fi

    # Wait for boot (SSH connectivity)
    echo_info "Waiting for boot (max ${TIMEOUT}s)..."
    echo "[$(date)] Waiting for SSH on port ${SSH_PORT}..." >> "$logfile"

    if wait_for_ssh "$TIMEOUT" "$SSH_PORT"; then
        local end_epoch=$(date +%s)
        local elapsed=$(get_elapsed_time "$start_epoch" "$end_epoch")

        echo_success "Boot complete in ${elapsed}s"
        {
            echo "[SUCCESS] Boot completed"
            echo "Boot time: ${elapsed}s"
            echo "End time: $(date)"
        } >> "$logfile"

        echo "$elapsed"
        return 0
    else
        echo_error "Boot timeout after ${TIMEOUT}s"
        {
            echo "[ERROR] Boot timeout"
            echo "Total time: ${TIMEOUT}s"
        } >> "$logfile"

        return 1
    fi
}

# =============================================================================
# Benchmark: Libvirt with KVM
# =============================================================================

benchmark_libvirt_kvm() {
    local logfile="${OUTPUT_DIR}/${TIMESTAMP}-libvirt-kvm.log"

    echo_info "Starting Libvirt KVM benchmark..."
    {
        echo "=== Libvirt KVM Benchmark ==="
        echo "Domain: ${DOMAIN_NAME}"
        echo "Timestamp: $(date)"
        echo "Timeout: ${TIMEOUT}s"
        echo ""
    } | tee "$logfile"

    # Check if domain exists
    if ! virsh dominfo "$DOMAIN_NAME" > /dev/null 2>&1; then
        echo_error "Domain '${DOMAIN_NAME}' not defined"
        echo "[ERROR] Domain not defined" >> "$logfile"
        return 1
    fi

    local start_epoch=$(date +%s)

    # Stop domain if running
    echo_info "Ensuring domain is stopped..."
    if virsh list --running 2>/dev/null | grep -q "$DOMAIN_NAME"; then
        echo_info "Stopping domain..."
        virsh shutdown "$DOMAIN_NAME" >> "$logfile" 2>&1 || virsh destroy "$DOMAIN_NAME" >> "$logfile" 2>&1
        sleep 3
    fi

    # Start domain
    echo_info "Starting domain..."
    echo "[$(date)] Starting domain..." >> "$logfile"

    if ! virsh start "$DOMAIN_NAME" >> "$logfile" 2>&1; then
        echo "[ERROR] Failed to start domain" | tee -a "$logfile"
        return 1
    fi

    # Wait for SSH
    echo_info "Waiting for boot (max ${TIMEOUT}s)..."
    echo "[$(date)] Waiting for SSH..." >> "$logfile"

    if wait_for_ssh "$TIMEOUT" "$SSH_PORT"; then
        local end_epoch=$(date +%s)
        local elapsed=$(get_elapsed_time "$start_epoch" "$end_epoch")

        echo_success "Boot complete in ${elapsed}s"
        {
            echo "[SUCCESS] Boot completed"
            echo "Boot time: ${elapsed}s"
            echo "End time: $(date)"
        } >> "$logfile"

        echo "$elapsed"
        return 0
    else
        echo_error "Boot timeout after ${TIMEOUT}s"
        {
            echo "[ERROR] Boot timeout"
            echo "Total time: ${TIMEOUT}s"
        } >> "$logfile"

        return 1
    fi
}

# =============================================================================
# Benchmark: Libvirt with TCG (KVM disabled)
# =============================================================================

benchmark_libvirt_tcg() {
    local logfile="${OUTPUT_DIR}/${TIMESTAMP}-libvirt-tcg.log"

    echo_info "Starting Libvirt TCG (non-KVM) benchmark..."
    {
        echo "=== Libvirt TCG (Non-KVM) Benchmark ==="
        echo "Domain: ${DOMAIN_NAME}"
        echo "Timestamp: $(date)"
        echo "Timeout: ${TIMEOUT}s"
        echo ""
    } | tee "$logfile"

    # Check if domain exists
    if ! virsh dominfo "$DOMAIN_NAME" > /dev/null 2>&1; then
        echo_error "Domain '${DOMAIN_NAME}' not defined"
        echo "[ERROR] Domain not defined" >> "$logfile"
        return 1
    fi

    echo_warning "Modifying domain to disable KVM (will be reverted after test)..."

    # Back up domain XML
    local backup_xml=$(mktemp)
    virsh dumpxml "$DOMAIN_NAME" > "$backup_xml"

    local start_epoch=$(date +%s)

    # Stop domain if running
    echo_info "Ensuring domain is stopped..."
    if virsh list --running 2>/dev/null | grep -q "$DOMAIN_NAME"; then
        echo_info "Stopping domain..."
        virsh shutdown "$DOMAIN_NAME" >> "$logfile" 2>&1 || virsh destroy "$DOMAIN_NAME" >> "$logfile" 2>&1
        sleep 3
    fi

    # Modify domain to remove KVM flag
    local tcg_xml=$(mktemp)
    sed 's/<qemu:arg value="-enable-kvm"\/>/<!-- KVM disabled for TCG test -->/g' "$backup_xml" > "$tcg_xml"

    echo_info "Redefining domain without KVM..."
    virsh undefine "$DOMAIN_NAME" >> "$logfile" 2>&1
    virsh define "$tcg_xml" >> "$logfile" 2>&1

    # Start domain
    echo_info "Starting domain in TCG mode..."
    echo "[$(date)] Starting domain..." >> "$logfile"

    if ! virsh start "$DOMAIN_NAME" >> "$logfile" 2>&1; then
        echo "[ERROR] Failed to start domain" | tee -a "$logfile"
        virsh define "$backup_xml" > /dev/null 2>&1  # Restore
        return 1
    fi

    # Wait for SSH
    echo_info "Waiting for boot (max ${TIMEOUT}s)..."
    echo "[$(date)] Waiting for SSH..." >> "$logfile"

    local elapsed=0
    if wait_for_ssh "$TIMEOUT" "$SSH_PORT"; then
        local end_epoch=$(date +%s)
        elapsed=$(get_elapsed_time "$start_epoch" "$end_epoch")

        echo_success "Boot complete in ${elapsed}s"
        {
            echo "[SUCCESS] Boot completed"
            echo "Boot time: ${elapsed}s"
            echo "End time: $(date)"
        } >> "$logfile"
    else
        echo_error "Boot timeout after ${TIMEOUT}s"
        {
            echo "[ERROR] Boot timeout"
            echo "Total time: ${TIMEOUT}s"
        } >> "$logfile"
        elapsed=$TIMEOUT
    fi

    # Restore original domain
    echo_info "Restoring original domain configuration..."
    virsh shutdown "$DOMAIN_NAME" >> /dev/null 2>&1 || virsh destroy "$DOMAIN_NAME" >> /dev/null 2>&1
    virsh undefine "$DOMAIN_NAME" >> /dev/null 2>&1
    virsh define "$backup_xml" >> /dev/null 2>&1

    # Cleanup temp files
    rm -f "$backup_xml" "$tcg_xml"

    echo "$elapsed"
    return 0
}

# =============================================================================
# Main Dispatcher
# =============================================================================

run_benchmark() {
    local mode=$1
    local result

    case "$mode" in
        docker-kvm)
            result=$(benchmark_docker_kvm) && echo "$result"
            ;;
        docker-tcg)
            result=$(benchmark_docker_tcg) && echo "$result"
            ;;
        libvirt-kvm)
            result=$(benchmark_libvirt_kvm) && echo "$result"
            ;;
        libvirt-tcg)
            result=$(benchmark_libvirt_tcg) && echo "$result"
            ;;
        *)
            echo_error "Unknown benchmark mode: $mode"
            return 1
            ;;
    esac
}

# =============================================================================
# Main
# =============================================================================

main() {
    local mode="${1:-docker-kvm}"

    if [[ "$mode" == "help" ]] || [[ "$mode" == "-h" ]]; then
        cat << 'EOF'
GNU/Hurd KVM Benchmark Script

USAGE:
  ./scripts/benchmark-kvm.sh [MODE]

MODES:
  docker-kvm    Benchmark Docker/Podman with KVM acceleration
  docker-tcg    Benchmark Docker/Podman with TCG (no KVM)
  libvirt-kvm   Benchmark Libvirt with KVM acceleration
  libvirt-tcg   Benchmark Libvirt with TCG (no KVM)
  all           Run all benchmarks sequentially

ENVIRONMENT VARIABLES:
  TIMEOUT       Max boot wait time in seconds (default: 300)
  DOMAIN_NAME   Libvirt domain name (default: gnu-hurd-dev)
  SSH_PORT      SSH port for health check (default: 2222)
  OUTPUT_DIR    Benchmark log directory (default: logs/benchmarks/)

EXAMPLES:
  # Single benchmark
  ./scripts/benchmark-kvm.sh docker-kvm

  # All benchmarks with 60s timeout
  TIMEOUT=60 ./scripts/benchmark-kvm.sh all

  # Libvirt with custom domain name
  DOMAIN_NAME=my-hurd ./scripts/benchmark-kvm.sh libvirt-kvm

NOTES:
- Results are saved to: logs/benchmarks/<timestamp>-<mode>.log
- For Docker/Podman benchmarks: docker-compose.yml and docker-compose.kvm.yml required
- For Libvirt benchmarks: domain must be defined (./scripts/libvirt-hurd.sh define)
- SSH port must be accessible (default: 2222)
EOF
        return 0
    fi

    if [[ "$mode" == "all" ]]; then
        echo_info "Running all benchmarks..."
        echo ""
        echo "=========================================="
        echo "GNU/Hurd Performance Benchmarks"
        echo "=========================================="
        echo ""

        declare -A results

        for bench_mode in docker-kvm docker-tcg libvirt-kvm libvirt-tcg; do
            echo ">>> Running: $bench_mode"
            if result=$(run_benchmark "$bench_mode" 2>&1); then
                results[$bench_mode]="$result"
                echo "Boot time: ${result}s"
            else
                results[$bench_mode]="TIMEOUT"
                echo "Boot time: TIMEOUT or ERROR"
            fi
            echo ""
            sleep 2
        done

        # Print summary
        echo "=========================================="
        echo "Summary"
        echo "=========================================="
        echo ""
        printf "%-20s %10s %10s\n" "Mode" "Boot Time" "Speedup"
        printf "%-20s %10s %10s\n" "----" "---------" "-------"

        local docker_kvm_time="${results[docker-kvm]:-0}"

        for mode in "${!results[@]}"; do
            local time="${results[$mode]}"
            if [[ "$time" == "TIMEOUT" ]] || [[ "$time" == "0" ]]; then
                printf "%-20s %10s %10s\n" "$mode" "$time" "—"
            else
                local speedup="1.0x"
                if [[ "$docker_kvm_time" != "0" ]] && [[ "$docker_kvm_time" != "$time" ]]; then
                    speedup=$(awk "BEGIN {printf \"%.1fx\", $docker_kvm_time / $time}")
                fi
                printf "%-20s %10ss %10s\n" "$mode" "$time" "$speedup"
            fi
        done

        echo ""
        echo "Logs saved to: $OUTPUT_DIR"
    else
        run_benchmark "$mode"
    fi
}

main "$@"
