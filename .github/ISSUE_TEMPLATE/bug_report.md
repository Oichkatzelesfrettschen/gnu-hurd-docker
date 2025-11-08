---
name: Bug Report
about: Report a bug to help us improve
title: '[BUG] '
labels: 'bug'
assignees: ''
---

## Bug Description

**Clear and concise description of the bug**:


## Steps to Reproduce

1.
2.
3.

## Expected Behavior

**What you expected to happen**:


## Actual Behavior

**What actually happened**:


## Environment

**Host System**:
- OS: [e.g., Ubuntu 24.04]
- Docker version: [e.g., 24.0.7]
- Docker Compose version: [e.g., v2.23.0]
- KVM available: [yes/no]

**Hurd Image**:
- Image file: [e.g., debian-hurd-amd64-80gb.qcow2]
- Image source: [e.g., cdimage.debian.org]
- Date downloaded: [e.g., 2025-11-07]

**QEMU Configuration**:
- Acceleration: [KVM or TCG]
- RAM: [e.g., 4096 MB]
- SMP: [e.g., 2 cores]

## Logs

**Docker Compose logs**:
```
# Paste output of: docker-compose logs hurd-x86_64 | tail -100
```

**QEMU logs** (if applicable):
```
# Paste contents of: logs/qemu.log
```

**Error messages**:
```
# Paste any error messages here
```

## Screenshots

**If applicable, add screenshots to help explain the problem**:


## Additional Context

**Any other information that might be relevant**:


## Checklist

- [ ] I have searched existing issues to ensure this is not a duplicate
- [ ] I have included all requested information above
- [ ] I have attached relevant logs
- [ ] I can reproduce this bug consistently
