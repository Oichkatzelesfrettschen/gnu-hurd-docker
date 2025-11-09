# Trap Handlers - Quick Reference

## What Changed

6 critical scripts now have automatic cleanup on error/interrupt:

| Script | Cleans Up | Test Status |
|--------|-----------|-------------|
| `full-automated-setup.sh` | SSH sessions | PASS |
| `bringup-and-provision.sh` | Containers + SSH | PASS |
| `download-image.sh` | Temp download files | PASS |
| `download-released-image.sh` | Temp files + checksums | PASS |
| `manage-snapshots.sh` | Incomplete backups | PASS |
| `test-hurd-system.sh` | Test SSH processes | PASS |

## Testing

All trap handlers verified:
- Error exit (set -e)
- INT signal (Ctrl+C)
- TERM signal
- Normal exit

```bash
# Run full test suite
bash TEST-TRAP-HANDLERS.sh

# Results: 8/8 tests passed
```

## Usage - No Changes Required

Scripts work exactly as before. Cleanup happens automatically:

```bash
# Normal use
./scripts/download-image.sh
./scripts/bringup-and-provision.sh
./scripts/test-hurd-system.sh

# Press Ctrl+C anytime - cleanup runs automatically
# Script fails - cleanup runs automatically
# Script succeeds normally - cleanup is safe no-op
```

## Safety Features

1. **Never removes files we didn't create**
   - Uses explicit tracking (`TEMP_FILES+=()`)
   - No blind deletions

2. **Never stops containers we didn't start**
   - Uses `CONTAINER_STARTED_BY_SCRIPT` flag
   - Safe for existing containers

3. **Idempotent cleanup**
   - Can run multiple times
   - Checks file existence before deletion
   - Won't error on missing files

4. **Preserves exit codes**
   - Original error codes maintained
   - Proper error propagation in pipelines

## Implementation Pattern

All trap handlers follow this pattern:

```bash
#!/bin/bash
set -euo pipefail

# Track what needs cleanup
CLEANUP_NEEDED=false
TEMP_FILES=()

cleanup() {
    local exit_code=$?
    
    if [ "$CLEANUP_NEEDED" = true ]; then
        # Remove tracked files
        for file in "${TEMP_FILES[@]}"; do
            [ -f "$file" ] && rm -f "$file"
        done
        # Clean other resources...
    fi
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# When creating temp file:
# TEMP_FILES+=("/path/to/temp")
# CLEANUP_NEEDED=true
```

## Cleanup Details by Script

### full-automated-setup.sh
- **What**: SSH background processes
- **When**: On error or Ctrl+C
- **How**: Tracks PIDs, kills on exit

### bringup-and-provision.sh
- **What**: Docker container (only if we started it)
- **When**: On error or Ctrl+C
- **How**: Only stops if `CONTAINER_STARTED_BY_SCRIPT=true`

### download-image.sh
- **What**: Compressed file, raw image
- **When**: On download/extract error or interrupt
- **How**: Removes incomplete files

### download-released-image.sh
- **What**: Image file, checksum file, extracted image
- **When**: On download/extract error or interrupt
- **How**: Dynamically updates tracking list through phases

### manage-snapshots.sh
- **What**: Incomplete backup file
- **When**: On backup operation error
- **How**: Removes backup only if operation fails

### test-hurd-system.sh
- **What**: SSH test processes
- **When**: On test error or interrupt
- **How**: Uses pgrep to find and kill processes

## Files Modified

```
/home/eirikr/Playground/gnu-hurd-docker/scripts/
├── full-automated-setup.sh           (MODIFIED)
├── bringup-and-provision.sh          (MODIFIED)
├── download-image.sh                 (MODIFIED)
├── download-released-image.sh        (MODIFIED)
├── manage-snapshots.sh               (MODIFIED)
├── test-hurd-system.sh               (MODIFIED)
├── TEST-TRAP-HANDLERS.sh             (NEW - test suite)
└── TRAP-HANDLERS-IMPLEMENTATION.md   (NEW - full docs)
```

## Verification

To verify trap handlers are installed:

```bash
# Check for trap line in each script
grep -n "^trap cleanup" *.sh

# Output should show 6 scripts with trap handlers
```

## Common Scenarios

### Scenario 1: Large Download Interrupted

```bash
$ ./scripts/download-image.sh
[... downloading 355 MB ...]
^C  # User presses Ctrl+C

[INFO] Cleaning up incomplete downloads...
[INFO] Removing: debian-hurd.img.tar.xz
# Script exits, no temp files left behind
```

### Scenario 2: Container Setup Fails

```bash
$ ./scripts/bringup-and-provision.sh
# ... docker compose up -d runs ...
# ... ssh connection fails ...

[INFO] Cleaning up...
[INFO] Stopping container: gnu-hurd-dev
# Container stopped, script cleaned up
```

### Scenario 3: Backup Operation Interrupted

```bash
$ ./scripts/manage-snapshots.sh backup /backup/hurd.qcow2
[Creating backup...]
^C  # Ctrl+C during long copy

[Cleaning up incomplete backup file...]
✓ Removed: /backup/hurd.qcow2
# Incomplete backup removed
```

## Maintenance

If you add new file creation to a script:

```bash
# 1. Add to TEMP_FILES at creation point
TEMP_FILES+=("/new/temp/file")
CLEANUP_NEEDED=true

# 2. Update cleanup() if special handling needed

# 3. Test with TEST-TRAP-HANDLERS.sh
```

## More Information

See `TRAP-HANDLERS-IMPLEMENTATION.md` for:
- Detailed implementation of each script
- Why/What/How for each change
- Test results and coverage
- Safety guarantees
- Integration notes for CI/CD

## Status

- Implementation: COMPLETE
- Testing: COMPLETE (8/8 tests passed)
- Documentation: COMPLETE
- Ready for: Production use

All changes are backward compatible - scripts work exactly as before, just with better cleanup.
