#!/bin/sh
# Remove everything install.sh added. Run as your normal user.
set -eu

KEY_PATH=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/touchpad-reset/
KEY_SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KEY_PATH"

echo "==> Removing the watchdog service"
sudo systemctl disable --now touchpad-watchdog 2>/dev/null || true
sudo rm -f /etc/systemd/system/touchpad-watchdog.service
sudo systemctl daemon-reload

echo "==> Removing scripts and sudoers rule"
sudo rm -f /usr/local/sbin/touchpad-watchdog /usr/local/sbin/touchpad-reset \
    /usr/local/sbin/touchpad-slots /etc/sudoers.d/touchpad-reset

if command -v gsettings >/dev/null 2>&1; then
    echo "==> Removing the keyboard shortcut"
    current=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
    updated=$(printf '%s' "$current" | sed -e "s#, '$KEY_PATH'##" -e "s#'$KEY_PATH', ##" -e "s#'$KEY_PATH'##")
    case "$updated" in
        "[]" | "@as []") gsettings reset org.gnome.settings-daemon.plugins.media-keys custom-keybindings ;;
        *) gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated" ;;
    esac
    for key in name command binding; do gsettings reset "$KEY_SCHEMA" "$key"; done
fi

echo "==> Done"
