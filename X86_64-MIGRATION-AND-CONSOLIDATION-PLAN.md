# x86_64 Migration and Documentation Consolidation Plan

**Date**: 2025-11-07
**Scope**: Complete i386→x86_64 migration + modular documentation architecture
**Status**: ACTION PLAN - Ready for execution

---

## Executive Summary

This repository currently contains:
1. **Mixed architecture artifacts** (i386 + amd64/x86_64)
2. **Fragmented documentation** (40+ markdown files, significant overlap)
3. **Legacy i386 references** in code, docs, and configurations
4. **Valuable lessons learned** scattered across multiple files

**Goal**: Create a clean x86_64-only environment with modular, consolidated documentation that preserves all lessons learned while eliminating redundancy.

---

## Part 1: Architecture Cleanup - i386 Artifact Removal

### 1.1 Disk Images - IMMEDIATE DELETION (Frees ~8.5 GB)

```bash
# DELETE (i386 artifacts)
rm -f ./debian-hurd-i386-20250807.img                    # 4.2 GB
rm -f ./debian-hurd-i386-20250807.img.bak.1762464911    # backup
rm -f ./debian-hurd-i386-20250807.qcow2.bak.1762464911  # backup qcow2
rm -f ./debian-hurd.img.tar.xz                           # if i386 (verify first)
rm -f ./scripts/debian-hurd.img                          # if symlink to i386

# KEEP (x86_64/amd64)
# ./debian-hurd-amd64-20250807.img (4.2 GB) - source image
# ./debian-hurd-amd64-80gb.qcow2 (2.2 GB) - active VM (copy-on-write)
# ./debian-hurd-amd64-20250807.img.tar.xz (354 MB) - compressed archive
```

### 1.2 Dockerfile - Fix Architecture References

**Current Issues**:
- Line 5: Label says "i386 microkernel"
- Line 11: Installs `qemu-system-i386`

**Actions**:
```dockerfile
# BEFORE
LABEL org.opencontainers.image.description="GNU/Hurd i386 microkernel development environment with QEMU"
    qemu-system-i386 \

# AFTER
LABEL org.opencontainers.image.description="GNU/Hurd x86_64 microkernel development environment with QEMU"
    qemu-system-x86-64 \
```

### 1.3 Entrypoint.sh - Fix Default Architecture

**Current Issues**:
- Line 10: Default path is i386 image
- Line 35: Default QEMU_ARCH is i386
- Line 47: Default CPU is pentium3 (i386-era)

**Actions**:
```bash
# Line 10 - BEFORE
QCOW2_IMAGE="${QEMU_DRIVE:-/opt/hurd-image/debian-hurd-i386-20250807.qcow2}"

# Line 10 - AFTER
QCOW2_IMAGE="${QEMU_DRIVE:-/opt/hurd-image/debian-hurd-amd64-80gb.qcow2}"

# Line 35 - BEFORE
QEMU_ARCH="${QEMU_ARCH:-i386}"  # Default to i386

# Line 35 - AFTER
QEMU_ARCH="${QEMU_ARCH:-x86_64}"  # Default to x86_64

# Line 47 - BEFORE
CPU_MODEL="${QEMU_CPU:-pentium3}"  # Default for maximum compatibility

# Line 47 - AFTER
CPU_MODEL="${QEMU_CPU:-qemu64}"  # x86_64 baseline, override with QEMU_CPU=host for KVM
```

### 1.4 Scripts - Update All Architecture References

**Files requiring updates**:

```bash
# Search and replace i386→x86_64
grep -rl "qemu-system-i386" scripts/ | while read file; do
    sed -i 's/qemu-system-i386/qemu-system-x86_64/g' "$file"
done

# Specific script fixes
scripts/monitor-qemu.sh:24        pgrep -f "qemu-system-x86_64"
scripts/validate-config.sh:80     if grep -q "qemu-system-x86_64" Dockerfile
scripts/validate-config.sh:121    if grep -q "qemu-system-x86_64" entrypoint.sh
```

### 1.5 CI/CD Workflows - Enforce x86_64 Only

**File**: `.github/workflows/push-ghcr.yml:80`

```yaml
# BEFORE
docker run --rm $TAG qemu-system-i386 --version

# AFTER
docker run --rm $TAG qemu-system-x86_64 --version
```

**File**: `.github/workflows/build-x86_64.yml` (rename to `build.yml`)

Consolidate all CI workflows into single x86_64 pipeline.

### 1.6 PKGBUILD - Update Package Metadata

```bash
# BEFORE (PKGBUILD:19)
'qemu-system-i386: For running QEMU outside Docker'

# AFTER
'qemu-system-x86-64: For running QEMU outside Docker'

# BEFORE (PKGBUILD:276)
- qemu-system-i386: Run QEMU outside Docker

# AFTER
- qemu-system-x86-64: Run QEMU outside Docker
```

---

## Part 2: Documentation Consolidation Strategy

### 2.1 Current State Analysis

**Top-Level Documentation** (26 files):
```
README.md                           - Main entry point
CI-CD-GUIDE-HURD.md                - CI/CD reference
CI-CD-MIGRATION-SUMMARY.md         - Migration lessons
COMPREHENSIVE-IMAGE-GUIDE.md       - Image building
CONTROL-PLANE-IMPLEMENTATION.md    - Control plane design
CUSTOM-HURD-FEATURES.md            - Custom features
FSCK-ERROR-FIX.md                  - Specific fix
HURD-SYSTEM-AUDIT.md               - System audit
INSTALLATION-COMPLETE-GUIDE.md     - Installation guide
INSTALLATION.md                    - Another installation guide (duplicate?)
IO-ERROR-FIX.md                    - Specific fix
LOCAL-TESTING-GUIDE.md             - Local testing
MANUAL-SETUP-REQUIRED.md           - Manual setup
MCP-SERVERS-SETUP.md               - MCP config
PORT-MAPPING-GUIDE.md              - Port mapping
PROJECT-SUMMARY.md                 - Project overview
QUICK-REFERENCE.md                 - Quick commands
QUICKSTART-CI-SETUP.md             - CI quickstart
QUICKSTART.md                      - General quickstart
REPO-AUDIT-FINDINGS.md             - Audit results
REPOSITORY-INDEX.md                - Index
requirements.md                    - Requirements
SIMPLE-START.md                    - Simple start
STRUCTURAL-MAP.md                  - Structure map
TEST-RESULTS.md                    - Test results
X86_64-ONLY-SETUP.md               - x86_64 setup
```

**docs/ Directory** (27 files):
```
docs/ARCHITECTURE.md
docs/CI-CD-GUIDE.md (DUPLICATE of top-level CI-CD-GUIDE-HURD.md)
docs/CI-CD-PROVISIONED-IMAGE.md
docs/COMPREHENSIVE-ANALYSIS-AND-IMPLEMENTATION-PLAN.md
docs/CREDENTIALS.md
docs/DEPLOYMENT.md
docs/DEPLOYMENT-STATUS.md
docs/EXECUTION-SUMMARY.md
docs/HURD-IMAGE-BUILDING.md
docs/HURD-TESTING-REPORT.md
docs/IMPLEMENTATION-COMPLETE.md
docs/index.md
docs/INDEX.md (duplicate index?)
docs/INTERACTIVE-ACCESS-GUIDE.md
docs/KERNEL-FIX-GUIDE.md
docs/KERNEL-STANDARDIZATION-PLAN.md
docs/MACH_QEMU_RESEARCH_REPORT.md
docs/MCP-TOOLS-ASSESSMENT-MATRIX.md
docs/QEMU-OPTIMIZATION-2025.md
docs/QEMU-TUNING.md (overlaps with QEMU-OPTIMIZATION-2025.md?)
docs/QUICK_START_GUIDE.md (duplicate of QUICKSTART.md?)
docs/RESEARCH-FINDINGS.md
docs/SESSION-COMPLETION-REPORT.md
docs/SSH-CONFIGURATION-RESEARCH.md
docs/TROUBLESHOOTING.md
docs/USER-SETUP.md
docs/VALIDATION-AND-TROUBLESHOOTING.md
```

**Total**: 53 markdown files, significant overlap

### 2.2 Proposed Modular Structure

```
/
├── README.md                          # Main entry - points to all other docs
├── QUICKSTART.md                      # Fast 5-minute start
│
├── docs/
│   ├── INDEX.md                       # Master documentation index
│   │
│   ├── 01-GETTING-STARTED/
│   │   ├── INSTALLATION.md           # Merge: INSTALLATION*.md, MANUAL-SETUP-REQUIRED.md
│   │   ├── QUICKSTART.md             # Merge: QUICKSTART*.md, SIMPLE-START.md
│   │   └── REQUIREMENTS.md           # Keep: requirements.md
│   │
│   ├── 02-ARCHITECTURE/
│   │   ├── SYSTEM-ARCHITECTURE.md    # Merge: ARCHITECTURE.md, STRUCTURAL-MAP.md
│   │   ├── CONTROL-PLANE.md          # Keep: CONTROL-PLANE-IMPLEMENTATION.md
│   │   └── CUSTOM-FEATURES.md        # Keep: CUSTOM-HURD-FEATURES.md
│   │
│   ├── 03-CONFIGURATION/
│   │   ├── QEMU-CONFIGURATION.md     # Merge: QEMU-*.md, entrypoint.sh docs
│   │   ├── NETWORK-PORTS.md          # Keep: PORT-MAPPING-GUIDE.md
│   │   └── MCP-SERVERS.md            # Keep: MCP-SERVERS-SETUP.md
│   │
│   ├── 04-OPERATION/
│   │   ├── LOCAL-TESTING.md          # Merge: LOCAL-TESTING-GUIDE.md, TEST-RESULTS.md
│   │   ├── SSH-ACCESS.md             # Merge: INTERACTIVE-ACCESS-GUIDE.md, SSH-*.md, CREDENTIALS.md
│   │   └── MONITORING.md             # New: extract monitoring from various guides
│   │
│   ├── 05-CI-CD/
│   │   ├── CI-CD-GUIDE.md            # Merge: CI-CD-*.md (3 files)
│   │   ├── IMAGE-BUILDING.md         # Merge: HURD-IMAGE-BUILDING.md, COMPREHENSIVE-IMAGE-GUIDE.md
│   │   └── DEPLOYMENT.md             # Merge: DEPLOYMENT*.md
│   │
│   ├── 06-TROUBLESHOOTING/
│   │   ├── COMMON-ISSUES.md          # Merge: TROUBLESHOOTING.md, VALIDATION-*.md
│   │   ├── KERNEL-FIXES.md           # Merge: KERNEL-*.md
│   │   └── SPECIFIC-FIXES.md         # Merge: FSCK-ERROR-FIX.md, IO-ERROR-FIX.md
│   │
│   ├── 07-RESEARCH-AND-LESSONS/
│   │   ├── RESEARCH-FINDINGS.md      # Keep: RESEARCH-FINDINGS.md
│   │   ├── MACH-QEMU-RESEARCH.md     # Keep: MACH_QEMU_RESEARCH_REPORT.md
│   │   ├── MIGRATION-LESSONS.md      # Merge: CI-CD-MIGRATION-SUMMARY.md, X86_64-ONLY-SETUP.md
│   │   └── IMPLEMENTATION-LOG.md     # Merge: IMPLEMENTATION-COMPLETE.md, EXECUTION-SUMMARY.md, SESSION-*.md
│   │
│   └── 08-REFERENCE/
│       ├── QUICK-REFERENCE.md        # Keep: QUICK-REFERENCE.md
│       ├── AUDIT-FINDINGS.md         # Merge: REPO-AUDIT-FINDINGS.md, HURD-SYSTEM-AUDIT.md
│       ├── PROJECT-SUMMARY.md        # Keep: PROJECT-SUMMARY.md
│       └── MCP-TOOLS-MATRIX.md       # Keep: MCP-TOOLS-ASSESSMENT-MATRIX.md
│
└── ARCHIVE/                           # Deprecated/historical docs
    ├── PROVISIONED-IMAGE.md          # Old provisioning approach
    ├── HURD-TESTING-REPORT.md        # Historical test results
    └── i386-LEGACY/                  # All i386-specific docs
```

### 2.3 Consolidation Matrix

| New Document | Source Documents (Merge/Integrate) | Action |
|-------------|-----------------------------------|--------|
| `docs/01-GETTING-STARTED/INSTALLATION.md` | INSTALLATION.md, INSTALLATION-COMPLETE-GUIDE.md, MANUAL-SETUP-REQUIRED.md | Merge installation workflows |
| `docs/01-GETTING-STARTED/QUICKSTART.md` | QUICKSTART.md, QUICKSTART-CI-SETUP.md, SIMPLE-START.md, docs/QUICK_START_GUIDE.md | Merge quick starts |
| `docs/02-ARCHITECTURE/SYSTEM-ARCHITECTURE.md` | docs/ARCHITECTURE.md, STRUCTURAL-MAP.md, REPOSITORY-INDEX.md | Merge architectural docs |
| `docs/03-CONFIGURATION/QEMU-CONFIGURATION.md` | docs/QEMU-OPTIMIZATION-2025.md, docs/QEMU-TUNING.md, entrypoint.sh (inline docs) | Consolidate QEMU tuning |
| `docs/04-OPERATION/SSH-ACCESS.md` | docs/INTERACTIVE-ACCESS-GUIDE.md, docs/SSH-CONFIGURATION-RESEARCH.md, docs/CREDENTIALS.md | Merge SSH guides |
| `docs/05-CI-CD/CI-CD-GUIDE.md` | CI-CD-GUIDE-HURD.md, docs/CI-CD-GUIDE.md, CI-CD-MIGRATION-SUMMARY.md | Merge CI/CD docs |
| `docs/05-CI-CD/IMAGE-BUILDING.md` | docs/HURD-IMAGE-BUILDING.md, COMPREHENSIVE-IMAGE-GUIDE.md | Merge image building |
| `docs/06-TROUBLESHOOTING/COMMON-ISSUES.md` | docs/TROUBLESHOOTING.md, docs/VALIDATION-AND-TROUBLESHOOTING.md | Merge troubleshooting |
| `docs/06-TROUBLESHOOTING/SPECIFIC-FIXES.md` | FSCK-ERROR-FIX.md, IO-ERROR-FIX.md | Consolidate fixes |
| `docs/07-RESEARCH-AND-LESSONS/MIGRATION-LESSONS.md` | CI-CD-MIGRATION-SUMMARY.md, X86_64-ONLY-SETUP.md | Consolidate migration lessons |
| `docs/07-RESEARCH-AND-LESSONS/IMPLEMENTATION-LOG.md` | docs/IMPLEMENTATION-COMPLETE.md, docs/EXECUTION-SUMMARY.md, docs/SESSION-COMPLETION-REPORT.md | Merge implementation logs |
| `docs/08-REFERENCE/AUDIT-FINDINGS.md` | REPO-AUDIT-FINDINGS.md, HURD-SYSTEM-AUDIT.md | Merge audit results |

---

## Part 3: Implementation Phases

### Phase 1: Architecture Cleanup (Priority: HIGH, Risk: LOW)

**Estimated time**: 30 minutes

```bash
# 1.1 Delete i386 disk images
rm -f debian-hurd-i386-20250807.img
rm -f debian-hurd-i386-20250807.img.bak.1762464911
rm -f debian-hurd-i386-20250807.qcow2.bak.1762464911

# 1.2 Update Dockerfile
# Manual edit: Change i386→x86_64

# 1.3 Update entrypoint.sh
# Manual edit: Fix defaults

# 1.4 Update all scripts
find scripts -type f -exec sed -i 's/qemu-system-i386/qemu-system-x86_64/g' {} \;

# 1.5 Update CI workflows
find .github/workflows -type f -name "*.yml" -exec sed -i 's/qemu-system-i386/qemu-system-x86_64/g' {} \;

# 1.6 Update PKGBUILD
sed -i 's/qemu-system-i386/qemu-system-x86-64/g' PKGBUILD

# 1.7 Commit changes
git add -A
git commit -m "Architecture: Complete i386→x86_64 migration"
```

### Phase 2: Documentation Audit (Priority: HIGH, Risk: NONE)

**Estimated time**: 1 hour

```bash
# Create analysis of all markdown files
./scripts/audit-documentation.sh > /tmp/doc-audit.txt

# Manually review for:
# - Duplicate content
# - Outdated information
# - i386 references
# - Consolidation opportunities
```

### Phase 3: Documentation Restructure (Priority: MEDIUM, Risk: LOW)

**Estimated time**: 3-4 hours

```bash
# Create new directory structure
mkdir -p docs/{01-GETTING-STARTED,02-ARCHITECTURE,03-CONFIGURATION,04-OPERATION,05-CI-CD,06-TROUBLESHOOTING,07-RESEARCH-AND-LESSONS,08-REFERENCE}
mkdir -p ARCHIVE/i386-LEGACY

# Move and consolidate documents (manual merge work)
# Use template below for each consolidated doc
```

### Phase 4: Validation (Priority: HIGH, Risk: NONE)

**Estimated time**: 30 minutes

```bash
# Check all internal links
./scripts/validate-links.sh

# Verify no broken references
grep -r "](/" docs/ | grep -v ".md:" | grep -v "#"

# Test docker build
docker-compose build

# Test VM boot
docker-compose up -d
sleep 300  # Wait 5 minutes
ssh -p 2223 root@localhost uname -m  # Should output: x86_64
```

---

## Part 4: Document Consolidation Templates

### 4.1 Consolidated Document Header Template

```markdown
# [Topic Title]

**Last Updated**: 2025-11-07
**Consolidated From**:
- Original: [filename.md] (YYYY-MM-DD)
- Integrated: [another-file.md] (YYYY-MM-DD)
- Lessons: [lesson-file.md] (YYYY-MM-DD)

**Purpose**: [Clear statement of document purpose]

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Document History

### Original Authors/Sessions
- [Date]: [Author/Session] - [Original contribution]
- [Date]: [Author/Session] - [Integration/lessons]

### Major Revisions
- 2025-11-07: Consolidated from [N] source documents
- [Previous dates if applicable]

---

[Main content follows]
```

### 4.2 Lesson Learned Preservation Template

When consolidating docs with lessons learned:

```markdown
## Lessons Learned

### [Topic Category]

**Issue**: [What problem was encountered]

**Root Cause**: [Why it happened]

**Solution**: [How it was fixed]

**Prevention**: [How to avoid in future]

**References**:
- Original finding: [filename:line]
- Related: [other-doc.md]

---
```

### 4.3 Archive Document Template

For deprecated/historical content:

```markdown
# [Original Document Title]

**Status**: ARCHIVED
**Date Archived**: 2025-11-07
**Reason**: [i386 deprecated | Superseded by [new-doc.md] | Outdated approach]

**Preserved For**: Historical reference and lessons learned

**Replacement**: See [current-doc.md]

---

[Original content preserved as-is]

---

## Archive Notes

This document is preserved for:
1. Historical context
2. Lessons learned during [project phase]
3. Reference for understanding why [decision was made]

**Do not use for current implementations**. See [replacement-doc.md] instead.
```

---

## Part 5: Critical Files - Manual Review Required

These files contain unique lessons and must be carefully integrated (not deleted):

```
REPO-AUDIT-FINDINGS.md           - Integration audit results
X86_64-ONLY-SETUP.md             - Migration experience
CI-CD-MIGRATION-SUMMARY.md       - CI/CD lessons
FSCK-ERROR-FIX.md                - Specific fix (filesystem check)
IO-ERROR-FIX.md                  - Specific fix (I/O errors)
docs/MACH_QEMU_RESEARCH_REPORT.md    - QEMU research findings
docs/SSH-CONFIGURATION-RESEARCH.md   - SSH setup research
docs/KERNEL-FIX-GUIDE.md            - Kernel issue resolution
```

**Action**: Extract all "Lessons Learned" sections → integrate into consolidated docs

---

## Part 6: Success Criteria

### 6.1 Architecture Cleanup
- [ ] Zero i386 disk images in repository
- [ ] All Dockerfiles reference x86_64 only
- [ ] All scripts use qemu-system-x86_64
- [ ] All CI/CD workflows test x86_64
- [ ] PKGBUILD updated for x86_64
- [ ] entrypoint.sh defaults to x86_64

### 6.2 Documentation Consolidation
- [ ] Documentation reduced from 53→~20 files
- [ ] Zero duplicate content across docs
- [ ] All lessons learned preserved in appropriate sections
- [ ] Clear directory structure (01-08 categories)
- [ ] Master INDEX.md references all docs
- [ ] All internal links validated

### 6.3 Functional Validation
- [ ] Docker build succeeds
- [ ] x86_64 VM boots successfully
- [ ] SSH access works (post-boot)
- [ ] `uname -m` reports x86_64
- [ ] CI/CD pipeline passes
- [ ] All scripts execute without errors

---

## Part 7: Rollback Plan

If issues occur during migration:

```bash
# Restore i386 images from backup
git checkout HEAD~1 -- debian-hurd-i386-20250807.img

# Restore Dockerfile
git checkout HEAD~1 -- Dockerfile

# Restore entrypoint
git checkout HEAD~1 -- entrypoint.sh

# Restore documentation
git checkout HEAD~1 -- docs/ *.md
```

**Backup before starting**:
```bash
tar czf backup-before-x86_64-migration-$(date +%Y%m%d).tar.gz \
  *.md docs/ scripts/ Dockerfile entrypoint.sh docker-compose.yml \
  .github/workflows/
```

---

## Part 8: Post-Migration Tasks

### 8.1 Update README.md

Must reflect:
- x86_64 only (no i386 support)
- Link to new documentation structure
- Updated quick start commands
- Architecture requirements

### 8.2 Update CI/CD

- Rename `build-x86_64.yml` → `build.yml`
- Remove any i386-specific test matrices
- Update test assertions (check `uname -m == x86_64`)

### 8.3 Create Migration Guide

Document this entire migration process for future reference:

```markdown
docs/07-RESEARCH-AND-LESSONS/I386-TO-X86_64-MIGRATION.md

Includes:
- Why we migrated
- What was removed
- Challenges encountered
- Solutions implemented
- Lessons learned
```

---

## Execution Order

```
1. Create backup (Part 7)
2. Remove i386 artifacts (Part 1.1)
3. Update Dockerfile (Part 1.2)
4. Update entrypoint.sh (Part 1.3)
5. Update scripts (Part 1.4)
6. Update CI/CD (Part 1.5)
7. Update PKGBUILD (Part 1.6)
8. Commit architecture changes
9. Test VM boot
10. Create doc structure (Part 3 Phase 3)
11. Consolidate documents (Part 2.3 matrix)
12. Validate links (Part 3 Phase 4)
13. Update README and INDEX
14. Final commit
15. Tag release: v2.0.0-x86_64-only
```

---

**Ready for execution**: YES
**Requires approval**: User confirmation before deleting i386 images

---

## Appendix A: Quick Reference Commands

```bash
# Check current architecture in VM
docker-compose up -d && sleep 300 && ssh -p 2223 root@localhost uname -m

# List all i386 references
grep -r "i386" . --exclude-dir=.git | grep -v ".md:"

# Find all qemu-system-i386 calls
grep -r "qemu-system-i386" . --exclude-dir=.git

# Check disk space before/after
du -sh debian-hurd-*.{img,qcow2} | sort -h

# Validate all markdown files
find . -name "*.md" -exec markdown-lint {} \;

# Check broken links
find docs -name "*.md" -exec grep -H "](/" {} \; | grep -v ".md#"
```

---

END OF MIGRATION PLAN
