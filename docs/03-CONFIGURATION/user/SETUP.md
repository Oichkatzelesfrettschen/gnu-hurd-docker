# User Account Setup and Configuration

## Creating Standard User Accounts

After initial access as root, create standard user accounts for daily use.

### Quick Start: Add New User

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
# Create user with specific UID and group
useradd -u 1001 -m -s /bin/bash -G sudo,adm developer

# Verify user was created
id developer
# Output: uid=1001(developer) gid=1001(developer) groups=1001(developer),4(adm),27(sudo)

# Verify home directory
ls -la /home/developer/
```

## SSH Key Setup for New User

### Generate SSH Key on Host

```bash
# On your host machine (not in container)
ssh-keygen -t ed25519 -f ~/.ssh/hurd_dev -C "developer@gnu-hurd"

# This creates:
# - ~/.ssh/hurd_dev (private key - keep secret)
# - ~/.ssh/hurd_dev.pub (public key - share with server)
```

### Configure SSH for New User

```bash
# As root in container, create .ssh directory
mkdir -p /home/developer/.ssh

# Add your public key
cat >> /home/developer/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAAC3Nza... (paste your public key here)
EOF

# Set proper permissions
chmod 700 /home/developer/.ssh
chmod 600 /home/developer/.ssh/authorized_keys
chown -R developer:developer /home/developer/.ssh

# Restart SSH
systemctl restart ssh
```

### Connect Using SSH Key

```bash
# From host, connect with specific key
ssh -i ~/.ssh/hurd_dev -p 2222 developer@localhost

# Or add to ~/.ssh/config for convenience
cat >> ~/.ssh/config <<'EOF'
Host gnu-hurd
    HostName localhost
    Port 2222
    User developer
    IdentityFile ~/.ssh/hurd_dev
    StrictHostKeyChecking accept-new
EOF

# Now connect easily
ssh gnu-hurd
```

## Sudo Configuration

### Grant Sudo Access

The `sudo` group already has sudo access (from `/etc/sudoers`):

```bash
# User is already in sudo group if added with -G sudo
usermod -aG sudo existinguser

# Verify
sudo -l
# Output should show allowed commands
```

### Configure Passwordless Sudo (Optional)

```bash
# Edit sudoers file safely
sudo visudo

# Add line at end (if you want passwordless sudo):
developer ALL=(ALL) NOPASSWD: ALL

# Save and exit (Ctrl+X in nano, or :wq in vi)
```

### Default Sudoers Configuration

The system includes standard sudo settings:

```bash
# View current sudoers file
sudo cat /etc/sudoers

# Common entries:
%sudo  ALL=(ALL:ALL) ALL        # sudo group can run all commands
%adm   ALL=(ALL) ALL            # adm group can run all commands
```

## Shell Configuration

### Set Default Shell

```bash
# Change shell for user
chsh -s /bin/bash developer

# Verify
grep developer /etc/passwd
# Should show: developer:x:1001:1001::/home/developer:/bin/bash
```

### Configure Shell Profile

```bash
# Edit user's .bashrc
sudo -u developer cat >> /home/developer/.bashrc <<'EOF'

# Custom aliases
alias ll='ls -la'
alias grep='grep --color=auto'

# Custom exports
export EDITOR=nano
export VISUAL=nano

EOF

# Reload profile
sudo -u developer bash -c 'source /home/developer/.bashrc'
```

## Group Management

### Common Groups and Purposes

| Group | Purpose | Members |
|-------|---------|---------|
| sudo | Superuser privileges | regular admins |
| adm | System administration | sysadmins |
| cdrom | CD/DVD access | users needing CD access |
| audio | Audio device access | audio users |
| video | Video device access | video users |

### Add User to Group

```bash
# Add existing user to group
usermod -aG groupname username

# Add multiple groups at once
usermod -aG sudo,adm,video newuser

# Verify
groups newuser
# Output: newuser : newuser sudo adm video
```

## Password Management

### Set Password

```bash
# Set password for user (interactive)
passwd username
# Prompts: Enter new UNIX password:

# Set password non-interactively (for scripts)
echo "username:newpassword" | chpasswd
```

### Change Own Password

```bash
# User can change their own password
passwd
# Prompts: (current) UNIX password:
# Then: Enter new UNIX password:
```

### Password Expiration

```bash
# Set password expiration (90 days)
chage -M 90 username

# Disable expiration
chage -M -1 username

# View expiration info
chage -l username
```

## Environment Variables

### Set Per-User Variables

```bash
# Add to user's .bashrc
echo 'export MYVAR=value' >> /home/username/.bashrc

# Add to /etc/environment for all users
echo 'MYVAR=value' >> /etc/environment
```

### View Environment

```bash
# List all environment variables
printenv

# Check specific variable
echo $PATH
```

## Home Directory Setup

### Create Home Directory Structure

```bash
# As new user, create common directories
mkdir -p ~/Documents ~/Downloads ~/Projects ~/Backups

# Set permissions
chmod 700 ~/Documents ~/Downloads ~/Projects
```

### Copy Dotfiles

```bash
# Copy template files from root
sudo cp /root/.bashrc /home/developer/.bashrc
sudo chown developer:developer /home/developer/.bashrc

# Or create new config
cat > /home/developer/.bashrc <<'EOF'
# User's custom bashrc
export PATH="$HOME/bin:$PATH"
alias ll='ls -la'
EOF
```

## User Limits and Resources

### Set Resource Limits

```bash
# Edit /etc/security/limits.conf
sudo cat >> /etc/security/limits.conf <<'EOF'
# User resource limits
developer soft nofile 2048
developer hard nofile 4096
developer soft nproc 1024
developer hard nproc 2048
EOF
```

### View Current Limits

```bash
# Show user's limits
ulimit -a
# Shows: file size, pipe size, number of processes, etc.
```

## User Deletion

### Remove User Account

```bash
# Remove user (keep home directory)
userdel username

# Remove user and home directory
userdel -r username

# Remove user's files from all directories
find / -user username -delete
```

## Batch User Creation

### Create Multiple Users

```bash
#!/bin/bash
# Script to create multiple users

USERS=("alice" "bob" "charlie")

for user in "${USERS[@]}"; do
    useradd -m -s /bin/bash -G sudo "$user"
    echo "$user:DefaultPassword123!" | chpasswd
    echo "Created user: $user"
done
```

## Testing User Access

### Verify User Setup

```bash
# Switch to user (as root)
su - username

# Or from host via SSH
ssh -p 2222 username@localhost

# Test sudo access
sudo whoami
# Should output: root (if sudoers configured)
```

### Check User Information

```bash
# View user in /etc/passwd
grep username /etc/passwd

# View user's groups
id username

# View user's login history
lastlog -u username
```

## Troubleshooting User Setup

### User Can't SSH

```bash
# Check SSH service running
systemctl status ssh

# Check SSH public key permissions
ls -la /home/username/.ssh/

# Expected:
# drwx------  2 username username  4096 ...  .ssh
# -rw-r--r--  1 username username   ... ... authorized_keys

# If wrong, fix permissions
chmod 700 /home/username/.ssh
chmod 600 /home/username/.ssh/authorized_keys
chown -R username:username /home/username/.ssh
```

### Sudo Not Working

```bash
# Check if user in sudo group
groups username
# Should include: sudo

# Check sudoers configuration
sudo visudo -c  # Check syntax

# View sudoers (read-only)
sudo cat /etc/sudoers

# Add user to sudoers group (easier way)
usermod -aG sudo username
```

### Can't Login

```bash
# Check account not locked
passwd -S username
# Output: username P 11/05/2025 0 99999 7 -1
# P = password set, L = locked

# Unlock if needed
passwd -u username

# Check shell exists
grep username /etc/passwd
# Verify shell path is correct (e.g., /bin/bash exists)
```

## Security Best Practices

1. **Never login as root** for daily tasks - use sudo instead
2. **Use SSH keys** instead of passwords
3. **Disable root SSH login** (edit `/etc/ssh/sshd_config`)
4. **Use strong passwords** (14+ characters, mixed case, numbers, symbols)
5. **Review sudo usage** regularly (`sudo /usr/bin/lastlog`)
6. **Disable unused accounts** (`passwd -l username`)
7. **Set password expiration** (`chage -M 90 username`)

## References

- GNU/Hurd User Administration Guide
- Linux User Management Documentation
- SSH Key Management Best Practices

---

**Last Updated:** 2025-11-05
**Status:** Complete
