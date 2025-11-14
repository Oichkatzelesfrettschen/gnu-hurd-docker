# GitHub Actions Best Practices Guide

**Version**: 1.0  
**Date**: 2025-11-14  
**Status**: Production Standard

---

## Overview

This document establishes best practices for GitHub Actions workflows in the GNU/Hurd Docker repository. All workflows must follow these standards to ensure reliability, security, and maintainability.

---

## 1. Action Version Management

### 1.1 Version Pinning Strategy

**ALWAYS pin actions to specific versions** - Never use floating tags like `@master` or `@main`.

#### ✅ Recommended Approach: Semantic Versioning

```yaml
# GOOD: Pin to major version (receives security updates)
uses: actions/checkout@v4
uses: actions/setup-python@v5

# GOOD: Pin to specific tag for critical workflows
uses: aquasecurity/trivy-action@0.28.0

# BAD: Using branch names (unstable, can break)
uses: aquasecurity/trivy-action@master  # ❌ DON'T DO THIS
```

#### Version Update Cadence

| Action Type | Update Frequency | Rationale |
|------------|------------------|-----------|
| Core GitHub Actions | Every 6 months | Stable, well-tested |
| Third-party Actions | Every 3 months | Check for updates |
| Security Scanners | Every 2 months | Latest vulnerability DB |

### 1.2 Current Action Versions (GNU/Hurd Docker)

#### Core Actions
```yaml
actions/checkout@v4                    # Latest stable (2024)
actions/setup-python@v5                # Latest stable (2024)
actions/upload-artifact@v4             # Latest stable
actions/upload-pages-artifact@v3       # Latest stable
actions/deploy-pages@v4                # Latest stable
```

#### Docker Actions
```yaml
docker/setup-buildx-action@v3          # Latest stable
docker/login-action@v3                 # Latest stable
docker/metadata-action@v5              # Latest stable
docker/build-push-action@v5            # Latest stable
actions/attest-build-provenance@v1     # Latest stable
```

#### Release Actions
```yaml
softprops/action-gh-release@v2         # Latest stable, replaces deprecated actions/create-release
```

#### Security Actions
```yaml
aquasecurity/trivy-action@0.28.0       # Pinned to specific version
github/codeql-action/upload-sarif@v3   # Latest stable
```

---

## 2. Python Version Management

### 2.1 Python Version Selection

**Current Standard**: Python 3.12 (latest stable as of 2024)

```yaml
- name: Setup Python
  uses: actions/setup-python@v5
  with:
    python-version: '3.12'  # Latest stable LTS
```

#### Python Version Lifecycle

| Version | Status | Support Until | Usage |
|---------|--------|---------------|-------|
| 3.12 | **RECOMMENDED** | October 2028 | All new workflows |
| 3.11 | Supported | October 2027 | Legacy workflows |
| 3.10 | Supported | October 2026 | Minimum version |
| 3.9 | Deprecated | October 2025 | Migrate away |

### 2.2 Python Setup Best Practices

```yaml
- name: Setup Python
  uses: actions/setup-python@v5
  with:
    python-version: '3.12'
    cache: 'pip'  # Enable pip caching for faster builds
    
- name: Install dependencies
  run: |
    python -m pip install --upgrade pip
    pip install -r requirements.txt
```

---

## 3. Permissions Management

### 3.1 Principle of Least Privilege

**ALWAYS explicitly define permissions** - Never rely on default permissions.

#### Workflow-Level Permissions

```yaml
# Restrictive default, override per job
permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    # Job inherits restrictive permissions
```

#### Job-Level Permissions

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write      # For creating releases
      packages: write      # For pushing to GHCR
      attestations: write  # For build provenance
      id-token: write      # For OIDC
```

### 3.2 Common Permission Sets

#### Read-Only (Validation/Testing)
```yaml
permissions:
  contents: read
```

#### Release Workflows
```yaml
permissions:
  contents: write
  packages: read
```

#### Container Publishing
```yaml
permissions:
  contents: read
  packages: write
  attestations: write
  id-token: write
```

#### Security Scanning
```yaml
permissions:
  contents: read
  security-events: write
```

#### Pages Deployment
```yaml
permissions:
  contents: read
  pages: write
  id-token: write
```

---

## 4. Workflow Structure Best Practices

### 4.1 Job Dependencies

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps: [...]

  test:
    runs-on: ubuntu-latest
    needs: lint  # Runs after lint
    steps: [...]

  deploy:
    runs-on: ubuntu-latest
    needs: [lint, test]  # Runs after both
    if: github.ref == 'refs/heads/main'  # Conditional
    steps: [...]
```

### 4.2 Conditional Execution

```yaml
# Run always, even if dependencies fail
needs: [lint, test]
if: always()

# Run only on specific branches
if: github.ref == 'refs/heads/main'

# Run only for tags
if: startsWith(github.ref, 'refs/tags/')

# Run only on pull requests
if: github.event_name == 'pull_request'
```

### 4.3 Error Handling

```yaml
# Continue workflow even if step fails
- name: Optional step
  continue-on-error: true
  run: ./optional-check.sh

# Fail fast (default behavior)
- name: Critical step
  run: ./required-check.sh
```

---

## 5. Caching Strategies

### 5.1 Dependency Caching

```yaml
# Python dependencies
- uses: actions/setup-python@v5
  with:
    python-version: '3.12'
    cache: 'pip'  # Automatic pip caching

# Node.js dependencies
- uses: actions/setup-node@v4
  with:
    node-version: '20'
    cache: 'npm'

# Custom caching
- uses: actions/cache@v4
  with:
    path: |
      ~/.cache/pip
      ~/.npm
    key: ${{ runner.os }}-deps-${{ hashFiles('**/requirements.txt') }}
```

### 5.2 Build Artifact Caching

```yaml
# Docker layer caching
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

---

## 6. Security Best Practices

### 6.1 Secret Management

```yaml
# ✅ GOOD: Use secrets for sensitive data
- name: Login to registry
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_PASSWORD }}

# ❌ BAD: Never hardcode secrets
password: "my-secret-password"  # DON'T DO THIS
```

### 6.2 Security Scanning

```yaml
# Trivy for container/filesystem scanning
- uses: aquasecurity/trivy-action@0.28.0
  with:
    scan-type: 'fs'
    severity: 'CRITICAL,HIGH,MEDIUM'
    format: 'sarif'
    output: 'trivy-results.sarif'

# Upload to GitHub Security
- uses: github/codeql-action/upload-sarif@v3
  if: always()
  with:
    sarif_file: 'trivy-results.sarif'
```

### 6.3 Dependency Auditing

```yaml
# Python dependency audit
- name: Check for known vulnerabilities
  run: |
    pip install safety
    safety check --json
```

---

## 7. Optimization Best Practices

### 7.1 Checkout Optimization

```yaml
# Shallow clone for speed (default)
- uses: actions/checkout@v4

# Full history when needed (e.g., changelogs)
- uses: actions/checkout@v4
  with:
    fetch-depth: 0

# Specific branch/tag
- uses: actions/checkout@v4
  with:
    ref: 'v2.0.0'
```

### 7.2 Parallel Execution

```yaml
jobs:
  # These run in parallel
  lint-shell:
    runs-on: ubuntu-latest
    steps: [...]
    
  lint-python:
    runs-on: ubuntu-latest
    steps: [...]
    
  lint-yaml:
    runs-on: ubuntu-latest
    steps: [...]
```

### 7.3 Matrix Strategies

```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        python: ['3.10', '3.11', '3.12']
    steps:
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python }}
```

---

## 8. Documentation Standards

### 8.1 Workflow Comments

```yaml
# Always include descriptive comments
name: Build and Test

# Trigger on these events
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    name: Build and Test  # Human-readable name
    runs-on: ubuntu-latest
    
    steps:
      # Step 1: Get the code
      - name: Checkout repository
        uses: actions/checkout@v4
```

### 8.2 Step Output Documentation

```yaml
- name: Generate version
  id: version
  run: |
    VERSION=${GITHUB_REF#refs/tags/}
    echo "version=$VERSION" >> $GITHUB_OUTPUT
    echo "Generated version: $VERSION"
    
# Use in later steps
- name: Create release
  run: echo "Releasing ${{ steps.version.outputs.version }}"
```

---

## 9. Monitoring and Debugging

### 9.1 Job Summaries

```yaml
- name: Generate summary
  if: always()
  run: |
    cat <<EOF >> $GITHUB_STEP_SUMMARY
    ## Build Results
    - Status: ${{ job.status }}
    - Duration: ${{ steps.time.outputs.duration }}
    EOF
```

### 9.2 Debug Logging

```yaml
# Enable debug logs by setting secrets
# ACTIONS_RUNNER_DEBUG: true
# ACTIONS_STEP_DEBUG: true

- name: Debug info
  run: |
    echo "::debug::This is a debug message"
    echo "::notice::This is a notice"
    echo "::warning::This is a warning"
    echo "::error::This is an error"
```

---

## 10. Migration Guide

### 10.1 Upgrading Actions

#### From actions/setup-python@v4 to v5

```yaml
# Before
- uses: actions/setup-python@v4
  with:
    python-version: '3.11'

# After
- uses: actions/setup-python@v5
  with:
    python-version: '3.12'  # Also upgrade Python version
    cache: 'pip'            # Enable caching
```

#### From actions/create-release@v1 (DEPRECATED)

```yaml
# Before (DEPRECATED)
- uses: actions/create-release@v1
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  with:
    tag_name: ${{ github.ref }}

# After (MODERN)
- uses: softprops/action-gh-release@v2
  with:
    tag_name: ${{ github.ref_name }}
```

#### From @master to Pinned Version

```yaml
# Before (UNSTABLE)
- uses: aquasecurity/trivy-action@master

# After (STABLE)
- uses: aquasecurity/trivy-action@0.28.0
```

---

## 11. Testing Workflows

### 11.1 Local Testing

```bash
# Install act for local testing
# https://github.com/nektos/act
brew install act  # macOS
# or
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Run workflow locally
act -j test  # Run 'test' job
act push     # Simulate push event
```

### 11.2 Validation Tools

```bash
# YAML validation
yamllint .github/workflows/*.yml

# Action validation
actionlint .github/workflows/*.yml
```

---

## 12. Deprecation Policy

### 12.1 Action Lifecycle

1. **Active**: Current recommended version
2. **Maintenance**: Receives security updates only
3. **Deprecated**: Will be removed, migrate away
4. **Removed**: No longer available

### 12.2 Migration Timeline

When an action is deprecated:
- **Immediate**: Update documentation
- **30 days**: Create migration plan
- **60 days**: Update all workflows
- **90 days**: Remove all deprecated usage

---

## 13. Repository-Specific Standards

### 13.1 GNU/Hurd Docker Workflows

| Workflow | Purpose | Trigger | Duration |
|----------|---------|---------|----------|
| validate.yml | Config validation | Push, PR | ~2 min |
| validate-config.yml | File validation | Push, PR | ~1 min |
| quality-and-security.yml | Comprehensive checks | Push, PR, Schedule | ~5 min |
| build-x86_64.yml | Build Hurd image | Push to main | ~15 min |
| push-ghcr.yml | Push to registry | Push, PR, Tags | ~10 min |
| deploy-pages.yml | Deploy docs | Push to main | ~3 min |
| release.yml | Create release | Tags | ~1 min |
| release-qemu-image.yml | Release QEMU image | Tags, Manual | ~5 min |
| release-artifacts.yml | Package artifacts | Tags, Manual | ~5 min |

### 13.2 Quality Gates

All workflows must pass:
- ✅ YAML linting
- ✅ ShellCheck (for shell scripts)
- ✅ Security scanning
- ✅ Dependency auditing

---

## 14. Maintenance Checklist

### Monthly
- [ ] Review GitHub Actions changelog
- [ ] Check for action updates
- [ ] Review workflow run times
- [ ] Check for failed workflows

### Quarterly
- [ ] Update action versions
- [ ] Update Python/Node versions
- [ ] Review permissions
- [ ] Optimize caching strategies
- [ ] Update documentation

### Annually
- [ ] Major version upgrades
- [ ] Architecture review
- [ ] Performance audit
- [ ] Security audit

---

## 15. Resources

### Official Documentation
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)

### Action Marketplaces
- [GitHub Marketplace](https://github.com/marketplace?type=actions)
- [Awesome Actions](https://github.com/sdras/awesome-actions)

### Tools
- [actionlint](https://github.com/rhysd/actionlint) - Workflow linter
- [act](https://github.com/nektos/act) - Local testing
- [yamllint](https://github.com/adrienverge/yamllint) - YAML validation

---

## Changelog

### 2025-11-14 - Version 1.0
- Initial best practices guide created
- Documented all modernized actions
- Established version standards
- Created migration guides

---

**Document Owner**: GNU/Hurd Docker Team  
**Review Cycle**: Quarterly  
**Last Updated**: 2025-11-14  
**Next Review**: 2025-02-14
