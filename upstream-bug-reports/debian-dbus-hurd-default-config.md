# could the Debian `dbus` Hurd port ship session.conf with ANONYMOUS+COOKIE_SHA1 already added?

**file against:** Debian BTS, `src:dbus`, with usertag `hurd`, severity
`wishlist` (since there's a workaround but it requires manual config).

## one-line summary

The default `/usr/share/dbus-1/session.conf` and `system.conf` shipped
in `dbus 1.16.2-4` offer only `<auth>EXTERNAL</auth>`.  On Debian
GNU/Hurd, `AUTH EXTERNAL` is unusable because the underlying syscall
(`getsockopt(SO_PEERCRED)`) returns `EPROTONOSUPPORT` -- Hurd's
pflocal translator doesn't implement socket credentials passing
(documented at
https://www.gnu.org/software/hurd/open_issues/pflocal_socket_credentials_for_local_sockets.html).

Result: every D-Bus client connection on Debian GNU/Hurd fails with
"Error sending data: Broken pipe" right after the AUTH EXTERNAL byte.

Adding `<auth>ANONYMOUS</auth>` and `<auth>DBUS_COOKIE_SHA1</auth>`
to the default Hurd-arch config files (or via a `+hurd`-tagged
debdiff) would let unmodified xfconfd, xfce4-session, ConsoleKit,
polkit, etc. work out of the box on Hurd.

## the workaround that confirms this hypothesis

Adding the two extra auth lines (and `<allow_anonymous/>`) to
`session.conf` + a system.d drop-in for the system bus lets the
whole D-Bus ecosystem work on Hurd.  Tested on:

* dbus 1.16.2-4 (hurd-amd64)
* gnumach 1.8+git20260224 amd64
* glibc 2.41+hurd
* xfconf 4.20.0-2 (consumer; previously failed)
* xfce4-session 4.20.X (consumer; previously failed)

After the workaround the full XFCE desktop comes up cleanly --
panel, Whisker menu, taskbar, tray, settings daemon, the whole
thing.

## suggested debian/rules conditional patch

```diff
--- a/dbus/session.conf.in
+++ b/dbus/session.conf.in
@@ ... @@
   <auth>EXTERNAL</auth>
+  <!-- On Hurd, SO_PEERCRED is unimplemented (pflocal limitation),
+       so AUTH EXTERNAL fails. Add ANONYMOUS + COOKIE so connections
+       can still authenticate. Has no effect on Linux where EXTERNAL
+       remains preferred and succeeds. -->
+  <auth>ANONYMOUS</auth>
+  <auth>DBUS_COOKIE_SHA1</auth>
+  <allow_anonymous/>
```

(Same change in system.conf.in.)

Alternatively, ship a hurd-only `auth-anonymous.conf` drop-in
in `/etc/dbus-1/{session.d,system.d}/` that adds those lines, only
populated by `dbus:hurd-amd64`.

## possible objection: ANONYMOUS is "less secure"

True on a system where pflocal *does* implement SO_PEERCRED -- you
wouldn't want anonymous auth in production.  But on Hurd, there is
currently no working alternative: the choice is between "use
ANONYMOUS/COOKIE_SHA1 with full filesystem-level access control" vs
"D-Bus simply doesn't work for any user on this architecture."  The
ANONYMOUS path is also restricted by the `<policy>` block in the
config, so application-level permissions still work normally.

## not affected

* Linux Debian (any arch) -- EXTERNAL works there, no change in
  behaviour.
* kFreeBSD ports -- have a different credentials path (`getpeereid`?).

---

**disclaimer**: LLM-assisted RCA.  I used Claude to help trace the
GIO error message back through the GDBus auth handshake to the
SO_PEERCRED gap.  The workaround is verified working on my own
Hurd install; the upstream-patch suggestion is just one possible
shape -- happy to revise if the dbus maintainers prefer a
drop-in conf file approach or anything else.
