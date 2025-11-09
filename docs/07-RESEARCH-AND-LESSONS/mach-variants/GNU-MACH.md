================================================================================
GNU MACH: PRIMARY MICROKERNEL FOR GNU/HURD
Document Version: 2.0 (2025-11-05)
Scope: Development, building, debugging in Docker environment
Target Audience: Systems engineers, kernel developers, GNU/Hurd contributors
================================================================================

EXECUTIVE SUMMARY
================================================================================

GNU Mach is the microkernel foundation of GNU/Hurd. It manages:
  - CPU scheduling and context switching
  - Memory management (paging, virtual addressing)
  - Inter-process communication (IPC) via messages
  - Basic hardware abstraction (interrupts, device I/O)

Key design goal: Minimize privileged-mode code; delegate services to userland.

Status: Production-ready (used in Debian GNU/Hurd), under active development.
Repository: https://git.savannah.gnu.org/git/hurd/gnumach.git
Current version: 1.8.x series with ongoing patches

================================================================================
ARCHITECTURE OVERVIEW
================================================================================

Mach Kernel Structure:

  +-------------------+
  |  User Applications |  (unprivileged ring 3)
  +-------------------+
         |
         | Message-based IPC
         |
  +---------------------------+
  |  GNU Hurd Servers         |  (ring 3: translators, filesystems)
  |  - proc (process mgmt)    |
  |  - auth (credentials)     |
  |  - ext2fs, tmpfs, etc.    |
  +---------------------------+
         |
         | Low-level IPC
         |
  +---------------------------+
  |     GNU Mach Kernel       |  (ring 0: privileged)
  | - Message dispatch        |
  | - Memory management       |
  | - Scheduling              |
  | - Hardware abstraction    |
  +---------------------------+
         |
   +-----+-----+
   |           |
  HAL      Device
  (CPU)      Drivers
  (x86)      (AHCI, UHCI)

Key architectural differences from monolithic kernels:

1. IPC is first-class (not syscalls)
   - Process communication via port objects
   - Transparent message passing to any server
   - No context switch for message delivery to another port

2. Memory management is explicit
   - Paging handled by kernel
   - User tasks manage virtual memory via task_create()
   - Page-based protection (no per-variable fine-grain)

3. Minimal privileged code
   - Only 50K-100K lines of assembly/C
   - Most services implemented as userland translators
   - Driver loading via device manager (userland)

Hardware abstraction:

  i386/i486/Pentium (and clones):
    - x86 page tables (2-level or 3-level PAE)
    - IDT/GDT for interrupts
    - Task switching via TSS
    - APIC support (multicore)

  x86-64 (newer work):
    - 64-bit addressing
    - Long mode page tables (4-level)
    - Still experimental/in-progress

Mach concepts:

  Task: Virtual address space + thread container (like Unix process)
  Thread: Kernel scheduling unit (like Unix thread)
  Port: Unidirectional message queue (like pipe or Unix socket)
  Message: Fixed + variable-size data, with inline/OOL regions
  Right: Capability granting access to port (send/receive/etc.)

================================================================================
DEVELOPMENT SETUP IN DOCKER
================================================================================

Docker environment provides:

  Base OS: Debian Hurd or i386 Linux
  Build tools: GCC 10+, binutils, automake, libtool
  Mach source: Pre-cloned or fetched from Savannah
  Cross-compiler: Available if cross-building (x86_64 -> i386)

Starting development container:

  docker-compose up -d hurd           # Or use entrypoint.sh
  docker exec -it <container> bash

Verify Mach source present:

  ls -la /home/eirikr/Playground/gnu-hurd-docker/
  # Look for gnumach source or git clone location

Development workflow:

  1. Fetch latest Mach:
     cd /path/to/gnumach
     git pull origin master

  2. Configure build:
     ./configure --prefix=/tmp/mach-install \
       --with-mig=/tmp/mig-install/bin/mig \
       --enable-kdb              # Kernel debugger
     # Note: MIG (message interface generator) often pre-built

  3. Build kernel:
     make -j4
     # Output: kernel (ELF binary) in build directory

  4. Install for testing:
     make install
     # Installs to /tmp/mach-install/boot/gnumach

  5. Boot new kernel (on native Hurd):
     cp gnumach /boot/gnumach
     reboot

For Docker/QEMU testing:

  # Kernel image location
  ls -la build-i386/kernel
  file build-i386/kernel  # Should be ELF i386

  # Copy to QEMU boot directory
  cp build-i386/kernel /mnt/qemu-images/hurd/boot/gnumach

  # Boot QEMU with new kernel
  qemu-system-i386 -kernel gnumach -initrd ... [other options]

================================================================================
BUILDING GNUMACH FROM SOURCE
================================================================================

Prerequisites (check container has these):

  build-essential (gcc, make, binutils)
  automake, autoconf, libtool
  libmig-dev (MIG compiler)
  Linux kernel source or Hurd source (for headers)

Clone and configure:

  git clone https://git.savannah.gnu.org/git/hurd/gnumach.git
  cd gnumach
  git log --oneline | head     # Verify clone successful

  ./bootstrap                  # Generate configure script
  ./configure --prefix=/opt/mach \
    --enable-kdb               # Include kernel debugger
    --disable-floppy           # Skip floppy driver (not needed)

Build process:

  make -j4 2>&1 | tee build.log

Common build issues:

  Issue: "mig: command not found"
  Fix: MIG (message interface generator) must be available
       apt-get install libmig-dev
       OR: Check /usr/bin/mig path

  Issue: "undefined reference to '__gnu_mach_interface'"
  Fix: MIG stubs not compiled; check .mig.c files generated
       Rebuild: make clean && make -j4

  Issue: x86_64 vs i386 architecture mismatch
  Fix: Check configure output: "checking for target triplet: i386-unknown-gnu0.9"
       If wrong arch: ./configure --build=x86_64-linux-gnu --target=i386-gnu

Compilation output:

  build-i386/kernel            # Main kernel binary (ELF)
  build-i386/libmach.a         # Mach library (static)
  build-i386/libmachdev.a      # Device interface library
  build-i386/libmachuser.a     # User-space Mach library

Size and optimization:

  # Check kernel size
  ls -lh build-i386/kernel        # Usually 500K-1.5M
  strip build-i386/kernel         # Remove symbols for production

  # Optimize further
  CFLAGS="-O2 -march=native -mtune=native" make clean && make -j4

================================================================================
MIG: MESSAGE INTERFACE GENERATOR
================================================================================

MIG translates .defs files (interface definitions) into:
  - C stubs for client RPC calls
  - Server request unpacking code
  - Type marshalling/unmarshalling

Example: Creating a simple interface

File: myservice.defs

  subsystem myservice 99;       /* subsystem name and base ID */

  #include <mach/std_types.defs>

  type my_data_t = array[256] of char;

  routine hello(
    in server  : mach_port_t;
    in name    : c_string_t;
    out reply  : c_string_t
  );

  routine sum_array(
    in server  : mach_port_t;
    in data    : my_data_t;
    out result : int
  );

Generate C code:

  mig myservice.defs

Output files:

  myserviceUser.c      # Client stubs
  myserviceServer.c    # Server unpacking routines
  myservice.h          # Shared header (types, IDs)

Client usage:

  #include "myservice.h"
  #include <mach.h>

  mach_port_t server;
  char reply[256];

  /* Look up service via name server */
  netname_look_up(netname_server_port, "", "myservice", &server);

  /* Call remote procedure */
  hello(server, "World", reply);  /* Blocks until server responds */
  printf("Got: %s\n", reply);

Server implementation:

  #include "myservice.h"
  #include <mach.h>

  kern_return_t myservice_hello_server(
    mach_port_t server,
    const char *name,
    char **reply,
    mach_msg_type_number_t *reply_len
  ) {
    asprintf(reply, "Hello, %s!", name);
    return KERN_SUCCESS;
  }

Key MIG directives:

  in        - Parameter passed to server
  out       - Return value from server
  inout     - Modified by server
  array[N]  - Fixed-size array
  c_string_t - Null-terminated C string (auto-marshalled)
  port_t    - Mach port right
  data      - Arbitrary data with length

Performance implications:

  - Message copy overhead: ~10-50 us (depends on size)
  - Inline vs. out-of-line data: OOL avoids copy but adds complexity
  - Batching requests reduces context switches

================================================================================
COMMON DEVELOPMENT TASKS
================================================================================

Task: Add a new syscall

1. Define in interface (e.g., gnumach/kern/syscall_sw.c)
2. Implement handler function
3. Register in syscall dispatch table
4. Test with userland stub

Example: Adding get_mach_version() syscall

File: kern/syscall_sw.c

  void mach_get_version(mach_port_t port,
                        vm_address_t *version_out) {
    *version_out = GNUMACH_VERSION_CODE;
  }

Add to export in hurd/mach/mach.defs

  routine get_mach_version(
    in server: mach_port_t;
    out version: vm_address_t
  );

Task: Debug with KDB (kernel debugger)

Prerequisites:

  Built with --enable-kdb
  Boot with option: -k (kernel debugger enabled)

Usage:

  b <address>       # Set breakpoint
  c                 # Continue
  p <value>         # Print value
  st                # Stack trace
  S <task_address>  # Examine task structure
  q                 # Quit debugger

Task: Profile kernel performance

Using kernel instrumentation:

  1. Rebuild with profiling enabled:
     ./configure --enable-profile
     make clean && make -j4

  2. Boot instrumented kernel
  3. Run workload
  4. Extract profile data:
     gprof gnumach gmon.out > profile.txt

Analysis:

  # Identify hot functions
  grep "% cumulative" profile.txt | head -20

  # Check which functions call slowest routine
  grep "incoming calls" profile.txt

Task: Add device driver support

Driver architecture:

  1. Implement driver interface (device.defs)
  2. Register with device manager (userland)
  3. Handle I/O requests from applications

Example skeleton:

  #include <device/device.h>
  #include <mach/mach_interface.h>

  static io_return_t my_device_open(
    dev_t dev,
    int flags,
    io_req_t ior
  ) {
    /* Allocate device context, initialize hardware */
    return D_SUCCESS;
  }

  static io_return_t my_device_read(
    dev_t dev,
    io_req_t ior
  ) {
    /* Read from device, enqueue data */
    return D_IO_QUEUED;
  }

  struct dev_ops my_device_ops = {
    .d_open = my_device_open,
    .d_read = my_device_read,
    /* ... other operations ... */
  };

================================================================================
DEBUGGING TECHNIQUES
================================================================================

Method 1: Console output (kprintf)

  #include <stdarg.h>

  void debug_message(const char *format, ...) {
    #ifdef DEBUG
    va_list args;
    va_start(args, format);
    printf(format, args);  /* Prints to console */
    va_end(args);
    #endif
  }

  /* Usage in kernel code */
  debug_message("Task %p created with PID %d\n", task, pid);

Method 2: Assertions and panic()

  #include <mach/mach_traps.h>

  void critical_operation() {
    if (unlikely(!validate_state())) {
      panic("Critical invariant violated: state=%d", state);
    }
  }

  /* panic() prints message and halts kernel (useful for testing) */

Method 3: Post-mortem analysis

  1. Capture kernel core dump:
     In QEMU: Ctrl-A c, then: dump-guest-memory dump.elf

  2. Analyze with GDB:
     gdb gnumach dump.elf
     (gdb) list *address  # Disassemble
     (gdb) p *task_pointer
     (gdb) bt             # Backtrace

  3. Inspect memory:
     (gdb) x/16i 0x1000:0  # Examine instructions
     (gdb) x/16x 0x2000:0  # Examine memory as hex

Method 4: Dynamic tracing (if available)

  Using SystemTap (Linux) or DTrace (native Hurd):
    probe syscall.mach_msg.entry { printf("IPC: %d bytes\n", $size) }

Method 5: Performance profiling

  Run with: time ./workload
  Analyze with: perf record -g ./workload

Interpret results:

  - High context switches: Task scheduling overhead
  - High IPC latency: Message path bottleneck
  - High page faults: Memory allocation/paging issues

================================================================================
PERFORMANCE TUNING
================================================================================

IPC optimization:

  1. Reduce message size (avoid OOL data when inline fits)
  2. Batch operations (multiple requests per RPC)
  3. Align data structures (cache-line friendly)

Memory tuning:

  1. Paging: Configure VM page size (usually 4K or 8K)
     vm_page_init() sets granularity

  2. Cache: Kernel code should fit in L2/L3
     Strip symbols for production: strip gnumach

  3. Locality: Group related data in same page

Scheduling optimization:

  1. Thread priorities: Use PRIORITY_SYSTEM for latency-sensitive tasks
  2. CPU affinity: Bind threads to cores (NUMA-aware)
  3. Real-time class: Set SCHEDULING_TIMESHARE or SCHEDULING_RR

Example: Set thread priority

  #include <mach/thread_info.h>

  void boost_priority(thread_t thread) {
    thread_info_t info;
    mach_msg_type_number_t count = THREAD_INFO_MAX;

    thread_info(thread, THREAD_BASIC_INFO, (int *)&info, &count);
    info.base_info.priority = 50;  /* 0-63, higher = more CPU time */

    thread_set_state(thread, THREAD_INFO_MAX, (int *)&info, count);
  }

Hardware-specific tuning (x86):

  1. TLB: Larger pages reduce misses (not always: memory overhead)
  2. Prefetch: L1/L2 prefetch hints in hot paths
  3. Branch prediction: Avoid unpredictable branches in tight loops

Measurement:

  perf stat ./workload
  Output: cache hits/misses, branch mispredicts, cycles/instruction

Typical performance targets:

  - IPC latency: < 10 us (null RPC)
  - Task creation: < 100 ms
  - Page fault: < 50 us
  - Context switch: < 5 us

================================================================================
CONTRIBUTING TO GNUMACH
================================================================================

Process:

1. Check mailing list: bug-hurd@gnu.org (read archives first)
2. Create feature branch: git checkout -b feature/my-patch
3. Make minimal, focused changes
4. Test thoroughly (see TESTING section below)
5. Write commit message following GNU style
6. Generate patch: git format-patch origin/master
7. Send to mailing list or create Savannah pull request

Commit message style:

  Subject: Brief one-line summary (50 chars max)

  Body:
  Detailed explanation of why change is needed.
  Reference related bugs or discussions.
  Explain implementation choice and tradeoffs.

  This fixes or implements [description].

  Related discussion: https://lists.gnu.org/archive/html/bug-hurd/...

Code style:

  - GNU Coding Standards (https://www.gnu.org/prep/standards/)
  - 80-char line length (soft); 100-char hard limit
  - Spaces not tabs (2-space indentation common)
  - Function names: lowercase_with_underscores
  - Constants: UPPERCASE_WITH_UNDERSCORES
  - Comments: Explain WHY, not WHAT (code is obvious)

Testing:

  [ ] Code compiles without warnings (CFLAGS="-Wall -Wextra -Werror")
  [ ] Existing tests pass: make check (if available)
  [ ] New functionality tested: write tests in tests/ subdir
  [ ] Performance not regressed: benchmark if relevant
  [ ] Backwards compatibility maintained

Review criteria:

  - Does it follow GNU style?
  - Is it minimal and focused?
  - Does it improve maintainability?
  - Are there performance implications?
  - Does it break existing APIs?

================================================================================
REFERENCES AND RESOURCES
================================================================================

Official documentation:
  - GNU Mach info pages: info gnumach
  - Hurd design document: https://www.gnu.org/software/hurd/hurd.html
  - Savannah repository: https://savannah.gnu.org/projects/hurd

Mailing lists:
  - bug-hurd@gnu.org (development discussion)
  - hurd-maintainers@gnu.org (core team)

Technical papers:
  - Mach IPC paper (original CMU design)
  - "The Mach Microkernel Architecture" (Rashid et al., 1989)

Internals:
  - gnumach/kern/task.c (task implementation)
  - gnumach/kern/ipc/ (message passing)
  - gnumach/vm/ (memory management)

Code references (in Docker):
  grep -r "SUBSYSTEM_" /path/to/gnumach/hurd  # Find all RPC interfaces
  grep -r "kern_return_t" /path/to/gnumach/kern  # Find all kernel functions

================================================================================
END DOCUMENT
================================================================================
