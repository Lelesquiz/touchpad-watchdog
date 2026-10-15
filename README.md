# touchpad-watchdog

Workaround for a touchpad that **gets stuck** because of a **ghost finger**:
the firmware keeps reporting a finger that is not there.

Tested on an **ASUS VivoBook 15 K3502ZA** (PixArt `ASUP1204:00 093A:2642`
touchpad, I2C HID) with Ubuntu, GNOME on Wayland and kernel 7.0.

## Symptoms

- The pointer stops moving with one finger, but moves with three.
- One finger scrolls instead of moving the pointer, as if two fingers were down.
- `journalctl` shows `kernel bug: Touch jump detected and discarded` messages
  for the touchpad.
- Everything goes back to normal after a reboot or after reloading the driver.

## Cause

Sometimes the touchpad firmware reports a contact that does not exist. It
stays **perfectly still** at the same coordinates (in the observed case
`x=1122, y=0`, on the top edge) until the device is reset. When you put down a
real finger, the system counts two, and you get scrolling instead of pointer
movement.

The problem is in the touchpad firmware, not in libinput or GNOME. The
`hid-multitouch` driver already has a protection against stuck fingers
(`MT_QUIRK_STICKY_FINGERS`), but it doesn't help here because the firmware
keeps confirming the contact about 140 times per second.

The full investigation, with commands and output, is in
[docs/diagnosi.md](docs/diagnosi.md).

## What it installs

| File | What it does |
|---|---|
| `/usr/local/sbin/touchpad-reset` | Reloads the touchpad driver (unbind + bind of `i2c_hid_acpi`). This clears the ghost finger. |
| `/usr/local/sbin/touchpad-watchdog` | Service that, every second, reads the touches the kernel sees. If a contact stays at **identical coordinates for 8 seconds** it resets the touchpad and sends a **desktop notification**. |
| `/etc/systemd/system/touchpad-watchdog.service` | Starts the watchdog at boot and restarts it if it exits. |
| `/usr/local/sbin/touchpad-slots` | Diagnostics: shows the fingers the kernel currently sees. |
| `/etc/sudoers.d/touchpad-reset` | Lets your user run **only** `touchpad-reset` without a password (needed by the shortcut). |
| GNOME shortcut **Super+F12** | Manual reset of the touchpad. |

The watchdog only **reads** the touchpad state (`EVIOCGMTSLOTS` ioctl): it
does not intercept, slow down or modify events.

## Installation

```sh
git clone https://github.com/<user>/touchpad-watchdog.git
cd touchpad-watchdog
./install.sh
```

Run it as your normal user: the script calls `sudo` itself when needed. To
use a different shortcut:

```sh
BINDING='<Super><Shift>t' ./install.sh
```

## Usage

- **Automatic:** do nothing. When the watchdog detects a ghost finger it
  resets the touchpad and you get a "Touchpad resettato" notification.
- **Manual:** press **Super+F12**.
- **Diagnostics:** if the touchpad acts up, don't touch it and run
  `sudo touchpad-slots`. Any line marked `ACTIVE` is a ghost finger.

Check when the watchdog has stepped in:

```sh
journalctl -u touchpad-watchdog
```

## Configuration

The constants are at the top of `bin/touchpad-watchdog`:

| Constant | Default | Meaning |
|---|---|---|
| `STUCK_SECONDS` | `8` | How long a contact must stay still before the reset. |
| `POLL_SECONDS` | `1` | How often the state is read. |
| `COOLDOWN_SECONDS` | `10` | Pause after a reset. |
| `DEVICE_NAME` | `ASUP1204:00 093A:2642 Touchpad` | Name of the touchpad's input device. |

After a change, run `./install.sh` again.

To try the detection without resetting anything:

```sh
sudo /usr/local/sbin/touchpad-watchdog --dry-run
```

## Adapting to another touchpad

1. Find the name of your touchpad:
   `grep -A1 -i touchpad /proc/bus/input/devices`.
2. Put it in `DEVICE_NAME` in `bin/touchpad-watchdog` and
   `tools/touchpad-slots`.
3. Find the I2C device and its driver:
   `ls /sys/bus/i2c/drivers/i2c_hid_acpi/`. Put the device name (e.g.
   `i2c-ELAN0001:00`) in `DEV` in `bin/touchpad-reset`.

This only works for I2C HID touchpads that use the `i2c_hid_acpi` driver.

## Uninstall

```sh
./uninstall.sh
```

## Known limitations

- It is a **workaround**: it does not stop the ghost finger from appearing,
  it removes it within about 8 seconds. The real fix would be a firmware
  update from the manufacturer (check whether a newer BIOS is available).
- If you keep a real finger **perfectly** still for 8 seconds, the touchpad
  gets reset (it comes back within about a second).
- The device names (`ASUP1204`, `i2c_hid_acpi`) are specific to this laptop;
  see [Adapting to another touchpad](#adapting-to-another-touchpad).

## License

MIT, see [LICENSE](LICENSE).
