# LLM-Controlled Testing: Complete Guide

## Overview

This guide documents how Large Language Models can control, test, and interact with QEMU guests across Docker, Podman, and Libvirt backends without relying on SSH, using serial console, HTTP APIs, and alternative mechanisms.

---

## Part 1: Serial Console Command Execution

### Why Serial Console?

- **Always Available**: No daemon required in guest
- **Bootstrap Method**: Works before SSH/network is ready
- **Debugging**: Can see kernel boot output
- **Fallback**: When SSH fails (like with Hurd)

### Architecture

```
LLM Process
  ↓ socat/nc + expect patterns
    ↓ Serial telnet port (5555)
      ↓ QEMU serial console  
        ↓ Guest kernel input device
          ↓ Process stdin
            ↓ Console output → socat/nc
              ↓ LLM parses response
```

### Implementation: Python Serial Controller

```python
#!/usr/bin/env python3
"""
LLM Serial Console Controller
Demonstrates automated guest interaction via serial console
"""

import socket
import time
import re
from typing import Optional, Tuple

class SerialConsoleController:
    def __init__(self, host: str = "localhost", port: int = 5555):
        self.host = host
        self.port = port
        self.sock: Optional[socket.socket] = None
        self.output_buffer = ""
    
    def connect(self):
        """Connect to serial console"""
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.connect((self.host, self.port))
        self.sock.settimeout(2.0)
        print(f"✓ Connected to {self.host}:{self.port}")
    
    def send_command(self, cmd: str, expected_pattern: Optional[str] = None, 
                     timeout: float = 5.0) -> Tuple[bool, str]:
        """
        Send command and wait for expected pattern
        
        Args:
            cmd: Command to send
            expected_pattern: Regex pattern to match in response
            timeout: Time to wait for response
            
        Returns:
            (success, output) tuple
        """
        if not self.sock:
            return False, "Not connected"
        
        try:
            # Send command
            self.sock.send(f"{cmd}\n".encode())
            time.sleep(0.5)  # Let guest process
            
            # Collect response
            output = ""
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    chunk = self.sock.recv(1024).decode('utf-8', errors='ignore')
                    if not chunk:
                        break
                    output += chunk
                except socket.timeout:
                    break
            
            # Check for pattern if provided
            if expected_pattern:
                if re.search(expected_pattern, output, re.IGNORECASE):
                    return True, output
                else:
                    return False, output
            
            return True, output
            
        except Exception as e:
            return False, f"Error: {e}"
    
    def execute_test_sequence(self) -> dict:
        """Execute test sequence and report results"""
        results = {
            "kernel_booted": False,
            "network_ready": False,
            "commands_executed": [],
        }
        
        # Test 1: Check if kernel is responsive
        success, output = self.send_command("", expected_pattern=r"root@|#|\$")
        results["kernel_booted"] = success
        
        if not success:
            return results
        
        # Test 2: Run diagnostic commands
        test_commands = [
            ("id", r"uid="),
            ("hostname", r"\w+"),
            ("uname -a", r"GNU"),
            ("ls -la /", r"total|drwx"),
        ]
        
        for cmd, pattern in test_commands:
            success, output = self.send_command(cmd, expected_pattern=pattern)
            results["commands_executed"].append({
                "command": cmd,
                "success": success,
                "first_200_chars": output[:200]
            })
        
        return results
    
    def close(self):
        """Close connection"""
        if self.sock:
            self.sock.close()
            print("✓ Connection closed")

# Example usage
if __name__ == "__main__":
    controller = SerialConsoleController()
    try:
        controller.connect()
        results = controller.execute_test_sequence()
        print(f"Test Results: {results}")
    finally:
        controller.close()
```

### Shell-Based Alternative (Bash)

```bash
#!/bin/bash
# Serial console command executor

SERIAL_PORT=5555
TIMEOUT=10

send_command() {
    local cmd="$1"
    local expected="$2"
    
    # Send command via telnet with timeout
    {
        sleep 0.5
        echo "$cmd"
        sleep 1
    } | timeout $TIMEOUT telnet localhost $SERIAL_PORT 2>&1 | tee /tmp/serial_output.log
    
    # Check if expected pattern found
    if [ -n "$expected" ] && grep -q "$expected" /tmp/serial_output.log; then
        echo "✓ Command '$cmd' succeeded"
        return 0
    else
        echo "✗ Command '$cmd' failed or no response"
        return 1
    fi
}

# Test sequence
send_command "id" "root"
send_command "hostname" "\w+"
send_command "df" "Filesystem|total"
```

---

## Part 2: Guest HTTP API Pattern

### Concept

Start an HTTP server in the guest, send requests from LLM, receive structured responses.

### Guest-Side Implementation

**Simple Flask API** (run in guest after boot)

```python
#!/usr/bin/env python3
# /opt/command-server.py
from flask import Flask, request, jsonify
import subprocess
import json

app = Flask(__name__)

@app.route('/api/execute', methods=['POST'])
def execute():
    """Execute command in guest"""
    data = request.json
    cmd = data.get('command', '')
    
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        return jsonify({
            'success': result.returncode == 0,
            'command': cmd,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/status', methods=['GET'])
def status():
    """Get guest status"""
    return jsonify({
        'status': 'online',
        'timestamp': str(datetime.now()),
        'hostname': subprocess.run('hostname', shell=True, capture_output=True).stdout.decode().strip()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
```

**Start via rc.local or init.d**

```bash
#!/bin/sh
# /etc/init.d/command-server
/usr/bin/python3 /opt/command-server.py > /var/log/command-server.log 2>&1 &
exit 0
```

### Host-Side LLM Control

```python
#!/usr/bin/env python3
import requests
import json

class GuestAPIController:
    def __init__(self, base_url="http://127.0.0.1:8080"):
        self.base_url = base_url
    
    def execute(self, command: str) -> dict:
        """Execute command via API"""
        try:
            response = requests.post(
                f"{self.base_url}/api/execute",
                json={"command": command},
                timeout=10
            )
            return response.json()
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def run_test_suite(self):
        """Run comprehensive test suite"""
        tests = {
            "system_info": "uname -a",
            "disk_usage": "df -h",
            "memory": "free -h",
            "processes": "ps aux",
            "network": "ip addr show",
        }
        
        results = {}
        for name, cmd in tests.items():
            result = self.execute(cmd)
            results[name] = result
            if result['success']:
                print(f"✓ {name}: OK")
            else:
                print(f"✗ {name}: FAILED")
        
        return results

# Usage
controller = GuestAPIController("http://127.0.0.1:8080")
results = controller.run_test_suite()
print(json.dumps(results, indent=2))
```

---

## Part 3: File-Based Communication

### Pattern: Guest Watches for Commands

**Guest Side**

```bash
#!/bin/bash
# /opt/command-watcher.sh - runs on guest boot

COMMAND_FILE="/tmp/llm_command.txt"
RESPONSE_FILE="/tmp/llm_response.txt"

while true; do
    if [ -f "$COMMAND_FILE" ]; then
        CMD=$(cat "$COMMAND_FILE")
        
        # Execute and capture output
        eval "$CMD" > "$RESPONSE_FILE" 2>&1
        
        # Signal completion
        touch /tmp/llm_response_ready
        
        # Wait for LLM to consume
        while [ -f "$COMMAND_FILE" ]; do
            sleep 0.5
        done
    fi
    
    sleep 1
done
```

**Host Side (LLM)**

```python
import os
import time
import tempfile

class FileBasedController:
    def __init__(self, shared_dir="/tmp"):
        self.shared_dir = shared_dir
        self.cmd_file = os.path.join(shared_dir, "llm_command.txt")
        self.resp_file = os.path.join(shared_dir, "llm_response.txt")
    
    def execute(self, command: str, timeout: float = 10.0) -> str:
        """Execute command via file exchange"""
        # Write command
        with open(self.cmd_file, 'w') as f:
            f.write(command)
        
        # Wait for response
        start = time.time()
        while time.time() - start < timeout:
            if os.path.exists(self.resp_file):
                with open(self.resp_file, 'r') as f:
                    response = f.read()
                
                # Clean up
                os.remove(self.cmd_file)
                os.remove(self.resp_file)
                
                return response
            time.sleep(0.1)
        
        return "TIMEOUT"

# Usage
controller = FileBasedController("/tmp")
result = controller.execute("id")
print(result)
```

---

## Part 4: Backend Integration Template

### Unified Backend Interface

```python
#!/usr/bin/env python3
"""
Unified interface for all backends
LLMs use this single interface regardless of backend
"""

from abc import ABC, abstractmethod
from enum import Enum
from typing import Dict, Optional
import subprocess

class Backend(Enum):
    DOCKER = "docker"
    PODMAN = "podman"
    LIBVIRT = "libvirt"

class GuestController(ABC):
    """Abstract base for all backends"""
    
    @abstractmethod
    def is_ready(self) -> bool:
        """Check if guest is ready"""
        pass
    
    @abstractmethod
    def execute(self, command: str) -> Dict:
        """Execute command in guest"""
        pass
    
    @abstractmethod
    def get_status(self) -> Dict:
        """Get guest status"""
        pass

class DockerGuestController(GuestController):
    def __init__(self, container_name="gnu-hurd-dev"):
        self.container = container_name
    
    def is_ready(self) -> bool:
        result = subprocess.run(
            ["docker", "exec", self.container, "test", "-f", "/etc/hostname"],
            capture_output=True
        )
        return result.returncode == 0
    
    def execute(self, command: str) -> Dict:
        result = subprocess.run(
            ["docker", "exec", self.container, "sh", "-c", command],
            capture_output=True,
            text=True
        )
        return {
            "success": result.returncode == 0,
            "stdout": result.stdout,
            "stderr": result.stderr
        }
    
    def get_status(self) -> Dict:
        result = subprocess.run(
            ["docker", "ps", "--filter", f"name={self.container}", "--format", "{{.Status}}"],
            capture_output=True,
            text=True
        )
        return {"status": result.stdout.strip()}

class LibvirtGuestController(GuestController):
    def __init__(self, domain_name="gnu-hurd"):
        self.domain = domain_name
    
    def is_ready(self) -> bool:
        result = subprocess.run(
            ["virsh", "dominfo", self.domain],
            capture_output=True
        )
        return result.returncode == 0
    
    def execute(self, command: str) -> Dict:
        # Via serial console
        result = subprocess.run(
            f"echo '{command}' | nc -q 2 localhost 5555",
            shell=True,
            capture_output=True,
            text=True
        )
        return {
            "success": result.returncode == 0,
            "stdout": result.stdout,
            "stderr": result.stderr
        }
    
    def get_status(self) -> Dict:
        result = subprocess.run(
            ["virsh", "dominfo", self.domain],
            capture_output=True,
            text=True
        )
        return {"status": result.stdout.strip()}

class UnifiedGuestController:
    """Single interface for all backends"""
    
    def __init__(self, backend: Backend, **kwargs):
        if backend == Backend.DOCKER:
            self.controller = DockerGuestController(**kwargs)
        elif backend == Backend.PODMAN:
            self.controller = PodmanGuestController(**kwargs)
        elif backend == Backend.LIBVIRT:
            self.controller = LibvirtGuestController(**kwargs)
    
    def run_test_suite(self) -> Dict:
        """Run tests across any backend"""
        tests = [
            ("System info", "uname -a"),
            ("Hostname", "hostname"),
            ("Disk usage", "df -h"),
        ]
        
        results = {}
        for name, cmd in tests:
            result = self.controller.execute(cmd)
            results[name] = result
        
        return results

# Usage - same code works for Docker, Podman, Libvirt
docker_controller = UnifiedGuestController(Backend.DOCKER)
docker_results = docker_controller.run_test_suite()

podman_controller = UnifiedGuestController(Backend.PODMAN)
podman_results = podman_controller.run_test_suite()

libvirt_controller = UnifiedGuestController(Backend.LIBVIRT)
libvirt_results = libvirt_controller.run_test_suite()
```

---

## Part 5: Expect-Based Serial Console Automation

### Using expect for Interactive Serial Sessions

```expect
#!/usr/bin/expect
# Serial console interactive automation

set timeout 10
set host "localhost"
set port 5555

# Connect to serial console
spawn telnet $host $port

# Wait for boot to complete
expect {
    "login:" {
        send "root\r"
        exp_continue
    }
    "password:" {
        send "root\r"
        exp_continue
    }
    "#" {
        send "id\r"
        expect "#"
        send "hostname\r"
        expect "#"
        send "exit\r"
    }
    timeout {
        puts "TIMEOUT waiting for prompt"
        exit 1
    }
}
```

---

## Comparison: All Methods

| Method | Setup | Performance | Reliability | Best For |
|--------|-------|-------------|-------------|----------|
| SSH | Complex | Fast | Excellent | Normal operations |
| Serial Console | Simple | Slow | Good | Fallback/debugging |
| HTTP API | Medium | Fast | Good | Structured tests |
| File Exchange | Simple | Slow | Moderate | Simple commands |
| Expect | Medium | Medium | Good | Interactive testing |
| Docker Exec | N/A | Very fast | Excellent | Container-level |

---

## Recommended Approach for LLM Testing

**Priority Order:**

1. **Try SSH** (fastest, most reliable if available)
2. **Fall back to Serial Console** (always available, slower)
3. **Use HTTP API** (if guest has Python/HTTP server)
4. **Use File Exchange** (last resort, most universal)

**Implementation Strategy:**

```python
class LLMGuestTester:
    def __init__(self, backend: Backend):
        self.backend = backend
        self.controller = UnifiedGuestController(backend)
    
    def execute_with_fallback(self, command: str) -> Dict:
        """Try multiple methods in order"""
        
        # Try 1: Direct exec (if Docker/Podman)
        if isinstance(self.controller.controller, (DockerGuestController, PodmanGuestController)):
            try:
                return self.controller.execute(command)
            except:
                pass
        
        # Try 2: SSH
        try:
            result = subprocess.run(
                ["ssh", "-p", "2222", "root@127.0.0.1", command],
                capture_output=True,
                timeout=10
            )
            return {"success": result.returncode == 0, "stdout": result.stdout.decode()}
        except:
            pass
        
        # Try 3: HTTP API
        try:
            return requests.post("http://127.0.0.1:8080/api/execute",
                                json={"command": command}).json()
        except:
            pass
        
        # Try 4: Serial Console
        try:
            return self.serial_execute(command)
        except:
            pass
        
        # Try 5: File exchange
        return self.file_exchange_execute(command)
```

---

## Testing Checklist for LLM Control

- [ ] Serial console connection established
- [ ] Serial command execution working (basic id/hostname)
- [ ] Guest response parsing implemented
- [ ] Error handling for timeouts
- [ ] Fallback method configured
- [ ] Test suite runs end-to-end
- [ ] Results logged and parsed
- [ ] Multi-backend switching tested
- [ ] Performance baselines recorded

---

**Last Updated**: 2026-01-15
**Status**: Ready for implementation
**Difficulty**: Intermediate (serial) to Advanced (full framework)

