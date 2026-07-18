#!/bin/sh
# Stage boot-time desktop autostart inside the Hurd guest.
# Run INSIDE the guest as root. Idempotent.
#
# One provisioned image serves two frontends, selected by a mode file:
#
#   vnc    headless route (QEMU/podman/docker): tigervnc Xvnc :1 renders
#          the XFCE session into its own virtual framebuffer (the Xvfb
#          role and the VNC export in one server) and websockify serves
#          noVNC on 6080, so a browser on the host shows the desktop.
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
# Runs as root from rc.local; the vnc session itself runs as 'user'.
MODE=$(cat /etc/hurd-desktop.mode 2>/dev/null || echo none)
LOG=/var/log/hurd-desktop.log

case "$MODE" in
vnc)
    {
        echo "hurd-desktop: vnc mode $(date 2>/dev/null)"
        # Xvnc :1 = virtual framebuffer + VNC on 5901, XFCE inside.
        su - user -c '
            mkdir -p ~/.vnc
            [ -f ~/.vnc/passwd ] || printf hurdhurd | vncpasswd -f > ~/.vnc/passwd
            chmod 600 ~/.vnc/passwd
            printf "#!/bin/sh\nexec startxfce4\n" > ~/.vnc/xstartup
            chmod +x ~/.vnc/xstartup
            tigervncserver :1 -geometry 1280x800 -depth 24 -localhost no 2>&1
        '
        # noVNC bridge: browser at http://host:6080/vnc.html
        websockify --daemon --web /usr/share/novnc 6080 localhost:5901 2>&1
    } >> "$LOG" 2>&1 &
    ;;
xorg)
    {
        echo "hurd-desktop: xorg mode $(date 2>/dev/null)"
        /etc/init.d/dbus start 2>&1 || true
        /etc/init.d/lightdm start 2>&1
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

say "Default mode"
[ -f /etc/hurd-desktop.mode ] || echo none > /etc/hurd-desktop.mode
echo "mode: $(cat /etc/hurd-desktop.mode)"

say "Keep lightdm out of the default boot (mode file decides)"
update-rc.d -f lightdm remove >/dev/null 2>&1 || true

say "Done. Select with: echo vnc|xorg|none > /etc/hurd-desktop.mode"
