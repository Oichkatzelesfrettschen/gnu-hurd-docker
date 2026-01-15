# GNU/Hurd Docker Documentation Index

> **Status**: Canonical documentation index (see git history for updates)

## Welcome

This documentation provides comprehensive guidance for running GNU/Hurd in Docker containers using QEMU virtualization. Whether you're a developer, researcher, or enthusiast, you'll find the resources you need to work with this unique operating system.

---

## Quick Start Path

New to GNU/Hurd Docker? Follow this path:

1. **[Requirements](01-GETTING-STARTED/REQUIREMENTS.md)** - Check system prerequisites
2. **[Installation](01-GETTING-STARTED/INSTALLATION.md)** - Set up your environment
3. **[Quick Start](01-GETTING-STARTED/QUICKSTART.md)** - Get running in minutes
4. **[First Steps](01-GETTING-STARTED/first-steps.md)** - Essential operations

---

## How to Use This Documentation

### For Different Roles

- **👨‍💻 Developers**: Start with [Architecture](02-ARCHITECTURE/) → [Configuration](03-CONFIGURATION/) → [CI/CD](05-CI-CD/)
- **Researchers**: Focus on [Research & Lessons](07-RESEARCH-AND-LESSONS/) → [Architecture](02-ARCHITECTURE/)
- **Operations**: Priority on [Operation](04-OPERATION/) → [Troubleshooting](06-TROUBLESHOOTING/)
- **Learners**: Begin with [Getting Started](01-GETTING-STARTED/) → [Reference](08-REFERENCE/)

### Navigation Tips

- Each section (01-08) is self-contained with its own README
- Documents are cross-linked where relevant
- Use the Quick Reference section below for common tasks
- Historical content is preserved in [archive/](archive/)

---

## Complete Documentation Structure

### 01-GETTING-STARTED
*Everything you need to begin your GNU/Hurd journey*

- **[README](01-GETTING-STARTED/README.md)** - Section overview
- **[installation.md](01-GETTING-STARTED/INSTALLATION.md)** - Complete setup guide
- **[quickstart.md](01-GETTING-STARTED/QUICKSTART.md)** - 5-minute getting started
- **[requirements.md](01-GETTING-STARTED/REQUIREMENTS.md)** - System prerequisites
- **[first-steps.md](01-GETTING-STARTED/first-steps.md)** - Initial operations
- **[docker-compose-basics.md](01-GETTING-STARTED/docker-compose-basics.md)** - Container orchestration

### 02-ARCHITECTURE
*System design and technical foundations*

- **[README](02-ARCHITECTURE/README.md)** - Architecture overview
- **[system-overview.md](02-ARCHITECTURE/OVERVIEW.md)** - Complete system design
- **[qemu-configuration.md](02-ARCHITECTURE/QEMU-CONFIGURATION.md)** - Virtualization layer
- **[control-plane.md](02-ARCHITECTURE/CONTROL-PLANE.md)** - Management infrastructure
- **[filesystem-layout.md](02-ARCHITECTURE/filesystem-layout.md)** - Storage organization
- **[network-architecture.md](02-ARCHITECTURE/network-architecture.md)** - Networking design

### 03-CONFIGURATION
*Customization and setup options*

- **[README](03-CONFIGURATION/README.md)** - Configuration guide
- **[user-setup.md](03-CONFIGURATION/USER-CONFIGURATION.md)** - User management
- **[port-forwarding.md](03-CONFIGURATION/PORT-FORWARDING.md)** - Network configuration
- **[custom-features.md](03-CONFIGURATION/CUSTOM-FEATURES.md)** - Advanced customization
- **[environment-variables.md](03-CONFIGURATION/environment-variables.md)** - Runtime settings
- **[mcp-servers.md](03-CONFIGURATION/mcp-servers.md)** - MCP server setup

### 04-OPERATION
*Day-to-day operations and management*

- **[README](04-OPERATION/README.md)** - Operations overview
- **[deployment.md](04-OPERATION/deployment/DEPLOYMENT.md)** - Production deployment
- **[monitoring.md](04-OPERATION/MONITORING.md)** - System monitoring
- **[testing.md](04-OPERATION/testing.md)** - Test procedures
- **[interactive-access.md](04-OPERATION/INTERACTIVE-ACCESS.md)** - Shell access
- **[backup-restore.md](04-OPERATION/backup-restore.md)** - Data management
- **[performance-tuning.md](04-OPERATION/performance-tuning.md)** - Optimization

### 05-CI-CD
*Automation and continuous integration*

- **[README](05-CI-CD/README.md)** - CI/CD overview
- **[workflows.md](05-CI-CD/WORKFLOWS.md)** - GitHub Actions
- **[docker-compose-guide.md](05-CI-CD/DOCKER-COMPOSE-GUIDE.md)** - Container orchestration
- **[image-building.md](05-CI-CD/image-building.md)** - Custom images
- **[release-process.md](05-CI-CD/release-process.md)** - Release management
- **[testing-automation.md](05-CI-CD/testing-automation.md)** - Automated testing

### 06-TROUBLESHOOTING
*Problem solving and issue resolution*

- **[README](06-TROUBLESHOOTING/README.md)** - Troubleshooting guide
- **[common-issues.md](06-TROUBLESHOOTING/COMMON-ISSUES.md)** - Frequent problems
- **[kernel-fixes.md](06-TROUBLESHOOTING/kernel-fixes.md)** - Kernel issues
- **[ssh-problems.md](06-TROUBLESHOOTING/SSH-ISSUES.md)** - SSH connectivity
- **[filesystem-issues.md](06-TROUBLESHOOTING/FSCK-ERRORS.md)** - Storage problems
- **[network-debugging.md](06-TROUBLESHOOTING/network-debugging.md)** - Network issues
- **[performance-issues.md](06-TROUBLESHOOTING/performance-issues.md)** - Speed problems

### 07-RESEARCH-AND-LESSONS
*Insights, findings, and deep dives*

- **[README](07-RESEARCH-AND-LESSONS/README.md)** - Research overview
- **[findings.md](07-RESEARCH-AND-LESSONS/FINDINGS.md)** - Key discoveries
- **[testing-reports.md](07-RESEARCH-AND-LESSONS/testing-reports.md)** - Test results
- **[implementation-notes.md](07-RESEARCH-AND-LESSONS/implementation-notes.md)** - Technical notes
- **[mach-variants-research.md](07-RESEARCH-AND-LESSONS/mach-variants-research.md)** - Mach kernel analysis
- **[performance-analysis.md](07-RESEARCH-AND-LESSONS/performance-analysis.md)** - Benchmarks
- **[security-considerations.md](07-RESEARCH-AND-LESSONS/security-considerations.md)** - Security analysis

### 08-REFERENCE
*Quick references and technical guides*

- **[README](08-REFERENCE/README.md)** - Reference overview
- **[quick-reference.md](08-REFERENCE/QUICK-REFERENCE.md)** - Command cheatsheet
- **[checklists.md](08-REFERENCE/checklists/X86_64-VALIDATION.md)** - Operational checklists
- **[maps.md](08-REFERENCE/maps.md)** - System maps
- **[guidelines.md](08-REFERENCE/guidelines.md)** - Best practices
- **[scripts.md](08-REFERENCE/SCRIPTS.md)** - Utility scripts
- **[api-reference.md](08-REFERENCE/api-reference.md)** - API documentation
- **[glossary.md](08-REFERENCE/glossary.md)** - Term definitions

---

## Common Tasks Quick Reference

### Essential Operations

| Task | Documentation | Quick Command |
|------|--------------|---------------|
| Start GNU/Hurd (dev bind mode) | [quickstart.md](01-GETTING-STARTED/QUICKSTART.md) | `./scripts/docker-orchestration.sh up` |
| Start GNU/Hurd (portable volume mode) | [usage-modes.md](01-GETTING-STARTED/USAGE-MODES.md) | `AUTO_DOWNLOAD_IMAGE=1 ./scripts/docker-orchestration.sh up-volume` |
| Connect via SSH | [interactive-access.md](04-OPERATION/INTERACTIVE-ACCESS.md) | `ssh root@localhost -p 2222` |
| Build container image | [docker-compose-guide.md](05-CI-CD/DOCKER-COMPOSE-GUIDE.md) | `docker compose build` |
| Monitor container logs | [monitoring.md](04-OPERATION/MONITORING.md) | `docker compose logs -f gnu-hurd-dev` |
| Debug issues | [common-issues.md](06-TROUBLESHOOTING/COMMON-ISSUES.md) | `./scripts/docker-orchestration.sh logs` |

### Advanced Tasks

| Task | Documentation | Notes |
|------|--------------|-------|
| Performance tuning | [performance-tuning.md](04-OPERATION/performance-tuning.md) | CPU/Memory optimization |
| Security hardening | [security-considerations.md](07-RESEARCH-AND-LESSONS/security-considerations.md) | Production recommendations |
| CI/CD setup | [workflows.md](05-CI-CD/WORKFLOWS.md) | GitHub Actions integration |
| MCP server config | [mcp-servers.md](03-CONFIGURATION/mcp-servers.md) | Advanced automation |
| Kernel research | [mach-variants-research.md](07-RESEARCH-AND-LESSONS/mach-variants-research.md) | Deep technical analysis |

---

## Documentation Metadata

### Directory Purpose

| Directory | Purpose | Status |
|-----------|---------|--------|
| `01-08 sections` | Main documentation | Active |
| `archive/` | Historical content | Preserved |
| `assets/` | Templates & scripts | Support |
| `audits/` | Audit outputs and reports | Active |

---

## Additional Resources

### Internal Links
- **[Archive](archive/)** - Historical documentation and versions
- **[Assets](assets/)** - Templates and migration tools
- **[Project Root](../)** - Main project directory

### External Resources
- [GNU/Hurd Official Site](https://www.gnu.org/software/hurd/)
- [QEMU Documentation](https://www.qemu.org/documentation/)
- [Docker Documentation](https://docs.docker.com/)
- [Project GitHub Repository](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker)

---

## Contributing
To contribute to this documentation:
1. Follow the existing structure (01-08 sections)
2. Update the appropriate section's README
3. Cross-link related content
4. Update this INDEX when adding major sections

---

## Next Steps

Based on your role and needs:

1. **New Users** → Start with [Getting Started](01-GETTING-STARTED/)
2. **Developers** → Dive into [Architecture](02-ARCHITECTURE/) and [Configuration](03-CONFIGURATION/)
3. **Operations** → Focus on [Operation](04-OPERATION/) and [Troubleshooting](06-TROUBLESHOOTING/)
4. **Researchers** → Explore [Research & Lessons](07-RESEARCH-AND-LESSONS/)

---

*This documentation is actively maintained and improved based on user feedback and project evolution.*
