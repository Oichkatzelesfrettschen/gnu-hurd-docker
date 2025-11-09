# Archived Scripts

This directory contains scripts that have been superseded or are no longer actively used.

## Why Archive Instead of Delete?

- Preserve historical context and implementation details
- Allow recovery if functionality is needed again
- Document evolution of the project

## Archived Scripts

### test-docker-provision.sh
**Archived:** 2025-11-08
**Reason:** Superseded by test-hurd-system.sh (comprehensive test suite)
**Original Purpose:** Test Docker provisioning workflow
**Replaced By:** test-hurd-system.sh provides more comprehensive testing including:
- Container status verification
- Boot process testing
- User account validation
- Compilation tests
- Package verification
- Filesystem checks
- Hurd-specific feature tests

**May Delete After:** 2 release cycles with no usage

### boot_hurd.sh
**Archived:** 2025-11-08
**Reason:** Superseded by docker compose orchestration
**Original Purpose:** Simple QEMU wrapper taking config file argument
**Replaced By:** docker-compose.yml provides full orchestration with:
- Automated container management
- Port forwarding configuration
- Volume mounting
- Network setup
- Environment variable management

The inline QEMU command in entrypoint.sh now serves the same purpose with better integration.

**May Delete After:** 2 release cycles with no usage

## Recovery Process

If you need functionality from an archived script:

1. Review the archived script to understand its implementation
2. Check if current scripts provide the same functionality
3. If needed, extract specific logic and integrate into current scripts
4. Do not restore entire archived script - refactor and modernize instead

## Deletion Policy

Archived scripts may be permanently deleted after:
- 2 release cycles (approximately 6 months)
- Confirmation that no workflows reference them
- Verification that functionality is covered elsewhere

## Questions?

If unsure whether functionality is still needed:
1. Check git history: `git log --all --full-history -- archive/script.sh`
2. Search for usage: `grep -r "script.sh" ..`
3. Review issue tracker for feature requests
4. Ask in project discussions before deleting
