# Tablet on Niri: virtual monitor + scrcpy + file transfer

Set up on 2026-10-19. Everything marked **works** was confirmed on my machine.

## What I ended up with

- A virtual monitor (`Virtual-1`) to the right of the laptop screen. The pointer slides onto it like any other monitor.
- scrcpy mirrors the tablet onto that monitor, so I can click and type on the tablet.
- Right-click **Send to tablet** in Nemo pushes files to `/sdcard/Laptop` on the tablet.
- `fromtab` pulls everything from that folder back to the laptop.

## What didn't work / why

- **KDE Connect / GSConnect / Valent**: can use the tablet as a touchpad for the PC, but can't use the PC mouse on the tablet. GSConnect is GNOME-only anyway.
- **REA (Reverse Engineer Anything)**: helps analyze a binary (pseudocode/assembly), doesn't recover source. Rebuilding Samsung Multi Control (account trust, discovery, pairing, input forwarding) isn't realistic.
- **scrcpy `--otg`**: USB only, blank window, captures the pointer. Doesn't give a seamless slide.
- **Drag and drop onto the scrcpy window**: didn't work for me. Replaced by the Nemo action below.

## 1. Virtual monitor with vkms (works)

```
sudo modprobe vkms
niri msg outputs        # a new Virtual-1 output should appear
```

Load it at every boot:

```
echo vkms | sudo tee /etc/modules-load.d/vkms.conf
```

Undo for the current session: `sudo modprobe -r vkms`.

### Match the tablet's resolution and pin the position

Position is in Niri's *logical* pixels. The laptop is 1669 logical px wide (1920 / 1.15 scale), so x=1670 sits just right of it. Use a negative x equal to the virtual monitor's width to put it on the left instead.

In `~/.config/niri/config.kdl`:

```kdl
output "Virtual-1" {
    mode "1920x1200@59.950"
    position x=1670 y=0
}
```

Live, without editing the config:

```
niri msg output Virtual-1 mode 1920x1200@59.950
niri msg output Virtual-1 position set 1670 0
```

`y` only changes where along the edge the crossing lines up (`y=0` aligns tops).

### Open scrcpy on that output automatically (not tested yet)

```kdl
window-rule {
    match app-id="scrcpy"
    open-on-output "Virtual-1"
    open-fullscreen true
}
```

Check the real app-id with `niri msg windows` while scrcpy is running.

## 2. scrcpy modes

```
scrcpy                                  # seamless slide, no visible cursor on the tablet
scrcpy --mouse=uhid --keyboard=uhid     # real mouse/keyboard on the tablet, but scrcpy captures the pointer
```

- `uhid` flag names are from memory; confirm with `scrcpy --help`.
- In `uhid` mode, scrcpy grabs the mouse while focused, so getting back to the laptop needs scrcpy's modifier key.
- Niri's own keybinds take priority over what scrcpy receives.
- Clipboard sync is on by default.
- Optional: `focus-follows-mouse` inside an `input { }` block in the Niri config, so keyboard focus follows the pointer onto the mirror. It changes focus for all windows.

## 3. Send files to the tablet (works)

### `~/.local/bin/totab`

```bash
#!/bin/sh
DEST="/sdcard/Laptop"
adb shell mkdir -p "$DEST"
for f in "$@"; do
  name=$(basename "$f")
  if adb push "$f" "$DEST/" >/dev/null 2>&1; then
    adb shell touch "'$DEST/$name'"
    notify-send "Sent to tablet" "$name → Laptop"
  else
    notify-send -u critical "Send to tablet FAILED" "$name (is the tablet connected? check adb devices)"
  fi
done
```

```
chmod +x ~/.local/bin/totab
```

Notes:

- `/sdcard` is just the tablet's internal storage (no SD card needed). The folder appears as **Internal storage → Laptop** in My Files.
- `adb push` keeps the file's old modified date; the `touch` line resets it so new sends sort first.
- adb uses the only connected device. If several are connected, set `export ANDROID_SERIAL="<serial from adb devices>"` in the script.
- Wireless debugging ports change on Android 11+, so reconnect with `adb connect` if pushes start failing.
- `mkdir -p` creates the folder on the first run and does nothing afterward.

### Nemo right-click action

`~/.local/share/nemo/actions/send-to-tablet.nemo_action`:

```ini
[Nemo Action]
Name=Send to tablet
Comment=Push selected files to the tablet via adb
Exec=/home/flickowens/.local/bin/totab %F
Icon-Name=phone
Selection=NotNone
Extensions=any;
Quote=double
```

Then restart Nemo with `nemo -q` and reopen it. Use the full path in `Exec` (Nemo doesn't expand `~`).

## 4. Pull files back to the laptop

### `~/.local/bin/fromtab`

```bash
#!/bin/sh
SRC="/sdcard/Laptop"
OUT="$HOME/Downloads/FromTablet"
mkdir -p "$OUT"

if adb pull "$SRC/." "$OUT/" >/dev/null 2>&1; then
  notify-send "Pulled from tablet" "Saved to $OUT"
else
  notify-send -u critical "Pull FAILED" "Is the tablet connected? Does $SRC exist?"
fi
```

```
chmod +x ~/.local/bin/fromtab
```

- The `/.` after `$SRC` copies the folder's contents instead of nesting a `Laptop` folder.
- It re-pulls everything and overwrites same-named files each run.

### PATH fix so `fromtab` runs by name

`~/.local/bin` wasn't in my PATH. Add to `~/.zshrc`, then `source ~/.zshrc`:

```
export PATH="$HOME/.local/bin:$PATH"
```

### Optional Niri keybind (use the full path)

```kdl
binds {
    Mod+Shift+T { spawn "/home/flickowens/.local/bin/fromtab"; }
}
```

Pick a key that doesn't clash with existing binds.

## Quick checks

| Problem | Check |
|---|---|
| Send fails silently or shows FAILED | `adb devices` (0 or 2+ devices breaks it) |
| Not sure a file arrived | `adb shell ls -l /sdcard/Laptop \| grep -i name` |
| No notification at all | A notification daemon (mako, dunst, swaync) has to be running |
| Image doesn't show in Gallery | It's in the folder; the media scanner may lag |
| Virtual-1 missing after reboot | Confirm `/etc/modules-load.d/vkms.conf` exists |
