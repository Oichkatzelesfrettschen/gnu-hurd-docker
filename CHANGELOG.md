# Changelog

All notable changes to the GNU/Hurd Docker project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed - 2025-11-14 (Critical Workflow Fixes)
- **CRITICAL**: Replaced deprecated `actions/create-release@v1` with `softprops/action-gh-release@v2`
  - Fixed `release.yml` workflow using archived/deprecated action
  - Added explicit `permissions: contents: write` for release creation
  - Added `fetch-depth: 0` for proper changelog generation
  - Updated to modern `github.ref_name` syntax
- **CRITICAL**: Upgraded `softprops/action-gh-release` from v1 to v2 in `release-artifacts.yml`
  - Ensures consistency across all release workflows
  - Provides latest security updates and features
- Added comprehensive workflow failure analysis documentation

### Fixed - 2025-11-14 (Workflow Fixes)
- **CRITICAL**: Fixed workflow file path references after harmonization
  - Updated `quality-and-security.yml` to reference correct documentation paths
  - Fixed Python linting to find files in `scripts/utils/` directory
  - Added resilience to `comprehensive-validation` job with `if: always()`
  - Fixed artifact path inconsistencies in `build-x86_64.yml`
- Enhanced error handling in workflows with existence checks and clear messages
- Improved workflow documentation with troubleshooting report

### Added - 2025-11-13 (Repository Harmonization)
- Created standard directories: `build/`, `logs/`, `src/` with README documentation
- Created `docs/audits/` subdirectory for audit reports and metrics
- Created `docs/reports/` subdirectory for project reports and summaries
- Created `scripts/utils/` subdirectory for utility scripts and tools
- Added comprehensive Repository Harmonization Report
- Merged main branch updates including security validation script

### Changed - 2025-11-13 (Repository Harmonization)
- **MAJOR**: Reorganized repository structure for better modularity
- Moved 14 documentation files from `scripts/` and root to `docs/` (audits/, reports/, 08-REFERENCE/)
- Moved 6 utility scripts from `docs/` to `scripts/utils/`
- Moved 6 project reports from root to `docs/reports/`:
  - CHATGPT-ANALYSIS-AND-ROADMAP.md
  - TRAP-HANDLERS-SUMMARY.md
  - QEMU-LAUNCHER-TEST-REPORT.md
  - V2.0.0-RELEASE-SUMMARY.md
  - IMPLEMENTATION-SUMMARY.md (from main merge)
  - X86_64-MIGRATION-FINAL-REPORT.md (from main merge)
- Updated `.gitignore` to properly exclude build/, logs/, src/ while tracking README files
- Fixed yamllint warning in validate.yml workflow

### Improved - 2025-11-13 (Repository Harmonization)
- Documentation: Clear separation between active docs and reports
- Scripts: Better organization with lib/ and utils/ subdirectories
- Build: Proper artifact management with gitignore rules
- Quality: All 30+ scripts pass ShellCheck validation
- Validation: All 9 GitHub Actions workflows pass yamllint
- All section README files maintain consistent format
- REQUIREMENTS.md verified as comprehensive and production-ready
- Integrated changes from main branch (security validation, script updates)

## [2.0.0] - 2025-11-08

### Added

#### Dual-Mode Usage Support
- **Standalone QEMU Launcher** (`scripts/run-hurd-qemu.sh`)
  - Run GNU/Hurd directly with QEMU without Docker
  - Automatic KVM detection with graceful TCG fallback
  - Comprehensive CLI arguments for configuration
  - Environment variable support for automation
  - VNC display support for visual boot monitoring
  - Serial console and QEMU monitor access
  - Auto-detection of QCOW2 image location
  - Color-coded logging with informative messages
  - Complete help text with usage examples
  - ShellCheck validated for quality assurance

- **Test Suite** (`scripts/test-run-hurd-qemu.sh`)
  - Automated validation of standalone launcher
  - Comprehensive test coverage for all features
  - Verification of prerequisites and dependencies
  - Integration with existing test infrastructure

#### Documentation
- **Usage Modes Guide** (`docs/01-GETTING-STARTED/USAGE-MODES.md`)
  - Comprehensive decision guide for choosing Docker vs standalone QEMU
  - Detailed comparison table with 13 criteria
  - Text-based decision flowchart
  - Use case scenarios for each mode
  - Performance considerations
  - Migration instructions between modes
  - Recommendations by user type

- **Standalone QEMU Guide** (`docs/01-GETTING-STARTED/STANDALONE-QEMU.md`)
  - Complete setup instructions for standalone usage
  - Prerequisites for multiple Linux distributions
  - KVM setup and verification
  - Configuration options documentation
  - Advanced configuration examples
  - Common workflows
  - Comprehensive troubleshooting section

- **Test Report** (`QEMU-LAUNCHER-TEST-REPORT.md`)
  - Detailed validation results for standalone launcher
  - Performance metrics and benchmarks
  - Screenshot analysis of boot process
  - Security validation results
  - Recommendations for release

- **Analysis and Roadmap** (`CHATGPT-ANALYSIS-AND-ROADMAP.md`)
  - Comprehensive analysis of project state
  - Mapping of ChatGPT recommendations to implementation
  - Detailed implementation roadmap
  - Success metrics and completion criteria

#### Workflow Updates
- **Release Artifacts** (`.github/workflows/release-artifacts.yml`)
  - Updated scripts README to highlight standalone QEMU launcher
  - Added dual-mode usage examples
  - Improved documentation of available scripts
  - Clear separation of Docker vs standalone paths

#### README Enhancements
- **Dual-Mode Quick Start**
  - Path A: Docker-based (recommended for most users)
  - Path B: Standalone QEMU (advanced users)
  - Clear "Best for" guidance for each path
  - Link to usage modes decision guide

- **Documentation Links**
  - Added Usage Modes guide to Quick Links
  - Added Standalone QEMU Guide to Quick Links
  - Improved discoverability of all documentation

### Changed

#### Docker Compose
- Updated examples to use `docker compose` (v2) instead of `docker-compose` (v1)
  - README quick start
  - Documentation examples
  - Workflow configurations

#### Documentation Organization
- Enhanced Getting Started section with four key guides:
  - Usage Modes (NEW)
  - Installation Guide (updated)
  - Quickstart (existing)
  - Standalone QEMU (NEW)

### Fixed

- Corrected Docker Compose v2 syntax throughout documentation
- Improved consistency in script documentation
- Fixed cross-references in documentation

### Performance

- **KVM Acceleration**
  - Verified working correctly in standalone launcher
  - ~72% CPU usage indicates efficient acceleration
  - 30-60 second boot time with KVM (vs 3-5 minutes with TCG)

- **Resource Usage**
  - Minimal overhead: <1 second startup time
  - 431 MB RSS for QEMU process (with 2GB VM)
  - Efficient resource allocation algorithms

### Security

- **Script Validation**
  - All scripts pass ShellCheck with no warnings
  - No hardcoded secrets or credentials
  - Proper input validation and error handling
  - No arbitrary file access vulnerabilities

### Testing

- **Comprehensive Validation**
  - Live VM boot testing with VNC monitoring
  - Screenshot analysis at multiple boot stages
  - Port availability verification (SSH, Serial, VNC, Monitor)
  - KVM detection and acceleration verification
  - Argument parsing and error handling tests

### Documentation

- **Total Documentation**: 26+ markdown files (2.5 MB)
- **New Guides**: 3 comprehensive new documents
- **Test Reports**: 1 detailed validation report
- **Analysis**: 1 strategic roadmap document

---

## Release Statistics

### Lines of Code
- **Standalone Launcher**: 350+ lines (scripts/run-hurd-qemu.sh)
- **Test Suite**: 150+ lines (scripts/test-run-hurd-qemu.sh)
- **Documentation**: 800+ lines across new guides

### Features
- **2 Major Features**: Standalone QEMU launcher + Dual-mode documentation
- **4 New Scripts**: Launcher, test suite, and utilities
- **3 New Documentation Files**: Usage modes, standalone guide, test report
- **1 Workflow Update**: Release artifacts workflow

### Test Coverage
- ✅ 8/8 script functionality tests passed
- ✅ 4/4 QEMU VM launch tests passed
- ✅ 4/4 network and console port tests passed
- ✅ 4/4 boot process verification tests passed
- ✅ 5/5 security validation checks passed

---

## Migration Guide

### From v1.x to v2.0.0

#### For Docker Users
No breaking changes. Continue using:
```bash
docker compose up -d
```

Note: `docker-compose` (v1) is deprecated but still works. Migrate to `docker compose` (v2) when convenient.

#### New Standalone QEMU Option
If you want native performance without Docker:
```bash
./scripts/run-hurd-qemu.sh
```

See [docs/01-GETTING-STARTED/USAGE-MODES.md](docs/01-GETTING-STARTED/USAGE-MODES.md) for decision guidance.

---

## Known Issues

### Expected Behavior (Not Bugs)

1. **First Boot Time**: 2-5 minutes for package configuration (normal for Debian)
2. **SSH Password Auth**: Requires provisioning via `scripts/install-ssh-hurd.sh`
3. **Base Image**: Not pre-provisioned (intentional - clean base state)

### Workarounds

For SSH access on base image:
```bash
# After first boot, run provisioning:
./scripts/full-automated-setup.sh
```

---

## Contributors

This release was made possible by:
- ChatGPT analysis and recommendations
- Claude Code (Sonnet 4.5) - implementation and testing
- Community feedback and requirements

---

## Links

- **Repository**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker
- **Documentation**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/tree/main/docs
- **Issues**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/issues
- **Releases**: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/releases

---

## What's Next (v2.1.0 Planned)

### Potential Features
- Pre-provisioned image variant with SSH enabled
- Performance tuning guide with benchmarks
- 9P filesystem sharing examples
- VNC/Graphics improvements
- Multi-platform support (macOS, WSL2)
- Automated health checks for VM readiness

### Community Requests
Submit feature requests at: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/issues

---

[Unreleased]: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/releases/tag/v2.0.0
