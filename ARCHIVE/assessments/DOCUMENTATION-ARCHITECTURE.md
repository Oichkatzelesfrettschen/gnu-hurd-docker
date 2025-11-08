================================================================================
GNU HURD DOCKER DOCUMENTATION ARCHITECTURE
Version: 1.0
Date: 2025-11-07
Purpose: Consolidate 58+ docs into maintainable knowledge system
================================================================================

================================================================================
PROPOSED DIRECTORY STRUCTURE
================================================================================

docs/
├── 00-overview/
│   ├── README.md              # Project introduction, links to all sections
│   ├── ARCHITECTURE.md        # System design, components, data flows
│   └── ROADMAP.md            # Future plans, milestones, vision
│
├── 01-getting-started/
│   ├── README.md              # Navigation for new users
│   ├── QUICKSTART.md         # 5-minute setup guide
│   ├── INSTALLATION.md       # Detailed install procedures
│   ├── FIRST-STEPS.md        # Basic usage, common tasks
│   └── REQUIREMENTS.md       # Prerequisites, dependencies
│
├── 02-user-guide/
│   ├── README.md              # User documentation index
│   ├── SSH-ACCESS.md         # Remote connection guide
│   ├── PORT-MAPPING.md       # Network configuration
│   ├── STORAGE.md            # Disk management, snapshots
│   └── TROUBLESHOOTING.md    # Common issues and solutions
│
├── 03-development/
│   ├── README.md              # Developer documentation index
│   ├── BUILD-SYSTEM.md       # Docker, QEMU configuration
│   ├── CUSTOM-IMAGES.md      # Creating custom Hurd images
│   ├── DEBUGGING.md          # GDB, serial console, traces
│   └── CONTRIBUTING.md       # Code style, PR process
│
├── 04-operations/
│   ├── README.md              # DevOps documentation index
│   ├── CI-CD.md              # GitHub Actions workflows
│   ├── DEPLOYMENT.md         # Production deployment guide
│   ├── MONITORING.md         # Logging, metrics, health checks
│   └── AUTOMATION.md         # Scripts, provisioning
│
├── 05-reference/
│   ├── README.md              # Technical reference index
│   ├── QEMU-CONFIG.md        # QEMU parameters, tuning
│   ├── KERNEL-CONFIG.md      # GNU Mach configuration
│   ├── API.md                # Programmatic interfaces
│   └── GLOSSARY.md           # Terms, acronyms, concepts
│
├── 06-research/
│   ├── README.md              # Research documentation index
│   ├── MACH-VARIANTS.md      # Comparison of Mach implementations
│   ├── PERFORMANCE.md        # Benchmarks, optimization findings
│   ├── LESSONS-LEARNED.md    # Historical decisions, rationale
│   └── EXPERIMENTS.md        # Failed attempts, why they failed
│
├── archive/
│   ├── README.md              # Deprecated documentation index
│   ├── 2025-11-migration/    # i386 to x86_64 migration docs
│   ├── legacy-configs/        # Old configuration files
│   └── historical-notes/      # Original research notes
│
├── assets/
│   ├── diagrams/             # Architecture diagrams (ASCII)
│   ├── scripts/              # Documentation helper scripts
│   └── templates/            # Document templates
│
└── INDEX.md                   # Master documentation index

================================================================================
DOCUMENT NAMING CONVENTIONS
================================================================================

1. STRUCTURE
   - All caps with hyphens: QUICKSTART.md, CI-CD.md
   - README.md for section indices (lowercase exception)
   - Dates in archive: YYYY-MM-description.md

2. PREFIXES (when needed for clarity)
   - GUIDE- for howto documents
   - REF- for reference materials
   - ARCH- for architecture documents
   - RESEARCH- for findings/experiments

3. SUFFIXES (avoid, but use when necessary)
   - -DEPRECATED for sunset documents
   - -DRAFT for work in progress
   - -v2 for major revisions (prefer git history)

================================================================================
CONSOLIDATED DOCUMENT TEMPLATE
================================================================================

```markdown
================================================================================
[DOCUMENT TITLE IN CAPS]
Version: X.Y
Last Updated: YYYY-MM-DD
Scope: [Target audience and purpose]
Status: [Active|Draft|Deprecated]
================================================================================

================================================================================
TABLE OF CONTENTS
================================================================================

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Main Content Section 1](#main-content-section-1)
4. [Main Content Section 2](#main-content-section-2)
5. [Troubleshooting](#troubleshooting)
6. [References](#references)
7. [Changelog](#changelog)

================================================================================
OVERVIEW
================================================================================

Brief description of document purpose and scope. 2-3 sentences maximum.

Key topics covered:
- Topic 1
- Topic 2
- Topic 3

================================================================================
PREREQUISITES
================================================================================

What reader needs to know/have before reading this document.

Required knowledge:
- Understanding of X
- Familiarity with Y

Required access:
- System Z
- Tool A

================================================================================
MAIN CONTENT SECTION 1
================================================================================

Detailed content goes here. Use clear headers and subheaders.

### Subsection Title

Content with examples:

```bash
# Example command
docker-compose up -d
```

Important notes:
- Note 1
- Note 2

================================================================================
MAIN CONTENT SECTION 2
================================================================================

Continue with additional sections as needed.

================================================================================
TROUBLESHOOTING
================================================================================

Common issues and solutions:

**Problem**: Description of issue
**Symptoms**: What user sees
**Solution**: Step-by-step fix
**Prevention**: How to avoid in future

================================================================================
REFERENCES
================================================================================

Internal links:
- [Related Document 1](../01-getting-started/QUICKSTART.md)
- [Related Document 2](../05-reference/QEMU-CONFIG.md)

External links:
- [GNU Hurd Official](https://www.gnu.org/software/hurd/)
- [Debian GNU/Hurd](https://www.debian.org/ports/hurd/)

Related documents:
- ARCHITECTURE.md - System design
- TROUBLESHOOTING.md - Common issues

================================================================================
CHANGELOG
================================================================================

## [X.Y] - YYYY-MM-DD
### Added
- New feature or section

### Changed
- Modified behavior

### Fixed
- Bug fixes

### Deprecated
- Features being phased out

================================================================================
END DOCUMENT
================================================================================
```

================================================================================
MASTER INDEX STRUCTURE
================================================================================

```markdown
# GNU Hurd Docker Documentation

## Quick Navigation

**New Users**: Start with [Quickstart Guide](01-getting-started/QUICKSTART.md)
**Developers**: See [Development Guide](03-development/README.md)
**DevOps**: Check [Operations Guide](04-operations/README.md)
**Troubleshooting**: Visit [Common Issues](02-user-guide/TROUBLESHOOTING.md)

## Documentation Map

### 00. Overview
- [Project Overview](00-overview/README.md)
- [System Architecture](00-overview/ARCHITECTURE.md)
- [Project Roadmap](00-overview/ROADMAP.md)

### 01. Getting Started
- [Quickstart (5 minutes)](01-getting-started/QUICKSTART.md)
- [Full Installation](01-getting-started/INSTALLATION.md)
- [System Requirements](01-getting-started/REQUIREMENTS.md)
- [First Steps](01-getting-started/FIRST-STEPS.md)

### 02. User Guide
- [SSH Access](02-user-guide/SSH-ACCESS.md)
- [Port Configuration](02-user-guide/PORT-MAPPING.md)
- [Storage Management](02-user-guide/STORAGE.md)
- [Troubleshooting](02-user-guide/TROUBLESHOOTING.md)

### 03. Development
- [Build System](03-development/BUILD-SYSTEM.md)
- [Custom Images](03-development/CUSTOM-IMAGES.md)
- [Debugging](03-development/DEBUGGING.md)
- [Contributing](03-development/CONTRIBUTING.md)

### 04. Operations
- [CI/CD Pipeline](04-operations/CI-CD.md)
- [Deployment Guide](04-operations/DEPLOYMENT.md)
- [Monitoring](04-operations/MONITORING.md)
- [Automation](04-operations/AUTOMATION.md)

### 05. Reference
- [QEMU Configuration](05-reference/QEMU-CONFIG.md)
- [Kernel Configuration](05-reference/KERNEL-CONFIG.md)
- [API Reference](05-reference/API.md)
- [Glossary](05-reference/GLOSSARY.md)

### 06. Research
- [Mach Kernel Variants](06-research/MACH-VARIANTS.md)
- [Performance Analysis](06-research/PERFORMANCE.md)
- [Lessons Learned](06-research/LESSONS-LEARNED.md)
- [Failed Experiments](06-research/EXPERIMENTS.md)

### Archive
- [Deprecated Documentation](archive/README.md)
- [i386 Migration (2025-11)](archive/2025-11-migration/)

## Document Status

| Section | Completeness | Last Updated | Maintainer |
|---------|-------------|--------------|------------|
| Overview | 100% | 2025-11-07 | Team |
| Getting Started | 95% | 2025-11-07 | Team |
| User Guide | 90% | 2025-11-07 | Team |
| Development | 85% | 2025-11-07 | Team |
| Operations | 90% | 2025-11-07 | Team |
| Reference | 80% | 2025-11-07 | Team |
| Research | 100% | 2025-11-07 | Team |

## Search

Use GitHub's search with these patterns:
- `path:docs/ KEYWORD` - Search documentation
- `path:docs/01-getting-started` - Search specific section
- `extension:md KEYWORD` - Search all markdown

## Contributing to Documentation

See [CONTRIBUTING.md](03-development/CONTRIBUTING.md#documentation)
```

================================================================================
CROSS-LINKING GUIDELINES
================================================================================

1. RELATIVE PATHS ONLY
   - Use: `../01-getting-started/QUICKSTART.md`
   - Avoid: `/docs/01-getting-started/QUICKSTART.md`
   - Never: Absolute URLs unless external

2. LINK FORMATS
   - Section link: `[Quickstart](../01-getting-started/QUICKSTART.md)`
   - Anchor link: `[SSH Setup](../02-user-guide/SSH-ACCESS.md#setup)`
   - External: `[GNU Hurd](https://www.gnu.org/software/hurd/)`

3. LINK VALIDATION
   - Use markdown link checker in CI
   - Verify during document review
   - Update when moving/renaming files

4. NAVIGATION AIDS
   - "See also" sections at document end
   - "Prerequisites" links at start
   - Breadcrumbs in complex documents

5. CROSS-REFERENCE MATRIX
   Create docs/CROSS-REFERENCES.md tracking major links between documents

================================================================================
METADATA STANDARDS
================================================================================

Required metadata in every document header:

```
Version: X.Y                    # Document version (not project)
Last Updated: YYYY-MM-DD        # ISO 8601 date
Scope: Brief description        # Target audience and purpose
Status: Active|Draft|Deprecated # Current state
Author: Name (optional)         # Primary author
Reviewed: YYYY-MM-DD (optional) # Last review date
```

Git provides additional metadata:
- Creation date: `git log --follow --format=%ai -- FILE | tail -1`
- Last modified: `git log -1 --format=%ai -- FILE`
- Contributors: `git shortlog -sn -- FILE`
- Change history: `git log --oneline -- FILE`

================================================================================
ARCHIVE STRUCTURE
================================================================================

archive/
├── README.md                    # Index of archived content
├── by-date/
│   ├── 2025-11-migration/      # i386 to x86_64 transition
│   │   ├── README.md           # Migration overview
│   │   ├── i386-configs/       # Old configurations
│   │   └── migration-notes/    # Conversion process
│   └── 2025-10-research/       # Earlier research phase
│
├── by-topic/
│   ├── failed-approaches/      # What didn't work and why
│   ├── experimental-features/  # Features that were removed
│   └── historical-decisions/   # Design choices and rationale
│
└── superseded/
    ├── old-quickstart-v1.md    # Replaced documentation
    ├── legacy-ci-cd.md         # Previous CI/CD approach
    └── original-architecture.md # Initial design

Archive principles:
1. Never delete - move to archive
2. Add DEPRECATED banner to old docs
3. Include forwarding link to new location
4. Preserve context and timestamps
5. Keep failed experiments (learning value)

================================================================================
MIGRATION CHECKLIST
================================================================================

Phase 1: Structure Creation
- [ ] Create directory structure under docs/
- [ ] Create section README.md files
- [ ] Create document templates in assets/templates/
- [ ] Set up INDEX.md master navigation

Phase 2: Content Consolidation
- [ ] Map existing 58 files to new structure
- [ ] Identify duplicate content for merging
- [ ] Extract common sections into shared files
- [ ] Consolidate related topics

Phase 3: Migration Execution
- [ ] Move root-level *.md to appropriate sections
- [ ] Consolidate QUICKSTART variants (5 files -> 1)
- [ ] Merge CI/CD documentation (3 files -> 1)
- [ ] Combine troubleshooting guides (4 files -> 1)
- [ ] Archive i386-specific documentation

Phase 4: Link Updates
- [ ] Update all internal cross-references
- [ ] Fix README.md project links
- [ ] Update CI/CD documentation paths
- [ ] Verify external links still valid

Phase 5: Validation
- [ ] Run markdown link checker
- [ ] Verify all files accessible from INDEX.md
- [ ] Check for orphaned documents
- [ ] Test navigation paths for each audience

Phase 6: Cleanup
- [ ] Remove duplicate content
- [ ] Archive deprecated files
- [ ] Update .gitignore if needed
- [ ] Commit with clear message

================================================================================
DOCUMENT CONSOLIDATION MAP
================================================================================

Target consolidations (58 -> ~20 core documents):

1. QUICKSTART files (5 -> 1):
   - QUICKSTART.md
   - QUICK-REFERENCE.md
   - SIMPLE-START.md
   - QUICKSTART-CI-SETUP.md
   - docs/QUICK_START_GUIDE.md
   -> docs/01-getting-started/QUICKSTART.md

2. Installation guides (4 -> 1):
   - INSTALLATION.md
   - INSTALLATION-COMPLETE-GUIDE.md
   - MANUAL-SETUP-REQUIRED.md
   - docs/USER-SETUP.md
   -> docs/01-getting-started/INSTALLATION.md

3. CI/CD documentation (3 -> 1):
   - CI-CD-GUIDE-HURD.md
   - CI-CD-MIGRATION-SUMMARY.md
   - docs/CI-CD-GUIDE.md
   -> docs/04-operations/CI-CD.md

4. Architecture docs (3 -> 1):
   - docs/ARCHITECTURE.md
   - STRUCTURAL-MAP.md
   - docs/COMPREHENSIVE-ANALYSIS-AND-IMPLEMENTATION-PLAN.md
   -> docs/00-overview/ARCHITECTURE.md

5. Troubleshooting (4 -> 1):
   - docs/TROUBLESHOOTING.md
   - FSCK-ERROR-FIX.md
   - IO-ERROR-FIX.md
   - docs/VALIDATION-AND-TROUBLESHOOTING.md
   -> docs/02-user-guide/TROUBLESHOOTING.md

6. x86_64 migration (5 -> archive):
   - X86_64-ONLY-SETUP.md
   - X86_64-MIGRATION-AND-CONSOLIDATION-PLAN.md
   - README-X86_64-MIGRATION.md
   - X86_64-VALIDATION-CHECKLIST.md
   - X86_64-MIGRATION-COMPLETE.md
   -> archive/2025-11-migration/

7. Research findings (4 -> 2):
   - docs/RESEARCH-FINDINGS.md
   - docs/MACH_QEMU_RESEARCH_REPORT.md
   - docs/SSH-CONFIGURATION-RESEARCH.md
   - docs/HURD-TESTING-REPORT.md
   -> docs/06-research/LESSONS-LEARNED.md
   -> docs/06-research/EXPERIMENTS.md

================================================================================
MAINTENANCE GUIDELINES
================================================================================

1. Regular Review (Monthly)
   - Check for outdated information
   - Verify links still valid
   - Update version numbers
   - Archive obsolete content

2. Version Control
   - Commit message: "docs: [section] description"
   - Tag releases: docs-v1.0, docs-v1.1
   - Branch for major reorganizations

3. Ownership
   - Each section has primary maintainer
   - Document owners listed in INDEX.md
   - Reviews required for cross-section changes

4. Quality Standards
   - ASCII-only (no Unicode/emojis)
   - 80-character line limit (soft)
   - Clear headers and sections
   - Code examples tested
   - Commands include expected output

================================================================================
END DOCUMENT
================================================================================