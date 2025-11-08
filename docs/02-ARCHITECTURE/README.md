# Architecture Documentation

**Last Updated**: 2025-11-07
**Section**: 02-ARCHITECTURE
**Purpose**: System design and technical architecture

---

## Overview

This section explains the technical architecture of the GNU/Hurd x86_64 Docker environment, including system design, QEMU configuration, and control plane implementation.

**Audience**: Advanced users, developers, system architects

**Prerequisites**: Basic understanding of Docker, QEMU, and microkernel architecture

---

## Documents in This Section

### [SYSTEM-DESIGN.md](SYSTEM-DESIGN.md)
**High-level architecture and design decisions**

- Mach microkernel architecture
- Docker containerization strategy
- QEMU emulation layer
- Networking model (user-mode NAT)
- Storage architecture (QCOW2)
- Component interaction diagram

**When to use**: Understand overall system design, architectural decisions

---

### [QEMU-CONFIGURATION.md](QEMU-CONFIGURATION.md)
**Comprehensive QEMU configuration reference**

- CPU configuration (x86_64-specific)
- Memory allocation (4GB recommended)
- Storage backend (SATA/AHCI vs IDE)
- Network devices (e1000 NIC)
- Serial console setup
- KVM vs TCG acceleration
- Performance tuning

**When to use**: Configure QEMU parameters, optimize performance

---

### [CONTROL-PLANE.md](CONTROL-PLANE.md)
**Control plane implementation and automation**

- Docker container lifecycle
- QEMU process management
- Serial console automation (expect scripts)
- Health monitoring
- Graceful shutdown procedures
- Snapshot management

**When to use**: Implement automation, understand container orchestration

---

## Architecture Highlights

### Microkernel Design
- **Mach Microkernel**: GNU Mach provides process management, IPC, memory management
- **Hurd Servers**: User-space servers implement POSIX functionality
- **Separation of Concerns**: Kernel does minimal work, servers implement features

### Containerization Strategy
- **Docker**: Provides isolation, resource limits, easy deployment
- **QEMU Inside Container**: Full system emulation for x86_64 Hurd
- **Volume Mounts**: QCOW2 image persists across container restarts

### Performance Considerations
- **KVM Acceleration**: 80-90% native performance (when available)
- **TCG Fallback**: 10-20% native performance (software emulation)
- **Memory**: 4GB recommended for smooth operation
- **CPU**: 2 cores stable on x86_64

---

## Quick Navigation

**Getting Started**:
- [Installation](../01-GETTING-STARTED/INSTALLATION.md)
- [Quickstart](../01-GETTING-STARTED/QUICKSTART.md)

**Configuration**:
- [Port Forwarding](../03-CONFIGURATION/PORT-FORWARDING.md)
- [User Configuration](../03-CONFIGURATION/USER-CONFIGURATION.md)
- [Custom Features](../03-CONFIGURATION/CUSTOM-FEATURES.md)

**Operation**:
- [Interactive Access](../04-OPERATION/INTERACTIVE-ACCESS.md)
- [Snapshots](../04-OPERATION/SNAPSHOTS.md)
- [Monitoring](../04-OPERATION/MONITORING.md)

**Deep Dives**:
- [Research](../07-RESEARCH/) - Migration insights, lessons learned
- [CI/CD](../05-CI-CD/) - Automated workflows

---

## For System Designers

**Key Architectural Decisions**:
1. **x86_64-only** - Dropped i386 support (better stability, performance)
2. **SATA/AHCI storage** - Avoids IDE I/O errors on q35 machine type
3. **e1000 NIC** - Best Hurd compatibility
4. **pc machine type** - More stable than q35 for x86_64 Hurd
5. **User-mode NAT networking** - Simplifies setup, no bridge configuration

**Performance Trade-offs**:
- **KVM vs TCG**: 80-90% vs 10-20% native performance
- **QCOW2 compression**: Space savings vs I/O overhead
- **SMP**: 1-2 cores stable; more cores experimental

**Security Model**:
- **Container isolation**: Docker provides process isolation
- **Network isolation**: User-mode NAT (no host network bridge)
- **Volume isolation**: QCOW2 image separate from host filesystem

---

## For Developers

**Extending the Architecture**:
- [CONTROL-PLANE.md](CONTROL-PLANE.md) - Add automation workflows
- [Scripts Reference](../08-REFERENCE/SCRIPTS.md) - Available automation tools
- [CI/CD Workflows](../05-CI-CD/WORKFLOWS.md) - Integrate into pipelines

**Understanding Performance**:
- [QEMU-CONFIGURATION.md](QEMU-CONFIGURATION.md) - Tuning parameters
- [Monitoring](../04-OPERATION/MONITORING.md) - Performance metrics

---

[← Back to Documentation Index](../INDEX.md)
