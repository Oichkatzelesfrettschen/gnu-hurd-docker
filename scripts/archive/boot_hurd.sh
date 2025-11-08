#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 <config_file>"
    echo "  <config_file>: Path to the QEMU configuration file."
    exit 1
}

# Check if a config file is provided
if [ -z "$1" ]; then
    usage
fi

CONFIG_FILE="$1"

# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file '$CONFIG_FILE' not found."
    exit 1
fi

# Source the configuration file to load variables
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# --- Default values for optional parameters ---
ARCH=${ARCH:-i386}
CPU=${CPU:-host}
MEMORY=${MEMORY:-1024M}
SMP=${SMP:-1}
ENABLE_KVM=${ENABLE_KVM:-yes}
NETWORK_MODE=${NETWORK_MODE:-user}
NETWORK_DEVICE=${NETWORK_DEVICE:-e1000}
HOST_FWD_SSH=${HOST_FWD_SSH:-}
VGA_TYPE=${VGA_TYPE:-std}
DISPLAY_TYPE=${DISPLAY_TYPE:-gtk}

# --- Construct the QEMU command ---
QEMU_CMD="qemu-system-${ARCH}"
QEMU_ARGS=()

# Basic VM configuration
QEMU_ARGS+=("-m" "${MEMORY}")
QEMU_ARGS+=("-cpu" "${CPU}")
QEMU_ARGS+=("-smp" "${SMP}")

# KVM acceleration
if [ "${ENABLE_KVM}" == "yes" ]; then
    QEMU_ARGS+=("-enable-kvm")
fi

# Disk image
if [ -n "${DISK_IMAGE}" ]; then
    QEMU_ARGS+=("-drive" "file=${DISK_IMAGE},format=qcow2,if=ide,cache=writeback")
else
    echo "Error: DISK_IMAGE not specified in config. VM cannot boot without a disk."
    exit 1
fi

# Network configuration
QEMU_ARGS+=("-netdev" "${NETWORK_MODE},id=net0")
if [ -n "${HOST_FWD_SSH}" ]; then
    QEMU_ARGS[${#QEMU_ARGS[@]}-1]+=",hostfwd=${HOST_FWD_SSH}"
fi
QEMU_ARGS+=("-device" "${NETWORK_DEVICE},netdev=net0")

# Graphics configuration
QEMU_ARGS+=("-vga" "${VGA_TYPE}")
QEMU_ARGS+=("-display" "${DISPLAY_TYPE}")

# --- Execute the QEMU command ---
echo "Launching QEMU with command:"
echo "${QEMU_CMD} ${QEMU_ARGS[*]}"
echo "--------------------------------------------------"

# Execute QEMU
"${QEMU_CMD}" "${QEMU_ARGS[@]}"

if [ $? -ne 0 ]; then
    echo "Error: QEMU command failed. Check your configuration and QEMU installation."
    exit 1
fi
