# GNU/Hurd Development Environment Guide

**Last Updated**: 2025-11-16
**Purpose**: Complete guide to setting up a Hurd development workstation
**Audience**: Kernel developers, microkernel researchers, systems programmers
**Scope**: MIG, GNU Mach, Hurd servers, Rust/LLVM toolchain

---

## Table of Contents

1. [Overview](#overview)
2. [Development Tools Installation](#development-tools-installation)
3. [MIG (Mach Interface Generator)](#mig-mach-interface-generator)
4. [Building GNU Mach](#building-gnu-mach)
5. [Building Hurd Servers](#building-hurd-servers)
6. [Rust and LLVM Support](#rust-and-llvm-support)
7. [Debugging Tools](#debugging-tools)
8. [Source Code Access](#source-code-access)
9. [Development Workflows](#development-workflows)
10. [References](#references)

---

## Overview

Debian GNU/Hurd 2025 provides a complete development environment for:

- **GNU Mach Microkernel** - Kernel development and debugging
- **Hurd Servers** - User-space server implementation
- **Translators** - Filesystem extension development
- **Glibc (Hurd)** - C library with Hurd-specific features
- **Modern Toolchains** - Rust, LLVM, Clang, GCC

### Why Develop on Hurd?

1. **Microkernel Research**: Study and modify real microkernel implementation
2. **User-Space Servers**: Implement OS services without kernel privileges
3. **Capability-Based Security**: Explore capability-based access control
4. **Translator Development**: Extend filesystem with user-space code
5. **Educational Value**: Understand OS design beyond monolithic kernels

---

## Development Tools Installation

### Essential Build Tools

```bash
# Update package lists
sudo apt update

# Install core development tools
sudo apt install \
    build-essential \
    git \
    pkg-config \
    autoconf \
    automake \
    libtool \
    bison \
    flex \
    texinfo \
    gdb \
    vim \
    emacs

# Install MIG (Mach Interface Generator)
sudo apt install mig

# Verify installation
mig --version
gcc --version
make --version
```

### Modern Toolchains

#### Rust and Cargo

Hurd 2025 includes **official Rust support** (since LLVM 8.0):

```bash
# Install Rust toolchain
sudo apt install rustc cargo

# Verify Rust installation
rustc --version
cargo --version

# Install additional Rust tools
sudo apt install \
    rust-clippy \
    rust-src \
    rustfmt
```

#### LLVM and Clang

```bash
# Install LLVM/Clang toolchain
sudo apt install \
    clang \
    llvm \
    lld \
    lldb

# Verify installation
clang --version
llvm-config --version
```

### Source Code Management

```bash
# Install Git and related tools
sudo apt install git git-buildpackage

# Configure Git
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

---

## MIG (Mach Interface Generator)

**MIG** generates RPC stub code from `.defs` interface definition files. It's essential for Mach and Hurd development.

### What is MIG?

MIG compiles interface definitions into:
- **Client stubs**: Functions to call remote procedures
- **Server stubs**: Dispatch code to handle RPC requests

### Installation

```bash
# Install MIG
sudo apt install mig

# On x86_64, this provides mig-x86_64-gnu
which mig
# Output: /usr/bin/mig
```

### Basic MIG Usage

**Example**: Simple RPC interface

Create `hello.defs`:

```c
subsystem hello 1000;

#include <mach/std_types.defs>

routine say_hello(
    server_port : mach_port_t;
    name : data_t);

routine get_greeting(
    server_port : mach_port_t;
out greeting : data_t);
```

**Generate stubs**:

```bash
mig hello.defs
```

**Output files**:
- `helloUser.c` - Client-side stubs
- `helloServer.c` - Server-side stubs
- `hello.h` - Shared header

### MIG in GNU Mach

Example from Mach source:

```bash
# Clone Mach sources
git clone https://git.savannah.gnu.org/git/hurd/gnumach.git
cd gnumach

# See .defs files
ls include/mach/*.defs
# mach.defs, mach_host.defs, memory_object.defs, etc.
```

MIG processes these during build to generate RPC infrastructure.

---

## Building GNU Mach

### Fetching Sources

#### Option 1: Official Git Repository

```bash
# Clone GNU Mach
git clone https://git.savannah.gnu.org/git/hurd/gnumach.git
cd gnumach

# Check out latest stable branch
git checkout master
```

#### Option 2: Debian Source Package

```bash
# Download Debian source
apt source gnumach

# Extract and enter directory
cd gnumach-*/
```

### Build Dependencies

```bash
# Install Mach build dependencies
sudo apt build-dep gnumach

# Additional dependencies
sudo apt install \
    mig \
    texinfo \
    bison \
    flex \
    libncurses-dev
```

### Standard Build (Single CPU)

```bash
# Prepare build
autoreconf -i
mkdir build && cd build

# Configure (standard build)
../configure \
    --prefix=/usr \
    --enable-kdb

# Build
make -j$(nproc)

# Generate compressed kernel
make gnumach.gz
```

**Output**: `gnumach.gz` - Bootable Mach kernel

### SMP Build (Multi-CPU Experimental)

To enable **experimental SMP support**:

```bash
# Configure with SMP options
../configure \
    --enable-ncpus=4 \
    --enable-apic \
    --enable-kdb \
    --disable-linux-groups

# Build
make -j$(nproc) gnumach.gz
```

**Configuration options**:
- `--enable-ncpus=N` - Support for N CPUs (default 1)
- `--enable-apic` - Enable APIC for multiprocessor systems
- `--enable-kdb` - Enable built-in kernel debugger
- `--disable-linux-groups` - Use NetBSD Rump drivers (not Linux)

**Warning**: SMP support is experimental. Systems with >2 CPUs may be unstable.

### Installing Custom Kernel

```bash
# Backup original kernel
sudo cp /boot/gnumach-1.8-486.gz /boot/gnumach-1.8-486.gz.bak

# Install new kernel
sudo cp gnumach.gz /boot/gnumach-1.8-486.gz

# Reboot to test
sudo reboot
```

**Important**: If using Rump drivers, device names change from `hd0` to `wd0`. Update:
- GRUB config: `/boot/grub/grub.cfg`
- Fstab: `/etc/fstab`

Example fstab change:

```bash
# Old (IDE naming)
/dev/hd0s1  /  ext2  defaults  0  1

# New (NetBSD Rump naming)
/dev/wd0s1  /  ext2  defaults  0  1
```

---

## Building Hurd Servers

### Fetching Hurd Sources

```bash
# Official Git repository
git clone https://git.savannah.gnu.org/git/hurd/hurd.git
cd hurd

# Or Debian source
apt source hurd
cd hurd-*/
```

### Build Dependencies

```bash
# Install Hurd build dependencies
sudo apt build-dep hurd

# Additional tools
sudo apt install \
    mig \
    autoconf \
    automake \
    libtool \
    libparted-dev \
    libstore-dev
```

### Build Process

```bash
# Prepare build
autoreconf -i
mkdir build && cd build

# Configure
../configure --prefix=/usr

# Build
make -j$(nproc)

# Install (optional - be careful!)
sudo make install
```

**Warning**: Installing system-wide can break your system. Test individual servers instead.

### Building Individual Servers

Example: Build `ext2fs` translator:

```bash
cd hurd/ext2fs

# Build single translator
make ext2fs

# Test it (as root)
sudo ./ext2fs --help
```

### Testing Translators

**Safe testing** (without system-wide install):

```bash
# Create test mount point
mkdir /tmp/testfs

# Run translator manually
settrans /tmp/testfs $PWD/build/ext2fs /path/to/disk.img

# Use it
ls /tmp/testfs

# Remove when done
settrans -g /tmp/testfs
```

---

## Rust and LLVM Support

### Why Rust on Hurd?

- **Memory Safety**: Prevents common kernel bugs
- **Modern Tooling**: Better than C for complex projects
- **LLVM Backend**: Full LLVM optimization pipeline
- **Concurrency**: Fearless concurrency for parallel servers

### Rust Installation

```bash
# Install Rust toolchain
sudo apt install \
    rustc \
    cargo \
    rust-clippy \
    rustfmt

# Verify
rustc --version
# Output: rustc 1.xx.x (running on hurd-amd64)
```

### Hello World in Rust

```rust
// hello.rs
fn main() {
    println!("Hello from Rust on GNU/Hurd!");
}
```

Compile and run:

```bash
rustc hello.rs
./hello
```

### Rust FFI with Mach

Example: Call Mach kernel functions from Rust:

```rust
// mach_ffi.rs
use std::ffi::c_void;

extern "C" {
    fn mach_task_self() -> u32;
    fn mach_port_allocate(
        task: u32,
        right: u32,
        port: *mut u32
    ) -> i32;
}

fn main() {
    unsafe {
        let task = mach_task_self();
        println!("Task port: {}", task);

        let mut port: u32 = 0;
        let result = mach_port_allocate(task, 1, &mut port);
        println!("Allocated port: {} (result: {})", port, result);
    }
}
```

Compile with Mach libraries:

```bash
rustc mach_ffi.rs -L /usr/lib/x86_64-gnu -l mach
./mach_ffi
```

### LLVM Tools

```bash
# Install LLVM toolchain
sudo apt install \
    clang \
    llvm \
    lld \
    lldb

# Use Clang to compile
clang -o hello hello.c

# Use LLDB for debugging
lldb ./hello
```

---

## Debugging Tools

### GDB for User-Space

Standard GDB works for user-space programs:

```bash
# Install GDB
sudo apt install gdb

# Debug a program
gdb ./myprogram

# Common GDB commands
(gdb) break main
(gdb) run
(gdb) next
(gdb) print variable
(gdb) backtrace
```

### Debugging Translators

Translators are user-space processes:

```bash
# Find translator PID
ps aux | grep ftpfs

# Attach GDB to running translator
sudo gdb -p <pid>

# Set breakpoints, inspect state
(gdb) break trivfs_S_io_read
(gdb) continue
```

### Kernel Debugging (KDB)

If you built Mach with `--enable-kdb`:

**Serial console method**:

1. Boot with serial output:
   ```bash
   # In QEMU
   qemu-system-x86_64 \
       -kernel gnumach.gz \
       -serial stdio \
       -append "--console=com0"
   ```

2. Break into KDB:
   - Press key combo (often Ctrl+Alt+D)
   - Or trigger from crash

3. KDB commands:
   ```
   db> show registers
   db> trace
   db> examine <address>
   db> continue
   ```

**GDB remote debugging**:

```bash
# Start QEMU with GDB stub
qemu-system-x86_64 \
    -kernel gnumach.gz \
    -s -S

# In another terminal, connect GDB
gdb gnumach
(gdb) target remote :1234
(gdb) break gnumach_main
(gdb) continue
```

### RPC Tracing

Hurd provides `trace` for RPC debugging:

```bash
# Install trace utility
sudo apt install hurd

# Trace a program's RPCs
trace ls /tmp

# Trace with details
trace -o rpc.log myprogram
```

### Performance Profiling

```bash
# Install profiling tools
sudo apt install \
    valgrind \
    perf-tools-unstable

# Profile with valgrind
valgrind --tool=callgrind ./myprogram

# Analyze results
callgrind_annotate callgrind.out.*
```

---

## Source Code Access

### Official Repositories

```bash
# GNU Mach kernel
git clone https://git.savannah.gnu.org/git/hurd/gnumach.git

# GNU Hurd servers
git clone https://git.savannah.gnu.org/git/hurd/hurd.git

# Glibc (Hurd port)
git clone https://sourceware.org/git/glibc.git
```

### Debian Packaging

```bash
# Get Debian source packages
apt source gnumach
apt source hurd
apt source glibc

# Install build dependencies
sudo apt build-dep gnumach hurd glibc
```

### Browsing Source Online

- **GNU Mach**: https://git.savannah.gnu.org/cgit/hurd/gnumach.git
- **GNU Hurd**: https://git.savannah.gnu.org/cgit/hurd/hurd.git
- **Glibc**: https://sourceware.org/git/glibc.git

---

## Development Workflows

### Workflow 1: Kernel Development

```bash
# 1. Clone and build Mach
git clone https://git.savannah.gnu.org/git/hurd/gnumach.git
cd gnumach
autoreconf -i && mkdir build && cd build
../configure --enable-kdb
make -j$(nproc) gnumach.gz

# 2. Install to test VM
scp gnumach.gz root@hurd-vm:/boot/gnumach-test.gz

# 3. Update GRUB on VM
ssh root@hurd-vm
grub-editenv /boot/grub/grubenv set saved_entry="GNU with test kernel"
reboot

# 4. Test and debug
# (boot VM, test changes, check logs)

# 5. Iterate
```

### Workflow 2: Translator Development

```bash
# 1. Get Hurd sources
git clone https://git.savannah.gnu.org/git/hurd/hurd.git
cd hurd

# 2. Create new translator (or modify existing)
cd trans
cp hello.c myhello.c
# Edit myhello.c

# 3. Build
make myhello

# 4. Test locally (no install)
settrans /tmp/test ./myhello
cat /tmp/test

# 5. Debug with GDB
gdb ./myhello
(gdb) run <args>

# 6. Clean up
settrans -g /tmp/test
```

### Workflow 3: Rust Development

```bash
# 1. Create Rust project
cargo new hurd-tool
cd hurd-tool

# 2. Add Mach FFI bindings
# Edit src/main.rs with extern "C" declarations

# 3. Build
cargo build

# 4. Run
cargo run

# 5. Test
cargo test

# 6. Release build
cargo build --release
```

---

## Example Projects

### Project 1: Custom Translator

Create a translator that returns system info:

```c
// sysinfo.c - Simple translator returning system info
#include <hurd/trivfs.h>
#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>

static char *content = NULL;

error_t trivfs_S_io_read(
    struct trivfs_protid *cred,
    mach_port_t reply,
    mach_msg_type_name_t reply_type,
    data_t *data,
    mach_msg_type_number_t *data_len,
    loff_t offs,
    mach_msg_type_number_t amount)
{
    struct utsname uts;
    uname(&uts);

    if (!content) {
        asprintf(&content, "System: %s\nRelease: %s\n",
                 uts.sysname, uts.release);
    }

    size_t len = strlen(content);
    if (offs >= len) {
        *data_len = 0;
        return 0;
    }

    size_t n = len - offs;
    if (n > amount) n = amount;

    *data = malloc(n);
    memcpy(*data, content + offs, n);
    *data_len = n;

    return 0;
}

// ... (implement other trivfs callbacks)
```

Compile and test:

```bash
gcc -o sysinfo sysinfo.c -ltrivfs
settrans /tmp/sysinfo ./sysinfo
cat /tmp/sysinfo
```

### Project 2: Mach Kernel Module

Add custom syscall to Mach (simplified):

1. Define interface in `.defs` file
2. Implement in kernel C code
3. Rebuild kernel
4. Write user-space client

---

## References

### Official Documentation

- **Hurd Hacking Guide**: https://www.gnu.org/software/hurd/hurd/hacking_guide.html
- **MIG Manual**: https://www.gnu.org/software/hurd/microkernel/mach/mig.html
- **Translator Writing**: https://www.gnu.org/software/hurd/hurd/translator/writing.html
- **GNU Mach**: https://www.gnu.org/software/hurd/microkernel/mach/gnumach.html

### Source Code

- **GNU Mach Git**: https://git.savannah.gnu.org/git/hurd/gnumach.git
- **GNU Hurd Git**: https://git.savannah.gnu.org/git/hurd/hurd.git
- **Glibc Git**: https://sourceware.org/git/glibc.git

### Community

- **Mailing Lists**: bug-hurd@gnu.org, debian-hurd@lists.debian.org
- **IRC**: #hurd on Freenet, #debian-hurd on OFTC
- **Bug Tracker**: https://savannah.gnu.org/bugs/?group=hurd

---

## Quick Reference

```bash
# Development tools
sudo apt install build-essential mig git gdb rustc cargo clang

# Get sources
git clone https://git.savannah.gnu.org/git/hurd/gnumach.git
git clone https://git.savannah.gnu.org/git/hurd/hurd.git

# Build Mach
cd gnumach
autoreconf -i && mkdir build && cd build
../configure --enable-kdb --enable-ncpus=4 --enable-apic
make -j$(nproc) gnumach.gz

# Build Hurd
cd hurd
autoreconf -i && mkdir build && cd build
../configure
make -j$(nproc)

# Rust development
cargo new hurd-project
cargo build --release

# Debugging
gdb ./program
trace ./program
```

---

## See Also

- [TRANSLATORS.md](../04-OPERATION/TRANSLATORS.md) - Translator guide
- [GUI-SETUP.md](../04-OPERATION/GUI-SETUP.md) - Desktop environment
- [OVERVIEW.md](../02-ARCHITECTURE/OVERVIEW.md) - System architecture
- [MACH-QEMU-RESEARCH.md](MACH-QEMU-RESEARCH.md) - Mach research notes

---

**Ready to hack the Hurd!** With MIG, GCC, Rust, and LLVM, you have a complete modern toolchain for microkernel development.
