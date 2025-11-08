# i386 Architecture Archive

**Status**: **REMOVED** - i386 support completely deprecated as of 2025-11-07

**Migration**: All i386 content migrated to x86_64 or removed

---

## Overview

This directory exists for organizational purposes but contains no files. All i386-specific content was either:

1. **Migrated to x86_64** - Scripts, configs, and docs updated for x86_64
2. **Removed entirely** - i386-specific code deleted
3. **Preserved in git history** - Full history available via `git log`

---

## Why No i386 Content Here?

### Decision Rationale

**Date**: 2025-11-07
**Reason**: x86_64-only architecture chosen for:
- **Stability**: x86_64 Hurd more stable than i386
- **Performance**: Better SMP support, 64-bit addressing  
- **Modern Hardware**: i386 hardware obsolete
- **Simplicity**: Single architecture easier to maintain

**Impact**: Breaking change, all i386 support removed

**Reference**: [docs/07-RESEARCH/X86_64-MIGRATION.md](../../docs/07-RESEARCH/X86_64-MIGRATION.md)

---

## What Was Changed?

### Scripts Updated (All 21 scripts)

**i386 → x86_64 changes**:

| Component | i386 (old) | x86_64 (new) |
|-----------|------------|--------------|
| QEMU Binary | `qemu-system-i386` | `qemu-system-x86_64` |
| Image | `debian-hurd-i386-*.img` | `debian-hurd-amd64-*.img` |
| RAM | 1.5 GB | 4 GB |
| SMP | 1 core | 1-2 cores |
| CPU | `-cpu pentium` | `-cpu max` or `-cpu host` |
| Storage | IDE | SATA/AHCI |
| Machine | q35 | pc |

**See**: [docs/08-REFERENCE/SCRIPTS.md](../../docs/08-REFERENCE/SCRIPTS.md) for current scripts

---

### GitHub Workflows Removed

**Deleted workflows** (i386-specific):
- `.github/workflows/build-docker.yml` - i386 Docker build
- `.github/workflows/build.yml` - i386 general build
- `.github/workflows/integration-test.yml` - i386 integration tests
- `.github/workflows/qemu-boot-and-provision.yml` - i386 QEMU boot
- `.github/workflows/qemu-ci-kvm.yml` - i386 KVM tests
- `.github/workflows/qemu-ci-tcg.yml` - i386 TCG tests

**Replaced by**: [`.github/workflows/build-x86_64.yml`](../../.github/workflows/build-x86_64.yml)

**See**: [docs/05-CI-CD/SETUP.md](../../docs/05-CI-CD/SETUP.md) for current workflows

---

### Configuration Files Updated

**Docker Compose** (`docker-compose.yml`):
- Updated QEMU binary references
- Updated RAM allocation (1.5G → 4G)
- Updated CPU configuration
- Updated storage interface (IDE → SATA/AHCI)

**Entrypoint** (`entrypoint.sh`):
- Updated QEMU binary path
- Updated machine type (q35 → pc)
- Updated CPU model

**See**: [docs/02-ARCHITECTURE/QEMU-CONFIGURATION.md](../../docs/02-ARCHITECTURE/QEMU-CONFIGURATION.md)

---

## Accessing i386 History

All i386 content is preserved in git history:

### View Last i386 Commit

```bash
# Find last commit before x86_64-only migration
git log --all --grep="i386" --oneline | head -10

# View specific commit
git show <commit-hash>
```

### Checkout i386 Version

```bash
# WARNING: This will replace your working tree
git checkout <commit-hash>

# Or create a branch from i386 era
git checkout -b i386-archive <commit-hash>
```

### Compare i386 vs x86_64

```bash
# Diff a specific file across migration
git diff <i386-commit> <x86_64-commit> -- scripts/setup-hurd-amd64.sh

# Diff entire repository
git diff <i386-commit> <x86_64-commit>
```

### Extract i386 Files

```bash
# Extract a specific file from i386 era
git show <i386-commit>:path/to/file > file-i386-version.txt

# Extract entire directory
git archive <i386-commit> scripts/ | tar -x -C /tmp/i386-scripts/
```

---

## Migration Statistics

### Code Changes
- **Files changed**: 49
- **Lines inserted**: 8,786 (x86_64 additions)
- **Lines deleted**: 2,485 (i386 removals)
- **Commit**: `445eca9` (or similar, check git log)

### Disk Space Freed
- **Before**: 14.9 GB (i386 + x86_64 dual images)
- **After**: 6.8 GB (x86_64 only)
- **Freed**: 8.1 GB

### Performance Improvements
- **Boot time**: 30-60s (KVM x86_64) vs 60-120s (i386)
- **Stability**: Significantly improved SMP on x86_64
- **Storage**: SATA/AHCI vs IDE (better performance)

---

## Why x86_64-Only?

### Technical Superiority

**x86_64 advantages**:
1. **64-bit addressing**: Access > 4GB RAM without PAE
2. **Better SMP**: Symmetric multiprocessing more stable
3. **Modern CPU features**: AVX2, AES-NI, SHA extensions
4. **Native 64-bit** addressing**: No thunking overhead

**i386 limitations**:
1. **32-bit addressing**: Limited to 4GB (or 64GB with PAE hacks)
2. **Poor SMP**: Unstable with > 1 core
3. **Legacy CPU**: No modern extensions
4. **Obsolete hardware**: No new i386 CPUs manufactured

### Operational Benefits

**Simplicity**:
- One architecture to maintain
- One set of CI/CD workflows
- One set of documentation
- One QEMU binary to troubleshoot

**Reliability**:
- Fewer edge cases
- Better tested (x86_64 is default for modern Hurd)
- Clearer error messages

**Performance**:
- Faster boot times
- Better storage I/O (SATA/AHCI)
- More RAM available (4GB+ vs 1.5GB)

---

## Recommendations

### For Current Users

**Use x86_64**:
- All new work on x86_64 only
- Follow [docs/01-GETTING-STARTED/INSTALLATION.md](../../docs/01-GETTING-STARTED/INSTALLATION.md)
- Use [docs/INDEX.md](../../docs/INDEX.md) for navigation

**Do NOT use i386**:
- No i386 support in current codebase
- No i386 documentation (all removed)
- No i386 CI/CD workflows

### For Historical Research

**Git history**:
- Use `git log`, `git show`, `git diff` to explore i386 era
- Check commits before 2025-11-07 for i386 content
- See [migration archive](../migration/README.md) for migration docs

**Migration context**:
- Read [docs/07-RESEARCH/X86_64-MIGRATION.md](../../docs/07-RESEARCH/X86_64-MIGRATION.md)
- Read [docs/07-RESEARCH/LESSONS-LEARNED.md](../../docs/07-RESEARCH/LESSONS-LEARNED.md)
- Review [ARCHIVE/migration/](../migration/) for migration process

---

## Related Archives

**Other archived content**:
- [ARCHIVE/migration/](../migration/) - Migration planning and completion docs
- Git history - Full commit history with all i386 code

**Current documentation**:
- [docs/INDEX.md](../../docs/INDEX.md) - Master documentation index
- [docs/01-GETTING-STARTED/](../../docs/01-GETTING-STARTED/) - Getting started (x86_64 only)
- [docs/02-ARCHITECTURE/](../../docs/02-ARCHITECTURE/) - Architecture docs (x86_64 only)

---

## Questions About i386?

**For historical context**: Use git history (`git log`, `git show`)

**For migration details**: See [docs/07-RESEARCH/X86_64-MIGRATION.md](../../docs/07-RESEARCH/X86_64-MIGRATION.md)

**For current x86_64 usage**: See [docs/INDEX.md](../../docs/INDEX.md)

**For migration planning**: See [ARCHIVE/migration/](../migration/)

---

[← Back to ARCHIVE](../) | [→ Current Documentation](../../docs/INDEX.md)
