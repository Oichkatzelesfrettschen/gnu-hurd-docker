#!/bin/sh
# Out-of-box-experience staging for the published Hurd guest image.
# Run INSIDE the guest as root, as the last provisioning step before an
# image is shut down and distributed.
#
# Establishes the documented generic credentials and expires them, so
# the first interactive login (VNC console, or SSH with password or
# keyboard-interactive auth through PAM) forces the person to choose
# their own password before they get a shell:
#
#   user / user   -- primary account, sudo member
#   root / root   -- console recovery account
#
# login(1) and sshd (UsePAM) both honor the shadow last-change field of
# zero that passwd -e writes, via pam_unix account management. Dropbear,
# kept on the image as a fallback SSH daemon, skips password aging, so
# the enforced path is the console and OpenSSH.
#
# Idempotent: safe to re-run; it resets both passwords and re-expires.

set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin

say() { printf '=== %s ===\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root" >&2; exit 1; }

say "Ensure primary account 'user' exists"
if ! getent passwd user >/dev/null 2>&1; then
    useradd -m -s /bin/bash -U user
fi
getent group sudo >/dev/null 2>&1 && usermod -a -G sudo user

say "Set the documented generic passwords"
printf 'user:user\nroot:root\n' | chpasswd

say "Expire both passwords (forces change at first PAM login)"
passwd -e user
passwd -e root

say "Stage first-login banner"
cat > /etc/motd <<'EOF'

  Debian GNU/Hurd -- gnu-hurd-docker guest

  First login? The generic passwords (user/user, root/root) are
  expired: the system asks you to set your own before continuing.
  SSH password logins and the VNC console both enforce this.

  Quick orientation:
    sudo -i                 become root (member of sudo group)
    apt update              package index (Debian sid, hurd-amd64 port)
    showtrans /             see a Hurd translator in action

EOF

say "Verify shadow aging fields"
for account in user root; do
    printf '%s: ' "$account"
    getent shadow "$account" | cut -d: -f1-3
done

say "OOBE staging complete"
