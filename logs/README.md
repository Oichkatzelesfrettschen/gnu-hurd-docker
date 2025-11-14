# Logs Directory

This directory contains runtime logs generated during QEMU operations and testing.

## Contents

- QEMU logs (`qemu*.log`)
- Serial console logs (`serial*.log`)
- Test execution logs
- Debug output files

## Notes

- This directory is gitignored (see `.gitignore`)
- Logs are automatically generated during runtime
- Clean old logs periodically to save disk space
- For debugging, check logs with: `tail -f logs/*.log`

## Log Retention

Logs are not version controlled. They are ephemeral runtime artifacts.
