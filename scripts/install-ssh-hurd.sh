#!/bin/bash
# Automated SSH Installation for GNU/Hurd via Serial Console
# Connects to running QEMU instance and installs OpenSSH server

# shellcheck disable=SC2154
set -euo pipefail

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
echo "[INFO] Connecting to serial console on port $SERIAL_PORT..."
echo ""

# Use expect to automate the serial console interaction
expect << EXPECT_SCRIPT
set timeout 600
set send_slow {1 .001}
log_user 1

puts "Connecting to telnet $SERIAL_HOST:$SERIAL_PORT"

# Connect to telnet
spawn telnet $SERIAL_HOST $SERIAL_PORT

# Send wake-up characters
send "\r\r\r"
sleep 2

	# Most upstream Hurd images do not provide a usable serial login.
	# Fail fast with actionable guidance if serial appears blank.
	set allow_wait 0
	if {[info exists env(ALLOW_BLANK_SERIAL_WAIT)] && $env(ALLOW_BLANK_SERIAL_WAIT) == "1"} {
	    set allow_wait 1
	}

	set quick_timeout 20
	expect -timeout $quick_timeout {
	    -re ".*login:\\s*$" {
	        puts "\nFound login prompt"
	        send -s "root\r"
	    }
	    timeout {
	        if {$allow_wait} {
	            puts "\nNo login prompt on serial after ${quick_timeout}s; continuing to wait (ALLOW_BLANK_SERIAL_WAIT=1)."
	        } else {
	            puts "\nNo login prompt on serial after ${quick_timeout}s."
	            puts "This is expected on many Debian GNU/Hurd images (serial is often blank)."
	            puts ""
	            puts "Use VNC/noVNC for provisioning instead:"
	            puts "  ./scripts/docker-orchestration.sh up-vnc"
	            puts "  Open: http://127.0.0.1:${NOVNC_PORT:-6080}/vnc.html"
	            puts ""
	            puts "If you intentionally want to wait on serial anyway, re-run with:"
	            puts "  ALLOW_BLANK_SERIAL_WAIT=1 ./scripts/install-ssh-hurd.sh"
	            exit 1
	        }
	    }
	}

	# If the user explicitly allows waiting, fall back to long wait for login.
	if {$allow_wait} {
	    expect {
	        -re ".*login:\\s*$" {
	            puts "\nFound login prompt"
	            send -s "root\r"
	        }
	        timeout {
	            puts "\nTimeout waiting for login prompt after 600s"
	            puts "The system may not have booted yet or serial is not responding"
	            exit 1
	        }
	    }
	}

# Wait for password prompt or shell
expect {
    "Password:" {
        puts "Password prompt, sending empty password"
        send "\r"
    }
    -re "#\s*\$" {
        puts "Already at shell"
    }
    timeout {
        puts "\nTimeout after login"
        exit 1
    }
}

# Wait for shell prompt
expect {
    -re "#\s*\$" {
        puts "\nLogged in as root"
    }
    timeout {
        puts "\nDid not get shell prompt"
        exit 1
    }
}

# Check network connectivity
send -s "ping -c 1 8.8.8.8 2>&1 | head -2\r"
expect -re "#"

# Update package lists
puts "\n[INFO] Updating package lists..."
send -s "apt-get update\r"
expect {
    -re "#" {
        puts "[SUCCESS] Package lists updated"
    }
    timeout {
        puts "\n[ERROR] apt-get update timed out"
        exit 1
    }
}

# Install SSH server and entropy daemon
puts "\n[INFO] Installing openssh-server and random-egd..."
send -s "DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server random-egd\r"
expect {
    -re "#" {
        puts "[SUCCESS] Packages installed"
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
expect -re "#"

# Enable SSH on boot
puts "\n[INFO] Enabling SSH on boot..."
send -s "update-rc.d ssh defaults\r"
expect -re "#"

# Configure sshd for password auth (simpler approach - no nested quotes)
puts "\n[INFO] Configuring sshd for password authentication..."
send -s "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\r"
expect -re "#"
send -s "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\r"
expect -re "#"
send -s "sed -i 's/^#\\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config\r"
expect -re "#"
send -s "/etc/init.d/ssh restart\r"
expect -re "#"

# Set root password
puts "\n[INFO] Setting root password..."
send -s "echo 'root:root' | chpasswd\r"
expect -re "#"

# Verify SSH config
puts "\n[INFO] Verifying SSH configuration..."
send -s "grep -E '^(PermitRootLogin|PasswordAuthentication|UsePAM)' /etc/ssh/sshd_config\r"
expect -re "#"

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
