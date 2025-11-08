# Contributing to GNU/Hurd Docker

Thank you for your interest in contributing to the GNU/Hurd x86_64 Docker environment! This document provides guidelines for contributing to this project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Commit Message Guidelines](#commit-message-guidelines)
- [Pull Request Process](#pull-request-process)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Enhancements](#suggesting-enhancements)

## Code of Conduct

This project adheres to a Code of Conduct that all contributors are expected to follow. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing.

## How Can I Contribute?

### Reporting Bugs

Found a bug? Help us fix it!

1. **Check existing issues** - Search [GitHub Issues](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/issues) to see if it's already reported
2. **Create a new issue** - Use the bug report template
3. **Provide details** - Include:
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Environment details (OS, Docker version, QEMU version)
   - Logs and screenshots

### Suggesting Enhancements

Have an idea for improvement?

1. **Check existing feature requests** - Search issues labeled `enhancement`
2. **Create a feature request** - Use the feature request template
3. **Explain the use case** - Describe:
   - Problem you're solving
   - Proposed solution
   - Alternative solutions considered
   - Impact on existing functionality

### Contributing Code

We welcome code contributions! Areas where we need help:

- **Documentation** - Improve clarity, fix typos, add examples
- **Bug fixes** - Address reported issues
- **Features** - Implement requested enhancements
- **Testing** - Improve test coverage
- **Performance** - Optimize boot time, resource usage
- **Compatibility** - Test on different host systems

## Development Setup

### Prerequisites

- Linux host (Ubuntu 20.04+, Arch, Debian)
- Docker 24.0+
- Docker Compose v2
- Git
- KVM support (optional but recommended)

### Fork and Clone

```bash
# Fork the repository on GitHub
# Then clone your fork
git clone https://github.com/YOUR_USERNAME/gnu-hurd-docker.git
cd gnu-hurd-docker

# Add upstream remote
git remote add upstream https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker.git
```

### Setup Development Environment

```bash
# Download Hurd image
./scripts/setup-hurd-amd64.sh

# Build Docker image
docker-compose build

# Start container
docker-compose up -d

# Check logs
docker-compose logs -f hurd-x86_64
```

### Running Tests

```bash
# Test basic functionality
./scripts/test-hurd-system.sh

# Test SSH connectivity
ssh -p 2222 root@localhost uname -a

# Test snapshot management
./scripts/manage-snapshots.sh create test-snapshot
./scripts/manage-snapshots.sh list
./scripts/manage-snapshots.sh delete test-snapshot
```

## Coding Standards

### Shell Scripts

All shell scripts must follow these standards:

```bash
#!/bin/bash
# Script purpose and description
# Usage: script.sh [options]

set -e  # Exit on error
set -u  # Error on undefined variables
set -o pipefail  # Error on pipe failures

# Use functions for modularity
main() {
    # Main logic here
}

# Call main
main "$@"
```

**Quality Gates**:
- Pass `shellcheck -S error script.sh`
- Use 2-space indentation
- Quote all variables: `"$variable"`
- Use `[[ ]]` for bash conditionals
- Prefer `$(command)` over backticks
- Add comprehensive comments

### Dockerfile

**Best Practices**:
- Use multi-stage builds where applicable
- Minimize layers (combine RUN commands)
- Run as non-root user
- Pin base image versions (use digest or specific tag)
- Clean up package lists (`rm -rf /var/lib/apt/lists/*`)
- Use `.dockerignore` to exclude unnecessary files

**Example**:
```dockerfile
FROM ubuntu:24.04

# Install packages (single layer)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        package1 \
        package2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Run as non-root
USER hurd
```

### Docker Compose

**Requirements**:
- No `version:` field (deprecated in Compose v2)
- Use Compose v2 resource limits (`mem_limit`, `cpus`)
- Add security options (`security_opt`, `cap_drop`)
- Use Docker secrets for credentials
- Include health checks
- Configure logging (max-size, max-file)

### Documentation

**Markdown Standards**:
- Use ATX-style headers (`# Header`)
- Include table of contents for long documents
- Use fenced code blocks with language hints
- Add navigation links between related docs
- Keep lines under 100 characters
- Use descriptive link text (not "click here")

**Quality Gates**:
- Pass `markdown-link-check`
- Generate TOC with `markdown-toc`
- Follow existing structure in `docs/` directory

## Testing Guidelines

### Manual Testing Checklist

Before submitting a pull request, verify:

- [ ] Docker image builds successfully
- [ ] Container starts without errors
- [ ] QEMU boots Hurd guest (2-5 minutes)
- [ ] SSH access works (`ssh -p 2222 root@localhost`)
- [ ] Serial console accessible (`telnet localhost 5555`)
- [ ] Health check passes (`docker-compose ps`)
- [ ] Clean shutdown works (`shutdown -h now`)
- [ ] Snapshots create/restore successfully
- [ ] Documentation updated (if applicable)
- [ ] No regression in existing functionality

### Automated Testing

```bash
# Run test suite
./scripts/test-hurd-system.sh

# Expected output:
# ✓ QEMU process running
# ✓ SSH accessible
# ✓ Disk space sufficient
# ✓ Network connectivity
```

### Performance Testing

Measure and document performance impact:

```bash
# Boot time (should be < 5 minutes with KVM)
time docker-compose up -d

# Monitor resources
./scripts/monitor-qemu.sh
```

## Commit Message Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style (formatting, no logic change)
- `refactor`: Code refactoring
- `perf`: Performance improvement
- `test`: Add or update tests
- `chore`: Maintenance (dependencies, build)
- `ci`: CI/CD changes

### Examples

```
feat(docker): add non-root user for security

- Create hurd user (UID 1000)
- Update volume ownership
- Switch to non-root before ENTRYPOINT

Closes #42
```

```
fix(scripts): correct binary name to qemu-system-x86_64

The Debian package provides qemu-system-x86_64 (with underscore),
not qemu-system-x86-64 (with hyphens).

Fixes #38
```

```
docs(reference): consolidate script documentation

- Create SCRIPTS.md with all 21 scripts documented
- Add categories: Setup, Installation, Configuration, etc.
- Include usage examples and disk space requirements

Related to documentation consolidation effort.
```

## Pull Request Process

### 1. Create Feature Branch

```bash
# Update main branch
git checkout main
git pull upstream main

# Create feature branch
git checkout -b feature/your-feature-name
# Or: fix/bug-description
# Or: docs/documentation-update
```

### 2. Make Changes

- Write code following coding standards
- Add tests if applicable
- Update documentation
- Run quality checks locally

### 3. Quality Checks

```bash
# Shellcheck (scripts)
shellcheck -S error scripts/*.sh

# Docker Compose syntax
docker-compose config

# Build test
docker-compose build --no-cache

# Documentation links
markdown-link-check README.md docs/**/*.md
```

### 4. Commit and Push

```bash
# Stage changes
git add .

# Commit with conventional message
git commit -m "feat(scope): description"

# Push to your fork
git push origin feature/your-feature-name
```

### 5. Open Pull Request

1. Go to [GitHub repository](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker)
2. Click "New Pull Request"
3. Select your branch
4. Fill out PR template completely
5. Link related issues (`Closes #123`)

### 6. Code Review

- Respond to reviewer feedback
- Make requested changes
- Push updates (GitHub will update PR automatically)
- Request re-review when ready

### 7. Merge

Once approved:
- Maintainer will merge PR
- Your branch will be deleted automatically
- Celebrate! 🎉

## Branch Naming Conventions

- `feature/feature-name` - New features
- `fix/bug-description` - Bug fixes
- `docs/topic` - Documentation updates
- `refactor/component` - Code refactoring
- `perf/optimization-target` - Performance improvements

## Style Guide Summary

### Shell Scripts

```bash
#!/bin/bash
set -euo pipefail

# Constants in UPPERCASE
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions in lowercase_with_underscores
check_prerequisites() {
    command -v docker >/dev/null || { echo "Docker required"; exit 1; }
}

# Main logic
main() {
    check_prerequisites
    echo "Script running..."
}

main "$@"
```

### Docker

- Base image: `ubuntu:24.04` (stable LTS)
- Non-root user: `USER hurd`
- Clean layers: combine `RUN` commands
- Security: `no-new-privileges`, `cap_drop`

### Documentation

- Headers: ATX style (`# Header`)
- Code blocks: Use language tags
- Links: Descriptive text
- Line length: Max 100 characters

## Getting Help

- **Documentation**: Check [docs/](docs/) directory
- **Issues**: Search existing [GitHub Issues](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/issues)
- **Discussions**: Use [GitHub Discussions](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/discussions)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors are recognized in:
- GitHub contributor graph
- Release notes (for significant contributions)
- Project README (for major features)

Thank you for contributing to GNU/Hurd Docker! 🚀
