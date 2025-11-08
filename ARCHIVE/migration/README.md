# Migration Archive

**Purpose**: Historical documentation from the i386 → x86_64 migration and documentation consolidation

**Archive Date**: 2025-11-07

**Status**: **DEPRECATED** - Reference only, do not use for active work

---

## Overview

This directory contains documents from two major transitions:

1. **Architecture Migration** (i386 → x86_64)
   - Transition from 32-bit i386 to 64-bit x86_64 architecture
   - Date: 2025-11-07
   - Impact: Breaking change, i386 deprecated entirely

2. **Documentation Consolidation**
   - Transition from 53 fragmented files to 26 organized documents
   - Structure: 8-section organized documentation
   - Reduction: 55% fewer files

---

## Why Archived?

These documents served critical purposes during migration but are now:

- **Superseded**: Replaced by consolidated documentation in `/docs`
- **Historical**: Capture decision-making process and rationale
- **Reference**: Useful for understanding migration choices
- **Transitional**: Temporary guides during migration period

**For current documentation**: See `/docs/INDEX.md`

---

## Documents in This Archive

### Core Migration Documents

**1. X86_64-MIGRATION-AND-CONSOLIDATION-PLAN.md**
- **Purpose**: Master plan for i386 → x86_64 migration
- **Content**: Migration strategy, breaking changes, timeline
- **Superseded by**: [docs/07-RESEARCH/X86_64-MIGRATION.md](../../docs/07-RESEARCH/X86_64-MIGRATION.md)

**2. README-X86_64-MIGRATION.md**
- **Purpose**: User-facing migration README
- **Content**: Migration instructions, what changed, how to adapt
- **Superseded by**: [docs/01-GETTING-STARTED/INSTALLATION.md](../../docs/01-GETTING-STARTED/INSTALLATION.md)

**3. X86_64-MIGRATION-COMPLETE.md**
- **Purpose**: Post-migration completion report
- **Content**: Final statistics, verification checklist, next steps
- **Superseded by**: [docs/07-RESEARCH/LESSONS-LEARNED.md](../../docs/07-RESEARCH/LESSONS-LEARNED.md)

**4. CI-CD-MIGRATION-SUMMARY.md**
- **Purpose**: CI/CD workflow migration summary
- **Content**: Old vs new workflows, GitHub Actions changes
- **Superseded by**: [docs/05-CI-CD/SETUP.md](../../docs/05-CI-CD/SETUP.md)

**5. X86_64-AUDIT-AND-ACTION-REPORT.md**
- **Purpose**: Pre-migration audit findings
- **Content**: Issues discovered, recommended actions, priorities
- **Superseded by**: Migration completed, issues resolved

---

### Audit and Analysis Documents

**6. REPO-AUDIT-FINDINGS.md**
- **Purpose**: Repository structure audit
- **Content**: File sprawl analysis, redundancy detection, cleanup recommendations
- **Superseded by**: Consolidation completed (53 → 26 files)

**7. HURD-SYSTEM-AUDIT.md**
- **Purpose**: Hurd system functionality audit
- **Content**: System tests, compatibility checks, performance benchmarks
- **Superseded by**: [docs/06-TROUBLESHOOTING/COMMON-ISSUES.md](../../docs/06-TROUBLESHOOTING/COMMON-ISSUES.md)

---

### Transitional Setup Guides (Superseded)

**8. QUICKSTART-CI-SETUP.md**
- **Purpose**: Fast CI setup during migration
- **Content**: Temporary CI setup instructions
- **Superseded by**: [docs/05-CI-CD/SETUP.md](../../docs/05-CI-CD/SETUP.md)

**9. X86_64-ONLY-SETUP.md**
- **Purpose**: x86_64-only setup guide (transitional)
- **Content**: Post-migration setup instructions
- **Superseded by**: [docs/01-GETTING-STARTED/INSTALLATION.md](../../docs/01-GETTING-STARTED/INSTALLATION.md)

**10. CI-CD-GUIDE-HURD.md**
- **Purpose**: Early CI/CD guide for Hurd
- **Content**: GitHub Actions setup, workflows, troubleshooting
- **Superseded by**: [docs/05-CI-CD/](../../docs/05-CI-CD/) (complete section)

**11. COMPREHENSIVE-IMAGE-GUIDE.md**
- **Purpose**: Hurd image setup and management
- **Content**: Image download, setup, configuration
- **Superseded by**: [docs/01-GETTING-STARTED/INSTALLATION.md](../../docs/01-GETTING-STARTED/INSTALLATION.md) + [docs/02-ARCHITECTURE/QEMU-CONFIGURATION.md](../../docs/02-ARCHITECTURE/QEMU-CONFIGURATION.md)

**12. INSTALLATION-COMPLETE-GUIDE.md**
- **Purpose**: Complete installation reference (pre-consolidation)
- **Content**: Installation, setup, verification
- **Superseded by**: [docs/01-GETTING-STARTED/INSTALLATION.md](../../docs/01-GETTING-STARTED/INSTALLATION.md)

---

## Migration Timeline

**Phase 1: Planning (Early 2025-11)**
- Audit repository structure
- Identify i386 dependencies
- Plan migration strategy

**Phase 2: Architecture Migration (2025-11-07)**
- Deprecate i386 architecture
- Update all scripts and configs to x86_64
- Migrate QEMU configurations
- Update CI/CD workflows

**Phase 3: Documentation Consolidation (2025-11-07)**
- Consolidate 53 files → 26 documents
- Create 8-section structure
- Add comprehensive navigation
- Archive transitional documents

**Phase 4: Validation and Cleanup (2025-11-07)**
- Validate all links
- Generate TOCs
- Archive deprecated content
- Final commit

---

## Key Migration Decisions

### Why x86_64-Only?

**Reasons**:
1. **Stability**: x86_64 Hurd more stable than i386
2. **Performance**: Better SMP support, 64-bit addressing
3. **Modern Hardware**: i386 hardware obsolete
4. **Simplicity**: Single architecture easier to maintain

**Impact**: Breaking change, i386 completely deprecated

**Reference**: [docs/07-RESEARCH/X86_64-MIGRATION.md](../../docs/07-RESEARCH/X86_64-MIGRATION.md)

---

### Why Consolidate Documentation?

**Problems**:
- 53 files, many redundant or outdated
- No clear navigation structure
- Inconsistent formatting and naming
- Hard to find relevant information

**Solution**:
- 8-section organized structure
- 26 total documents (18 content + 8 navigation)
- Comprehensive navigation and cross-references
- Consistent formatting and x86_64-only content

**Impact**: 55% reduction in file count, vastly improved usability

**Reference**: [docs/INDEX.md](../../docs/INDEX.md)

---

## Architecture Changes Summary

### Binary Naming (CRITICAL)

**i386 (deprecated)**:
```bash
qemu-system-i386
```

**x86_64 (current)**:
```bash
qemu-system-x86_64  # Note: UNDERSCORE, not hyphen!
```

### Image Naming

**i386 (deprecated)**:
```bash
debian-hurd-i386-20250807.img
```

**x86_64 (current)**:
```bash
debian-hurd-amd64-20250807.img
```

### QEMU Configuration

| Aspect | i386 | x86_64 |
|--------|------|--------|
| Binary | qemu-system-i386 | qemu-system-x86_64 |
| RAM | 1.5 GB | 4 GB |
| SMP | 1 core | 1-2 cores |
| CPU | `-cpu pentium` | `-cpu max` |
| Storage | IDE | SATA/AHCI |
| Machine | q35 | pc |

### Scripts Updated

**All 21 scripts** updated from i386 to x86_64:
- Setup scripts: download-image.sh, setup-hurd-amd64.sh
- Installation scripts: All updated for x86_64
- Configuration scripts: All updated
- Management scripts: All updated

**See**: [docs/08-REFERENCE/SCRIPTS.md](../../docs/08-REFERENCE/SCRIPTS.md)

---

## Using Archived Documents

**For Reference Only**:
- Historical context for migration decisions
- Understanding past architecture choices
- Comparing old vs new workflows

**Do NOT Use For**:
- Active development
- Setup or installation
- CI/CD configuration
- Troubleshooting

**Instead, Use**: Current documentation at `/docs/INDEX.md`

---

## Migration Statistics

### Code Changes
- **Files changed**: 49
- **Lines inserted**: 8,786
- **Lines deleted**: 2,485

### Disk Space Freed
- **Before**: 14.9 GB (i386 + x86_64)
- **After**: 6.8 GB (x86_64 only)
- **Freed**: 8.1 GB

### Documentation Consolidation
- **Before**: 53 files
- **After**: 26 files
- **Reduction**: 55%

### CI/CD Performance
- **Before**: 20-40 min (serial automation)
- **After**: 2-5 min (pre-provisioned images)
- **Speedup**: 3-6x faster, 35% more reliable

---

## Related Archives

**Other archived content**:
- `ARCHIVE/i386/` - i386-specific code and configs (if applicable)
- Git history - Full commit history preserved

**See also**:
- [docs/07-RESEARCH/LESSONS-LEARNED.md](../../docs/07-RESEARCH/LESSONS-LEARNED.md) - Migration lessons
- [docs/07-RESEARCH/X86_64-MIGRATION.md](../../docs/07-RESEARCH/X86_64-MIGRATION.md) - Migration details

---

## Questions About Archived Content?

**For historical context**: Read the archived documents in this directory

**For current usage**: See [docs/INDEX.md](../../docs/INDEX.md)

**For migration rationale**: See [docs/07-RESEARCH/](../../docs/07-RESEARCH/)

**For troubleshooting**: See [docs/06-TROUBLESHOOTING/](../../docs/06-TROUBLESHOOTING/)

---

[← Back to Repository Root](../../README.md) | [→ Current Documentation](../../docs/INDEX.md)
