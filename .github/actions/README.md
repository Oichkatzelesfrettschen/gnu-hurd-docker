# Composite Actions

This directory contains reusable composite actions for the GNU/Hurd Docker project workflows.

## Available Actions

### 1. shellcheck-validate

Runs ShellCheck on shell scripts with configurable severity.

**Usage:**
```yaml
- uses: ./.github/actions/shellcheck-validate
  with:
    scripts-path: '.'
    severity: 'warning'
    exclude-patterns: 'TEMPLATE|example'
```

**Inputs:**
- `scripts-path`: Path to search for shell scripts (default: '.')
- `severity`: Minimum severity level (default: 'warning')
- `exclude-patterns`: Regex patterns to exclude (default: '')

**Outputs:**
- `scripts-checked`: Number of scripts checked
- `result`: Validation result (pass/fail)

### 2. yaml-validate

Validates YAML files using Python YAML parser.

**Usage:**
```yaml
- uses: ./.github/actions/yaml-validate
  with:
    yaml-files: 'docker-compose.yml mkdocs.yml .github/workflows/*.yml'
    strict: 'true'
```

**Inputs:**
- `yaml-files`: Space-separated list of YAML files (supports globbing)
- `strict`: Enable strict validation mode (default: 'true')

**Outputs:**
- `files-checked`: Number of files checked
- `result`: Validation result (pass/fail)

### 3. workflow-summary

Generates comprehensive workflow summary for GitHub Actions.

**Usage:**
```yaml
- uses: ./.github/actions/workflow-summary
  if: always()
  with:
    workflow-name: 'Validate Configuration'
    status: ${{ job.status }}
    checks-performed: |
      - ✓ Dockerfile validation
      - ✓ YAML syntax validation
      - ✓ Script executability
    additional-info: |
      ### Files Validated
      - docker-compose.yml
      - entrypoint.sh
```

**Inputs:**
- `workflow-name`: Name of the workflow (required)
- `status`: Workflow status (required, use `${{ job.status }}`)
- `checks-performed`: Markdown list of checks performed (required)
- `additional-info`: Additional markdown content (optional)

## Benefits

1. **Consistency**: Ensures consistent validation across all workflows
2. **Maintainability**: Centralized logic - update once, apply everywhere
3. **Reusability**: Easy to use in multiple workflows
4. **Caching**: Built-in caching for better performance
5. **Documentation**: Self-documenting with clear inputs/outputs

## Future Actions

Potential composite actions for future implementation:
- `setup-docker-buildx`: Configure Docker Buildx with caching
- `security-scan`: Run Trivy or other security scanners
- `artifact-upload`: Upload artifacts with standard settings
- `notification-send`: Send notifications on workflow status

## Usage Guidelines

1. Always use the latest version of composite actions
2. Test composite actions in feature branches before merging
3. Keep actions focused on a single responsibility
4. Document all inputs and outputs clearly
5. Use semantic versioning for breaking changes

## Contributing

When adding new composite actions:
1. Create a new directory under `.github/actions/`
2. Add an `action.yml` file with clear metadata
3. Include branding (icon and color)
4. Document inputs, outputs, and usage
5. Update this README
6. Test thoroughly before merging

---

**Last Updated:** 2025-11-17
**Maintained by:** GNU/Hurd Docker Team
