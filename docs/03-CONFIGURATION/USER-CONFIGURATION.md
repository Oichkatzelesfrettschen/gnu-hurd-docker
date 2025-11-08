# GNU/Hurd Docker - User Configuration and Credentials

**Last Updated**: 2025-11-07
**Consolidated From**:
- docs/USER-SETUP.md (user account management)
- docs/CREDENTIALS.md (default credentials and security)

**Purpose**: Complete guide to user account management, credentials, and access configuration

**Scope**: Debian GNU/Hurd x86_64 only (i386 deprecated 2025-11-07)

---

## Default Root Account

The Debian GNU/Hurd 2025 x86_64 image includes a default root account for initial setup and configuration.

### Root User Details

- **Username**: `root`
- **Default Shell**: `/bin/bash`
- **Home Directory**: `/root`
- **UID**: 0 (superuser)
- **Default Password**: Varies by Debian release

### Root Password Options

The root account in official Debian GNU/Hurd 2025 (hurd-amd64) typically uses one of:

1. **No password** (password login disabled, SSH key-only)
2. **Empty password** (press Enter at login prompt)
3. **Default password**: `root` (check Debian release notes)

**Recommended**: Check official documentation at https://www.debian.org/ports/hurd/

### First-Time Login

**Via Serial Console**:
```bash
# From host
telnet localhost 5555

# At login prompt
login: root
Password: [press Enter or try "root"]
```

**Via SSH** (after boot completes):
```bash
# From host
ssh -p 2222 root@localhost

# Password: (empty) or "root"
```

---

## Access Methods

### SSH Access

**Default SSH Port Mapping**: Host:2222 → Container:2222 → Guest:22

**Basic SSH Connection**:
```bash
ssh -p 2222 root@localhost
```

**Default Behavior**:
- Password authentication may be disabled by default
- Key-based authentication preferred
- PermitRootLogin may be set to `prohibit-password`

**Enable Password Authentication** (if needed):

Inside guest (via serial console):
```bash
# Edit SSH config
vi /etc/ssh/sshd_config.d/10-allow-password.conf

# Add:
PasswordAuthentication yes
PermitRootLogin yes

# Restart SSH
systemctl restart ssh
# or
/etc/init.d/ssh restart
```

### Serial Console Access

**Direct TTY Access** for troubleshooting and initial setup:

```bash
# Connect from host
telnet localhost 5555

# Exit telnet
Ctrl+]
telnet> quit
```

**Use Cases**:
- Initial configuration before SSH is available
- Boot debugging (GRUB menu, kernel messages)
- Emergency access if network fails
- Password reset

**Login via Serial**:
```
Debian GNU/Hurd 2025 hurd-x86_64 ttyS0

hurd-x86_64 login: root
Password: [empty or "root"]

root@hurd-x86_64:~#
```

---

## Creating Standard User Accounts

**Security Best Practice**: Do NOT use root for daily tasks. Create standard user accounts with sudo privileges.

### Quick User Creation

```bash
# Create new user with home directory
useradd -m -s /bin/bash newuser

# Set password
passwd newuser

# Add to sudo group (for administrative tasks)
usermod -aG sudo newuser
```

### Detailed User Creation

```bash
# Create user with specific UID and multiple groups
useradd -u 1001 -m -s /bin/bash -G sudo,adm developer

# Verify user created
id developer
# Output: uid=1001(developer) gid=1001(developer) groups=1001(developer),4(adm),27(sudo)

# Verify home directory
ls -la /home/developer/

# Set password
passwd developer
# Enter new password twice
```

### User Creation Parameters

| Option | Purpose | Example |
|--------|---------|---------|
| `-m` | Create home directory | `/home/username` |
| `-s` | Set login shell | `/bin/bash` |
| `-G` | Add to supplementary groups | `sudo,adm,video` |
| `-u` | Set specific UID | `1001` |
| `-c` | Add comment/full name | `"John Doe"` |
| `-e` | Set account expiration | `2025-12-31` |

---

## SSH Key-Based Authentication

**Recommended** for security and automation. No passwords required.

### Generate SSH Key on Host

```bash
# Generate ED25519 key (recommended)
ssh-keygen -t ed25519 -f ~/.ssh/hurd_dev -C "developer@gnu-hurd"

# Creates:
# - ~/.ssh/hurd_dev (private key - keep secret!)
# - ~/.ssh/hurd_dev.pub (public key - share with server)
```

**Key Types**:
- **ed25519**: Modern, fast, secure (recommended)
- **rsa -b 4096**: Traditional, widely supported
- **ecdsa -b 521**: Elliptic curve, good security

### Configure SSH for New User

**Inside Hurd Guest** (as root):

```bash
# Create .ssh directory for user
mkdir -p /home/developer/.ssh
chmod 700 /home/developer/.ssh

# Add public key (from host ~/.ssh/hurd_dev.pub)
cat >> /home/developer/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... developer@gnu-hurd
EOF

# Set proper permissions (CRITICAL!)
chmod 600 /home/developer/.ssh/authorized_keys
chown -R developer:developer /home/developer/.ssh

# Restart SSH service
systemctl restart ssh
# or
/etc/init.d/ssh restart
```

**Copy via 9p Mount** (easier method):

```bash
# On host: Copy public key to shared directory
cp ~/.ssh/hurd_dev.pub ./share/

# Inside guest: Mount and copy
mkdir -p /mnt/host
mount -t 9p -o trans=virtio scripts /mnt/host
mkdir -p /home/developer/.ssh
cat /mnt/host/hurd_dev.pub >> /home/developer/.ssh/authorized_keys
chmod 700 /home/developer/.ssh
chmod 600 /home/developer/.ssh/authorized_keys
chown -R developer:developer /home/developer/.ssh
```

### SSH Config for Convenience

**On Host** (create ~/.ssh/config entry):

```bash
cat >> ~/.ssh/config <<'EOF'
Host gnu-hurd
    HostName localhost
    Port 2222
    User developer
    IdentityFile ~/.ssh/hurd_dev
    StrictHostKeyChecking accept-new

Host hurd-root
    HostName localhost
    Port 2222
    User root
    IdentityFile ~/.ssh/hurd_dev
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

chmod 600 ~/.ssh/config
```

**Connect Easily**:
```bash
# As developer
ssh gnu-hurd

# As root
ssh hurd-root

# Run commands
ssh gnu-hurd "uname -a"
```

---

## Sudo Configuration

### Grant Sudo Access

**Add User to sudo Group**:

```bash
# Add existing user to sudo group
usermod -aG sudo existinguser

# Verify
groups existinguser
# Output: existinguser : existinguser sudo

# Test sudo access
su - existinguser
sudo whoami
# Output: root (if working correctly)
```

**Sudo Group Permissions**:

The `sudo` group has full administrative privileges via `/etc/sudoers`:

```bash
# View sudoers configuration
sudo cat /etc/sudoers | grep sudo

# Common entry:
%sudo  ALL=(ALL:ALL) ALL
```

### Configure Passwordless Sudo (Optional)

**For automation and convenience**:

```bash
# Edit sudoers file safely (ALWAYS use visudo!)
sudo visudo

# Add at end (for specific user):
developer ALL=(ALL) NOPASSWD: ALL

# Or for entire sudo group:
%sudo ALL=(ALL) NOPASSWD: ALL

# Save and exit (Ctrl+X in nano, :wq in vi)
```

**Test Passwordless Sudo**:
```bash
su - developer
sudo whoami
# Should NOT prompt for password
# Output: root
```

**Security Warning**: Passwordless sudo reduces security. Only use in trusted environments or for specific commands.

### Restrict Sudo to Specific Commands

**Limit sudo to safe commands**:

```bash
# Edit sudoers (always use visudo!)
sudo visudo

# Add lines for limited access:
developer ALL=(ALL) NOPASSWD: /bin/systemctl restart ssh
developer ALL=(ALL) NOPASSWD: /usr/bin/apt-get update
developer ALL=(ALL) /bin/mount

# Save and exit
```

**Test Restricted Sudo**:
```bash
sudo systemctl restart ssh  # Works without password
sudo mount /mnt/host        # Prompts for password
sudo rm -rf /               # Denied (command not in sudoers)
```

---

## Shell Configuration

### Set Default Shell

```bash
# Change shell for user
chsh -s /bin/bash developer

# Available shells
cat /etc/shells
# /bin/sh
# /bin/bash
# /bin/dash

# Verify change
grep developer /etc/passwd
# Expected: developer:x:1001:1001::/home/developer:/bin/bash
```

### Configure Shell Profile

**User's ~/.bashrc** (custom aliases and environment):

```bash
# Edit user's .bashrc
sudo -u developer cat >> /home/developer/.bashrc <<'EOF'

# Custom aliases
alias ll='ls -la --color=auto'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Custom exports
export EDITOR=vim
export VISUAL=vim
export PATH="$HOME/bin:$PATH"

# Colorized prompt
export PS1='\[\033[01;32m\]\u@hurd-x86_64\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

EOF

# Reload profile
sudo -u developer bash -c 'source /home/developer/.bashrc'
```

**System-wide Profile** (/etc/profile.d/):

```bash
# Create system-wide custom settings
cat > /etc/profile.d/custom.sh <<'EOF'
#!/bin/bash
# System-wide custom settings

export MACH_INCLUDE="/usr/include/mach"
export HURD_INCLUDE="/usr/include/hurd"
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/lib/x86_64-gnu/pkgconfig"

EOF

chmod +x /etc/profile.d/custom.sh
```

---

## Group Management

### Common Groups and Purposes

| Group | Purpose | Typical Members |
|-------|---------|----------------|
| `sudo` | Superuser privileges via sudo | Administrators |
| `adm` | System administration, log viewing | Sysadmins |
| `cdrom` | CD/DVD drive access | Desktop users |
| `audio` | Audio device access | Audio users |
| `video` | Video device access | Video/X11 users |
| `plugdev` | Removable device access | Desktop users |
| `netdev` | Network device management | Network admins |

### Add User to Groups

```bash
# Add user to single group
usermod -aG groupname username

# Add user to multiple groups
usermod -aG sudo,adm,video,audio developer

# Verify group membership
groups developer
# Output: developer : developer sudo adm video audio

# View all members of a group
getent group sudo
# Output: sudo:x:27:developer,alice,bob
```

**Note**: User must logout/login for group changes to take effect.

---

## Password Management

### Set User Password

```bash
# Set password for user (interactive)
passwd username
# Prompts: Enter new UNIX password:
# Prompts: Retype new UNIX password:

# Set password non-interactively (for scripts)
echo "username:newpassword" | chpasswd
```

### Change Own Password

```bash
# User can change their own password
passwd
# Prompts: (current) UNIX password:
# Prompts: Enter new UNIX password:
# Prompts: Retype new UNIX password:
```

### Password Policies

```bash
# Set password expiration (90 days)
chage -M 90 username

# Disable password expiration
chage -M -1 username

# Set minimum password age (7 days)
chage -m 7 username

# Require password change on next login
chage -d 0 username

# View password expiration info
chage -l username
```

### Password Strength Requirements

**Install libpam-pwquality** (if not present):

```bash
apt-get install libpam-pwquality
```

**Configure** /etc/security/pwquality.conf:

```bash
# Minimum password length
minlen = 14

# Require lowercase
lcredit = -1

# Require uppercase
ucredit = -1

# Require digit
dcredit = -1

# Require special character
ocredit = -1

# Maximum same consecutive characters
maxrepeat = 2
```

---

## Environment Variables

### Set Per-User Variables

```bash
# Add to user's .bashrc
echo 'export MYVAR=value' >> /home/username/.bashrc

# Add to user's .profile (login shells)
echo 'export MYVAR=value' >> /home/username/.profile

# Reload
source /home/username/.bashrc
```

### Set System-Wide Variables

```bash
# Add to /etc/environment (all users, all sessions)
echo 'MYVAR=value' >> /etc/environment

# Add to /etc/profile (all users, login shells)
echo 'export MYVAR=value' >> /etc/profile
```

### View Environment

```bash
# List all environment variables
printenv

# List all (including shell variables)
env

# Check specific variable
echo $PATH
echo $HOME
echo $USER
```

---

## Home Directory Setup

### Create Home Directory Structure

```bash
# As new user, create common directories
mkdir -p ~/Documents ~/Downloads ~/Projects ~/Backups ~/bin

# Set permissions (private)
chmod 700 ~/Documents ~/Downloads ~/Projects ~/Backups

# Public bin directory
chmod 755 ~/bin
```

### Copy Template Files

```bash
# Copy skeleton files from /etc/skel
cp /etc/skel/.bashrc /home/developer/.bashrc
cp /etc/skel/.profile /home/developer/.profile

# Set ownership
chown developer:developer /home/developer/.bashrc /home/developer/.profile

# Or create custom .bashrc
cat > /home/developer/.bashrc <<'EOF'
# User's custom bashrc for GNU/Hurd x86_64

# PATH
export PATH="$HOME/bin:/usr/local/bin:/usr/bin:/bin"

# Aliases
alias ll='ls -la'
alias ..='cd ..'

# Prompt
export PS1='\u@\h:\w\$ '

EOF
```

---

## User Limits and Resources

### Set Resource Limits

**Edit /etc/security/limits.conf**:

```bash
# Add user-specific limits
cat >> /etc/security/limits.conf <<'EOF'
# User resource limits
developer soft nofile 2048      # Soft limit: open files
developer hard nofile 4096      # Hard limit: open files
developer soft nproc 1024       # Soft limit: processes
developer hard nproc 2048       # Hard limit: processes
developer soft memlock 512      # Memory lock (KB)
developer hard memlock 1024     # Memory lock (KB)
EOF
```

### View Current Limits

```bash
# Show user's limits
ulimit -a

# Output:
# file size               (blocks, -f) unlimited
# pipe size            (512 bytes, -p) 8
# max memory size         (kbytes, -m) unlimited
# open files                      (-n) 1024
# stack size              (kbytes, -s) 8192
# cpu time               (seconds, -t) unlimited
# max user processes              (-u) 7823
```

**Change Limits for Current Session**:
```bash
# Increase open file limit
ulimit -n 4096

# Verify
ulimit -n
# Output: 4096
```

---

## User Deletion

### Remove User Account

```bash
# Remove user (keep home directory)
userdel username

# Remove user AND home directory
userdel -r username

# Remove user, home, and mail spool
userdel -r -f username
```

### Cleanup User Files

```bash
# Find all files owned by user
find / -user username 2>/dev/null

# Remove all files owned by user (DANGEROUS!)
find / -user username -delete 2>/dev/null

# Archive user files before deletion
tar czf /tmp/username-backup.tar.gz /home/username
userdel -r username
```

---

## Batch User Creation

### Create Multiple Users (Script)

```bash
#!/bin/bash
# Batch create users for GNU/Hurd x86_64

USERS=("alice" "bob" "charlie" "developer")

for user in "${USERS[@]}"; do
    echo "Creating user: $user"

    # Create user with home directory
    useradd -m -s /bin/bash -G sudo "$user"

    # Set default password (change on first login)
    echo "$user:ChangeMe123!" | chpasswd

    # Require password change on first login
    chage -d 0 "$user"

    echo "✓ Created user: $user"
done

echo "All users created successfully!"
```

**Run Script**:
```bash
chmod +x create-users.sh
sudo ./create-users.sh
```

---

## Testing User Access

### Verify User Setup

```bash
# Switch to user (as root)
su - username

# Verify environment
whoami
# Output: username

pwd
# Output: /home/username

groups
# Output: username sudo adm
```

### Test SSH Access

```bash
# From host
ssh -p 2222 username@localhost

# Test sudo
ssh -p 2222 username@localhost "sudo whoami"
# Output: root (if sudo configured)
```

### Check User Information

```bash
# View user in /etc/passwd
grep username /etc/passwd
# Output: username:x:1001:1001::/home/username:/bin/bash

# View user's groups
id username
# Output: uid=1001(username) gid=1001(username) groups=1001(username),27(sudo)

# View user's login history
lastlog -u username

# View last logins
last username
```

---

## Troubleshooting User Access

### User Can't SSH

**Symptom**: SSH connection refused or authentication failed

**Diagnostics**:
```bash
# Check SSH service running
systemctl status ssh

# Check SSH logs
journalctl -u ssh -f

# Check user's .ssh permissions
ls -la /home/username/.ssh/
# Expected:
# drwx------  2 username username  .ssh
# -rw-------  1 username username  authorized_keys

# Fix permissions if wrong
chmod 700 /home/username/.ssh
chmod 600 /home/username/.ssh/authorized_keys
chown -R username:username /home/username/.ssh
```

**Common Issues**:
1. Wrong file permissions (must be 700 for .ssh, 600 for authorized_keys)
2. SSH keys not properly configured
3. PermitRootLogin or PasswordAuthentication disabled
4. User's shell doesn't exist (/bin/bash must be present)

### Sudo Not Working

**Symptom**: `sudo: username is not in the sudoers file`

**Fix**:
```bash
# Check if user in sudo group
groups username
# Should include: sudo

# Add user to sudo group
usermod -aG sudo username

# Verify sudoers configuration
sudo visudo -c
# Output: /etc/sudoers: parsed OK

# Check sudo group in sudoers
grep "%sudo" /etc/sudoers
# Expected: %sudo  ALL=(ALL:ALL) ALL
```

### Can't Login

**Symptom**: Login fails with "Authentication failure"

**Diagnostics**:
```bash
# Check account not locked
passwd -S username
# Output: username P ... (P = password set, L = locked)

# Unlock account if locked
passwd -u username

# Check shell exists
grep username /etc/passwd
# Verify shell path (e.g., /bin/bash) exists
ls -l /bin/bash

# Check password expired
chage -l username

# Reset password expiration
chage -M -1 username
```

---

## Security Best Practices

### Account Security

1. **Never login as root** for daily tasks
   - Use sudo instead
   - Create standard user accounts

2. **Use SSH keys** instead of passwords
   - Disable password authentication
   - Use ED25519 keys

3. **Disable root SSH login** (after key setup)
   ```bash
   # /etc/ssh/sshd_config
   PermitRootLogin prohibit-password
   ```

4. **Use strong passwords** (when required)
   - 14+ characters
   - Mixed case, numbers, symbols
   - Enable password quality checks

5. **Set password expiration**
   ```bash
   chage -M 90 username  # Expire after 90 days
   ```

### Access Control

1. **Principle of Least Privilege**
   - Grant minimum permissions needed
   - Use sudo for specific commands only

2. **Review sudo usage regularly**
   ```bash
   sudo /usr/bin/lastlog
   sudo journalctl -u sudo
   ```

3. **Disable unused accounts**
   ```bash
   passwd -l username  # Lock password
   chage -E 0 username # Expire account
   ```

4. **Monitor login attempts**
   ```bash
   tail -f /var/log/auth.log | grep "Failed password"
   ```

### SSH Hardening

**Edit /etc/ssh/sshd_config.d/10-hardening.conf**:

```bash
# Disable password authentication
PasswordAuthentication no

# Disable root login
PermitRootLogin prohibit-password

# Allow only specific users
AllowUsers developer alice bob

# Or allow only specific groups
AllowGroups ssh-users

# Disable empty passwords
PermitEmptyPasswords no

# Limit authentication attempts
MaxAuthTries 3

# Disable X11 forwarding (if not needed)
X11Forwarding no

# Set idle timeout
ClientAliveInterval 300
ClientAliveCountMax 2

# Restart SSH
systemctl restart ssh
```

---

## Summary

**Default Access**:
- Root username: `root`
- Root password: Empty OR `root` (varies by release)
- SSH port: 2222 (host) → 22 (guest)
- Serial console: telnet localhost:5555

**User Management**:
- Create users: `useradd -m -s /bin/bash username`
- Grant sudo: `usermod -aG sudo username`
- Set password: `passwd username`
- Delete user: `userdel -r username`

**SSH Keys**:
- Generate: `ssh-keygen -t ed25519`
- Install: Copy public key to `~/.ssh/authorized_keys`
- Permissions: 700 for .ssh/, 600 for authorized_keys

**Security Best Practices**:
- Never use root for daily tasks
- Use SSH keys instead of passwords
- Enable password expiration
- Monitor login attempts
- Disable unused accounts
- Harden SSH configuration

---

**Status**: Production Ready (x86_64-only)
**Last Updated**: 2025-11-07
**Maintainer**: Oichkatzelesfrettschen
**Architecture**: Pure x86_64
