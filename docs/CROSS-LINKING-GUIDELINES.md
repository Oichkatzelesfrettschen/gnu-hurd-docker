================================================================================
CROSS-LINKING GUIDELINES FOR GNU HURD DOCKER DOCUMENTATION
Version: 1.0
Last Updated: 2025-11-07
Purpose: Standards for linking between documents
================================================================================

================================================================================
LINK SYNTAX STANDARDS
================================================================================

### 1. RELATIVE PATHS ONLY

CORRECT:
```markdown
[Installation Guide](../01-getting-started/INSTALLATION.md)
[Troubleshooting](../02-user-guide/TROUBLESHOOTING.md)
[Same Directory](./ANOTHER-DOC.md)
```

INCORRECT:
```markdown
[Wrong](/docs/01-getting-started/INSTALLATION.md)  # Absolute path
[Wrong](https://github.com/.../INSTALLATION.md)    # Full URL for internal
```

### 2. ANCHOR LINKS

For linking to specific sections:
```markdown
[SSH Setup](../02-user-guide/SSH-ACCESS.md#setup)
[Problem 1](./TROUBLESHOOTING.md#problem-1-description)
```

### 3. EXTERNAL LINKS

Always use full URLs for external resources:
```markdown
[GNU Hurd Official](https://www.gnu.org/software/hurd/)
[QEMU Documentation](https://www.qemu.org/docs/master/)
```

================================================================================
NAVIGATION PATTERNS
================================================================================

### 1. BREADCRUMB NAVIGATION

At the top of deep documents:
```markdown
[Docs](../) > [Getting Started](../01-getting-started/) > Installation
```

### 2. SEE ALSO SECTIONS

At the end of documents:
```markdown
## See Also
- [Related Doc 1](../path/to/doc1.md) - Why it's related
- [Related Doc 2](../path/to/doc2.md) - Why it's related
```

### 3. PREREQUISITES LINKS

At the beginning of technical documents:
```markdown
## Prerequisites
Before reading this document, ensure you've reviewed:
- [System Requirements](../01-getting-started/REQUIREMENTS.md)
- [Basic Concepts](../00-overview/ARCHITECTURE.md#concepts)
```

================================================================================
LINK VALIDATION
================================================================================

### 1. MANUAL VALIDATION

Before committing:
```bash
# Check for broken internal links
grep -r "\[.*\](" docs/ | grep -v "http" | while read line; do
  # Verify each link target exists
done
```

### 2. AUTOMATED VALIDATION

In CI/CD pipeline:
```yaml
- name: Check markdown links
  uses: gaurav-nelson/github-action-markdown-link-check@v1
  with:
    folder-path: 'docs'
```

### 3. VALIDATION CHECKLIST

- [ ] All internal links use relative paths
- [ ] All external links use https where possible
- [ ] Anchor links match actual section headers
- [ ] No orphaned documents (unreachable from INDEX.md)
- [ ] No circular dependencies

================================================================================
CROSS-REFERENCE MATRIX
================================================================================

Major document relationships:

```
QUICKSTART.md
  -> INSTALLATION.md (detailed setup)
  -> REQUIREMENTS.md (prerequisites)
  -> TROUBLESHOOTING.md (if problems)

INSTALLATION.md
  -> REQUIREMENTS.md (must read first)
  -> ARCHITECTURE.md (understanding design)
  -> TROUBLESHOOTING.md (common issues)

CI-CD.md
  -> BUILD-SYSTEM.md (understanding builds)
  -> DEPLOYMENT.md (production setup)
  -> AUTOMATION.md (related scripts)

TROUBLESHOOTING.md
  -> ARCHITECTURE.md (understanding system)
  -> DEBUGGING.md (advanced tools)
  -> FAQ.md (common questions)
```

================================================================================
LINK MAINTENANCE
================================================================================

### 1. WHEN MOVING FILES

Before moving a file:
1. Search for all references: `grep -r "FILENAME.md" docs/`
2. Update all links to new location
3. Consider adding redirect note in old location

### 2. WHEN RENAMING FILES

1. Update all internal references
2. Update INDEX.md
3. Update section README.md files
4. Check CI/CD scripts for hardcoded paths

### 3. WHEN DELETING FILES

1. Never delete - move to archive/
2. Add DEPRECATED banner
3. Add forwarding link to replacement
4. Update all references

================================================================================
COMMON LINK PATTERNS
================================================================================

### 1. FROM ROOT TO DOCS

```markdown
From README.md:
[Documentation](docs/)
[Architecture](docs/00-overview/ARCHITECTURE.md)
```

### 2. BETWEEN SECTIONS

```markdown
From 01-getting-started/ to 02-user-guide/:
[User Guide](../02-user-guide/)
[SSH Access](../02-user-guide/SSH-ACCESS.md)
```

### 3. WITHIN SECTION

```markdown
Within 01-getting-started/:
[Installation](./INSTALLATION.md)
[Requirements](./REQUIREMENTS.md)
```

### 4. TO ARCHIVE

```markdown
To archived content:
[Deprecated Guide](../archive/2025-11-migration/OLD-GUIDE.md)
Note: This document has been archived. See [New Guide](../current/NEW-GUIDE.md)
```

================================================================================
LINK TYPES AND USAGE
================================================================================

| Link Type | Usage | Example |
|-----------|-------|---------|
| Document Link | Link to entire document | `[Guide](../guide.md)` |
| Section Link | Link to specific section | `[Setup](../guide.md#setup)` |
| Directory Link | Link to section index | `[Guides](../02-guides/)` |
| Code Link | Link to source code | `[Script](../../scripts/setup.sh)` |
| External Link | Link outside repo | `[GNU](https://gnu.org)` |

================================================================================
SPECIAL CASES
================================================================================

### 1. LINKING TO CODE

```markdown
See implementation in [entrypoint.sh](../../entrypoint.sh#L42)
Configuration in [docker-compose.yml](../../docker-compose.yml)
```

### 2. LINKING TO WORKFLOWS

```markdown
CI/CD workflow: [.github/workflows/build.yml](../../.github/workflows/build.yml)
```

### 3. LINKING TO IMAGES/ASSETS

```markdown
![Architecture Diagram](../assets/diagrams/architecture.png)
[Download Template](../assets/templates/template.md)
```

================================================================================
BEST PRACTICES
================================================================================

1. **Be Specific**: Link to sections, not just documents
2. **Add Context**: Explain why the link is relevant
3. **Test Links**: Click through before committing
4. **Update Promptly**: Fix broken links immediately
5. **Use Descriptive Text**: Not "click here" but "Installation Guide"
6. **Avoid Deep Nesting**: Max 3 levels of ../ navigation
7. **Document Relationships**: Maintain cross-reference matrix
8. **Version Carefully**: Link to specific versions if needed

================================================================================
TROUBLESHOOTING BROKEN LINKS
================================================================================

### Finding Broken Links

```bash
# Find all markdown links
find docs -name "*.md" -exec grep -H "\[.*\](" {} \;

# Check if link targets exist
for file in docs/**/*.md; do
  grep "\[.*\](" "$file" | while read line; do
    # Extract and validate link target
  done
done
```

### Common Issues

1. **File moved**: Update all references
2. **Section renamed**: Update anchor links
3. **External site down**: Find alternative or cache
4. **Typo in path**: Fix spelling
5. **Wrong path depth**: Count ../ levels

================================================================================
END GUIDELINES
================================================================================