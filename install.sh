#!/usr/bin/env bash
# Rebuild this setup on a fresh Arch/CachyOS machine.
# Usage:
#   ./install.sh                  # interactive profile menu + stow
#   ./install.sh --wallpapers     # also copy wallpapers, no prompt
#   ./install.sh --no-wallpapers  # skip wallpapers, no prompt
#   ./install.sh --system         # also install locale/vconsole/sddm configs (needs sudo)
#   ./install.sh --all-packages   # skip hardware filtering (install everything)
#   ./install.sh --help           # show this message

# ---------------------------------------------------------------------------
# Globals (set before parse_args so test harnesses can override them)
# ---------------------------------------------------------------------------
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM=0
WALLPAPERS=""    # empty = ask, yes = copy, no/skipped = skip
ALL_PACKAGES=0
PROFILE=""       # set by interactive menu

# Stow package lists
FULL_PACKAGES=(
  zsh niri noctalia kitty alacritty foot ghostty fuzzel btop yazi cava rmpc
  mpd micro zed nvim fastfetch matugen gtk qt kde autostart pipewire
  thunar rog opencode bin notes
)
MINIMAL_PACKAGES=(
  zsh niri noctalia kitty fastfetch matugen pipewire
)

# PACKAGES is set after profile selection; kept as a global so move_conflicts
# and stow_packages can reference it without arguments.
PACKAGES=()

# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTION]...

  --system          also install locale.conf, vconsole.conf and sddm.conf
                    into /etc/ (needs sudo)
  --wallpapers      copy the 32 MB wallpaper set to ~/Pictures/Wallpapers
  --no-wallpapers   skip wallpapers without asking
  --all-packages    skip hardware filtering; install every package in the lists
  -h, --help        show this help and exit

Flags can be combined, e.g. ./install.sh --system --no-wallpapers
EOF
}

# ---------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --system)        SYSTEM=1 ;;
      --wallpapers)    WALLPAPERS=yes ;;
      --no-wallpapers) WALLPAPERS=no ;;
      --all-packages)  ALL_PACKAGES=1 ;;
      -h|--help)       usage; exit 0 ;;
      *)               usage >&2; exit 1 ;;
    esac
    shift
  done
}

# ---------------------------------------------------------------------------
# Profile selection — always interactive menu
# ---------------------------------------------------------------------------
select_profile() {
  local ans tries=0

  if [ ! -t 0 ]; then
    PROFILE=minimal
    echo "stdin is not a terminal — defaulting to minimal profile."
    return
  fi

  while [[ $tries -lt 3 ]]; do
    printf '\nChoose what to install:\n'
    printf '  1) Minimal - niri + noctalia + kitty + fastfetch   [default]\n'
    printf '  2) Full    - all packages and dotfiles from my setup\n'
    printf 'Choice [1/2]: '
    read -r ans || ans=""
    case "${ans,,}" in
      ""|1|minimal) PROFILE=minimal; break ;;
      2|full)       PROFILE=full;    break ;;
      *)
        echo "Invalid choice; please enter 1 or 2."
        (( tries++ )) || true
        ;;
    esac
  done

  if [[ -z "$PROFILE" ]]; then
    PROFILE=minimal
    echo "No valid choice after 3 attempts — using minimal."
  fi

  echo "Profile: $PROFILE"
}

# ---------------------------------------------------------------------------
# Apply chosen profile → set PACKAGES and active package list files
# ---------------------------------------------------------------------------
apply_profile() {
  case "$PROFILE" in
    full)
      PACKAGES=("${FULL_PACKAGES[@]}")
      ACTIVE_PKGLIST="$REPO/pkglist.txt"
      ACTIVE_AURLIST="$REPO/pkglist-aur.txt"
      ;;
    minimal)
      PACKAGES=("${MINIMAL_PACKAGES[@]}")
      ACTIVE_PKGLIST="$REPO/pkglist-minimal.txt"
      ACTIVE_AURLIST="$REPO/pkglist-aur.txt"
      ;;
    *)
      echo "ERROR: unknown profile '$PROFILE'" >&2; exit 1 ;;
  esac
  echo "Installing profile: $PROFILE"
  echo "  Stow packages: ${PACKAGES[*]}"
}

# ---------------------------------------------------------------------------
# FIX 2a – Bootstrap: ensure git, base-devel, stow, zsh, fastfetch, chafa
# ---------------------------------------------------------------------------
bootstrap_pacman() {
  echo "NOTE: Running pacman -Syu — this is a full system upgrade; you can Ctrl-C now to abort."
  sudo pacman -Syu --needed git base-devel stow zsh fastfetch chafa
}

# ---------------------------------------------------------------------------
# FIX 2b – Install paru if missing
# ---------------------------------------------------------------------------
install_paru() {
  if command -v paru >/dev/null 2>&1; then
    return 0
  fi
  echo "paru not found — trying pacman (CachyOS repo)…"
  if sudo pacman -S --needed paru 2>/dev/null; then
    echo "paru installed from pacman."
    return 0
  fi
  echo "Not in pacman repos; building paru from AUR…"
  local tmpdir
  tmpdir="$(mktemp -d)"
  git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
  ( cd "$tmpdir/paru" && makepkg -si )
  rm -rf "$tmpdir"
  if ! command -v paru >/dev/null 2>&1; then
    echo "ERROR: paru build failed. Install it manually and re-run." >&2
    return 1
  fi
  echo "paru installed from AUR."
}

# ---------------------------------------------------------------------------
# FIX 2d – Hardware detection helpers
# ---------------------------------------------------------------------------
_has_pci_vendor_in_class() {
  # Usage: _has_pci_vendor_in_class <class_prefix_hex> <vendor_hex>
  # class_prefix e.g. "0x03" for display (0x030000–0x03ffff)
  # vendor e.g. "0x10de" for NVIDIA
  local class_prefix="$1" vendor_target="$2"
  local devpath class_val vendor_val
  for devpath in /sys/bus/pci/devices/*/class; do
    [[ -r "$devpath" ]] || continue
    class_val="$(cat "$devpath" 2>/dev/null)" || continue
    # class is a full 6-digit hex e.g. 0x030000; check prefix
    [[ "${class_val,,}" == "${class_prefix,,}"* ]] || continue
    vendor_val="$(cat "${devpath%class}vendor" 2>/dev/null)" || continue
    [[ "${vendor_val,,}" == "${vendor_target,,}" ]] && return 0
  done
  return 1
}

_has_nvidia()      { _has_pci_vendor_in_class "0x03" "0x10de"; }
_has_intel_gpu()   { _has_pci_vendor_in_class "0x03" "0x8086"; }
_has_asus()        { grep -qi "ASUS" /sys/class/dmi/id/sys_vendor 2>/dev/null; }
_is_genuine_intel_bare() {
  grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null && \
  ! systemd-detect-virt -q 2>/dev/null
}

# Build ONE exclusion regex from hardware that isn't present.
# Returns the regex in SKIP_REGEX (empty string = skip nothing).
build_skip_regex() {
  SKIP_REGEX=""
  local parts=()

  # Kernels: always skip by default unless --all-packages
  if [[ "$ALL_PACKAGES" -eq 0 ]]; then
    parts+=("^linux-cachyos")
  fi

  if [[ "$ALL_PACKAGES" -eq 0 ]]; then
    _has_nvidia      || parts+=("nvidia")
    _has_asus        || parts+=("^asusctl$" "^rog-control-center$" "^supergfxctl$")
    _has_intel_gpu   || parts+=("^intel-media-driver$" "^libva-intel-driver$" \
                                "^vulkan-intel$" "^lib32-vulkan-intel$" "^vpl-gpu-rt$")
    _is_genuine_intel_bare || parts+=("^intel-ucode$" "^intel-lpmd$")
  fi

  if [[ "${#parts[@]}" -gt 0 ]]; then
    # Join with |
    local IFS="|"
    SKIP_REGEX="${parts[*]}"
  fi
}

# ---------------------------------------------------------------------------
# FIX 2c – Install packages safely
# ---------------------------------------------------------------------------
install_packages() {
  export LC_ALL=C

  local aur_pkgs=()
  # Read full AUR list (always used for AUR resolution regardless of profile)
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    aur_pkgs+=("$line")
  done < "$ACTIVE_AURLIST"

  # Build hardware skip regex
  build_skip_regex

  # Read the profile package list, strip comments/blanks, apply hardware filter
  local all_pkgs=()
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    all_pkgs+=("$line")
  done < "$ACTIVE_PKGLIST"

  local filtered_pkgs=() skipped_hw=()
  for pkg in "${all_pkgs[@]}"; do
    if [[ -n "$SKIP_REGEX" ]] && echo "$pkg" | grep -Eq "$SKIP_REGEX"; then
      skipped_hw+=("$pkg")
    else
      filtered_pkgs+=("$pkg")
    fi
  done

  # Get available packages in enabled repos (sorted)
  local repo_avail
  repo_avail="$(pacman -Slq 2>/dev/null | sort)"

  # Split filtered list into repo-available and not
  local avail_pkgs=() unavail_pkgs=() aur_set=()
  # Build a lookup set for AUR packages
  for p in "${aur_pkgs[@]}"; do aur_set+=("$p"); done

  for pkg in "${filtered_pkgs[@]}"; do
    if echo "$repo_avail" | grep -Fxq "$pkg"; then
      avail_pkgs+=("$pkg")
    else
      unavail_pkgs+=("$pkg")
    fi
  done

  # Install repo-available packages
  if [[ "${#avail_pkgs[@]}" -gt 0 ]]; then
    echo "Installing ${#avail_pkgs[@]} packages from repos…"
    paru -S --needed "${avail_pkgs[@]}" || echo "WARNING: some repo packages failed; continuing"
  fi

  # Report unavailable packages that are NOT in the AUR list
  local truly_unavail=()
  for pkg in "${unavail_pkgs[@]}"; do
    local in_aur=0
    for a in "${aur_set[@]}"; do [[ "$a" == "$pkg" ]] && in_aur=1 && break; done
    [[ "$in_aur" -eq 0 ]] && truly_unavail+=("$pkg")
  done

  # For minimal profile: only install AUR packages that appear in the active pkglist
  local active_aur_pkgs=()
  if [[ "$PROFILE" == "minimal" ]]; then
    for pkg in "${aur_pkgs[@]}"; do
      for active in "${all_pkgs[@]}"; do
        if [[ "$active" == "$pkg" ]]; then
          active_aur_pkgs+=("$pkg")
          break
        fi
      done
    done
  else
    active_aur_pkgs=("${aur_pkgs[@]}")
  fi

  # Install AUR list: batch first, then per-package retry on failure
  local aur_failed=()
  if [[ "${#active_aur_pkgs[@]}" -gt 0 ]]; then
    echo "Installing ${#active_aur_pkgs[@]} AUR packages…"
    if ! paru -S --needed "${active_aur_pkgs[@]}" 2>/dev/null; then
      echo "Batch AUR install failed; retrying one at a time…"
      for pkg in "${active_aur_pkgs[@]}"; do
        if ! paru -S --needed "$pkg" 2>/dev/null; then
          echo "  WARNING: AUR package '$pkg' failed to build"
          aur_failed+=("$pkg")
        fi
      done
    fi
  fi

  # Summary
  echo ""
  echo "── Package install summary ──────────────────────────────"
  if [[ "${#skipped_hw[@]}" -gt 0 ]]; then
    echo "  Skipped (hardware not detected):"
    printf '    %s\n' "${skipped_hw[@]}"
  else
    echo "  Skipped (hardware): none"
  fi
  if [[ "${#truly_unavail[@]}" -gt 0 ]]; then
    echo "  Not found in any repo (check spelling or add repos):"
    printf '    %s\n' "${truly_unavail[@]}"
  else
    echo "  Not available in repos: none"
  fi
  if [[ "${#aur_failed[@]}" -gt 0 ]]; then
    echo "  AUR packages that failed to build:"
    printf '    %s\n' "${aur_failed[@]}"
  else
    echo "  AUR failed: none"
  fi
  echo "─────────────────────────────────────────────────────────"
}

# ---------------------------------------------------------------------------
# Conflict handling (FIX: safe under set -euo pipefail)
# ---------------------------------------------------------------------------
move_conflicts() {
  local pkg
  for pkg in "${PACKAGES[@]}"; do
    [[ -d "$REPO/$pkg" ]] || continue   # FIX 2e guard
    while IFS= read -r f; do
      local rel="${f#*/}"
      local t="$HOME/$rel"
      if [[ -e "$t" ]] && [[ ! -L "$t" ]]; then
        mv "$t" "$t.pre-stow"
        echo "  moved $t → $t.pre-stow"
      fi
    done < <(find "$REPO/$pkg" -type f)
  done
}

# ---------------------------------------------------------------------------
# FIX 2e – Stow only packages whose directory exists in the repo
# ---------------------------------------------------------------------------
stow_packages() {
  local to_stow=() missing=()
  local pkg
  for pkg in "${PACKAGES[@]}"; do
    if [[ -d "$REPO/$pkg" ]]; then
      to_stow+=("$pkg")
    else
      missing+=("$pkg")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "WARNING: these package dirs are missing from the repo and were skipped:"
    printf '  %s\n' "${missing[@]}"
  fi

  if [[ "${#to_stow[@]}" -gt 0 ]]; then
    stow --no-folding -v -t "$HOME" "${to_stow[@]}"
  fi
}

# ---------------------------------------------------------------------------
# FIX 1c – setup_fastfetch
# ---------------------------------------------------------------------------
setup_fastfetch() {
  local cfg_link="$HOME/.config/fastfetch/config.jsonc"
  local repo_cfg="$REPO/fastfetch/.config/fastfetch/config.jsonc"

  # Warn if fastfetch / chafa missing
  command -v fastfetch >/dev/null 2>&1 || \
    echo "WARNING: fastfetch not found; install it and re-run to verify config"
  command -v chafa >/dev/null 2>&1 || \
    echo "WARNING: chafa not found; fastfetch kitty-logo rendering needs chafa"

  # Copy pngs from the repo into ~/.config/fastfetch/pngs/
  local repo_pngs="$REPO/fastfetch/.config/fastfetch/pngs"
  local user_pngs="$HOME/.config/fastfetch/pngs"
  if [[ -d "$repo_pngs" ]]; then
    mkdir -p "$user_pngs"
    cp -a "$repo_pngs/." "$user_pngs/"
    echo "fastfetch: copied pngs to $user_pngs"
  else
    echo "WARNING: fastfetch pngs directory not found in repo ($repo_pngs)"
  fi

  [[ -f "$repo_cfg" ]] || { echo "WARNING: fastfetch config not in repo ($repo_cfg)"; return; }

  # Read the config to find /home/<name> paths
  local cfg_content
  cfg_content="$(cat "$repo_cfg")"
  local has_foreign_home=0
  if echo "$cfg_content" | grep -qE '"/home/[^/"]+'; then
    local embedded_home
    embedded_home="$(echo "$cfg_content" | grep -oE '/home/[^/"]+' | head -1)"
    if [[ "$embedded_home" != "$HOME" ]]; then
      has_foreign_home=1
    fi
  fi

  if [[ "$has_foreign_home" -eq 1 ]]; then
    local user_cfg_dir="$HOME/.config/fastfetch"
    local user_cfg="$user_cfg_dir/config.jsonc"
    mkdir -p "$user_cfg_dir"
    # Remove stow's symlink if present, write a real per-user copy
    if [[ -L "$user_cfg" ]]; then
      rm "$user_cfg"
    elif [[ -f "$user_cfg" ]]; then
      mv "$user_cfg" "$user_cfg.pre-stow"
    fi
    # Rewrite embedded_home → $HOME in the copy; repo file untouched
    sed "s|$embedded_home|$HOME|g" "$repo_cfg" > "$user_cfg"
    echo "fastfetch: wrote per-user config (paths rewritten for $HOME)"
  else
    echo "fastfetch: HOME already matches repo paths; symlink is correct"
  fi

  # Check logo source
  local logo_source
  logo_source="$(echo "$cfg_content" | grep -oP '"source"\s*:\s*"\K[^"]+' | head -1)"
  if [[ -z "$logo_source" ]]; then
    return
  fi

  # Expand ~ and $HOME in logo source
  local expanded_source="${logo_source/#\~/$HOME}"
  expanded_source="${expanded_source/\$HOME/$HOME}"

  # Skip built-in names (not an absolute path)
  if [[ "$expanded_source" != /* ]]; then
    return
  fi

  # Absolute path — check if it exists
  if [[ ! -f "$expanded_source" ]]; then
    # Compute the relative path under ~/.config/fastfetch/ using the
    # original logo_source (before expansion) so it works regardless of HOME.
    # Strip any leading ~/ or $HOME/ and the fastfetch config prefix.
    local orig_rel="${logo_source#\~/}"
    orig_rel="${orig_rel#\$HOME/}"
    orig_rel="${orig_rel#.config/fastfetch/}"
    echo "WARNING: fastfetch logo '$expanded_source' does not exist."
    echo "  → The file should live in the repo at:"
    echo "    $REPO/fastfetch/.config/fastfetch/$orig_rel"
    echo "  → Copy it there and re-run stow."
  fi
}

# ---------------------------------------------------------------------------
# FIX 3 – link_noctalia_toml
# ---------------------------------------------------------------------------
link_noctalia_toml() {
  local noctalia_config_dir="$REPO/noctalia/.config/noctalia"
  local noctalia_pkg_dir="$REPO/noctalia"
  local target_dir="$HOME/.config/noctalia"
  local linked=()

  mkdir -p "$target_dir"

  # Preferred layout: noctalia/.config/noctalia/*.toml  (stow links these)
  if [[ -d "$noctalia_config_dir" ]]; then
    local toml
    while IFS= read -r toml; do
      local name
      name="$(basename "$toml")"
      local link="$target_dir/$name"

      # Stow should have already created the symlink; verify / fix it
      if [[ -L "$link" ]]; then
        local cur_target
        cur_target="$(readlink "$link")"
        if [[ "$cur_target" == "$toml" ]] || [[ "$(realpath "$link" 2>/dev/null)" == "$toml" ]]; then
          linked+=("$name (already correct)")
          continue
        fi
        # Pointing elsewhere — replace
        rm "$link"
      elif [[ -e "$link" ]]; then
        mv "$link" "$link.pre-stow"
        echo "  moved $link → $link.pre-stow"
      fi
      ln -sf "$toml" "$link"
      linked+=("$name")
    done < <(find "$noctalia_config_dir" -maxdepth 1 -name '*.toml' 2>/dev/null)
  fi

  # Old layout: noctalia/*.toml at the package root
  local toml
  while IFS= read -r toml; do
    local name
    name="$(basename "$toml")"
    local link="$target_dir/$name"
    local stray_link="$HOME/$name"

    if [[ -L "$link" ]]; then
      local cur_target
      cur_target="$(readlink "$link")"
      if [[ "$cur_target" == "$toml" ]] || [[ "$(realpath "$link" 2>/dev/null)" == "$toml" ]]; then
        linked+=("$name (already correct, old layout)")
        # Remove stray home link if it points into the repo
        if [[ -L "$stray_link" ]] && \
           [[ "$(realpath "$stray_link" 2>/dev/null)" == "$REPO/"* ]]; then
          rm "$stray_link"
          echo "  removed stray link $stray_link"
        fi
        continue
      fi
      rm "$link"
    elif [[ -e "$link" ]]; then
      mv "$link" "$link.pre-stow"
      echo "  moved $link → $link.pre-stow"
    fi
    ln -sf "$toml" "$link"
    linked+=("$name (old layout)")

    # Remove stray home-level link created by stow for root-level files
    if [[ -L "$stray_link" ]] && \
       [[ "$(realpath "$stray_link" 2>/dev/null)" == "$REPO/"* ]]; then
      rm "$stray_link"
      echo "  removed stray link $stray_link"
    fi
  done < <(find "$noctalia_pkg_dir" -maxdepth 1 -name '*.toml' 2>/dev/null)

  if [[ "${#linked[@]}" -eq 0 ]]; then
    echo "noctalia: no TOML files found in repo — nothing to link"
  else
    echo "noctalia: linked TOML files:"
    printf '  %s\n' "${linked[@]}"
  fi
}

# ---------------------------------------------------------------------------
# Wallpaper handling
# ---------------------------------------------------------------------------
handle_wallpapers() {
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
}

# ---------------------------------------------------------------------------
# System files
# ---------------------------------------------------------------------------
install_system_files() {
  for f in locale.conf vconsole.conf sddm.conf; do
    sudo install -m 644 -o root -g root "$REPO/system/etc/$f" "/etc/$f"
  done
  echo "Copied locale.conf, vconsole.conf and sddm.conf to /etc/."
  echo "Host files (fstab, hostname, pacman.conf, mkinitcpio*, limine-*) are"
  echo "kept as reference in system/reference/ - review them, do not copy them"
  echo "to another machine."
}

# ---------------------------------------------------------------------------
# Post-install summary
# ---------------------------------------------------------------------------
print_summary() {
  echo ""
  echo "── Installed profile: $PROFILE ──────────────────────────"
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

  if [[ "$PROFILE" == "minimal" ]]; then
    cat <<'EOF'

── Minimal profile: keybinds / features NOT available ───────────────────────
  The following are configured in niri but the programs are not installed:
    Mod+B          → firefox       (browser)
    Mod+W          → librewolf     (browser)
    Mod+O          → obsidian      (notes app)
    Mod+M          → spotify-launcher
    Mod+E          → nemo          (file manager)
    Ctrl+Shift+Space → niri-animations picker (noctalia plugin)

  Run ./install.sh --full to install all packages and stow all dotfiles.
─────────────────────────────────────────────────────────────────────────────
EOF
  fi

  # Suggest chsh if login shell isn't zsh
  local zsh_path
  zsh_path="$(command -v zsh 2>/dev/null || true)"
  if [[ -n "$zsh_path" ]]; then
    local login_shell
    login_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)"
    if [[ "$login_shell" != "$zsh_path" ]]; then
      echo ""
      echo "Your login shell is not zsh. To change it run:"
      echo "  chsh -s \"$zsh_path\""
    fi
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  set -euo pipefail

  parse_args "$@"

  # 1. Select and apply install profile
  select_profile
  apply_profile

  # 2. Bootstrap base tools (Syu + essentials)
  bootstrap_pacman

  # 3. Install paru
  install_paru

  # 4. Install packages from lists
  install_packages

  # 5. Stow dotfiles
  cd "$REPO"
  move_conflicts
  stow_packages

  # 6. Post-stow setup
  setup_fastfetch
  link_noctalia_toml

  # 7. Wallpapers (opt-in)
  handle_wallpapers

  # 8. System files (optional)
  if [[ "$SYSTEM" -eq 1 ]]; then
    install_system_files
  fi

  # 9. Summary
  print_summary
}

# ---------------------------------------------------------------------------
# Only run main when executed directly, not when sourced (for testing)
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
