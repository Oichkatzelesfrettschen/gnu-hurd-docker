#!/bin/sh
# Minty Hurd full install (resilient: skips missing packages).
set +e
PATH=$PATH:/usr/sbin:/sbin
export DEBIAN_FRONTEND=noninteractive

log() { printf '\n=== %s ===\n' "$*"; }

# Install one package at a time, log skips
inst() {
    for p in "$@"; do
        if apt-cache show "$p" >/dev/null 2>&1; then
            apt-get install -y --no-install-recommends "$p" 2>&1 | tail -2
        else
            echo "  skip-missing: $p"
        fi
    done
}

log "Step 0: dpkg state + apt update"
dpkg --configure -a 2>&1 | tail -3
apt-get update 2>&1 | tail -3

log "Step 2: Xorg core + input/video"
inst xserver-xorg-core xserver-xorg-input-kbd xserver-xorg-input-mouse \
     xserver-xorg-video-vesa xserver-xorg-video-fbdev xserver-xorg-video-dummy \
     xinit xauth x11-utils x11-xserver-utils x11-apps \
     dbus dbus-x11

log "Step 3: XFCE + Whisker + display manager"
inst xfce4 xfce4-goodies xfce4-terminal \
     xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin \
     xfce4-notifyd xfce4-screensaver xfce4-screenshooter \
     thunar lightdm lightdm-gtk-greeter

log "Step 4: Mint themes already installed - icons + arc + papirus"
inst arc-theme papirus-icon-theme adwaita-icon-theme gnome-themes-extra \
     breeze-icon-theme hicolor-icon-theme

log "Step 5: audio + utilities"
inst pulseaudio pulseaudio-utils pavucontrol \
     gvfs gvfs-backends gvfs-daemons \
     upower gnome-keyring \
     file-roller galculator mousepad \
     fonts-dejavu fonts-liberation fonts-noto

log "Step 6: polkit"
inst policykit-1 xfce-polkit consolekit libpam-ck-connector

log "Step 7: VNC + noVNC"
inst x11vnc tigervnc-standalone-server tigervnc-common websockify novnc

log "Step 8: tmux + mosh + CLI utilities"
inst tmux mosh htop iotop ncdu tree jq ripgrep fd-find bat \
     bash-completion zsh fish-shell rsync openssl ca-certificates

log "Step 9: fastfetch"
inst fastfetch

mkdir -p /etc/skel/.config/fastfetch
cat > /etc/skel/.config/fastfetch/config.jsonc <<'FF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": { "source": "Mint", "type": "builtin", "padding": { "top": 1, "right": 2 } },
    "display": { "color": { "keys": "green", "title": "cyan" }, "separator": " > " },
    "modules": [
        "break",
        { "type": "title", "format": "{6}Minty Hurd{2} -- {7}{user-name}{2}@{8}{host-name}" },
        "separator", "os", "kernel", "uptime", "packages", "shell", "wm",
        "terminal", "cpu", "memory", "disk", "localip",
        "break", "colors"
    ]
}
FF
mkdir -p /home/user/.config
cp -r /etc/skel/.config/fastfetch /home/user/.config/ 2>/dev/null || true
chown -R 1001:1001 /home/user/.config/fastfetch 2>/dev/null || true

# Splash on login
for rc in /etc/skel/.bashrc /home/user/.bashrc /root/.bashrc; do
    [ -f "$rc" ] && ! grep -q FASTFETCH_SHOWN "$rc" 2>/dev/null && cat >> "$rc" <<'RC'

# Minty Hurd splash
if [ -t 1 ] && [ -z "$FASTFETCH_SHOWN" ] && command -v fastfetch >/dev/null 2>&1; then
    export FASTFETCH_SHOWN=1
    fastfetch
fi
RC
done

# /etc/issue + /etc/motd branding
cat > /etc/issue <<'ISSUE'

  Minty Hurd  (\d \l)
  Debian GNU/Hurd 0.9 + LMDE7 (gigi) themes
  GNU-Mach 1.8 + Hurd-0.9 -- amd64

ISSUE

cat > /etc/motd <<'MOTD'
    _____ _____ _____  _____  __ __    _____ _____ _____ _____
   |     |     |   | ||_   _||  |  |  |  |  |  |  | __  |  _  |
   | | | |-   -| | | |  | |  |_   _|  |     |  |  |    -|     |
   |_|_|_|_____|_|___|  |_|    |_|    |__|__|_____|__|__|__|__|

   Minty Hurd  --  Linux Mint themes + Debian GNU/Hurd + Whisker Menu

MOTD

log "Step 10: tmux + mosh config"
cat > /etc/skel/.tmux.conf <<'TC'
set -g default-terminal "tmux-256color"
set -g terminal-overrides ',xterm-256color:RGB'
set -g mouse on
set -g history-limit 100000
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
setw -g mode-keys vi
set -g escape-time 10
unbind C-b
set -g prefix C-a
bind C-a send-prefix
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind r source-file ~/.tmux.conf \; display "tmux.conf reloaded"
set -g status-style "bg=#3eb489,fg=#1a1a1a"
set -g status-left "#[fg=#1a1a1a,bold] Minty Hurd "
set -g status-left-length 24
set -g status-right "#[fg=#1a1a1a] %Y-%m-%d %H:%M "
setw -g window-status-current-style "bg=#1a1a1a,fg=#3eb489"
TC
cp /etc/skel/.tmux.conf /home/user/.tmux.conf 2>/dev/null || true
chown 1001:1001 /home/user/.tmux.conf 2>/dev/null || true

grep -q MOSH_PORT_RANGE /etc/skel/.profile 2>/dev/null || echo 'export MOSH_PORT_RANGE=60000-60100' >> /etc/skel/.profile
grep -q MOSH_PORT_RANGE /home/user/.profile 2>/dev/null || echo 'export MOSH_PORT_RANGE=60000-60100' >> /home/user/.profile

log "Step 11: lightdm + dbus at boot"
update-rc.d lightdm enable 2 3 4 5 2>&1 | head -3
update-rc.d dbus enable 2 3 4 5 2>&1 | head -3

log "=== Done -- Minty Hurd installed ==="
df -h / | head -2
echo
echo "Run: startxfce4   (from a tty session)"
echo "Or:  /etc/init.d/lightdm start"
