# Diagnosis

How the cause of the stuck touchpad was found, step by step. Useful if
you have a similar problem on another laptop.

## System

| | |
|---|---|
| Laptop | ASUS VivoBook 15 K3502ZA, BIOS `K3502ZA.308` (05/05/2023) |
| Touchpad | `ASUP1204:00 093A:2642` (PixArt), I2C HID, drivers `i2c_hid_acpi` + `hid-multitouch` |
| OS | Ubuntu, GNOME on Wayland, libinput 1.31.1, kernel 7.0 |

## 1. The kernel shows no errors

```sh
journalctl -k -b | grep -i -E 'i2c|hid|touchpad'
```

Only the normal boot messages, no I2C or HID errors. The touchpad interrupt
(`grep ASUP /proc/interrupts`) keeps counting up: the hardware is not frozen.

## 2. libinput reports "touch jump"

```sh
journalctl -b | grep 'Touch jump'
```

```
libinput error: event4  - ASUP1204:00 093A:2642 Touchpad: kernel bug: Touch jump detected and discarded.
```

Dozens per day, during normal use (not only after resume from sleep). The
firmware sometimes sends a finger position that jumps to an impossible
point. This was the first clue.

## 3. Side issue: invalid libinput quirks file

At every login, libinput logged:

```
libinput error: Failed to load the device quirks from /usr/share/libinput and /etc/libinput/local-overrides.quirks.
```

```sh
libinput quirks validate
# quirks parser error: /etc/libinput/local-overrides.quirks:5: failed to parse AttrPressureRange=0:0
```

An old `/etc/libinput/local-overrides.quirks`, written in an earlier attempt
to fix the touchpad, contained `AttrPressureRange=0:0`. libinput 1.31 rejects
that value, and a single invalid line makes it throw away **all** quirks for
**all** devices.

The file was also useless. The touchpad's capabilities
(`B: ABS=2e0800000000003` in `/proc/bus/input/devices`) contain only
`ABS_MT_SLOT`, `ABS_MT_POSITION_X/Y`, `ABS_MT_TOOL_TYPE` and
`ABS_MT_TRACKING_ID`. There is no pressure or contact-size axis, so
`AttrPressureRange`, `AttrPalmSizeThreshold` and `AttrThumbSizeThreshold` had
no effect.

**Fix:** move the file aside.

```sh
sudo mv /etc/libinput/local-overrides.quirks /etc/libinput/local-overrides.quirks.bak
libinput quirks validate   # no output = OK
```

This fixes the libinput error, but **not** the stuck touchpad.

## 4. Catching the ghost finger

The key clue came from the symptoms: while it was stuck, three fingers moved
the pointer, and later one finger scrolled as if there were two. That points
to a finger that is "down" but doesn't exist.

With the touchpad stuck and **nobody touching it**, the multitouch slot state
was read straight from the kernel (`tools/touchpad-slots`, which uses the
`EVIOCGMTSLOTS` ioctl):

```
slot 0: tracking_id=    -1  x=  615 y=  536
slot 1: tracking_id=  1162  x= 1122 y=    0   <-- ACTIVE
slot 2: tracking_id=    -1  x=  599 y=  343
slot 3: tracking_id=    -1  x=    0 y=    0
slot 4: tracking_id=    -1  x=    0 y=    0
keys down: BTN_TOOL_FINGER, BTN_TOUCH
```

The kernel sees a finger in slot 1, on the top edge (`y=0`), with nothing
touching the touchpad.

Further checks:

- **Same position after 3 seconds:** `tracking_id`, `x` and `y` were
  identical. A real finger always moves at least a little.
- **The firmware keeps reporting it:** about 700 interrupts in 5 seconds
  (~140/s) with the touchpad untouched. So the contact is not "forgotten" by
  the kernel: it is the firmware that keeps sending it. That's why the
  driver's `MT_QUIRK_STICKY_FINGERS` (already active: `quirks` = `334864` in
  `/sys/bus/hid/devices/0018:093A:2642.0001/quirks`) doesn't help, because it
  only releases contacts the device has **stopped** reporting.
- **A reset clears it:** after unbind + bind of the driver, all slots are
  empty (`tracking_id=-1`) and `keys down: none`.

## 5. Conclusion and solution

The touchpad firmware sometimes gets stuck reporting a non-existent contact,
probably after a "touch jump", and the only way to clear it is to reset the
device. Since the ghost stays perfectly still, it can be told apart from a
real finger. Hence the watchdog: a contact at identical coordinates for 8
seconds is treated as a ghost, and the touchpad gets reset.

Possible fixes at the root, not verified:

- A BIOS update from ASUS (the installed one is from 2023).
- Physical causes: ghost contacts on the edges can come from pressure on the
  touchpad, for example a swollen battery. In the observed case the battery
  was at 85% of its original capacity, with no signs of trouble.

## Warning: resetting the driver by hand

The reset is two commands, **unbind** and **bind**. If only the first one
runs, for example because sudo fails on the second, the touchpad stays
disconnected until the bind or a reboot. That's why `touchpad-reset` is a
single script that runs both.

```sh
echo i2c-ASUP1204:00 | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/unbind
echo i2c-ASUP1204:00 | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/bind
```
