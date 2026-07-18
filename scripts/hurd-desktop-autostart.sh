#!/bin/sh
# Stage boot-time desktop autostart inside the Hurd guest.
# Run INSIDE the guest as root. Idempotent.
#
# One provisioned image serves two frontends, selected by a mode file:
#
#   vnc    headless route (QEMU/podman/docker): Xvfb :1 renders the
#          XFCE session into a virtual framebuffer and x11vnc exports
#          it on 5901. Browser access comes from the compose vnc
#          profile's novnc container on the host side; debian-ports
#          currently has no hurd-amd64 websockify/tigervnc candidates,
#          and tightvnc's 1.3-era Xtightvnc cannot open the modern
#          font layout ("could not open default font 'fixed'"), so the
#          Xvfb + x11vnc pair is the supported stack.
#   xorg   console route (VirtualBox/QEMU with a display): lightdm
#          starts XFCE on the real VGA console via the Xorg vesa/fbdev
#          driver.
#   none   no desktop at boot (SSH-only.)
#
# Select with: echo vnc > /etc/hurd-desktop.mode  (default: none)

set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin

say() { printf '=== %s ===\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root" >&2; exit 1; }

say "Install /usr/local/sbin/hurd-desktop"
cat > /usr/local/sbin/hurd-desktop <<'EOF'
#!/bin/sh
# Boot-time desktop launcher; mode comes from /etc/hurd-desktop.mode.
# Runs as root from rc.local; the desktop session runs as 'user' via
# runuser, whose PAM stack skips account aging -- su would refuse the
# OOBE-expired password and the desktop would never start.
MODE=$(cat /etc/hurd-desktop.mode 2>/dev/null || echo none)
LOG=/var/log/hurd-desktop.log

case "$MODE" in
vnc)
    {
        echo "hurd-desktop: vnc mode $(date 2>/dev/null)"
        /etc/init.d/dbus start 2>&1 || true
        rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
        # Xvfb renders; the session runs via minty-hurd-xfce because
        # startxfce4 would go through dbus-launch, whose default-config
        # session bus offers only EXTERNAL auth and dies on Hurd's
        # missing SO_PEERCRED. x11vnc needs -noshm: MIT-SHM attaches
        # fail on Hurd and kill the poller.
        runuser -l user -c '
            mkdir -p ~/.vnc
            [ -f ~/.vnc/passwd ] || x11vnc -storepasswd hurdhurd ~/.vnc/passwd
            chmod 600 ~/.vnc/passwd
            nohup Xvfb :1 -screen 0 1280x800x24 >>/tmp/xvfb.log 2>&1 &
            sleep 8
            DISPLAY=:1 nohup /usr/local/bin/minty-hurd-xfce >>/tmp/xfce-vnc.log 2>&1 &
            sleep 5
            nohup x11vnc -noshm -display :1 -rfbauth ~/.vnc/passwd \
                -rfbport 5901 -forever -shared >>/tmp/x11vnc.log 2>&1 &
        '
    } >> "$LOG" 2>&1 &
    ;;
xorg)
    {
        echo "hurd-desktop: xorg mode $(date 2>/dev/null)"
        /etc/init.d/dbus start 2>&1 || true
        # startx as 'user' with the minty-hurd-xfce wrapper: lightdm's
        # greeter never spawns on Hurd (no logind seat), and startxfce4's
        # dbus-launch starts a default-config session bus whose only auth
        # is EXTERNAL, which needs the SO_PEERCRED that pflocal lacks.
        # minty-hurd-xfce runs xfce4-session against the TCP session bus
        # from start-dbus-hurd instead. Requires Xwrapper allowed_users=
        # anybody (staged below) since 'user' does not hold the console.
        runuser -l user -c 'startx /usr/local/bin/minty-hurd-xfce -- :0' 2>&1
    } >> "$LOG" 2>&1 &
    ;;
esac
exit 0
EOF
chmod 0755 /usr/local/sbin/hurd-desktop

say "Hook into /etc/rc.local"
touch /etc/rc.local
chmod 0755 /etc/rc.local
grep -q hurd-desktop /etc/rc.local || {
    # insert before the final exit 0 if present, else append
    if grep -q '^exit 0$' /etc/rc.local; then
        sed -i 's|^exit 0$|/usr/local/sbin/hurd-desktop\nexit 0|' /etc/rc.local
    else
        printf '/usr/local/sbin/hurd-desktop\n' >> /etc/rc.local
    fi
}

say "Xwrapper policy for non-console startx"
cat > /etc/X11/Xwrapper.config <<'EOF'
# 'user' launches X from an rc-started shell, not a console session, so
# the console-ownership check must be waived; Hurd Xorg needs root for
# direct VGA/input device access regardless.
allowed_users=anybody
needs_root_rights=yes
EOF

say "lightdm vt-argument shim (for anyone starting lightdm manually)"
cat > /usr/local/sbin/xserver-novt <<'EOF'
#!/bin/sh
# lightdm passes vtN to the X server; Hurd Xorg has no VT concept and
# rejects the option. Strip vtN and pass everything else through.
args=""
for a in "$@"; do
    case "$a" in
        vt[0-9]*) ;;
        *) args="$args $a" ;;
    esac
done
# shellcheck disable=SC2086
exec /usr/bin/Xorg $args
EOF
chmod 0755 /usr/local/sbin/xserver-novt
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-hurd-novt.conf <<'EOF'
[Seat:*]
xserver-command=/usr/local/sbin/xserver-novt
EOF

say "Default mode"
[ -f /etc/hurd-desktop.mode ] || echo none > /etc/hurd-desktop.mode
echo "mode: $(cat /etc/hurd-desktop.mode)"

say "Keep lightdm out of the default boot (mode file decides)"
update-rc.d -f lightdm remove >/dev/null 2>&1 || true

say "Done. Select with: echo vnc|xorg|none > /etc/hurd-desktop.mode"
