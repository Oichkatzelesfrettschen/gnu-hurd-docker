# Security Policy

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          | Architecture | Status |
| ------- | ------------------ | ------------ | ------ |
| 2.x     | :white_check_mark: | x86_64 only  | Active |
| 1.x     | :x:                | i386/x86_64  | Deprecated (2025-11-07) |

**Note**: Version 1.x (dual-architecture i386/x86_64) is no longer supported. Please migrate to version 2.x (pure x86_64).

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please report it responsibly.

### Reporting Process

**DO NOT** open a public GitHub issue for security vulnerabilities.

Instead:

1. **Email**: Send details to [INSERT SECURITY EMAIL]
2. **Subject**: `[SECURITY] Brief description`
3. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if known)
   - Your contact information

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 5 business days
- **Status Update**: Every 7 days until resolved
- **Fix**: Target 30 days for critical vulnerabilities

### Disclosure Policy

- **Coordinated Disclosure**: We follow responsible disclosure practices
- **Public Disclosure**: After fix is released and users have had time to upgrade (typically 14 days)
- **Credit**: Security researchers will be credited in release notes (unless they prefer anonymity)

## Security Considerations

### Development Environment Security

This project provides a **development environment** for GNU/Hurd. Default configurations prioritize convenience over security.

**Default credentials** are used for ease of access:
- Root password: `root`
- Agents password: `agents`

**⚠️ WARNING**: These defaults are **INSECURE** and must be changed for any production or public-facing deployment.

### Production Hardening Checklist

If deploying this environment beyond local development, you **MUST**:

#### 1. Credentials
- [ ] Change root password: `passwd root` (inside guest)
- [ ] Change agents password: `passwd agents` (inside guest)
- [ ] Use Docker secrets (not hardcoded passwords)
- [ ] Rotate credentials every 90 days

#### 2. SSH Configuration
- [ ] Disable password authentication (use SSH keys only)
  ```bash
  # Inside guest
  sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  systemctl restart ssh
  ```
- [ ] Disable root SSH login (if agents account is sufficient)
  ```bash
  sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
  ```
- [ ] Use SSH key-based authentication:
  ```bash
  ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2222 root@localhost
  ```

#### 3. Network Security
- [ ] Bind ports to localhost only (not `0.0.0.0`):
  ```yaml
  ports:
    - "127.0.0.1:2222:2222"  # SSH localhost-only
    - "127.0.0.1:5555:5555"  # Serial console localhost-only
  ```
- [ ] Use firewall rules to restrict access
- [ ] Consider VPN or SSH tunnel for remote access
- [ ] Disable unused ports (VNC, QEMU monitor)

#### 4. Container Security
- [ ] Run as non-root user (already configured in Dockerfile)
- [ ] Use Docker secrets for credentials (configured in docker-compose.yml)
- [ ] Enable security options:
  - `security_opt: [no-new-privileges:true]` ✅ (configured)
  - `cap_drop: [ALL]` ✅ (configured)
  - `cap_add: [NET_ADMIN, SYS_ADMIN]` ✅ (configured)
- [ ] Set resource limits to prevent DoS
- [ ] Use read-only root filesystem where possible
- [ ] Enable Docker Content Trust (image signing)

#### 5. Host Security
- [ ] Keep Docker and QEMU up to date
- [ ] Use KVM with SELinux/AppArmor policies
- [ ] Restrict access to `/dev/kvm` device
- [ ] Monitor container logs for suspicious activity
- [ ] Use vulnerability scanning (Trivy, Clair)

#### 6. Guest Security
- [ ] Update Hurd packages regularly: `apt-get update && apt-get dist-upgrade`
- [ ] Enable automatic security updates (if stable enough)
- [ ] Disable unused services
- [ ] Configure firewall inside guest (if Hurd supports it)
- [ ] Monitor system logs for intrusions

### Known Security Limitations

#### 1. QEMU Escape Risks

QEMU provides virtualization isolation, but vulnerabilities in QEMU can lead to container escape:

- **Mitigation**: Keep QEMU updated
- **Mitigation**: Use KVM mode (reduces attack surface vs TCG)
- **Mitigation**: Run Docker with least privilege
- **Monitoring**: Watch for QEMU CVEs

#### 2. KVM Device Access

Container has access to `/dev/kvm` for acceleration:

- **Risk**: Potential for privilege escalation if KVM has vulnerabilities
- **Mitigation**: Use `security_opt` and `cap_drop` to limit capabilities
- **Mitigation**: Keep host kernel updated
- **Alternative**: Run in TCG mode (slower but no KVM device needed)

#### 3. Serial Console Exposure

Serial console (port 5555) provides unauthenticated root access:

- **Risk**: Anyone with network access can control the VM
- **Mitigation**: Bind to localhost only (`127.0.0.1:5555:5555`)
- **Mitigation**: Use SSH instead of serial console for remote access
- **Mitigation**: Disable serial console in production (`SERIAL_PORT=""`)

#### 4. QEMU Monitor Exposure

QEMU monitor (port 9999) allows full VM control:

- **Risk**: Pause/resume VM, access memory, modify state
- **Mitigation**: Bind to localhost only
- **Mitigation**: Disable monitor in production (`MONITOR_PORT=""`)
- **Mitigation**: Use authentication if monitor is needed

#### 5. Default Credentials

Development convenience vs security trade-off:

- **Risk**: Well-known passwords enable trivial unauthorized access
- **Mitigation**: Change passwords immediately after provisioning
- **Mitigation**: Use SSH keys (disable password auth)
- **Mitigation**: Use Docker secrets (not environment variables)

### Secure Configuration Examples

#### Localhost-Only Access (Recommended for Development)

```yaml
# docker-compose.yml
services:
  hurd-x86_64:
    ports:
      - "127.0.0.1:2222:2222"  # SSH
      - "127.0.0.1:5555:5555"  # Serial console
    secrets:
      - root_password
      - agents_password
```

#### Production Deployment (External Access Required)

```yaml
# docker-compose.yml
services:
  hurd-x86_64:
    ports:
      - "2222:2222"  # SSH only (serial console disabled)
    environment:
      SERIAL_PORT: ""      # Disable serial console
      MONITOR_PORT: ""     # Disable QEMU monitor
      ENABLE_VNC: 0        # Disable VNC
    secrets:
      - root_password
      - agents_password
```

With SSH hardening inside guest:
```bash
# Disable password auth, require SSH keys
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password

# Rate limiting
MaxAuthTries 3
MaxStartups 10:30:60
```

## Security Best Practices

### For Contributors

- **Never commit secrets** to version control (`.env`, `*.txt` in `secrets/`)
- **Review dependencies** for known vulnerabilities
- **Follow principle of least privilege** in code
- **Validate all inputs** (especially from environment variables)
- **Document security implications** of changes

### For Users

- **Change default passwords** immediately after setup
- **Update regularly** (Docker images, QEMU, Hurd packages)
- **Monitor logs** for suspicious activity
- **Use SSH keys** instead of passwords
- **Restrict network access** to only necessary ports
- **Backup important data** (snapshots, configuration)

## Vulnerability Disclosure History

| Date       | CVE            | Severity | Component | Status   |
|------------|----------------|----------|-----------|----------|
| 2025-11-07 | N/A            | N/A      | N/A       | No known vulnerabilities |

*This section will be updated as vulnerabilities are discovered and fixed.*

## Security Tools and Testing

### Recommended Security Tools

- **Docker Bench Security**: Audit Docker host security
  ```bash
  docker run --rm --net host --pid host --userns host --cap-add audit_control \
    -v /var/lib:/var/lib -v /var/run/docker.sock:/var/run/docker.sock \
    docker/docker-bench-security
  ```

- **Trivy**: Container vulnerability scanning
  ```bash
  trivy image ghcr.io/oichkatzelesfrettschen/gnu-hurd-x86_64:latest
  ```

- **Hadolint**: Dockerfile linter
  ```bash
  hadolint Dockerfile
  ```

### CI/CD Security Gates

Our CI/CD pipeline includes:
- Dockerfile linting (Hadolint)
- Vulnerability scanning (Trivy)
- Secret scanning (detect committed credentials)
- Docker Bench for Security (host audit)

## Acknowledgments

We thank the following security researchers for responsible disclosure:

*(No reports yet)*

## Contact

For security-related questions or concerns:
- **Email**: [INSERT SECURITY EMAIL]
- **PGP Key**: [INSERT PGP KEY FINGERPRINT] (for encrypted communication)

For general questions, use [GitHub Discussions](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/discussions).

## CI/CD and Workflow Security

### GitHub Actions Security

This project uses GitHub Actions for CI/CD automation with the following security measures:

#### 1. Dependency Management
- **Dependabot**: Automated dependency updates for GitHub Actions, Docker, Python, and npm
  - Weekly updates on Mondays at 09:00 UTC
  - Automatic security vulnerability alerts
  - Pull requests auto-assigned to maintainers

#### 2. Action Version Pinning
- All GitHub Actions use semantic versioning (e.g., `@v4`)
- Verified publishers for all third-party actions
- Regular updates through Dependabot

#### 3. Workflow Permissions
- **Least-privilege principle**: All workflows have explicit permissions
- **Read-only by default**: `contents: read` for most workflows
- **Write permissions**: Only where necessary (`packages: write`, `security-events: write`)
- **Token scope**: Minimal GITHUB_TOKEN permissions

#### 4. Security Scanning
- **Trivy**: Scans Docker images for vulnerabilities
  - Version: 0.28.0
  - Runs on: Push to main, PRs, weekly schedule
  - Reports uploaded to GitHub Security tab
- **ShellCheck**: All shell scripts validated with warnings as errors
- **Hadolint**: Dockerfile best practices validation

#### 5. Concurrency Control
- Duplicate workflow runs automatically cancelled
- Prevents resource exhaustion attacks
- Configured per workflow type (dev vs. release)

#### 6. Timeout Protection
- All jobs have timeout limits (10-180 minutes)
- Prevents infinite loops and hanging workflows
- Resource consumption safeguards

#### 7. Artifact Security
- Build provenance attestation enabled
- Artifacts retention limited to 7-30 days
- Access controlled through workflow permissions

### Security Policies in Workflows

```yaml
# Example: Minimal permissions
permissions:
  contents: read       # Read repository contents
  packages: write      # Push to GHCR (only when needed)
  security-events: write  # Upload security scan results
```

### Reporting Workflow Security Issues

If you discover security vulnerabilities in our CI/CD workflows:

1. **Scope**: Workflow security, secrets exposure, permission escalation
2. **Report**: Use the same process as general vulnerabilities (see above)
3. **Include**: Workflow file name, specific step, potential impact

### Best Practices for Contributors

When contributing workflow changes:

1. **Minimal Permissions**: Use least-privilege permissions
2. **No Secrets**: Never hardcode secrets in workflows
3. **Verify Actions**: Use actions from verified publishers
4. **Test in Forks**: Test workflow changes in your fork first
5. **Review Changes**: Request security review for workflow modifications

### Automated Security Updates

- **Dependabot PRs**: Reviewed and merged weekly
- **Security Patches**: Applied within 48 hours of availability
- **Breaking Changes**: Tested in feature branches before merging

## References

- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [QEMU Security Process](https://www.qemu.org/contribute/security-process/)
- [GNU/Hurd Security](https://www.gnu.org/software/hurd/community/weblogs/antrik/hurd-security.html)
- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
