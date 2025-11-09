# Research and Deep Dives

**Last Updated**: 2025-11-07
**Section**: 07-RESEARCH
**Purpose**: In-depth research, migration insights, and lessons learned

---

## Overview

This section contains comprehensive research findings, migration documentation, and institutional knowledge gained from developing and operating the GNU/Hurd x86_64 Docker environment.

**Audience**: Advanced users, researchers, system architects, maintainers

**Prerequisites**: Solid understanding of Mach/Hurd, QEMU, Docker

---

## Documents in This Section

### [MACH-QEMU.md](MACH-QEMU.md)
**Mach microkernel and QEMU compatibility research**

- Mach/QEMU interaction deep dive
- nf_tables kernel networking (Docker integration)
- QEMU image investigation (20-step process)
- x86_64 successful implementation
- Boot verification and system testing
- C compilation tests
- Known limitations and workarounds

**When to use**: Understand Mach/QEMU integration, debug boot issues, kernel debugging

---

### [X86_64-MIGRATION.md](X86_64-MIGRATION.md)
**Complete i386 → x86_64 migration documentation**

- Migration rationale (stability, performance, modern hardware)
- Technical challenges (binary naming, CPU models, storage interfaces)
- Breaking changes (QEMU flags, machine types, RAM requirements)
- Critical fixes (qemu-system-x86_64 vs x86-64 naming)
- Migration statistics (49 files changed, 8.1 GB freed)
- Smart KVM/TCG detection
- Pre-provisioned image advantages
- Architecture comparison table (i386 vs x86_64)

**When to use**: Understand migration decisions, reference x86_64 specifics, troubleshoot architecture issues

---

### [LESSONS-LEARNED.md](LESSONS-LEARNED.md)
**Comprehensive operational wisdom and key takeaways**

- Architecture decisions (x86_64-only, storage, network, machine type)
- QEMU optimization (KVM, CPU, memory, SMP)
- Hurd-specific insights (boot time, microkernel behavior, packages)
- CI/CD wisdom (pre-provisioned images, workflow simplification)
- Documentation management (sprawl prevention, best practices)
- Operational best practices (SSH, snapshots, clean shutdown)
- Binary naming and tooling (critical naming conventions)
- Performance optimization (QCOW2, cache modes)
- Provisioning features (dev tools, user management)
- 20 key takeaways (technical and process)

**When to use**: Learn from past mistakes, understand design rationale, avoid known pitfalls

---

## Research Highlights

### Key Technical Discoveries

**1. x86_64 Binary Naming (Critical)**
```bash
# CORRECT (Ubuntu/Debian)
Package: qemu-system-x86          # hyphen
Binary:  /usr/bin/qemu-system-x86_64  # UNDERSCORE!

# WRONG (common mistake)
qemu-system-x86-64  ❌  # with hyphens - doesn't exist!
```

**Impact**: Hours wasted debugging "command not found" errors

**File**: [X86_64-MIGRATION.md](X86_64-MIGRATION.md#binary-naming-critical-fix)

---

**2. nf_tables Kernel Mismatch (Docker Networking)**
```bash
# Problem: Docker networking fails with "nf_tables not found"
# Root cause: Kernel module version mismatch

# Solution:
sudo pacman -Syu linux-cachyos linux-cachyos-headers
sudo reboot
```

**Impact**: Complete Docker networking failure

**File**: [MACH-QEMU.md](MACH-QEMU.md#critical-discovery-nf_tables-fix)

---

**3. Pre-Provisioned Images (CI/CD Game Changer)**

**Traditional Workflow**:
- Time: 20-40 minutes
- Reliability: 60-70% (serial automation fragile)

**Pre-Provisioned Workflow**:
- Time: 2-5 minutes (85% faster!)
- Reliability: 95%+ (no serial automation)

**Impact**: 3-6x faster CI, 35% more reliable

**File**: [LESSONS-LEARNED.md](LESSONS-LEARNED.md#ci-cd-wisdom)

---

### Architecture Evolution

**i386 (Legacy)** → **x86_64 (Current)**

| Aspect | i386 | x86_64 |
|--------|------|--------|
| Binary | qemu-system-i386 | qemu-system-x86_64 |
| RAM | 1.5 GB | 4 GB |
| SMP | 1 core (unstable with >1) | 1-2 cores (stable) |
| CPU | `-cpu pentium` | `-cpu max` or `-cpu host` |
| Storage | IDE (issues on q35) | SATA/AHCI (recommended) |
| Machine | q35 (I/O errors) | pc (stable) |
| Status | Deprecated 2025-11-07 | Production |

**File**: [X86_64-MIGRATION.md](X86_64-MIGRATION.md#x86_64-vs-i386-configuration)

---

### Lessons Learned: Top 10

1. **x86_64 is the future** - Always choose x86_64 for new Hurd work
2. **KVM is critical** - 3x faster boot, essential for good UX
3. **Pre-provision images** - 85% faster CI, 35% more reliable
4. **Clean shutdown always** - Prevents fsck errors
5. **Snapshots before changes** - Easy rollback
6. **Use e1000 NIC** - Best Hurd compatibility
7. **Use SATA/AHCI storage** - Best x86_64 Hurd performance
8. **Use pc machine type** - Avoid q35 I/O errors
9. **1-2 cores sufficient** - SMP still maturing
10. **4 GB RAM optimal** - x86_64 needs more than i386

**File**: [LESSONS-LEARNED.md](LESSONS-LEARNED.md#key-takeaways)

---

## Quick Navigation

**Getting Started**:
- [Installation](../01-GETTING-STARTED/INSTALLATION.md)
- [Quickstart](../01-GETTING-STARTED/QUICKSTART.md)

**Architecture** (implementation of research):
- [System Design](../02-ARCHITECTURE/SYSTEM-DESIGN.md)
- [QEMU Configuration](../02-ARCHITECTURE/QEMU-CONFIGURATION.md)

**Troubleshooting** (apply research to problems):
- [Common Issues](../06-TROUBLESHOOTING/COMMON-ISSUES.md)
- [SSH Issues](../06-TROUBLESHOOTING/SSH-ISSUES.md)
- [Filesystem Errors](../06-TROUBLESHOOTING/FSCK-ERRORS.md)

**CI/CD** (apply research to automation):
- [Setup](../05-CI-CD/SETUP.md)
- [Workflows](../05-CI-CD/WORKFLOWS.md)
- [Pre-Provisioned Images](../05-CI-CD/PROVISIONED-IMAGE.md)

---

## For Researchers

**Methodology**:
- Systematic investigation (20-step QEMU image process)
- Root cause analysis (nf_tables kernel mismatch)
- Performance benchmarking (KVM vs TCG, provisioned vs serial)
- Documentation of failures (lessons learned)

**Key Resources**:
- [MACH-QEMU.md](MACH-QEMU.md) - Technical deep dive
- [X86_64-MIGRATION.md](X86_64-MIGRATION.md) - Migration process
- [LESSONS-LEARNED.md](LESSONS-LEARNED.md) - Operational wisdom

---

## For Architects

**Design Decisions**:
- Why x86_64-only? [X86_64-MIGRATION.md](X86_64-MIGRATION.md#migration-rationale)
- Why SATA/AHCI? [LESSONS-LEARNED.md](LESSONS-LEARNED.md#architecture-decisions)
- Why pre-provisioned images? [LESSONS-LEARNED.md](LESSONS-LEARNED.md#ci-cd-wisdom)
- Why e1000 NIC? [LESSONS-LEARNED.md](LESSONS-LEARNED.md#architecture-decisions)

**Trade-offs**:
- KVM vs TCG: Performance vs compatibility
- Simplicity vs features: One workflow vs six
- Automation vs reliability: Pre-provisioned vs serial

---

## For Maintainers

**Institutional Knowledge**:
- [LESSONS-LEARNED.md](LESSONS-LEARNED.md) - Don't repeat mistakes
- [X86_64-MIGRATION.md](X86_64-MIGRATION.md) - Migration process template
- [MACH-QEMU.md](MACH-QEMU.md) - Debugging methodology

**Critical Information**:
- Binary naming conventions (underscores vs hyphens!)
- Kernel module dependencies (nf_tables)
- Pre-provisioning strategy (85% faster CI)
- Clean shutdown procedures (prevent fsck)

**Document Updates**:
- Add new lessons to [LESSONS-LEARNED.md](LESSONS-LEARNED.md)
- Track architecture changes in [X86_64-MIGRATION.md](X86_64-MIGRATION.md)
- Document research in [MACH-QEMU.md](MACH-QEMU.md)

---

## Research Metrics

### Migration Impact (i386 → x86_64)

**Code Changes**:
- Files changed: 49
- Lines inserted: 8,786
- Lines deleted: 2,485
- Commit hash: 445eca9

**Disk Space**:
- Before: 14.9 GB (i386 + x86_64)
- After: 6.8 GB (x86_64 only)
- Freed: 8.1 GB

**Reliability**:
- i386 stability: Moderate (SMP issues, storage issues)
- x86_64 stability: High (better SMP, SATA/AHCI support)

**File**: [X86_64-MIGRATION.md](X86_64-MIGRATION.md#migration-statistics)

---

### CI/CD Performance

**Serial Automation (Traditional)**:
- Time: 20-40 minutes
- Success rate: 60-70%
- Complexity: High (expect scripts)

**Pre-Provisioned Images**:
- Time: 2-5 minutes (85% faster)
- Success rate: 95%+ (35% more reliable)
- Complexity: Low (simple download)

**Speedup**: 3-6x faster, 35% more reliable

**File**: [LESSONS-LEARNED.md](LESSONS-LEARNED.md#ci-cd-wisdom)

---

### Boot Performance

**KVM Acceleration**:
- Boot time: 30-60 seconds
- Performance: 80-90% native
- Availability: Self-hosted runners, local development

**TCG Emulation**:
- Boot time: 3-5 minutes
- Performance: 10-20% native
- Availability: GitHub Actions, no KVM

**Impact**: KVM 3x faster boot

**File**: [LESSONS-LEARNED.md](LESSONS-LEARNED.md#qemu-optimization)

---

## Future Research Directions

1. **SMP Stability**: Test 4-8 cores on x86_64
2. **VirtIO Networking**: Alternative to e1000
3. **9p Filesystem**: Shared folders host ↔ guest
4. **Nested Virtualization**: Hurd inside Hurd
5. **Hurd-Specific Optimizations**: Microkernel tuning

---

[← Back to Documentation Index](../INDEX.md)
