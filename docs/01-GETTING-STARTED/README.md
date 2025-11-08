# Getting Started with GNU/Hurd Docker

**Last Updated**: 2025-11-07
**Section**: 01-GETTING-STARTED
**Purpose**: Quick start guides and installation instructions

---

## Overview

This section provides everything you need to get started with the GNU/Hurd x86_64 Docker environment, from installation to your first successful boot.

**Audience**: New users, quick reference

**Time to Complete**: 15-30 minutes (installation + quickstart)

---

## Documents in This Section

### [INSTALLATION.md](INSTALLATION.md)
**Complete installation guide with all prerequisites and setup steps**

- System requirements (CPU, RAM, disk space)
- Docker and QEMU installation (Linux, macOS, Windows)
- Image download and setup
- Troubleshooting installation issues

**When to use**: First-time setup, reinstallation, or reference

---

### [QUICKSTART.md](QUICKSTART.md)
**Fast-track guide to boot GNU/Hurd and verify functionality**

- Quick setup (5-minute path)
- Boot verification
- First SSH connection
- Basic system tests

**When to use**: After installation, want to quickly verify everything works

---

## Quick Navigation

**Next Steps After Getting Started**:
- [Architecture](../02-ARCHITECTURE/) - Understand system design
- [Configuration](../03-CONFIGURATION/) - Customize your setup
- [Operation](../04-OPERATION/) - Day-to-day usage

**Reference Materials**:
- [Troubleshooting](../06-TROUBLESHOOTING/) - Fix common issues
- [Scripts Reference](../08-REFERENCE/SCRIPTS.md) - Automation tools
- [Credentials](../08-REFERENCE/CREDENTIALS.md) - Access and security

**Advanced Topics**:
- [CI/CD](../05-CI-CD/) - Automated workflows
- [Research](../07-RESEARCH/) - Deep dives and lessons learned

---

## Typical User Journey

1. **Installation** (15-20 min)
   - Read [INSTALLATION.md](INSTALLATION.md)
   - Install Docker and QEMU
   - Download Hurd image

2. **Quickstart** (5-10 min)
   - Read [QUICKSTART.md](QUICKSTART.md)
   - Boot container
   - Connect via SSH
   - Verify functionality

3. **Next Steps**
   - Customize configuration ([Configuration](../03-CONFIGURATION/))
   - Learn daily operations ([Operation](../04-OPERATION/))
   - Explore advanced features ([CI/CD](../05-CI-CD/))

---

## Support

**If you encounter issues**:
1. Check [Troubleshooting](../06-TROUBLESHOOTING/COMMON-ISSUES.md)
2. Review [SSH Issues](../06-TROUBLESHOOTING/SSH-ISSUES.md) (most common)
3. Check [Filesystem Errors](../06-TROUBLESHOOTING/FSCK-ERRORS.md) if boot fails

**For questions about**:
- Access credentials → [CREDENTIALS.md](../08-REFERENCE/CREDENTIALS.md)
- Available scripts → [SCRIPTS.md](../08-REFERENCE/SCRIPTS.md)
- System architecture → [SYSTEM-DESIGN.md](../02-ARCHITECTURE/SYSTEM-DESIGN.md)

---

[← Back to Documentation Index](../INDEX.md)
