#!/bin/bash
# ================================================================================
# Documentation Migration Script
# Purpose: Reorganize documentation into new structure
# Date: 2025-11-07
# ================================================================================

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
# shellcheck disable=SC2034  # Reserved for future archive operations
ARCHIVE_DIR="$DOCS_DIR/archive"

echo "================================================================================
GNU HURD DOCKER DOCUMENTATION MIGRATION
Repository: $REPO_ROOT
================================================================================
"

# ================================================================================
# Create directory structure
# ================================================================================
echo "Creating directory structure..."

directories=(
    "00-overview"
    "01-getting-started"
    "02-user-guide"
    "03-development"
    "04-operations"
    "05-reference"
    "06-research"
    "archive/2025-11-migration"
    "archive/by-date"
    "archive/by-topic"
    "archive/superseded"
    "assets/diagrams"
    "assets/scripts"
    "assets/templates"
)

for dir in "${directories[@]}"; do
    mkdir -p "$DOCS_DIR/$dir"
    echo "  Created: docs/$dir/"
done

# ================================================================================
# Create section README files
# ================================================================================
echo ""
echo "Creating section README files..."

sections=(
    "00-overview:Project overview and architecture documentation"
    "01-getting-started:Documentation for new users getting started"
    "02-user-guide:User guides for common tasks and operations"
    "03-development:Developer documentation and contribution guides"
    "04-operations:DevOps and operational documentation"
    "05-reference:Technical reference documentation"
    "06-research:Research findings and experiments"
    "archive:Deprecated and historical documentation"
)

for section_desc in "${sections[@]}"; do
    IFS=':' read -r section description <<< "$section_desc"
    readme_file="$DOCS_DIR/$section/README.md"

    if [ ! -f "$readme_file" ]; then
        cat > "$readme_file" << EOF
================================================================================
${section##*-} DOCUMENTATION
Last Updated: $(date +%Y-%m-%d)
================================================================================

## Overview

$description

## Documents in This Section

| Document | Description | Status |
|----------|-------------|--------|
| [Coming Soon] | Documentation is being migrated | Migration |

## Section Maintainer

Primary: Team

================================================================================
END DOCUMENT
================================================================================
EOF
        echo "  Created: $section/README.md"
    fi
done

# ================================================================================
# Migration mapping
# ================================================================================
echo ""
echo "Migration mapping prepared..."
echo ""
echo "CONSOLIDATION PLAN:"
echo "===================="
echo ""

cat << 'EOF'
1. QUICKSTART files (5 -> 1):
   Source files:
   - QUICKSTART.md
   - QUICK-REFERENCE.md
   - SIMPLE-START.md
   - QUICKSTART-CI-SETUP.md
   - docs/QUICK_START_GUIDE.md
   Target: docs/01-getting-started/QUICKSTART.md

2. Installation guides (4 -> 1):
   Source files:
   - INSTALLATION.md
   - INSTALLATION-COMPLETE-GUIDE.md
   - MANUAL-SETUP-REQUIRED.md
   - docs/USER-SETUP.md
   Target: docs/01-getting-started/INSTALLATION.md

3. CI/CD documentation (3 -> 1):
   Source files:
   - CI-CD-GUIDE-HURD.md
   - CI-CD-MIGRATION-SUMMARY.md
   - docs/CI-CD-GUIDE.md
   Target: docs/04-operations/CI-CD.md

4. Architecture docs (3 -> 1):
   Source files:
   - docs/ARCHITECTURE.md
   - STRUCTURAL-MAP.md
   - docs/COMPREHENSIVE-ANALYSIS-AND-IMPLEMENTATION-PLAN.md
   Target: docs/00-overview/ARCHITECTURE.md

5. x86_64 migration docs -> archive:
   Source files:
   - X86_64-*.md
   - README-X86_64-MIGRATION.md
   Target: docs/archive/2025-11-migration/

EOF

# ================================================================================
# Create migration checklist
# ================================================================================
echo "Creating migration checklist..."

cat > "$DOCS_DIR/MIGRATION-CHECKLIST.md" << 'EOF'
================================================================================
DOCUMENTATION MIGRATION CHECKLIST
Date: 2025-11-07
Status: In Progress
================================================================================

## Phase 1: Structure Creation [COMPLETE]
- [x] Create directory structure under docs/
- [x] Create section README.md files
- [x] Create document templates in assets/templates/
- [ ] Set up INDEX.md master navigation

## Phase 2: Content Consolidation [IN PROGRESS]
- [ ] Map existing 58 files to new structure
- [ ] Identify duplicate content for merging
- [ ] Extract common sections into shared files
- [ ] Consolidate related topics

## Phase 3: Migration Execution [TODO]

### Quickstart Consolidation
- [ ] Merge QUICKSTART.md
- [ ] Merge QUICK-REFERENCE.md
- [ ] Merge SIMPLE-START.md
- [ ] Merge QUICKSTART-CI-SETUP.md
- [ ] Merge docs/QUICK_START_GUIDE.md
- [ ] Create unified docs/01-getting-started/QUICKSTART.md

### Installation Consolidation
- [ ] Merge INSTALLATION.md
- [ ] Merge INSTALLATION-COMPLETE-GUIDE.md
- [ ] Merge MANUAL-SETUP-REQUIRED.md
- [ ] Merge docs/USER-SETUP.md
- [ ] Create unified docs/01-getting-started/INSTALLATION.md

### CI/CD Consolidation
- [ ] Merge CI-CD-GUIDE-HURD.md
- [ ] Merge CI-CD-MIGRATION-SUMMARY.md
- [ ] Merge docs/CI-CD-GUIDE.md
- [ ] Create unified docs/04-operations/CI-CD.md

### Architecture Consolidation
- [ ] Merge docs/ARCHITECTURE.md
- [ ] Merge STRUCTURAL-MAP.md
- [ ] Merge docs/COMPREHENSIVE-ANALYSIS-AND-IMPLEMENTATION-PLAN.md
- [ ] Create unified docs/00-overview/ARCHITECTURE.md

### x86_64 Migration Archive
- [ ] Move X86_64-ONLY-SETUP.md to archive
- [ ] Move X86_64-MIGRATION-AND-CONSOLIDATION-PLAN.md to archive
- [ ] Move README-X86_64-MIGRATION.md to archive
- [ ] Move X86_64-VALIDATION-CHECKLIST.md to archive
- [ ] Move X86_64-MIGRATION-COMPLETE.md to archive

## Phase 4: Link Updates [TODO]
- [ ] Update all internal cross-references
- [ ] Fix README.md project links
- [ ] Update CI/CD documentation paths
- [ ] Verify external links still valid

## Phase 5: Validation [TODO]
- [ ] Run markdown link checker
- [ ] Verify all files accessible from INDEX.md
- [ ] Check for orphaned documents
- [ ] Test navigation paths for each audience

## Phase 6: Cleanup [TODO]
- [ ] Remove duplicate content from root
- [ ] Archive deprecated files
- [ ] Update .gitignore if needed
- [ ] Commit with clear message

================================================================================
END CHECKLIST
================================================================================
EOF

echo "  Created: docs/MIGRATION-CHECKLIST.md"

# ================================================================================
# Create file mapping
# ================================================================================
echo ""
echo "Creating file mapping for reference..."

cat > "$DOCS_DIR/FILE-MAPPING.md" << 'EOF'
================================================================================
DOCUMENTATION FILE MAPPING
Generated: 2025-11-07
Purpose: Track where each file should be migrated
================================================================================

## Root Level Files (31 files)

| Current File | Target Location | Action |
|-------------|-----------------|--------|
| README.md | Keep in root | Update links |
| QUICKSTART.md | docs/01-getting-started/QUICKSTART.md | Consolidate |
| QUICK-REFERENCE.md | docs/01-getting-started/QUICKSTART.md | Merge |
| SIMPLE-START.md | docs/01-getting-started/QUICKSTART.md | Merge |
| QUICKSTART-CI-SETUP.md | docs/04-operations/CI-CD.md | Merge |
| INSTALLATION.md | docs/01-getting-started/INSTALLATION.md | Consolidate |
| INSTALLATION-COMPLETE-GUIDE.md | docs/01-getting-started/INSTALLATION.md | Merge |
| PORT-MAPPING-GUIDE.md | docs/02-user-guide/PORT-MAPPING.md | Move |
| CI-CD-GUIDE-HURD.md | docs/04-operations/CI-CD.md | Consolidate |
| CI-CD-MIGRATION-SUMMARY.md | docs/04-operations/CI-CD.md | Merge |
| COMPREHENSIVE-IMAGE-GUIDE.md | docs/03-development/CUSTOM-IMAGES.md | Move |
| CUSTOM-HURD-FEATURES.md | docs/05-reference/KERNEL-CONFIG.md | Move |
| HURD-SYSTEM-AUDIT.md | docs/06-research/LESSONS-LEARNED.md | Move |
| MCP-SERVERS-SETUP.md | docs/03-development/DEBUGGING.md | Move |
| REPO-AUDIT-FINDINGS.md | docs/06-research/LESSONS-LEARNED.md | Move |
| X86_64-*.md (5 files) | docs/archive/2025-11-migration/ | Archive |
| FSCK-ERROR-FIX.md | docs/02-user-guide/TROUBLESHOOTING.md | Merge |
| IO-ERROR-FIX.md | docs/02-user-guide/TROUBLESHOOTING.md | Merge |
| TEST-RESULTS.md | docs/06-research/EXPERIMENTS.md | Move |
| LOCAL-TESTING-GUIDE.md | docs/03-development/DEBUGGING.md | Move |
| CONTROL-PLANE-IMPLEMENTATION.md | docs/00-overview/ARCHITECTURE.md | Merge |
| PROJECT-SUMMARY.md | docs/00-overview/README.md | Merge |
| STRUCTURAL-MAP.md | docs/00-overview/ARCHITECTURE.md | Merge |
| REPOSITORY-INDEX.md | docs/INDEX.md | Transform |
| requirements.md | docs/01-getting-started/REQUIREMENTS.md | Move |
| MANUAL-SETUP-REQUIRED.md | docs/01-getting-started/INSTALLATION.md | Merge |

## Docs Directory Files (27 files)

| Current File | Target Location | Action |
|-------------|-----------------|--------|
| docs/ARCHITECTURE.md | docs/00-overview/ARCHITECTURE.md | Move |
| docs/QUICK_START_GUIDE.md | docs/01-getting-started/QUICKSTART.md | Merge |
| docs/USER-SETUP.md | docs/01-getting-started/INSTALLATION.md | Merge |
| docs/SSH-CONFIGURATION-RESEARCH.md | docs/06-research/EXPERIMENTS.md | Move |
| docs/INTERACTIVE-ACCESS-GUIDE.md | docs/02-user-guide/SSH-ACCESS.md | Move |
| docs/DEPLOYMENT.md | docs/04-operations/DEPLOYMENT.md | Move |
| docs/DEPLOYMENT-STATUS.md | docs/04-operations/DEPLOYMENT.md | Merge |
| docs/TROUBLESHOOTING.md | docs/02-user-guide/TROUBLESHOOTING.md | Move |
| docs/VALIDATION-AND-TROUBLESHOOTING.md | docs/02-user-guide/TROUBLESHOOTING.md | Merge |
| docs/QEMU-TUNING.md | docs/05-reference/QEMU-CONFIG.md | Move |
| docs/QEMU-OPTIMIZATION-2025.md | docs/05-reference/QEMU-CONFIG.md | Merge |
| docs/KERNEL-FIX-GUIDE.md | docs/05-reference/KERNEL-CONFIG.md | Move |
| docs/KERNEL-STANDARDIZATION-PLAN.md | docs/05-reference/KERNEL-CONFIG.md | Merge |
| docs/HURD-IMAGE-BUILDING.md | docs/03-development/CUSTOM-IMAGES.md | Move |
| docs/CI-CD-GUIDE.md | docs/04-operations/CI-CD.md | Merge |
| docs/CI-CD-PROVISIONED-IMAGE.md | docs/04-operations/CI-CD.md | Merge |
| docs/RESEARCH-FINDINGS.md | docs/06-research/LESSONS-LEARNED.md | Move |
| docs/MACH_QEMU_RESEARCH_REPORT.md | docs/06-research/MACH-VARIANTS.md | Move |
| docs/HURD-TESTING-REPORT.md | docs/06-research/EXPERIMENTS.md | Move |
| docs/mach-variants/* | docs/06-research/MACH-VARIANTS.md | Consolidate |
| docs/CREDENTIALS.md | docs/02-user-guide/SSH-ACCESS.md | Merge |
| docs/MCP-TOOLS-ASSESSMENT-MATRIX.md | docs/03-development/DEBUGGING.md | Move |
| docs/IMPLEMENTATION-COMPLETE.md | Archive | Archive |
| docs/EXECUTION-SUMMARY.md | Archive | Archive |
| docs/SESSION-COMPLETION-REPORT.md | Archive | Archive |

================================================================================
CONSOLIDATION STATISTICS
================================================================================

Before: 58+ markdown files
After: ~20 core documents + archived materials

Reduction: 65% fewer files
Benefit: Easier navigation, less duplication, clearer structure

================================================================================
END MAPPING
================================================================================
EOF

echo "  Created: docs/FILE-MAPPING.md"

# ================================================================================
# Summary
# ================================================================================
echo ""
echo "================================================================================
MIGRATION PREPARATION COMPLETE
================================================================================
"
echo "Directory structure created: ${#directories[@]} directories"
echo "Section READMEs created: ${#sections[@]} files"
echo ""
echo "Next steps:"
echo "1. Review docs/MIGRATION-CHECKLIST.md"
echo "2. Review docs/FILE-MAPPING.md"
echo "3. Begin consolidating documents according to the mapping"
echo "4. Use templates in docs/assets/templates/ for new documents"
echo ""
echo "To start migration:"
echo "  cd $REPO_ROOT"
echo "  # Begin with the quickstart consolidation"
echo "  # Then work through each section systematically"
echo ""
echo "================================================================================
"