# GNU/Hurd Translators Guide

**Last Updated**: 2025-11-16
**Source**: Official Debian GNU/Hurd 2025 README and GNU Hurd documentation
**Purpose**: Introduction to Hurd's powerful translator filesystem
**Audience**: Developers and system administrators exploring Hurd capabilities

---

## Table of Contents

1. [What are Translators?](#what-are-translators)
2. [Basic Translator Operations](#basic-translator-operations)
3. [Translator Examples](#translator-examples)
4. [Common Translators](#common-translators)
5. [Advanced Usage](#advanced-usage)
6. [Practical Applications](#practical-applications)
7. [References](#references)

---

## What are Translators?

**Translators** are one of the most unique and powerful features of GNU/Hurd. They are user-space servers that implement filesystem interfaces, allowing any user to extend the filesystem with custom behavior.

### Key Concepts

- **User-Space Servers**: Translators run as normal processes, not kernel code
- **Filesystem Extension**: Any user can mount translators on nodes they own
- **Dynamic**: Can be attached/removed at runtime without rebooting
- **Flexible**: Can chain translators for complex functionality
- **Powerful**: Enable features impossible in traditional Unix systems

### Why Translators Matter

Traditional Unix requires root privileges and kernel modules to extend filesystem behavior. Hurd allows **any user** to create filesystem services using translators.

**Examples**:
- Mount FTP sites as directories (as normal user!)
- Create virtual filesystems with custom logic
- Implement network protocols as filesystem operations
- Stack translators for complex pipelines

---

## Basic Translator Operations

### Essential Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `settrans` | Set/attach a translator to a node | `settrans hello /hurd/hello` |
| `showtrans` | Show active translator on a node | `showtrans hello` |
| `fsysopts` | View/modify translator options | `fsysopts hello` |
| `settrans -g` | Remove translator (go away) | `settrans -g hello` |

### Command Options

```bash
# Set translator (create passive + active)
settrans <node> <translator> [args...]

# Create passive only (no active instance)
settrans -c <node> <translator> [args...]

# Start active translator immediately
settrans -a <node> <translator> [args...]

# Remove translator and kill active instance
settrans -g <node>

# Force removal (even if translator is busy)
settrans -fg <node>
```

---

## Translator Examples

### Example 1: Hello World Translator

The simplest translator - demonstrates basic concepts.

**Step-by-step:**

```bash
# 1. Create an empty file/node
touch hello

# 2. Verify it's empty
cat hello
# (no output - file is empty)

# 3. Attach the hello translator
settrans hello /hurd/hello

# 4. Read the file - translator now responds!
cat hello
# Output: Hello World!

# 5. Check translator options
fsysopts hello
# Output: /hurd/hello --contents='Hello World!\n'

# 6. Modify the translator's output
fsysopts hello --contents='Hello GNU!\n'

# 7. Read again - content changed!
cat hello
# Output: Hello GNU!

# 8. Remove the translator
settrans -g hello

# 9. Verify file is empty again
cat hello
# (no output - translator removed)
```

**What happened?**
- The file `hello` became a **node** with an attached translator
- The `/hurd/hello` translator responds to read requests
- We changed the translator's behavior at runtime
- Removing the translator restored the original empty file

---

### Example 2: Transparent FTP Access

Mount FTP sites as local directories - **as a normal user**!

**Setup:**

```bash
# Create a node for FTP access
settrans -c ftp: /hurd/hostmux /hurd/ftpfs /
```

**What this does:**
- `ftp:` - The node (directory) where FTP sites appear
- `/hurd/hostmux` - Multiplexer translator (handles multiple hosts)
- `/hurd/ftpfs` - FTP filesystem translator
- `/` - Root path on FTP servers

**Usage:**

```bash
# Browse GNU FTP server
ls ftp://ftp.gnu.org/

# List Hurd releases
ls ftp://ftp.gnu.org/gnu/hurd/

# Read a file directly from FTP
cat ftp://ftp.gnu.org/README

# Copy file from FTP
cp ftp://ftp.gnu.org/gnu/hurd/hurd-0.9.tar.gz ~/downloads/

# Access different FTP servers
ls ftp://ftp.debian.org/debian/
ls ftp://mirrors.kernel.org/gnu/
```

**No mounting as root required!** Any user can access FTP sites as filesystems.

---

### Example 3: Mount Remote ISO File

Combine FTP + ISO9660 translators to mount remote ISO images.

**Step-by-step:**

```bash
# 1. Create mount point
mkdir mnt

# 2. Mount remote ISO via FTP
settrans -c mnt /hurd/iso9660fs \
  $PWD/ftp://ftp.gnu.org/old-gnu/gnu-f2/hurd-F2-main.iso

# 3. Browse the ISO contents
ls mnt/

# 4. Read files from the ISO
cat mnt/README
```

**What happened?**
- `ftpfs` translator fetches ISO file from FTP server
- `iso9660fs` translator reads ISO9660 filesystem format
- FTP only downloads **requested blocks** (not entire ISO!)
- Combined translators create transparent remote ISO access

**Unmount:**

```bash
settrans -g mnt
```

---

### Example 4: HTTP Access

Similar to FTP, but for HTTP/HTTPS servers.

```bash
# Setup HTTP translator
settrans -c http: /hurd/hostmux /hurd/httpfs --proxy=<proxy-host:port> /

# Access web servers as directories
ls http://www.gnu.org/
cat http://www.gnu.org/robots.txt
```

---

## Common Translators

### Filesystem Translators

| Translator | Purpose | Example |
|------------|---------|---------|
| `/hurd/ext2fs` | ext2 filesystem | `settrans /mnt /hurd/ext2fs /dev/hd0s1` |
| `/hurd/iso9660fs` | ISO9660 CD/DVD filesystem | `settrans /cdrom /hurd/iso9660fs /dev/cd0` |
| `/hurd/fatfs` | FAT filesystem | `settrans /usb /hurd/fatfs /dev/sd0s1` |
| `/hurd/tmpfs` | RAM-based temporary filesystem | `settrans /tmp /hurd/tmpfs 100M` |
| `/hurd/unionfs` | Union of multiple filesystems | `settrans /union /hurd/unionfs /dir1 /dir2` |

### Network Translators

| Translator | Purpose | Example |
|------------|---------|---------|
| `/hurd/ftpfs` | FTP filesystem | See Example 2 above |
| `/hurd/httpfs` | HTTP filesystem | See Example 4 above |
| `/hurd/socketio` | Socket I/O redirection | Advanced networking |

### Device Translators

| Translator | Purpose | Example |
|------------|---------|---------|
| `/hurd/null` | Null device (discards all data) | `settrans /dev/null /hurd/null` |
| `/hurd/zero` | Zero device (infinite zeros) | `settrans /dev/zero /hurd/zero` |
| `/hurd/random` | Random number generator | `settrans /dev/random /hurd/random` |
| `/hurd/storeio` | Block device access | Device I/O operations |

### Special Purpose Translators

| Translator | Purpose | Example |
|------------|---------|---------|
| `/hurd/hello` | Hello world (demo) | See Example 1 above |
| `/hurd/magic` | Magic translator (lookup) | Advanced path resolution |
| `/hurd/symlink` | Symbolic link | `settrans link /hurd/symlink target` |
| `/hurd/fifo` | FIFO pipe | `settrans pipe /hurd/fifo` |
| `/hurd/proc` | Process information | `settrans /proc /hurd/procfs` |
| `/hurd/password` | Password prompt | User authentication |

---

## Advanced Usage

### Translator Chaining

Stack multiple translators for complex functionality:

```bash
# Transparent gzip decompression
settrans -c file.txt.gz /hurd/gunzip /path/to/compressed.gz
cat file.txt.gz  # Automatically decompressed!

# Network + filesystem + compression
settrans -c data /hurd/gunzip ftp://server/file.tar.gz
tar -xf data  # Extract remote compressed archive
```

### Custom Mount Points

Any user can create mount points in their home directory:

```bash
cd ~
mkdir myiso
settrans -c myiso /hurd/iso9660fs ~/downloads/debian.iso
ls myiso/
```

### Per-User Translators

Each user can have different translators on the same node:

```bash
# User alice
settrans ~/shared /hurd/symlink /home/alice/docs

# User bob
settrans ~/shared /hurd/symlink /home/bob/documents

# Same path, different targets per user!
```

---

## Practical Applications

### Development Use Cases

1. **Testing Filesystems**: Mount experimental filesystems as normal user
2. **Network Debugging**: Intercept network traffic with custom translators
3. **Virtualization**: Layer filesystems for containerization
4. **Remote Development**: Mount remote systems via FTP/HTTP/SSH

### System Administration

1. **Custom Filesystems**: Implement business logic in user-space
2. **Union Mounts**: Combine read-only and read-write filesystems
3. **Transparent Compression**: Auto-compress files on write
4. **Audit Logging**: Log all filesystem access

### Research and Education

1. **Microkernel Research**: Study user-space servers
2. **Filesystem Design**: Prototype new filesystem types
3. **Security Models**: Implement custom access controls
4. **OS Education**: Understand capability-based systems

---

## Security Considerations

### Permissions

- Users can only attach translators to nodes they **own**
- Translators run with **user's privileges** (not root)
- Cannot affect other users' nodes
- No kernel privileges required

### Best Practices

1. **Validate translator source**: Only use trusted translators
2. **Check active translators**: `showtrans <node>` before accessing
3. **Remove unused translators**: `settrans -g <node>` when done
4. **Monitor resources**: Translators can consume memory/CPU

---

## Troubleshooting

### Common Issues

**Translator won't start:**
```bash
# Check if translator binary exists
ls -la /hurd/ftpfs

# Try manual invocation
/hurd/ftpfs --help
```

**Can't remove translator:**
```bash
# Force removal
settrans -fg <node>

# Kill translator process
ps aux | grep ftpfs
kill <pid>
```

**Permission denied:**
```bash
# Check node ownership
ls -la <node>

# Must own the node to attach translator
chown $USER <node>
```

---

## Translator Development

### Creating Custom Translators

Translators are standard Hurd servers using `libdiskfs`, `libtrivfs`, or `libnetfs`.

**Simple example structure:**
```c
#include <hurd.h>
#include <trivfs.h>

// Implement trivfs callbacks
// - trivfs_S_io_read()
// - trivfs_S_io_write()
// - trivfs_S_file_get_translator_cntl()

// Main loop
int main(int argc, char **argv) {
    // Parse arguments
    // Setup trivfs
    // Enter port receive loop
}
```

**See**: https://www.gnu.org/software/hurd/hurd/translator/writing.html

---

## References

### Official Documentation

- **Hurd Translator Guide**: https://www.gnu.org/software/hurd/hurd/translator.html
- **Writing Translators**: https://www.gnu.org/software/hurd/hurd/translator/writing.html
- **Translator Examples**: https://www.gnu.org/software/hurd/hurd/translator/examples.html
- **settrans Manual**: `man settrans` (on Hurd system)

### Example Translators

- **Source Code**: `/hurd/` directory on Debian GNU/Hurd
- **Hurd Git**: https://git.savannah.gnu.org/git/hurd/hurd.git
- **Hurd Examples**: https://www.gnu.org/software/hurd/hurd/running/translator/examples.html

### Learning Resources

- **Hurd FAQ**: https://darnassus.sceen.net/~hurd-web/faq/
- **Translator Tutorial**: https://www.gnu.org/software/hurd/hurd/translator.html
- **Community**: IRC #hurd on Freenet, #debian-hurd on OFTC

---

## Quick Reference Card

```bash
# Basic operations
settrans <node> <translator>        # Attach translator
settrans -c <node> <translator>     # Create passive translator
settrans -g <node>                  # Remove translator
showtrans <node>                    # Show active translator
fsysopts <node>                     # View translator options

# Common translators
/hurd/hello                         # Hello world demo
/hurd/ftpfs                         # FTP filesystem
/hurd/httpfs                        # HTTP filesystem
/hurd/iso9660fs                     # ISO9660 CD filesystem
/hurd/ext2fs                        # ext2 filesystem
/hurd/tmpfs                         # Temporary RAM filesystem

# Examples
settrans hello /hurd/hello
settrans -c ftp: /hurd/hostmux /hurd/ftpfs /
settrans -c iso /hurd/iso9660fs /dev/cd0
settrans -g <node>                  # Remove when done
```

---

## See Also

- [INTERACTIVE-ACCESS.md](INTERACTIVE-ACCESS.md) - Accessing Hurd system
- [MANUAL-SETUP.md](MANUAL-SETUP.md) - Manual configuration
- [../02-ARCHITECTURE/OVERVIEW.md](../02-ARCHITECTURE/OVERVIEW.md) - Hurd architecture
- [../07-RESEARCH-AND-LESSONS/README.md](../07-RESEARCH-AND-LESSONS/README.md) - Deep dives

---

**Translators are what make Hurd unique!** They enable user-space filesystem innovation impossible in monolithic kernels. Experiment, learn, and extend your system without kernel modules or root privileges.
