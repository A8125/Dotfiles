# =============================================================================
# functions.zsh - Functions (sourced from ~/.zshrc in interactive shells only)
# =============================================================================

# Weather query via wttr.in
# Usage: wthr [location]
# use with "-s" flag to only get one line.
wthr() {
    # Check if the first argument is '-s' (short)
    if [[ "$1" == "-s" ]]; then
        shift # Remove the -s from arguments
        local location="${(j:+:)@}"
        curl "wttr.in/${location}?format=%c+%t"
    else
        local location="${(j:+:)@}"
        curl "wttr.in/${location}"
    fi
}

# Creates a directory and changes into it.
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# YAZI
# change the current working directory when exiting Yazi
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}

#-- LM- Studio--
llm() {
    /mnt/media/Documents/do_not_delete_linux/appimages/LM-Studio*(Om[1]) "$@"
}
# The (om[1]) glob qualifier picks the most recently modified file

# share zram1 directory with waydroid at pictures point inside waydroid
# Function to remount Waydroid pictures to ZRAM
waydroid_bind() {
    local target="$HOME/.local/share/waydroid/data/media/0/Pictures"
    local source="/mnt/zram1"

    # 1. Attempt to unmount recursively.
    # 2>/dev/null silences the error if it's not mounted.
    # || true ensures the script doesn't abort if you have 'set -e' active or strict chaining.
    sudo umount -R "$target" 2>/dev/null || true

    # 2. Perform the bind mount
    # We check if the source exists first to avoid mounting nothing.
    if [[ -d "$source" ]]; then
        sudo mount --bind "$source" "$target"
        echo "Successfully bound $source to Waydroid Pictures."
    else
        echo "Error: Source $source does not exist."
        return 1
    fi
}

# --- Windows 10 KVM Manager ---
# HOW TO USE
# Start VM: win start
# Open Looking Glass: win view
# Do both (One-click gaming): win launch
# Kill it: win kill

# Colored output helpers
_win_info() { echo -e "\e[34m[WIN10]\e[0m $1"; }
_win_err()  { echo -e "\e[31m[ERROR]\e[0m $1"; }

win() {
    local vm="win10"
    local shm_file="/dev/shm/looking-glass"
    local lg_cmd="looking-glass-client -f ${shm_file} -m KEY_F6"

    case "$1" in
        start)
            _win_info "Starting VM..."
            sudo virsh start "$vm"
            ;;
        stop|shutdown)
            _win_info "Sending shutdown signal..."
            sudo virsh shutdown "$vm"
            ;;
        kill|destroy)
            _win_info "Forcefully destroying VM..."
            sudo virsh destroy "$vm"
            ;;
        reboot)
            _win_info "Rebooting VM..."
            sudo virsh reboot "$vm"
            ;;
        view|lg|show)
            if [ -f "$shm_file" ]; then
                _win_info "Launching Looking Glass..."
                eval "$lg_cmd"
            else
                _win_err "Looking Glass SHM file not found. Is the VM running?"
            fi
            ;;
        # --- Advanced Options ---
        launch|play)
            # Starts VM and waits for Looking Glass to be ready
            _win_info "Two birds one stone: Starting VM and waiting for Looking Glass..."
            sudo virsh start "$vm" 2>/dev/null

            _win_info "Waiting for Shared Memory..."
            # Efficient bash wait loop (timeout after 30s)
            local timeout=30
            while [ ! -f "$shm_file" ] && [ $timeout -gt 0 ]; do
                sleep 1
                ((timeout--))
            done

            if [ -f "$shm_file" ]; then
                _win_info "Ready! Launching Client..."
                eval "$lg_cmd"
            else
                _win_err "Timed out waiting for VM graphics."
            fi
            ;;
        status)
            sudo virsh domstate "$vm"
            ;;
        edit)
            sudo virsh edit "$vm"
            ;;
        *)
            echo "Usage: win {start|shutdown|destroy|reboot|view|launch|status|edit}"
            ;;
    esac
}

# --- Auto-Completion for 'win' ---
# This makes hitting 'tab' show your options
_win_completion() {
    local -a commands
    commands=('start' 'shutdown' 'destroy' 'reboot' 'view' 'launch' 'status' 'edit')
    _describe 'command' commands
}
compdef _win_completion win

# =============================================================================
# Pacman/Expac Utility: Unified Package Querying (Platinum Edition)
# Usage: pkg <command> [count]
# =============================================================================

# DRY Header Helper — defined once at source time, not re-created on every pkg call.
# Args: $1 = title string, $2 = count integer
_pkg_header() {
    print -P "\n%F{blue}::%f %B${1}%b (Top ${2})"
    print -P "%F{238}------------------------------------------------------------%f"
}

pkg() {
    # 1. Pre-flight Check: Ultra-fast Zsh native dependency validation
    if (( ! $+commands[expac] )); then
        print -u2 -P "%F{red}✖ Error:%f 'expac' is not installed. Run: sudo pacman -S expac"
        return 1
    fi

    # 2. Scope & Defaults
    local cmd="${1:-help}"
    local num="${2:-20}"

    # 3. Strict Validation: Must be a POSITIVE integer (no zeros, no letters)
    if [[ ! "$num" =~ ^[1-9][0-9]*$ ]]; then
        print -u2 -P "%F{red}✖ Error:%f Count must be a positive integer (1 or higher)."
        return 1
    fi

    # 4. Core Execution Pipeline
    case "${cmd:l}" in
        hogs|size|all)
            _pkg_header "Largest Packages (Including Dependencies)" "$num"
            expac '%m|%n' | sort -rn | head -n "$num" | numfmt --to=iec-i --suffix=B --field=1 --delimiter='|' | column -t -s '|'
            ;;

        explicit|user)
            _pkg_header "Largest Explicitly Installed Packages" "$num"
            pacman -Qeq | expac '%m|%n' - | sort -rn | head -n "$num" | numfmt --to=iec-i --suffix=B --field=1 --delimiter='|' | column -t -s '|'
            ;;

        new|recent|latest)
            _pkg_header "Recently Installed Packages" "$num"
            expac --timefmt='%Y-%m-%d %T' '%l|%n' | sort -r | head -n "$num" | column -t -s '|'
            ;;

        old|ancient)
            _pkg_header "Oldest Installed Packages" "$num"
            expac --timefmt='%Y-%m-%d %T' '%l|%n' | sort | head -n "$num" | column -t -s '|'
            ;;

        help|*)
            print -P "\n%F{green}Usage:%f pkg <command> [count (default: 20)]\n"
            print -P "%BCommands:%b"
            print "  hogs, size, all          - List largest packages (overall)"
            print "  explicit, user           - List largest explicitly installed packages"
            print "  new, recent, latest      - List recently installed (newest first)"
            print "  old, ancient             - List oldest installed (oldest first)\n"
            print -P "%BExamples:%b"
            print "  pkg size 10        # Top 10 largest packages overall"
            print "  pkg explicit 50    # Top 50 largest packages you explicitly installed\n"

            [[ "${cmd:l}" == "help" ]] && return 0 || return 1
            ;;
    esac

    # 5. Trailing newline for prompt breathing room
    print ""
}

# Native Zsh tab-completion — proper named function, unambiguously correct.
_pkg() {
    _arguments \
        "1:command:(hogs size all explicit user new recent latest old ancient help)" \
        "2:count: "
}
compdef _pkg pkg

# =============================================================================
# logs() - loaded lazily on first use.
# The 46 KB body lives in ~/.config/zshrc/logs (the canonical copy, left
# untouched). Parsing it on every shell start is unnecessary, so this stub
# replaces itself the first time you call logs.
# =============================================================================
logs() {
    unfunction logs
    source "$HOME/.config/zshrc/logs"
    logs "$@"
}
