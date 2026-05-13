#!/bin/sh
# Install the Hurd dbus-session workaround for the SO_PEERCRED gap.
#
# Background: Hurd's pflocal translator doesn't implement SO_PEERCRED
# (getsockopt SOL_SOCKET SO_PEERCRED returns EPROTONOSUPPORT "Protocol
# not available").  dbus-daemon's default session.conf only allows
# AUTH EXTERNAL, which requires SO_PEERCRED to verify the connecting
# UID.  Result: every GIO/GDBus connection (xfconfd, xfce4-session,
# almost any GTK app) fails with "Error sending data: Broken pipe"
# (surfaced to user-visible messages as "Unable to contact settings
# server / Unexpected lack of content trying to read a line").
#
# This script writes a Hurd-friendly /etc/dbus-1/session-hurd.conf
# that adds ANONYMOUS + DBUS_COOKIE_SHA1 to the auth offerings, and
# a wrapper start-dbus-hurd in /usr/local/bin that launches a session
# bus with that config + exports DBUS_SESSION_BUS_ADDRESS into the
# caller's shell.
#
# Verified working: 2026-05-13 on Debian GNU/Hurd 0.9 / GNU-Mach 1.8 /
# glibc 2.41+hurd / xfconf 4.20.0-2 / dbus 1.16.2.

set -e
log() { printf '\n=== %s ===\n' "$*"; }

log "Step 1: install /etc/dbus-1/session-hurd.conf"
cat > /etc/dbus-1/session-hurd.conf <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<!--
    Hurd-friendly D-Bus session bus config.  Adds ANONYMOUS and
    DBUS_COOKIE_SHA1 to the auth offerings so that connections work
    on GNU/Hurd, where SO_PEERCRED is not implemented in pflocal.
    See https://www.gnu.org/software/hurd/open_issues/pflocal_socket_credentials_for_local_sockets.html
-->
<busconfig>
  <type>session</type>
  <listen>tcp:host=127.0.0.1,port=0,family=ipv4</listen>
  <auth>ANONYMOUS</auth>
  <auth>DBUS_COOKIE_SHA1</auth>
  <auth>EXTERNAL</auth>
  <allow_anonymous/>
  <standard_session_servicedirs/>
  <servicehelper>/usr/lib/dbus-1.0/dbus-daemon-launch-helper</servicehelper>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF

log "Step 2: install /usr/local/bin/start-dbus-hurd"
cat > /usr/local/bin/start-dbus-hurd <<'EOF'
#!/bin/sh
# Launch a Hurd-compatible D-Bus session bus and emit the address on stdout.
# Usage:
#   eval "$(start-dbus-hurd)"
#   xfconfd &
#   xfce4-session &
set -eu
ADDR=$(dbus-daemon --config-file=/etc/dbus-1/session-hurd.conf --print-address --fork)
case "$ADDR" in
    tcp:*) ;;
    *) echo "expected tcp address, got: $ADDR" >&2; exit 1;;
esac
printf 'export DBUS_SESSION_BUS_ADDRESS=%s\n' "$ADDR"
EOF
chmod +x /usr/local/bin/start-dbus-hurd

log "Step 3: install /etc/X11/Xsession.d/95dbus-hurd-session"
cat > /etc/X11/Xsession.d/95dbus-hurd-session <<'EOF'
# Source by Xsession(5).  Launches a Hurd-compatible D-Bus session bus
# (over TCP loopback, with ANONYMOUS auth allowed) before the user's
# desktop session starts.  Without this, xfconfd, xfce4-session, gtk
# apps that need a session bus, etc. fail at startup with "Error
# sending data: Broken pipe" on GNU/Hurd.
if [ -x /usr/local/bin/start-dbus-hurd ] && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval "$(/usr/local/bin/start-dbus-hurd)"
    export DBUS_SESSION_BUS_ADDRESS
fi
EOF

log "Step 4: convenience wrapper for ad-hoc XFCE launching"
cat > /usr/local/bin/minty-hurd-xfce <<'EOF'
#!/bin/sh
# Launch xfce4-session against the Hurd-friendly D-Bus.
# Run inside an SSH X11-forwarded session OR with $DISPLAY set.
set -eu
eval "$(/usr/local/bin/start-dbus-hurd)"
export DBUS_SESSION_BUS_ADDRESS
# Start xfconfd in the background so other XFCE components can find it.
/usr/lib/x86_64-gnu/xfce4/xfconf/xfconfd &
sleep 1
exec dbus-launch xfce4-session
EOF
chmod +x /usr/local/bin/minty-hurd-xfce

log "Done.  Test with:"
echo "  eval \"\$(start-dbus-hurd)\""
echo "  /usr/lib/x86_64-gnu/xfce4/xfconf/xfconfd &"
echo "  sleep 1"
echo "  dbus-send --session --print-reply --dest=org.xfce.Xfconf \\"
echo "      /org/xfce/Xfconf org.xfce.Xfconf.ListChannels"
echo
echo "Expected output: list of xfconf channels (xfce4-keyboard-shortcuts,"
echo "xfce4-session, xsettings, plus any deployed Mint channels)."
