# Documentation Archive

**Purpose**: Historical documentation and content from major transitions

**Status**: Reference only - **DO NOT USE for active work**

---

## Overview

This directory preserves historical documentation from:

1. **i386 → x86_64 Architecture Migration** (2025-11-07)
2. **Documentation Consolidation** (2025-11-07)

All active documentation is in [`/docs`](../docs/INDEX.md).

---

## Archive Structure

### [`migration/`](migration/)
**Historical migration planning and completion documents**

**Contents**:
- Migration plans and strategies
- Audit reports and findings
- Transitional setup guides
- CI/CD migration documentation
- Post-migration completion reports

**Why archived**: Migration complete, documents superseded by consolidated docs

**Date range**: Planning through 2025-11-07 completion

**File count**: 12 documents

---

### [`i386/`](i386/)
**i386 architecture content (REMOVED, not archived)**

**Contents**: None (README only)

**Why empty**: i386 content was migrated to x86_64 or removed entirely

**Access**: Via git history (`git log --all`)

**Date range**: Pre-2025-11-07

---

## Using Archived Content

### For Historical Reference

**Migration documents** ([`migration/`](migration/)):
- Understand decision-making process
- Review migration methodology
- Learn from audit findings
- See pre/post comparison

**i386 content** ([`i386/`](i386/)):
- Access via git history only
- Use `git show <commit>` to view old files
- See [`i386/README.md`](i386/README.md) for git commands

---

### NOT For Active Use

**Do not use archived docs for**:
- Installation or setup
- Daily operations
- CI/CD configuration
- Troubleshooting
- Architecture reference

**Instead**: See current documentation at [`/docs/INDEX.md`](../docs/INDEX.md)

---

## Key Dates

**2025-11-07 - Migration Complete**:
- i386 architecture deprecated
- x86_64-only codebase
- Documentation consolidation (53 → 26 files)

**2025-11-07 - Archive Created**:
- Migration docs archived
- i386 references removed
- Consolidation complete

---

## Migration Summary

### Architecture Migration (i386 → x86_64)

**Breaking changes**:
- QEMU binary: `qemu-system-i386` → `qemu-system-x86_64`
- Image: `debian-hurd-i386` → `debian-hurd-amd64`
- RAM: 1.5 GB → 4 GB
- Storage: IDE → SATA/AHCI
- Machine: q35 → pc

**Impact**:
- 49 files changed
- 8.1 GB disk space freed
- 3-6x faster CI/CD (with pre-provisioned images)

**See**: [migration/README.md](migration/README.md)

---

### Documentation Consolidation

**Before**: 53 fragmented files
**After**: 26 organized documents (18 content + 8 navigation)
**Reduction**: 55% fewer files

**New structure**:
- 01-GETTING-STARTED/
- 02-ARCHITECTURE/
- 03-CONFIGURATION/
- 04-OPERATION/
- 05-CI-CD/
- 06-TROUBLESHOOTING/
- 07-RESEARCH/
- 08-REFERENCE/

**Impact**:
- Clear navigation
- Comprehensive cross-references
- Consistent formatting
- x86_64-only content

**See**: [/docs/INDEX.md](../docs/INDEX.md)

---

## Related Resources

**Current documentation**: [/docs/INDEX.md](../docs/INDEX.md)

**Migration details**: [/docs/07-RESEARCH/X86_64-MIGRATION.md](../docs/07-RESEARCH/X86_64-MIGRATION.md)

**Lessons learned**: [/docs/07-RESEARCH/LESSONS-LEARNED.md](../docs/07-RESEARCH/LESSONS-LEARNED.md)

**Git history**: `git log --all --oneline`

---

## Questions?

**For historical context**: Browse this archive directory

**For current usage**: See [/docs/INDEX.md](../docs/INDEX.md)

**For migration rationale**: See [/docs/07-RESEARCH/](../docs/07-RESEARCH/)

---

[← Back to Repository Root](../README.md) | [→ Current Documentation](../docs/INDEX.md)
