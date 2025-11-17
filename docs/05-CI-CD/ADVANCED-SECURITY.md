# Advanced Security Features

## Overview

This document describes the advanced security features implemented in the GNU/Hurd Docker project's CI/CD workflows.

## Security Layers

### Layer 1: Dependency Management

#### Dependabot Configuration
**File:** `.github/dependabot.yml`

Automated dependency updates for:
- **GitHub Actions**: Weekly updates on Mondays
- **Docker base images**: Weekly security patches
- **Python dependencies**: Automatic vulnerability alerts
- **npm dependencies**: Package security monitoring

**Benefits:**
- Automatic security patches
- Reduced manual update overhead
- Proactive vulnerability management
- Pull requests auto-assigned to maintainers

### Layer 2: Workflow Security

#### Explicit Permissions
All workflows follow the least-privilege principle:

```yaml
permissions:
  contents: read        # Default: read-only
  packages: write       # Only for container registry
  attestations: write   # For provenance and SBOM
  id-token: write       # For OIDC authentication
```

#### Concurrency Control
Prevents duplicate runs and resource exhaustion:
- **Dev workflows**: `cancel-in-progress: true`
- **Release workflows**: `cancel-in-progress: false`

#### Timeout Protection
All jobs have timeout limits:
- Quick validations: 10-15 minutes
- Standard builds: 20-30 minutes
- Long operations: 120-180 minutes

### Layer 3: Supply Chain Security

#### Build Provenance
**Implemented in:** `push-ghcr.yml`

```yaml
- uses: actions/attest-build-provenance@v1
  with:
    subject-name: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
    subject-digest: ${{ steps.push.outputs.digest }}
    push-to-registry: true
```

**Benefits:**
- Verifiable build artifacts
- Tamper detection
- Supply chain attestation
- Sigstore integration

#### SBOM Generation
**Implemented in:** `push-ghcr.yml`

```yaml
- uses: anchore/sbom-action@v0
  with:
    image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.push.outputs.digest }}
```

**Benefits:**
- Complete dependency tracking
- Vulnerability scanning
- Compliance requirements (NTIA, EO 14028)
- License compliance

#### SBOM Attestation
Links SBOM to container image:

```yaml
- uses: actions/attest-sbom@v1
  with:
    subject-name: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
    subject-digest: ${{ steps.push.outputs.digest }}
    sbom-path: sbom.spdx.json
    push-to-registry: true
```

### Layer 4: Security Scanning

#### Trivy Vulnerability Scanning
**Version:** 0.28.0
**Frequency:** Push to main, PRs, weekly schedule

```yaml
- uses: aquasecurity/trivy-action@0.28.0
  with:
    scan-type: 'fs'
    severity: 'CRITICAL,HIGH'
```

**Scans:**
- Docker images
- Filesystem
- Git repositories
- Configuration files

#### ShellCheck Analysis
**Severity:** Warnings as errors
**Coverage:** All shell scripts

```yaml
- uses: ./.github/actions/shellcheck-validate
  with:
    severity: 'warning'
    exclude-patterns: 'TEMPLATE|example'
```

#### Hadolint Dockerfile Linting
**Version:** 2.12.0
**Threshold:** Warning

```yaml
- name: Install Hadolint
  run: |
    wget -O /usr/local/bin/hadolint \
      https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64
```

### Layer 5: Artifact Security

#### Artifact Retention
- **Build artifacts**: 7-30 days
- **Security scan results**: Permanent (GitHub Security tab)
- **SBOMs**: Attached to container images

#### Access Control
- Artifacts accessible only to repository members
- Container registry: Public read, write requires authentication
- Security scan results: Repository-scoped

## Security Best Practices

### For Contributors

1. **Workflow Changes**
   - Test in your fork first
   - Request security review for permission changes
   - Never hardcode secrets
   - Use verified GitHub Actions

2. **Code Changes**
   - Run ShellCheck locally
   - Validate YAML syntax
   - Test security-sensitive changes
   - Update SECURITY.md if needed

3. **Dependency Updates**
   - Review Dependabot PRs
   - Test breaking changes
   - Monitor security advisories
   - Update pinned versions

### For Maintainers

1. **Dependency Management**
   - Review and merge Dependabot PRs weekly
   - Apply security patches within 48 hours
   - Monitor GitHub Security tab
   - Keep action versions current

2. **Security Monitoring**
   - Review Trivy scan results
   - Check SBOM for vulnerabilities
   - Monitor build provenance
   - Audit workflow permissions

3. **Incident Response**
   - Follow SECURITY.md procedures
   - Document security fixes in CHANGELOG
   - Notify users of critical vulnerabilities
   - Update security documentation

## Verification

### Verify Build Provenance

```bash
# Install gh CLI and verify-provenance extension
gh attestation verify \
  oci://ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest \
  --owner Oichkatzelesfrettschen
```

### Verify SBOM

```bash
# Download SBOM from GitHub
gh attestation download \
  oci://ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest \
  --owner Oichkatzelesfrettschen

# Verify SBOM attestation
gh attestation verify \
  oci://ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest \
  --owner Oichkatzelesfrettschen \
  --signer-repo Oichkatzelesfrettschen/gnu-hurd-docker
```

### Scan Container Image

```bash
# Scan with Trivy
trivy image ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest

# View SBOM
docker sbom ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest
```

## Security Roadmap

### Completed ✅
- [x] Explicit workflow permissions
- [x] Dependabot configuration
- [x] Build provenance attestation
- [x] SBOM generation and attestation
- [x] Trivy vulnerability scanning
- [x] Security documentation updates

### Future Enhancements

#### Short-term (1-3 months)
- [ ] SHA pinning for all GitHub Actions
- [ ] Additional security badges in README
- [ ] Automated security patch backporting
- [ ] Enhanced SBOM vulnerability tracking

#### Long-term (3-6 months)
- [ ] Sigstore Cosign signatures
- [ ] SLSA Level 3 compliance
- [ ] Container image signing
- [ ] Advanced threat detection

## Compliance

### Standards Supported

- **SLSA Level 2**: Build provenance and SBOM attestation
- **NTIA SBOM Minimum Elements**: Complete SPDX SBOM
- **Executive Order 14028**: Software supply chain security
- **CIS Docker Benchmark**: Dockerfile security best practices

### Audit Trail

All security-related actions are logged:
- Workflow runs: GitHub Actions logs
- Security scans: GitHub Security tab
- Dependency updates: Dependabot PRs
- Attestations: Container registry

## Resources

### Documentation
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides)
- [Supply Chain Security](https://slsa.dev/)
- [SBOM Guidance](https://www.ntia.gov/sbom)
- [Container Security](https://www.nist.gov/publications/application-container-security-guide)

### Tools
- [Trivy](https://aquasecurity.github.io/trivy/)
- [Syft](https://github.com/anchore/syft)
- [Cosign](https://github.com/sigstore/cosign)
- [GitHub CLI](https://cli.github.com/)

---

**Last Updated:** 2025-11-17
**Maintained by:** GNU/Hurd Docker Team
**Review Cycle:** Quarterly
