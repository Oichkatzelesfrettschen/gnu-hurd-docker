#!/bin/bash
# Documentation Audit Script
# Analyzes all markdown files for consolidation opportunities

set -euo pipefail

echo "=================================================="
echo "Documentation Audit Report"
echo "Date: $(date +%Y-%m-%d)"
echo "=================================================="
echo ""

# Count total markdown files
echo "## File Counts"
echo ""
TOP_LEVEL=$(find . -maxdepth 1 -name "*.md" -type f | wc -l)
DOCS_DIR=$(find docs -name "*.md" -type f 2>/dev/null | wc -l || echo 0)
TOTAL=$((TOP_LEVEL + DOCS_DIR))

echo "Top-level markdown files: $TOP_LEVEL"
echo "docs/ directory files: $DOCS_DIR"
echo "Total markdown files: $TOTAL"
echo ""

# Find duplicates by name
echo "## Potential Duplicates (by similar names)"
echo ""
find . -name "*.md" -type f | sed 's|.*/||' | sort | uniq -d | while read -r dup; do
    echo "Duplicate name: $dup"
    find . -name "$dup" -type f
    echo ""
done

# Find files with "GUIDE" in name
echo "## Files containing 'GUIDE'"
echo ""
find . -name "*GUIDE*.md" -type f | sort
echo ""

# Find files with "QUICKSTART" in name
echo "## Files containing 'QUICKSTART'"
echo ""
find . -name "*QUICKSTART*.md" -o -name "*QUICK*.md" -type f | sort
echo ""

# Find files with "CI" or "CD" in name
echo "## CI/CD related files"
echo ""
find . -name "*CI*.md" -o -name "*CD*.md" -type f | sort
echo ""

# Find files with "INSTALLATION" in name
echo "## Installation related files"
echo ""
find . -name "*INSTALL*.md" -type f | sort
echo ""

# Check for i386 references
echo "## Files with i386 references"
echo ""
grep -l "i386" *.md 2>/dev/null | while read -r file; do
    count=$(grep -c "i386" "$file" || echo 0)
    echo "$file: $count references"
done
echo ""

grep -l "i386" docs/*.md 2>/dev/null | while read -r file; do
    count=$(grep -c "i386" "$file" || echo 0)
    echo "$file: $count references"
done
echo ""

# Check for qemu-system-i386 references
echo "## Files with qemu-system-i386 references"
echo ""
find . -name "*.md" -type f -exec grep -l "qemu-system-i386" {} \; | sort
echo ""

# Analyze file sizes
echo "## Documentation Size Analysis"
echo ""
echo "Top-level markdown files by size:"
find . -maxdepth 1 -name "*.md" -type f -exec du -h {} \; | sort -h | tail -10
echo ""

echo "docs/ markdown files by size:"
find docs -name "*.md" -type f -exec du -h {} \; 2>/dev/null | sort -h | tail -10 || echo "No docs found"
echo ""

# Count total lines
echo "## Total Documentation Lines"
echo ""
TOTAL_LINES=$(find . -name "*.md" -type f -exec wc -l {} \; | awk '{sum+=$1} END {print sum}')
echo "Total lines across all markdown: $TOTAL_LINES"
echo ""

# Find files mentioning "lesson" or "learned"
echo "## Files with Lessons Learned"
echo ""
find . -name "*.md" -type f -exec grep -l -i "lesson" {} \; | sort
echo ""

# Find files mentioning "deprecated" or "outdated"
echo "## Potentially Outdated Files"
echo ""
find . -name "*.md" -type f -exec grep -l -i "deprecated\|outdated\|obsolete\|legacy" {} \; | sort
echo ""

# Check for files with dates in content (potential staleness)
echo "## Files with Old Dates (pre-2025)"
echo ""
find . -name "*.md" -type f -exec grep -l "202[0-4]-" {} \; | sort
echo ""

echo "=================================================="
echo "Audit Complete"
echo "=================================================="
echo ""
echo "Next Steps:"
echo "1. Review duplicate files for consolidation"
echo "2. Merge similar guides (QUICKSTART, INSTALLATION, CI/CD)"
echo "3. Update all i386 references to x86_64"
echo "4. Archive outdated/deprecated content"
echo "5. Create new modular structure per migration plan"
echo ""
