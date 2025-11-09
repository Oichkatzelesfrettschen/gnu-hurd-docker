# MCP Servers for GNU Hurd Development

This document describes the MCP (Model Context Protocol) servers installed for QEMU/KVM and GDB debugging support.

## Installed MCP Servers

### 1. KVM Control MCP Server
**Purpose**: QEMU/KVM virtual machine management through libvirt

**Location**: `~/.local/share/kvm-mcp/`

**Features**:
- VM lifecycle management (create, start, stop, reboot, delete)
- Network management (bridge configuration, IP tracking)
- Storage management (disk creation, qcow2 support)
- Display management (VNC access, port assignment)
- Installation support (ISO, CDROM, network install)
- Performance optimizations (connection pooling, caching)

**Configuration** (in `~/.claude/.mcp.json`):
```json
"kvm-control": {
  "command": "/home/eirikr/.local/share/kvm-mcp/.venv/bin/python",
  "args": ["/home/eirikr/.local/share/kvm-mcp/kvm_mcp/server.py"],
  "cwd": "/home/eirikr/.local/share/kvm-mcp",
  "env": {
    "VM_DISK_PATH": "/home/eirikr/Playground/gnu-hurd-docker",
    "VM_DEFAULT_NETWORK": "virbr0"
  }
}
```

**Source**: https://github.com/steveydevey/kvm-mcp

### 2. GDB Debugger MCP Server
**Purpose**: GDB debugging capabilities for kernel and application debugging

**Location**: `~/bin/mcp-server-gdb`

**Features**:
- Create and manage multiple GDB debug sessions
- Set and manage breakpoints
- View stack frames and variables
- Control program execution (run, pause, step, next)
- Support for concurrent multi-session debugging
- Read memory contents and registers
- Built-in TUI for inspecting agent behaviors

**Configuration** (in `~/.claude/.mcp.json`):
```json
"gdb-debugger": {
  "command": "/home/eirikr/bin/mcp-server-gdb",
  "args": []
}
```

**Source**: https://github.com/pansila/mcp_server_gdb

## Usage for GNU Hurd Development

### QEMU VM Management
The KVM Control server can be used to:
- List running GNU Hurd VMs
- Start/stop the Hurd VM
- Access VNC display
- Monitor VM resource usage
- Manage VM networking

### Kernel Debugging
The GDB server can be used to:
- Debug GNU Hurd kernel (gnumach) via QEMU's GDB stub
- Set breakpoints in kernel code
- Inspect kernel memory and registers
- Step through kernel execution
- Manage multiple debug sessions (kernel + user processes)

## Testing

### Test KVM Server
```bash
# Ensure libvirtd is running
sudo systemctl start libvirtd

# The server will be available via Claude Code's MCP interface
# You can ask Claude to list VMs, start VMs, etc.
```

### Test GDB Server
```bash
# Test the binary
~/bin/mcp-server-gdb --help

# The server will be available via Claude Code's MCP interface
# You can ask Claude to create debug sessions, set breakpoints, etc.
```

## Prerequisites

### For KVM Control Server
- libvirt and qemu-kvm installed
- libvirtd service running
- User in libvirt group: `sudo usermod -a -G libvirt $USER`
- Network bridge configured (default: virbr0)

### For GDB Server
- gdb installed
- For remote debugging: QEMU with `-gdb tcp::1234` flag
- Debug symbols in binaries being debugged

## Integration with GNU Hurd QEMU Setup

The current GNU Hurd QEMU setup can be enhanced with these tools:

1. **VM Management**: Use KVM Control to manage the Hurd VM instead of manual QEMU commands
2. **Kernel Debugging**: Use GDB Server to debug gnumach kernel via QEMU's GDB stub
3. **Combined Workflow**: Start VM with KVM Control, attach GDB Server for debugging

## Example Workflows

### Starting Hurd VM with KVM Control
```
User: "Start the GNU Hurd VM"
Claude: [Uses KVM Control MCP server to start VM]
```

### Debugging Hurd Kernel
```
User: "Set a breakpoint in gnumach at boot_script_exec"
Claude: [Uses GDB Server MCP to create session and set breakpoint]
```

### Combined: Boot and Debug
```
User: "Start the Hurd VM with GDB debugging enabled"
Claude:
1. [Uses KVM Control to start VM with -gdb tcp::1234]
2. [Uses GDB Server to attach to localhost:1234]
3. [Sets initial breakpoints as needed]
```

## Troubleshooting

### KVM Control Issues
- Verify libvirtd is running: `systemctl status libvirtd`
- Check libvirt permissions: `groups | grep libvirt`
- Verify Python dependencies: `~/.local/share/kvm-mcp/.venv/bin/pip list`

### GDB Server Issues
- Verify GDB is installed: `which gdb`
- Test binary directly: `~/bin/mcp-server-gdb --help`
- Check logs in Claude Code MCP settings

## Future Enhancements

Potential improvements:
1. Custom scripts to integrate with existing `scripts/` directory
2. Automated Hurd VM provisioning via KVM Control
3. Pre-configured GDB sessions for common debugging tasks
4. Integration with CI/CD workflows for automated testing
5. Support for multiple Hurd VMs (different configurations)

## References

- MCP Protocol: https://modelcontextprotocol.io/
- KVM/libvirt docs: https://libvirt.org/
- GDB/MI Protocol: https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI.html
- GNU Hurd debugging: https://www.gnu.org/software/hurd/debugging.html
