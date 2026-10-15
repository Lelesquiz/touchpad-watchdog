#!/bin/sh
# Install the touchpad reset script, the ghost-finger watchdog service and
# the Super+F12 shortcut. Run as your normal user: it uses sudo when needed.
set -eu
cd "$(dirname "$0")"

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your normal user, not root: the script calls sudo itself." >&2
    exit 1
fi

KEY_PATH=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/touchpad-reset/
KEY_SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEY_PATH"
BINDING=${BINDING:-'<Super>F12'}

echo "==> Installing scripts"
sudo install -o root -g root -m 0755 bin/touchpad-reset /usr/local/sbin/touchpad-reset
sudo install -o root -g root -m 0755 bin/touchpad-watchdog /usr/local/sbin/touchpad-watchdog
sudo install -o root -g root -m 0755 tools/touchpad-slots /usr/local/sbin/touchpad-slots

echo "==> Allowing $(id -un) to run touchpad-reset without a password"
rule=$(mktemp)
echo "$(id -un) ALL=(root) NOPASSWD: /usr/local/sbin/touchpad-reset" > "$rule"
sudo visudo -cf "$rule" >/dev/null
sudo install -o root -g root -m 0440 "$rule" /etc/sudoers.d/touchpad-reset
rm -f "$rule"

echo "==> Enabling the watchdog service"
sudo install -o root -g root -m 0644 systemd/touchpad-watchdog.service /etc/systemd/system/touchpad-watchdog.service
sudo systemctl daemon-reload
sudo systemctl enable --now touchpad-watchdog
sudo systemctl restart touchpad-watchdog

if command -v gsettings >/dev/null 2>&1; then
    echo "==> Adding the $BINDING shortcut"
    gsettings set "$KEY_SCHEMA" name 'Reset touchpad'
    gsettings set "$KEY_SCHEMA" command 'sudo -n /usr/local/sbin/touchpad-reset'
    gsettings set "$KEY_SCHEMA" binding "$BINDING"
    current=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    case "$current" in
        *"$KEY_PATH"*) ;;
        "@as []" | "[]") gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$KEY_PATH']" ;;
        *) gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "${current%]}, '$KEY_PATH']" ;;
    esac
fi

echo "==> Done"
systemctl status touchpad-watchdog --no-pager --lines=3 || true
