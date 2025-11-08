#!/usr/bin/env python3
"""
QMP Helper Script - QEMU Machine Protocol Control

This script provides a simple interface to QEMU's QMP (QEMU Machine Protocol)
for controlling and querying QEMU virtual machines.

Usage:
    echo '{"execute":"query-status"}' | python3 qmp-helper.py
    echo '{"execute":"stop"}' | python3 qmp-helper.py

Environment Variables:
    QMP_SOCKET - Path to QMP socket (default: vm/qmp/qmp.sock)
    QMP_TIMEOUT - Connection timeout in seconds (default: 5)
"""

import json
import socket
import sys
import os
from typing import Dict, Any, Optional


class QMPClient:
    """QEMU Machine Protocol Client"""

    def __init__(self, socket_path: str, timeout: int = 5):
        """
        Initialize QMP client

        Args:
            socket_path: Path to QMP Unix socket
            timeout: Connection timeout in seconds
        """
        self.socket_path = socket_path
        self.timeout = timeout
        self.sock: Optional[socket.socket] = None

    def connect(self) -> None:
        """Connect to QMP socket and perform handshake"""
        try:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(self.timeout)
            self.sock.connect(self.socket_path)

            # Receive greeting
            greeting = self._receive()
            if "QMP" not in greeting:
                raise RuntimeError(f"Invalid QMP greeting: {greeting}")

            # Send capabilities negotiation
            self._send({"execute": "qmp_capabilities"})
            response = self._receive()

            if "error" in response:
                raise RuntimeError(f"QMP capabilities failed: {response['error']}")

        except socket.timeout:
            raise RuntimeError(f"Connection timeout: {self.socket_path}")
        except FileNotFoundError:
            raise RuntimeError(f"Socket not found: {self.socket_path}")
        except PermissionError:
            raise RuntimeError(f"Permission denied: {self.socket_path}")

    def _send(self, command: Dict[str, Any]) -> None:
        """Send command to QMP socket"""
        if not self.sock:
            raise RuntimeError("Not connected")

        data = json.dumps(command) + "\n"
        self.sock.sendall(data.encode())

    def _receive(self, buffer_size: int = 65536) -> Dict[str, Any]:
        """Receive response from QMP socket"""
        if not self.sock:
            raise RuntimeError("Not connected")

        data = self.sock.recv(buffer_size)
        if not data:
            raise RuntimeError("Connection closed by peer")

        # QMP responses may be multi-line; handle the first complete JSON object
        response_str = data.decode().strip()

        # Handle multiple JSON objects (events + response)
        lines = response_str.split("\n")
        for line in lines:
            if line.strip():
                try:
                    obj = json.loads(line)
                    # Return first non-event response
                    if "return" in obj or "error" in obj:
                        return obj
                    # If it's an event, continue to next line
                    if "event" in obj:
                        continue
                    # Otherwise, it's the greeting or a valid response
                    return obj
                except json.JSONDecodeError:
                    continue

        # If we only got events, return the last valid JSON
        for line in reversed(lines):
            if line.strip():
                try:
                    return json.loads(line)
                except json.JSONDecodeError:
                    continue

        raise RuntimeError(f"No valid JSON in response: {response_str}")

    def execute(self, command: Dict[str, Any]) -> Dict[str, Any]:
        """
        Execute QMP command and return response

        Args:
            command: QMP command dict with 'execute' key

        Returns:
            Response dict with 'return' or 'error' key
        """
        self._send(command)
        return self._receive()

    def close(self) -> None:
        """Close QMP connection"""
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
            finally:
                self.sock = None


def format_output(response: Dict[str, Any], pretty: bool = True) -> str:
    """
    Format QMP response for output

    Args:
        response: QMP response dict
        pretty: Use pretty-printing

    Returns:
        Formatted JSON string
    """
    if pretty:
        return json.dumps(response, indent=2, sort_keys=True)
    else:
        return json.dumps(response)


def main() -> int:
    """Main entry point"""
    # Configuration
    socket_path = os.getenv("QMP_SOCKET", "vm/qmp/qmp.sock")
    timeout = int(os.getenv("QMP_TIMEOUT", "5"))
    pretty = os.getenv("QMP_PRETTY", "1") == "1"

    # Read command from stdin
    try:
        command_str = sys.stdin.read().strip()
        if not command_str:
            print("Error: No command provided on stdin", file=sys.stderr)
            print(
                'Usage: echo \'{"execute":"query-status"}\' | python3 qmp-helper.py',
                file=sys.stderr,
            )
            return 1

        # Parse command
        try:
            command = json.loads(command_str)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON: {e}", file=sys.stderr)
            return 1

        # Validate command structure
        if "execute" not in command:
            print("Error: Command must have 'execute' key", file=sys.stderr)
            return 1

        # Connect and execute
        client = QMPClient(socket_path, timeout)
        try:
            client.connect()
            response = client.execute(command)

            # Output response
            print(format_output(response, pretty))

            # Return appropriate exit code
            if "error" in response:
                return 1
            else:
                return 0

        finally:
            client.close()

    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        return 130
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
