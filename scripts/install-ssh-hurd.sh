#!/bin/bash
# Automated SSH Installation for GNU/Hurd via Serial Console
# Connects to running QEMU instance and installs OpenSSH server

set -e

SERIAL_PORT="${SERIAL_PORT:-5555}"
SERIAL_HOST="${SERIAL_HOST:-localhost}"

echo "========================================================================"
echo "  GNU/Hurd SSH Server Installation via Serial Console"
echo "========================================================================"
echo ""
echo "This script will:"
echo "  1. Connect to QEMU serial console (telnet $SERIAL_HOST:$SERIAL_PORT)"
echo "  2. Login as root (default: no password)"
echo "  3. Configure network if needed"
echo "  4. Install openssh-server and random-egd"
echo "  5. Start SSH daemon"
echo "  6. Set root password for security"
echo ""
echo "Press Ctrl+C to cancel, or Enter to continue..."
read -r

echo ""
echo "[INFO] Connecting to serial console..."
echo ""

# Use expect to automate the serial console interaction
expect << 'EXPECT_SCRIPT'
set timeout 120
set send_slow {1 .001}

# Connect to telnet
spawn telnet localhost 5555

# Wait for login prompt (could be various forms)
expect {
    "login:" {
        send -s "root\r"
    }
    "localhost login:" {
        send -s "root\r"
    }
    "debian login:" {
        send -s "root\r"
    }
    timeout {
        puts "\n[ERROR] Timeout waiting for login prompt"
        puts "[INFO] The system may still be booting. Wait 2-3 more minutes."
        exit 1
    }
}

# Wait for password prompt or shell
expect {
    "Password:" {
        # Empty password - just press Enter
        send "\r"
    }
    "#" {
        # Already at shell
    }
    timeout {
        puts "\n[ERROR] Timeout after login"
        exit 1
    }
}

# Wait for shell prompt
expect {
    "#" {
        puts "\n[SUCCESS] Logged in as root"
    }
    timeout {
        puts "\n[ERROR] Did not get shell prompt"
        exit 1
    }
}

# Check network connectivity
send -s "ping -c 1 8.8.8.8 2>&1 | head -2\r"
expect "#"

# Update package lists
puts "\n[INFO] Updating package lists..."
send -s "apt-get update\r"
expect {
    "#" {
        puts "[SUCCESS] Package lists updated"
    }
    "Err:" {
        puts "\n[WARN] Some package sources may have failed"
        expect "#"
    }
    timeout {
        puts "\n[ERROR] apt-get update timed out"
        exit 1
    }
}

# Install SSH server and entropy daemon
puts "\n[INFO] Installing openssh-server and random-egd..."
send -s "apt-get install -y openssh-server random-egd\r"
expect {
    "#" {
        puts "[SUCCESS] Packages installed"
    }
    "E: " {
        puts "\n[ERROR] Package installation failed"
        expect "#"
        exit 1
    }
    timeout {
        puts "\n[ERROR] Package installation timed out (this can take 5-10 minutes)"
        puts "[INFO] You may need to continue manually"
        exit 1
    }
}

# Start SSH daemon
puts "\n[INFO] Starting SSH daemon..."
send -s "/etc/init.d/ssh start\r"
expect "#"

# Enable SSH on boot
puts "\n[INFO] Enabling SSH on boot..."
send -s "update-rc.d ssh defaults\r"
expect "#"

# Relax sshd restrictions for password auth (override hardened defaults)
puts "\n[INFO] Configuring sshd for password authentication..."
send -s "grep -q '^PermitRootLogin' /etc/ssh/sshd_config && sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config\r"
expect "#"
send -s "grep -q '^PasswordAuthentication' /etc/ssh/sshd_config && sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config\r"
expect "#"
send -s "grep -q '^UsePAM' /etc/ssh/sshd_config && sed -i 's/^UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config || echo 'UsePAM yes' >> /etc/ssh/sshd_config\r"
expect "#"
send -s "/etc/init.d/ssh restart\r"
expect "#"

# Set root password
puts "\n[INFO] Setting root password..."
send -s "echo 'root:root' | chpasswd\r"
expect "#"

puts "\n========================================================================"
puts "  SSH Installation Complete!"
puts "========================================================================"
puts ""
puts "SSH server is now running. Test with:"
puts "  ssh -p 2222 root@localhost"
puts ""
puts "Default credentials:"
puts "  Username: root"
puts "  Password: root"
puts ""
puts "SECURITY: Change the password after first login!"
puts ""

# Keep connection open for user
puts "Press Ctrl+] then 'quit' to exit telnet, or Ctrl+C to disconnect"
interact

EXPECT_SCRIPT

echo ""
echo "[INFO] Script completed. Test SSH connectivity:"
echo "  ssh -p 2222 root@localhost"
echo ""
