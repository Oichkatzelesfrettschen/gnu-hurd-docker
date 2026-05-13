# umm so `SO_PEERCRED` returns "Protocol not available" on Hurd and it breaks pretty much every D-Bus-using app?

**file this against:** `bug-hurd@gnu.org` (the canonical place for GNU
Hurd kernel/translator bugs), plus probably link from the existing open
issue at
https://www.gnu.org/software/hurd/open_issues/pflocal_socket_credentials_for_local_sockets.html
which has been open since I think 2002.

**not new, but maybe worth a fresh write-up:** the linked open issue is
documented but very old, and I couldn't find a recent description of the
*downstream impact* (which apps break, which workarounds exist, etc.).
Wanted to write it up since I just hit it.  Apologies if this is
duplicative.

## what's broken

On Debian GNU/Hurd 0.9 (gnumach 1.8+git20260224 amd64, glibc 2.41+hurd),
basically every D-Bus-using application fails to connect to the session
bus.  The user-visible symptoms vary:

* **xfconfd** -- *"Xfconfd failed to start: Unexpected lack of content
  trying to read a line"*.  This in turn makes xfce4-session pop a
  *"Unable to contact settings server"* dialog and refuse to bring up
  the desktop.
* **ConsoleKit proxy** in xfce4-session -- *"Failed to get a ConsoleKit
  proxy: Error sending data: Broken pipe"*.
* **gnome-keyring**, **NetworkManager**, **polkitd** -- variants of the
  same broken-pipe-after-AUTH-EXTERNAL story.

I think every one of these is the same root cause.

## what's actually going on

GIO/GDBus default behaviour, when connecting to a session bus over a
unix socket, is to authenticate via `AUTH EXTERNAL`.  That handshake
sends a credentials byte on the wire and expects the bus to verify the
connecting UID via `getsockopt(fd, SOL_SOCKET, SO_PEERCRED, ...)`.

On Linux, `SO_PEERCRED` is implemented and returns `(pid, uid, gid)`
of the peer.  On Hurd, pflocal returns `EPROTONOSUPPORT` -- the Python
`socket` module surfaces it as `errno=1073741866 (Protocol not
available)`.

dbus-daemon then *rejects* the AUTH EXTERNAL handshake (it has no way
to verify the connector's UID).  After the rejection it closes the
socket.  GIO's next write to the socket returns `EPIPE`.

The user sees one of two error messages depending on whether GIO was
in the middle of reading or writing when the close happened:

* mid-read: `"Unexpected lack of content trying to read a line"`
  (`G_IO_ERROR_PARTIAL_INPUT`)
* mid-write: `"Error sending data: Broken pipe"` (`G_IO_ERROR_BROKEN_PIPE`)

The first message is misleading -- it makes it look like an XML
parse or config-file issue.  It took me a while of poking at
xfconfd's source code (which uses `g_mapped_file_new`, not
`g_data_input_stream_read_line`) to realise the error was coming from
*deeper* in GIO's GDBus auth handshake.

## minimal reproducer

Python 3 + `socket.socketpair` is enough:

```python
import socket, struct
a, b = socket.socketpair(socket.AF_UNIX)
try:
    cred = a.getsockopt(socket.SOL_SOCKET, 17, struct.calcsize("3i"))
    pid, uid, gid = struct.unpack("3i", cred)
    print(f"SO_PEERCRED OK: pid={pid} uid={uid} gid={gid}")
except OSError as e:
    print(f"SO_PEERCRED FAILED: errno={e.errno} ({e.strerror})")
```

On Linux: `SO_PEERCRED OK: pid=1234 uid=1000 gid=1000`
On Hurd:  `SO_PEERCRED FAILED: errno=1073741866 (Protocol not available)`

(That `17` is the Linux numeric value for `SO_PEERCRED`.  Hurd
inherits the numeric value but the implementation just returns
`EPROTONOSUPPORT`.)

`SCM_RIGHTS` (passing file descriptors over unix sockets) works
fine on Hurd in the same socketpair test, FWIW.

## the workaround I'm using

Add `AUTH ANONYMOUS` + `AUTH DBUS_COOKIE_SHA1` to both the dbus
session config and system config so connectors don't have to use
EXTERNAL.

`/etc/dbus-1/session-hurd.conf` (used by a wrapper script
`start-dbus-hurd` that exports the resulting bus address into
the user's shell):

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

`/etc/dbus-1/system.d/00-hurd-anonymous.conf` (auto-included by
`/usr/share/dbus-1/system.conf`'s `<includedir>`):

```xml
<busconfig>
  <auth>EXTERNAL</auth>
  <auth>DBUS_COOKIE_SHA1</auth>
  <auth>ANONYMOUS</auth>
  <allow_anonymous/>
</busconfig>
```

With both in place + a TCP-loopback session bus, the full Hurd XFCE
desktop comes up cleanly -- panel + Whisker menu + taskbar + tray +
xfconfd serving channels.

I have a screenshot of it working on my own machine if useful;
it's in
[`docs/minty-hurd-desktop-2026-05-13.png`](https://github.com/Oichkatzelesfrettschen/gnu-hurd-docker/blob/main/docs/minty-hurd-desktop-2026-05-13.png).

## the proper fix

would be implementing `SO_PEERCRED` in pflocal so the unmodified
upstream dbus configs work.  Looking at
https://www.gnu.org/software/hurd/open_issues/sendmsg_scm_creds.html
the comments suggest this needs to plumb the auth ports through
pflocal's IPC -- pflocal would need to know who sent each message,
either via `auth_user_authenticate` / `auth_server_authenticate`
roundtrips or via a smaller credentials-only protocol.

I am very much not a Hurd kernel dev and won't try this myself, but
if anyone is interested in picking it up, fixing pflocal would
unblock the entire Hurd desktop ecosystem.

## affected components I've actually confirmed broken

* `dbus-daemon` 1.16.2-4 (session + system buses)
* `xfconfd` 4.20.0-2
* `xfce4-session` 4.20.X
* libxfce4util ConsoleKit proxy
* gnupg `gpg-agent` startup (also uses sockets but seems to recover)

(probably anything using gdbus to talk to a session/system bus, but
those are what I bumped into.)

## not affected

* Pubkey auth over OpenSSH (different code path)
* Raw socket access via SCM_RIGHTS (works fine)
* X11 apps that don't need a session bus (xterm, xeyes, xclock,
  xfce4-terminal in standalone mode -- all work via SSH X11
  forwarding)

---

**disclaimer**: I used a large language model (Claude) to help me trace
this down.  Specifically: comparing the misleading GIO error string to
the actual underlying error via `G_DEBUG=fatal-criticals`, writing the
Python socketpair reproducer, and reading the dbus + glib source to find
where SO_PEERCRED is queried.  The reproducer output above is real and
running on my machine; the config files are minimum-viable adaptations
of upstream session.conf with the auth list extended.  Apologies in
advance if the writeup is rough or if it's already filed somewhere I
didn't find -- I tried searching but the GIO error message is generic
enough that hits were mostly about other things.

If anyone wants more context (rpctrace logs, gdb backtrace of xfconfd
SIGABRT-on-fatal-critical, etc.) I have those and am happy to attach.
