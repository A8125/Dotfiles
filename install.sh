#!/usr/bin/env bash
# Rebuild this setup on a fresh Arch/CachyOS machine.
# Usage:
#   ./install.sh                  # packages + stow; asks about wallpapers
#   ./install.sh --wallpapers     # also copy wallpapers, no prompt
#   ./install.sh --no-wallpapers  # skip wallpapers, no prompt
#   ./install.sh --system         # also install locale/vconsole/sddm configs (needs sudo)
#   ./install.sh --help           # show this message
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES=(
  zsh niri noctalia kitty alacritty foot ghostty fuzzel btop yazi cava rmpc
  mpd micro zed nvim fastfetch matugen gtk qt kde autostart pipewire
  thunar rog opencode bin notes
)

SYSTEM=0
WALLPAPERS=""   # empty = ask, yes = copy, no/skipped = skip

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTION]...

  --system          also install locale.conf, vconsole.conf and sddm.conf
                    into /etc/ (needs sudo)
  --wallpapers      copy the 32 MB wallpaper set to ~/Pictures/Wallpapers
  --no-wallpapers   skip wallpapers without asking
  -h, --help        show this help and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)        SYSTEM=1 ;;
    --wallpapers)    WALLPAPERS=yes ;;
    --no-wallpapers) WALLPAPERS=no ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2; exit 1 ;;
  esac
  shift
done

command -v stow >/dev/null || { echo "install GNU stow first: sudo pacman -S stow"; exit 1; }

# --- packages ---------------------------------------------------------------
if command -v paru >/dev/null; then
  paru -S --needed - < "$REPO/pkglist.txt" || echo "WARNING: some packages failed; continuing"
  paru -S --needed - < "$REPO/pkglist-aur.txt" || echo "WARNING: some packages failed; continuing"
else
  echo "paru not found - install pkglist.txt / pkglist-aur.txt manually"
fi

# --- dotfiles ---------------------------------------------------------------
cd "$REPO"

# On a fresh machine some targets may already exist (e.g. ~/.bashrc is fine,
# but ~/.zshrc or ~/.config/gtk-3.0/settings.ini may not). Move those aside,
# never delete:
for pkg in "${PACKAGES[@]}"; do
  while IFS= read -r f; do
    rel="${f#*/}"
    t="$HOME/$rel"
    [ -e "$t" ] && [ ! -L "$t" ] && mv "$t" "$t.pre-stow"
  done < <(find "$pkg" -type f)
done

stow --no-folding -v -t "$HOME" "${PACKAGES[@]}"

# --- wallpapers (opt-in) ----------------------------------------------------
# Plain files, not stowed: they belong in the XDG Pictures dir, not ~/.config.
# Copy the *contents* so re-running merges instead of nesting Wallpapers/.
if [[ -z "$WALLPAPERS" ]]; then
  if [ -t 0 ]; then
    printf 'Copy the 32 MB wallpaper set to ~/Pictures/Wallpapers? [y/N] '
    read -r ans || ans=""
    case "$ans" in
      [yY]|[yY][eE][sS]) WALLPAPERS=yes ;;
      *) WALLPAPERS=no ;;
    esac
  else
    WALLPAPERS=no
    echo "stdin is not a terminal - skipping wallpapers (use --wallpapers to copy them)."
  fi
fi

if [[ "$WALLPAPERS" == yes ]]; then
  if [ -d "$REPO/Wallpapers" ]; then
    mkdir -p "$HOME/Pictures/Wallpapers"
    cp -a "$REPO/Wallpapers/." "$HOME/Pictures/Wallpapers/"
    echo "Wallpapers copied to $HOME/Pictures/Wallpapers"
  else
    echo "WARNING: $REPO/Wallpapers not found - skipping wallpapers"
    WALLPAPERS=skipped
  fi
else
  echo "Skipping wallpapers (re-run with --wallpapers to copy them later)."
fi

# --- system files (optional) ------------------------------------------------
if [[ "$SYSTEM" -eq 1 ]]; then
  for f in locale.conf vconsole.conf sddm.conf; do
    sudo install -m 644 -o root -g root "$REPO/system/etc/$f" "/etc/$f"
  done
  echo "Copied locale.conf, vconsole.conf and sddm.conf to /etc/."
  echo "Host files (fstab, hostname, pacman.conf, mkinitcpio*, limine-*) are"
  echo "kept as reference in system/reference/ - review them, do not copy them"
  echo "to another machine."
fi

cat <<'EOF'

Done. Manual steps that are NOT automated:
  - fonts: copy/download your Nerd Fonts into ~/.fonts (not tracked: 318 MB)
  - niri display config is host-specific (~/.config/niri/cfg/display.kdl):
    regenerate with `niri msg outputs`
  - noctalia wallpaper dir is hardcoded in ~/.config/noctalia/settings.json:
    set wallpaper.directory to ~/Pictures/Wallpapers if your $HOME differs
  - re-auth: gh auth login, ssh keys, gnupg (never tracked)
  - enabled services: see services-system.txt / services-user.txt
  - matugen: regenerate ~/.config/matugen/generated/ then reload niri
EOF

if [[ "$WALLPAPERS" != yes ]]; then
  cat <<'EOF'
  - wallpapers were skipped: matugen and Noctalia expect a wallpaper directory.
    Copy them later with `./install.sh --wallpapers` (or
    `mkdir -p ~/Pictures/Wallpapers && cp -a ./Wallpapers/. ~/Pictures/Wallpapers/`),
    or point wallpaper.directory in ~/.config/noctalia/settings.json at another
    directory.
EOF
fi
