#!/bin/bash
set -euo pipefail

# Shared helpers for installer serial-log parsing and evidence extraction.

sanitize_serial_tail() {
    local serial_log="$1"
    local bytes="${2:-262144}"
    if [ ! -f "$serial_log" ]; then
        return 0
    fi
    tail -c "$bytes" "$serial_log" 2>/dev/null \
        | tr -d '\r' \
        | perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(\a|\e\\)//g'
}

extract_partman_error_lines() {
    local cleaned_log="$1"
    if [ ! -f "$cleaned_log" ]; then
        return 0
    fi
    rg -n -i \
        "partman|failed to create|error|computing the new partitions|write the changes|filesystem|swap" \
        "$cleaned_log" || true
}
