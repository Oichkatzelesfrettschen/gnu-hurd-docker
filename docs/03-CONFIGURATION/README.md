# Configuration Guide

**Last Updated**: 2025-11-07
**Section**: 03-CONFIGURATION
**Purpose**: Customize and configure your GNU/Hurd environment

---

## Overview

This section covers all configuration options for customizing the GNU/Hurd x86_64 Docker environment, from network port forwarding to user management and advanced features.

**Audience**: Users who want to customize their setup beyond defaults

**Prerequisites**: Completed [Getting Started](../01-GETTING-STARTED/)

---

## Documents in This Section

### [PORT-FORWARDING.md](PORT-FORWARDING.md)
**Configure network port mappings between host and guest**

- Default ports (SSH 2222, Serial 5555)
- Add custom port forwards (HTTP, databases, services)
- Modify docker-compose.yml
- Verify port accessibility
- Firewall configuration

**When to use**: Expose additional services, configure custom ports

---

### [USER-CONFIGURATION.md](USER-CONFIGURATION.md)
**User account management and permissions**

- Root account configuration
- Create standard users
- Configure sudo access (NOPASSWD)
- SSH key setup
- Password policies
- User groups

**When to use**: Create additional users, configure permissions

---

### [CUSTOM-FEATURES.md](CUSTOM-FEATURES.md)
**Advanced customizations and feature flags**

- Install desktop environment (Xfce4, GNOME)
- Configure display modes (VNC, X11 forwarding)
- Install additional software (Node.js, Python, Claude Code)
- Shell customization (aliases, prompts)
- Hurd-specific features (MIG, Mach utilities)
- Performance tuning

**When to use**: Install GUI, configure development environment, optimize performance

---

## Common Configuration Tasks

### Quick Start Configurations

**Minimal Development** (default):
```yaml
# docker-compose.yml (no changes needed)
ports:
  - "2222:22"    # SSH access
memory: 4GB      # Standard RAM
```

**Web Development**:
```yaml
ports:
  - "2222:22"    # SSH
  - "8080:80"    # HTTP server
  - "3000:3000"  # Node.js app
memory: 4GB
```

**Database Development**:
```yaml
ports:
  - "2222:22"    # SSH
  - "5432:5432"  # PostgreSQL
  - "3306:3306"  # MySQL/MariaDB
memory: 6GB      # Extra RAM for databases
```

**GUI Desktop**:
```yaml
ports:
  - "2222:22"    # SSH
  - "5900:5900"  # VNC
memory: 8GB      # Extra RAM for desktop
```

---

## Quick Navigation

**Getting Started**:
- [Installation](../01-GETTING-STARTED/INSTALLATION.md)
- [Quickstart](../01-GETTING-STARTED/QUICKSTART.md)

**Architecture** (understand before configuring):
- [System Design](../02-ARCHITECTURE/SYSTEM-DESIGN.md)
- [QEMU Configuration](../02-ARCHITECTURE/QEMU-CONFIGURATION.md)

**Operation** (use after configuration):
- [Interactive Access](../04-OPERATION/INTERACTIVE-ACCESS.md)
- [Snapshots](../04-OPERATION/SNAPSHOTS.md) - Backup before major config changes
- [Monitoring](../04-OPERATION/MONITORING.md)

**Reference**:
- [Scripts](../08-REFERENCE/SCRIPTS.md) - Automation tools
- [Credentials](../08-REFERENCE/CREDENTIALS.md) - Default passwords, SSH keys

---

## Configuration Workflows

### Workflow 1: Add New User

1. **SSH into guest**:
   ```bash
   ssh -p 2222 root@localhost
   ```

2. **Follow [USER-CONFIGURATION.md](USER-CONFIGURATION.md)**:
   - Create user with `useradd`
   - Set password
   - Add to sudo group
   - Configure SSH keys

3. **Test new user**:
   ```bash
   ssh -p 2222 newuser@localhost
   ```

---

### Workflow 2: Enable HTTP Service

1. **Edit docker-compose.yml** ([PORT-FORWARDING.md](PORT-FORWARDING.md)):
   ```yaml
   ports:
     - "8080:80"
   ```

2. **Restart container**:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

3. **Install web server inside guest**:
   ```bash
   ssh -p 2222 root@localhost
   apt-get install -y nginx
   systemctl start nginx
   ```

4. **Test from host**:
   ```bash
   curl http://localhost:8080
   ```

---

### Workflow 3: Install Desktop Environment

1. **Create snapshot** (in case something breaks):
   ```bash
   ./scripts/manage-snapshots.sh create before-desktop
   ```

2. **Follow [CUSTOM-FEATURES.md](CUSTOM-FEATURES.md)**:
   - Install Xfce4 (~750 MB)
   - Configure VNC server
   - Add VNC port to docker-compose.yml

3. **Connect via VNC**:
   ```bash
   vncviewer localhost:5900
   ```

4. **If issues occur, restore**:
   ```bash
   ./scripts/manage-snapshots.sh restore before-desktop
   ```

---

## Configuration Best Practices

1. **Snapshot before major changes**:
   ```bash
   ./scripts/manage-snapshots.sh create before-config-change
   ```

2. **Document custom configurations**:
   - Note changes in project README or CHANGELOG
   - Track docker-compose.yml changes in git

3. **Test incremental changes**:
   - Make one change at a time
   - Verify each change works before proceeding

4. **Use automation scripts**:
   - [configure-users.sh](../08-REFERENCE/SCRIPTS.md#10-configure-userssh)
   - [configure-shell.sh](../08-REFERENCE/SCRIPTS.md#11-configure-shellsh)

5. **Review security implications**:
   - Changed port forwarding? Update firewall rules
   - New user? Set strong password
   - Exposed services? Restrict to localhost only

---

## For Advanced Users

**Custom Kernel Builds**:
- See [CUSTOM-FEATURES.md](CUSTOM-FEATURES.md#kernel-development)
- Install Hurd development tools
- Build from source

**Network Configuration**:
- Default: User-mode NAT (simple, isolated)
- Advanced: Bridged networking (see [System Design](../02-ARCHITECTURE/SYSTEM-DESIGN.md))

**Performance Tuning**:
- QEMU CPU parameters: [QEMU-CONFIGURATION.md](../02-ARCHITECTURE/QEMU-CONFIGURATION.md)
- Memory allocation: [QEMU-CONFIGURATION.md](../02-ARCHITECTURE/QEMU-CONFIGURATION.md)
- Storage cache modes: [QEMU-CONFIGURATION.md](../02-ARCHITECTURE/QEMU-CONFIGURATION.md)

---

## Troubleshooting Configuration

**Port already in use**:
- See [PORT-FORWARDING.md](PORT-FORWARDING.md#troubleshooting)
- Change host port or stop conflicting service

**User creation fails**:
- See [USER-CONFIGURATION.md](USER-CONFIGURATION.md#troubleshooting)
- Check sudo availability, permissions

**Custom feature installation fails**:
- See [CUSTOM-FEATURES.md](CUSTOM-FEATURES.md#troubleshooting)
- Check disk space, network connectivity
- Review apt logs

**Configuration not persisting**:
- Ensure changes made inside QCOW2 (not Docker container filesystem)
- Verify docker-compose.yml volume mounts
- Check [Snapshots](../04-OPERATION/SNAPSHOTS.md) for state management

---

[← Back to Documentation Index](../INDEX.md)
