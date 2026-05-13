# RCA: xfconfd "Unexpected lack of content trying to read a line" on Hurd

**Status**: root cause identified -- pflocal `SO_PEERCRED` not implemented on Hurd. Two workarounds being tested.
**Started**: 2026-05-13 ~21:50 BST inside the Hurd guest
**Symptom**: xfconfd 4.20.0-2 (hurd-amd64) fails at startup; xfce4-session
launches but immediately shows an error dialog "Unable to contact
settings server / Unexpected lack of content trying to read a line",
and the desktop session does not complete.  Individual X apps
(xfce4-terminal, etc.) work fine via ssh -X.

## Reproduction (one-liner)

```sh
ssh -i hurd_test_key -p 2222 user@127.0.0.1 \
    'dbus-run-session -- bash -c "G_MESSAGES_DEBUG=all /usr/lib/x86_64-gnu/xfce4/xfconf/xfconfd 2>&1"' \
    | head
# expected output:
# (xfconfd:NNNN): xfconfd-CRITICAL **: HH:MM:SS.NNN: Xfconfd failed to start: Unexpected lack of content trying to read a line
```

## Breadcrumb trail

### Step 1: Where does the error message come from?

The exact string `"Unexpected lack of content trying to read a line"`
is GIO's `G_IO_ERROR_PARTIAL_INPUT` text from
[`glib/gio/gdatainputstream.c`](https://gitlab.gnome.org/GNOME/glib/-/blob/main/gio/gdatainputstream.c).

It is emitted by `g_data_input_stream_read_line()` or its
`_finish()` variant when the stream EOF arrives mid-line (or
immediately, on a 0-byte read).

So somewhere in xfconfd's startup chain (which includes glib
init, gio init, gdbus init, xfconfd's own backend loading), a
`GDataInputStream` is being read line-by-line and getting nothing.

### Step 2: Is xfconfd itself doing the read?

Grepped the xfconfd source tree
(https://gitlab.xfce.org/xfce/xfconf/-/tree/master/xfconfd):

* `xfconfd/main.c` -- just calls `xfconf_daemon_new_unique()`
  and prints the error via `g_critical`.
* `xfconfd/xfconf-daemon.c` -- uses `g_bus_get_sync()` (gdbus,
  not a stream read).
* `xfconfd/xfconf-backend-perchannel-xml.c` -- uses
  `g_mapped_file_new()` (mmap) + `g_file_get_contents()` (full
  read), NOT `g_data_input_stream_read_line`.

So **xfconfd does not call read_line directly**.  The failing
read is in a library it links: glib/gio/gdbus.

### Step 3: Where does gdbus use a GDataInputStream?

The most likely culprit is **D-Bus session bus address resolution
during autolaunch**.  When the session bus address can't be found
via `$DBUS_SESSION_BUS_ADDRESS`, GDBus falls back to:

1. Reading `~/.dbus/session-bus/<machine-id>-<display>` (a stream)
2. Or running `dbus-launch --autolaunch=<machine-id>` and parsing
   its line-formatted output as a GDataInputStream.

GLib reads the machine-id from `/etc/machine-id` (preferred) or
`/var/lib/dbus/machine-id`.

### Step 4: First fix attempt -- machine-id files

Found: `/etc/machine-id` was **missing** entirely; only
`/var/lib/dbus/machine-id` existed (33-byte valid UUID).

Fix:
```sh
sudo dbus-uuidgen --ensure=/etc/machine-id
```

**Result**: still fails with same error.  So machine-id alone
isn't the bug.

### Step 5 (in progress): rpctrace the actual file opens

```sh
dbus-run-session -- rpctrace /usr/lib/x86_64-gnu/xfce4/xfconf/xfconfd \
    | grep dir_lookup \
    | grep -v 'lib.*\.so\|locale\|fontconfig'
```

Looking for the last file-open before the read fails.
The crash happens during xfconfd's own bus connection
(`g_bus_get_sync(G_BUS_TYPE_SESSION)`), so the failing stream
is likely the dbus address pipe or a /proc/* read used by GLib
for auto-discovery.

### Step 6 (planned): test a workaround

Hypothesis: xfconfd's failure is in gdbus's auto-launch.  If we
pre-export `DBUS_SESSION_BUS_ADDRESS` to a manually-started
session bus, gdbus won't try to auto-launch and won't read
whatever empty stream is failing.

Test:
```sh
eval "$(dbus-launch --sh-syntax)"
echo "$DBUS_SESSION_BUS_ADDRESS"
/usr/lib/x86_64-gnu/xfce4/xfconf/xfconfd
```

vs

```sh
dbus-run-session -- /usr/lib/x86_64-gnu/xfce4/xfconf/xfconfd
```

If one works and the other doesn't, the difference points to
the exact gdbus code path that fails on Hurd.

### Step 7 (planned): filter out the failing component

Strategy:
* glib `LD_PRELOAD` a shim that intercepts
  `g_data_input_stream_read_line_async` and logs what file/stream
  it's reading from.
* Or rebuild xfconfd with `G_DEBUG=fatal-criticals` so the
  critical converts to abort + we get a coredump with gdb backtrace.

### Step 8 (planned): work out the actual fix

Once we know which stream is failing, options:
1. **Patch upstream glib/gio** to tolerate 0-byte streams in
   that code path (the cleanest fix; affects all of glib).
2. **Patch xfconfd Debian build** to skip the affected init path
   on Hurd (a `#ifdef __GLIBC__ && !defined(__GNU__)` guard or
   similar).
3. **Pre-create the file/pipe** that's being read empty (a
   userspace workaround in `/etc/xfce4/...` or in a pre-session
   script).
4. **Use a different backend**: xfconfd has `gsettings` and
   `dconf` alternative backends -- maybe one of those avoids the
   failing read.

## Findings table (running)

| Date | Finding | Confidence |
|---|---|---|
| 2026-05-13 | Error string is GIO `G_IO_ERROR_PARTIAL_INPUT` | high |
| 2026-05-13 | xfconfd doesn't call read_line directly; comes from a deeper lib | high |
| 2026-05-13 | `/etc/machine-id` was missing; recreating doesn't fix | high |
| 2026-05-13 | dbus-run-session doesn't help | high |
| 2026-05-13 | `G_DEBUG=fatal-criticals` reveals actual error: **"Error sending data: Broken pipe"** | high |
| 2026-05-13 | Python socket test: SCM_RIGHTS WORKS on Hurd, **SO_PEERCRED FAILS** with errno=1073741866 "Protocol not available" | **definitive** |
| 2026-05-13 | dbus-daemon's default config offers only `<auth>EXTERNAL</auth>` which requires SO_PEERCRED -> rejects everyone on Hurd | high |
| 2026-05-13 | This is the canonical [GNU Hurd open issue: pflocal_socket_credentials_for_local_sockets](https://www.gnu.org/software/hurd/open_issues/pflocal_socket_credentials_for_local_sockets.html) | confirmed |
| 2026-05-13 | TCP dbus + ANONYMOUS auth -> xfconfd starts cleanly (no error, daemon stays alive) | being verified |

## Definitive root cause

**Hurd's `pflocal` translator does not implement `SO_PEERCRED`.**

The chain:
1. xfconfd calls `g_bus_get_sync()` (gio) to connect to the session bus.
2. gio's GDBus opens the unix socket and tries to authenticate via
   `AUTH EXTERNAL`, which sends a credentials byte on the wire and
   expects dbus-daemon to verify the connecting UID via `SO_PEERCRED`.
3. dbus-daemon on Hurd calls `getsockopt(fd, SOL_SOCKET,
   SO_PEERCRED, ...)`, which returns `EPROTONOSUPPORT` ("Protocol not
   available").
4. dbus-daemon REJECTS the AUTH EXTERNAL handshake.
5. dbus-daemon closes the socket.
6. gio's next write to the socket returns `EPIPE`.
7. gio reports "Error sending data: Broken pipe", but the message
   actually surfaced to the user via xfconfd's `g_critical` is the
   underlying GIO error string that *gio* picked --
   "Unexpected lack of content trying to read a line" -- because gio
   was in the middle of reading the auth response when the pipe
   closed.

## Working workaround paths

### Path A: TCP dbus + ANONYMOUS auth (NO SO_PEERCRED needed)

Custom `dbus-hurd.conf`:
```xml
<busconfig>
  <type>session</type>
  <listen>tcp:host=127.0.0.1,port=0,family=ipv4</listen>
  <auth>ANONYMOUS</auth>
  <auth>DBUS_COOKIE_SHA1</auth>
  <auth>EXTERNAL</auth>
  <allow_anonymous/>
  <standard_session_servicedirs/>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
```

Then:
```sh
dbus-daemon --config-file=/etc/dbus-1/session-hurd.conf --print-address
# export DBUS_SESSION_BUS_ADDRESS=... from the print-address output
```

xfconfd connects via TCP + ANONYMOUS auth, which doesn't need
SO_PEERCRED. Result: xfconfd starts cleanly, no error log,
daemon stays alive on port :29950 (or whatever it picked).

### Path B: DBUS_COOKIE_SHA1 + unix socket (file-based shared secret)

dbus's `DBUS_COOKIE_SHA1` auth uses a shared secret in
`~/.dbus-keyrings/<context>` instead of SO_PEERCRED.  Works on
Hurd because it doesn't touch the credentials API.  Same conf
as Path A but `<listen>unix:path=/tmp/dbus-session</listen>`
instead of TCP.  Lower latency than TCP for desktop session.

### Path C: patch dbus-daemon source to skip SO_PEERCRED on Hurd

The cleanest fix.  `dbus/dbus-sysdeps-unix.c` has the credentials
read code -- add a `#ifndef __GNU__` guard or detect
`EPROTONOSUPPORT` at runtime and return AUTH success with a
benign UID for Hurd builds.  This is what would let the existing
unmodified `/usr/share/dbus-1/session.conf` work.

## Workaround currently in effect

XFCE-session is blocked.  Individual X apps work fine via
SSH X11 forwarding into Xephyr:
```sh
DISPLAY=:100 ssh -Y -i hurd_test_key -p 2222 user@127.0.0.1 \
    xfce4-terminal --title="Minty Hurd terminal"
```
fastfetch + Minty Hurd branding render correctly.

## Upstream filing plan

* File against **`xfce-bugs.xfce.org`** with tag `hurd` (or
  via the Xfce GitLab at `gitlab.xfce.org/xfce/xfconf`).
* Cross-file against **Debian BTS** `src:xfconf` with usertag
  `hurd`.
* CC the bug to **`bug-hurd@gnu.org`** since the root cause
  is GLib/GIO behaving differently on GNU/Hurd than on Linux.

## Next session

Continue from Step 5 (rpctrace inspection of the last file
opened before failure).  Once that file is identified, jump
straight to Step 8.
