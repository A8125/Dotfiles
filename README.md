# Dotfiles

Niri + Noctalia desktop, zsh, and CLI configs, managed with **GNU Stow**.

Live files in `$HOME` are symlinks into this repo. Editing
`~/.config/kitty/kitty.conf` edits `kitty/.config/kitty/kitty.conf` here.

## Screenshots

| Desktop | Overview |
|---|---|
| ![Niri desktop with fastfetch](assets/screenshots/Desktop.png) | ![Niri overview](assets/screenshots/overview.png) |

btop, rmpc and cava running as a floating TUI stack:

![btop and rmpc](assets/screenshots/btop-and-rmpc.png)

## Layout

| Package | Target |
|---|---|
| `zsh` | `~/.zshrc`, `~/.config/zsh/{aliases,functions}.zsh`, `~/.config/zshrc/logs` |
| `niri` | `~/.config/niri/` (`config.kdl`, `cfg/`, `animations/`) |
| `noctalia` | `~/.config/noctalia/{settings,colors,plugins}.json` |
| `kitty` `alacritty` `foot` `ghostty` `fuzzel` | terminal + launcher configs |
| `btop` `yazi` `cava` `rmpc` `mpd` | TUI apps (mpd: config only) |
| `micro` `zed` `nvim` `fastfetch` | editors + fetch (micro settings only, no syntax/) |
| `matugen` `gtk` `qt` `kde` `autostart` `pipewire` `thunar` `rog` | theming / desktop integration |
| `opencode` | `opencode.jsonc`, `package.json`, `plugins/`, `skills/` |
| `bin` | `~/.local/bin/{fromtab,mkm3u,syncm3u,tabscreen}` |
| `notes` | `~/notes/` (personal) |
| `assets` | README screenshots (not stowed) |
| `Wallpapers` | copied to `~/Pictures/Wallpapers` on request (not stowed) |

Not stowed: `assets/`, `Wallpapers/`, `pkglist*.txt`, `services-*.txt`,
`system/` (`etc/` copied with sudo, `reference/` is read-only reference),
`install.sh`, `README.md`, `.gitignore`.

## Prerequisites

- **Arch-based system**, tested on CachyOS. `pkglist.txt` contains packages that
  only exist in the CachyOS repositories: all 17 `cachyos-*` entries, the six
  `linux-cachyos*` kernels/headers, `chwd`, and `limine-snapper-sync`. On plain
  Arch, delete those lines or add the CachyOS repos to `/etc/pacman.conf` first.
- A normal `sudo` user with internet access.
- `git`, `base-devel` and `stow` — the script exits if `stow` is missing:

    ```bash
    sudo pacman -S --needed git base-devel stow
    ```

- An AUR helper. `install.sh` looks for **paru** specifically: on CachyOS
  `sudo pacman -S paru` is enough, on Arch install it from the AUR first. If it
  is missing the script skips packages (warning only) but still stows the
  dotfiles, so you would have to install `pkglist.txt` and `pkglist-aur.txt` by
  hand. `paru` is listed in `pkglist.txt` too, but it has to exist *before* the
  script runs.
- Hardware-specific lines in `pkglist.txt` — delete the ones that do not apply
  to your machine:
  - NVIDIA: `nvidia-utils` `nvidia-settings` `nvidia-prime` `opencl-nvidia`
    `lib32-nvidia-utils` `lib32-opencl-nvidia` `libva-nvidia-driver`
    `linux-cachyos-nvidia-open` `linux-cachyos-lts-nvidia-open`
  - ASUS/ROG: `asusctl` `rog-control-center`
  - Intel CPU/GPU: `intel-lpmd` `intel-ucode` `intel-media-driver`
    `vulkan-intel` `lib32-vulkan-intel` `vpl-gpu-rt`
  - Extra kernels: `linux-cachyos` `linux-cachyos-headers` `linux-cachyos-lts`
    `linux-cachyos-lts-headers` (keep only the one you boot)
- AUR packages most likely to fail: `checkra1n-cli` / `checkra1n-gui` (obsolete
  x86_64 jailbreak binaries), `woeusb` (unmaintained; `woeusb-ng` is the
  maintained fork), `python-fabric-git` + `fabric-cli-git` (two git builds of
  the same tool), `gray-git`, `qtengine`, `peaclock` and `awww-git` (git builds
  that can break or take a while to compile). Comment out any that fail and
  re-run — the script is re-runnable.

## Install

```bash
git clone https://github.com/A8125/Dotfiles.git ~/Projects/dots
cd ~/Projects/dots
./install.sh                  # packages + stow; asks about wallpapers
./install.sh --wallpapers     # also copy wallpapers, no prompt
./install.sh --no-wallpapers  # skip wallpapers, no prompt
./install.sh --system         # also copy locale/vconsole/sddm configs to /etc
```

All flags combine (for example `./install.sh --system --no-wallpapers`), and
`./install.sh --help` prints the usage. The wallpaper prompt defaults to **no**,
and a non-interactive stdin (pipe, cron, `curl | bash`) also means no.

Review and trim `pkglist.txt` / `pkglist-aur.txt` first (see Prerequisites).
Package failures are non-fatal: both `paru` calls end with
`WARNING: some packages failed; continuing`, so a broken AUR build does not
block the dotfiles from being stowed.

What `install.sh` does, in order:

1. Exits with `install GNU stow first: sudo pacman -S stow` if `stow` is missing.
2. If `paru` is on `PATH`, runs `paru -S --needed - < pkglist.txt` and then the
   same for `pkglist-aur.txt`; without `paru` it prints a warning and continues.
   The AUR names also appear in `pkglist.txt`; `--needed` makes the duplicates
   harmless.
3. Moves conflicting files aside: every tracked file that already exists in
   `$HOME` as a real file is renamed to `<file>.pre-stow` (never deleted; an
   existing `.pre-stow` is overwritten).
4. Stows the 28 packages with `stow --no-folding -v -t "$HOME" …`.
5. Copies `Wallpapers/` (32 MB) to `~/Pictures/Wallpapers` only if you answer
   yes to the prompt or pass `--wallpapers`. The files are copied, never
   symlinked, and re-runs merge into the existing directory. With
   `--no-wallpapers`, a non-interactive stdin, or a missing `Wallpapers/`
   directory it skips the copy.
6. With `--system` as the first argument, installs `locale.conf`,
   `vconsole.conf` and `sddm.conf` into `/etc/` via
   `sudo install -m 644 -o root -g root`.
7. Prints the leftover manual steps.

Log out and back in afterwards (or reboot) so the new shell, session and `PATH`
entries take effect.

### Stow target

Always pass `-t ~`. Stow's default target is the parent of the stow directory, so
running `stow zsh` inside the repo would link `~/Projects/.zshrc` instead of
`~/.zshrc`.

`--no-folding` is used deliberately: every file is linked individually, so apps
writing new files into `~/.config/<app>/` do not write into this repo.

### System files (`--system`)

The flag copies only three safe files into `/etc/`, owned by root with mode
`644`:

```
/etc/locale.conf
/etc/vconsole.conf
/etc/sddm.conf
```

Everything host- or boot-specific is kept as **reference only** in
`system/reference/` and is never copied by the script: `fstab`, `hostname`,
`pacman.conf`, `mkinitcpio.conf`, `mkinitcpio.conf.d/` (with `10-chwd.conf` and
`10-limine-snapper-sync.conf`) and `limine-entry-tool.conf` +
`limine-snapper-sync.conf`. Read them when rebuilding a machine: `fstab` pins
that disk's UUIDs and btrfs subvolumes, `mkinitcpio.conf` and `10-chwd.conf`
assume its NVIDIA modules, `pacman.conf` assumes its repo setup, and the Limine
files describe its ESP path and snapshot layout. Copying `fstab`,
`mkinitcpio.conf` or the `limine-*` files to a different machine can make it
unbootable.

## After installing

- Log out and back in if you have not already, then re-authenticate:
  `gh auth login`, and recreate your SSH and GPG keys (never tracked).
- Regenerate the monitor layout: run `niri msg outputs` and edit
  `~/.config/niri/cfg/display.kdl` to match your outputs.
- If your home directory is not `/home/flickowens`, point `wallpaper.directory`
  in `~/.config/noctalia/settings.json` at your own `~/Pictures/Wallpapers`.
- Enable the services you need; the full lists are in `services-system.txt` and
  `services-user.txt`:

    ```bash
    sudo systemctl enable --now bluetooth.service
    systemctl --user enable --now mpd.service
    ```

- Pick a wallpaper once (Noctalia's picker) so matugen regenerates
  `~/.config/matugen/generated/`, then reload niri so the generated colours are
  picked up.
- System-level pieces that are not tracked here: the SDDM `silent` theme
  install, Limine bootloader configuration, Snapper snapshots, `ufw` rules, plus
  fonts and any `secrets.zsh` (both covered under Manual steps).

## Manual steps

- Fonts: `~/.fonts` is 318 MB and untracked.
- `kitty/.config/kitty/kitty-colors.conf` is a placeholder; matugen normally
  regenerates it into `~/.config/matugen/generated/`.
- Secrets are never tracked: `~/.config/gh/hosts.yml`,
  `~/.config/opencode/service.json`, `~/.ssh`, `~/.gnupg`,
  and any `secrets.zsh` (sourced optionally by `.zshrc`).

## Rollback

```bash
cd ~/Projects/dots
stow -D -t ~ zsh niri noctalia kitty alacritty foot ghostty fuzzel btop yazi \
  cava rmpc mpd micro zed nvim fastfetch matugen gtk qt kde autostart \
  pipewire thunar rog opencode bin notes
find ~ -maxdepth 6 -name '*.pre-stow'
```

`*.pre-stow` files are the pre-stow originals; rename them back if needed.
Wallpapers copied to `~/Pictures/Wallpapers` are not stow-managed — delete the
directory by hand if you want them gone.
