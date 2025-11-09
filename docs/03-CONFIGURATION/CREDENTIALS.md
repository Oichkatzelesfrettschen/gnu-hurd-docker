# Access Credentials and Default Configuration

## Default Root Account

The Debian GNU/Hurd system image includes a default root account for initial setup and configuration.

### Root User

- **Username:** `root`
- **Default Shell:** `/bin/bash`
- **Home Directory:** `/root`
- **UID:** 0 (superuser)

### Root Password

The root account in the official Debian GNU/Hurd 2025 image is typically either:

1. **No password** (password login disabled, key-based only)
2. **Empty password** (press Enter at login prompt)
3. **Default password:** Check Debian release notes at https://www.debian.org/ports/hurd/

For the official Debian GNU/Hurd 2025 release (August 2025):
- **Login Method:** SSH with key-based authentication preferred
- **Password Authentication:** See official documentation or trial access

### SSH Access

SSH is mapped host:2222 -> guest:22.

Default behavior before provisioning: may reject passwords if PermitRootLogin prohibit-password.
Run scripts/install-ssh-hurd.sh to force password authentication.

```bash
# Enable password auth and set root password
./scripts/install-ssh-hurd.sh

# Then connect
ssh -p 2222 root@localhost   # Password: root
```

### Serial Console Access

The serial console provides direct TTY access for troubleshooting and setup.

```bash
# Find PTY from Docker logs
docker-compose logs | grep "char device redirected"

# Connect to serial console
screen /dev/pts/X
# (Replace X with actual PTY number, e.g., /dev/pts/5)

# Exit screen: Ctrl+A followed by :quit
```

Serial console login works the same as SSH - use root with the appropriate password or empty password.

## Creating Standard User Accounts

See [USER-SETUP.md](user/SETUP.md) for detailed instructions on:

- Creating new user accounts
- Configuring sudo privileges
- Setting up SSH key authentication
- Configuring user environments
- Password management

## Security Recommendations

### For Development/Testing

1. Change default root password immediately:
   ```bash
   passwd root
   # Enter new password twice
   ```

2. Create standard user account (non-root) for daily use:
   ```bash
   useradd -m -G sudo newuser
   passwd newuser
   # Set password for new user
   ```

3. Disable root SSH login (optional, for enhanced security):
   ```bash
   # Edit /etc/ssh/sshd_config
   PermitRootLogin no
   
   # Restart SSH
   systemctl restart ssh
   ```

### For Production

1. **Always change default root password** before exposing to network
2. **Use SSH key-based authentication** instead of passwords
3. **Create standard user accounts** for all administrative tasks
4. **Restrict SSH access** to specific hosts/networks
5. **Enable firewall rules** on Docker host
6. **Use secrets management** for sensitive credentials

## SSH Key-Based Authentication

Setup SSH keys for secure authentication without passwords:

### On Host (one-time setup)

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "hurd-dev"

# Copy public key to container
ssh-copy-id -p 2222 root@localhost
```

### Inside Container

```bash
# As root, configure SSH to accept your key
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Paste your public key (from ~/.ssh/id_ed25519.pub on host)
echo "your-public-key-here" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Restart SSH service
systemctl restart ssh
```

## Container Environment Variables

The Docker container inherits no special environment variables beyond standard Linux. To set persistent environment variables:

```bash
# Edit /etc/environment or user's shell profile
echo "VARIABLE=value" >> /root/.bashrc
source /root/.bashrc
```

## Port Mappings

Current port mappings from host to container:

| Host Port | Container Port | Service | Usage |
|-----------|----------------|---------|-------|
| 2222 | 22 | SSH | Remote terminal access |
| 9999 | 9999 | Custom | Extensible for other services |

To add additional port mappings:

```bash
# Edit docker-compose.yml
ports:
  - "8080:8080"  # Add HTTP service
  - "3000:3000"  # Add Node.js service
  etc.

# Rebuild and restart
docker-compose up -d --force-recreate
```

## Network Configuration

The container uses user-mode NAT networking:

- **Network Type:** NAT (Network Address Translation)
- **Container IP:** Assigned by QEMU user networking (typically 10.0.2.x)
- **DNS:** Uses host's DNS resolver
- **Gateway:** 10.0.2.2 (QEMU user network gateway)
- **DHCP:** Automatic IP assignment via QEMU user networking

### From Inside Container

```bash
# View network configuration
ifconfig

# Test connectivity
ping 8.8.8.8        # External network
ping google.com     # DNS resolution

# Check routing
netstat -rn
```

## Volume Mounts

The QCOW2 disk image is mounted as read-only:

- **Host Path:** Current directory (project root)
- **Container Path:** `/opt/hurd-image`
- **Mount Type:** Read-only bind mount
- **Permissions:** Read-only from container perspective

To persist data, use SSH/SCP to transfer files or create additional named volumes.

## Troubleshooting Access Issues

### SSH Connection Refused

```bash
# Check if SSH service is running inside container
docker-compose exec gnu-hurd-dev systemctl status ssh

# Restart SSH if needed
docker-compose exec gnu-hurd-dev systemctl restart ssh

# Verify port mapping
docker-compose ps
# Should show 0.0.0.0:2222->22/tcp
```

### Serial Console Unresponsive

```bash
# Check PTY exists
ls /dev/pts/

# Try sending Enter key to wake up console
# Press Enter in screen session

# Exit and retry
# Ctrl+A :quit
```

### Password Not Working

```bash
# Try empty password (press Enter only)
# Refer to Debian GNU/Hurd documentation
# Use SSH keys instead (more secure)
```

### QEMU Not Started

```bash
# Check container logs
docker-compose logs

# Verify image built successfully
docker image ls | grep gnu-hurd

# Rebuild if necessary
docker-compose build --no-cache
```

## References

- [Debian GNU/Hurd](https://www.debian.org/ports/hurd/) - Official distribution
- [QEMU Documentation](https://www.qemu.org/documentation/) - Emulator details
- [Linux SSH Guide](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server) - SSH setup

## Security Notes

- **Do not** share default root password publicly
- **Do not** use default passwords in production
- **Always** use SSH keys for remote access
- **Always** create standard user accounts for regular tasks
- **Always** run updates and security patches

---

**Last Updated:** 2025-11-05
**Status:** Production-ready
