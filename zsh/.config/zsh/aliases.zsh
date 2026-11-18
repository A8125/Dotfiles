# =============================================================================
# aliases.zsh - Aliases (sourced from ~/.zshrc in interactive shells only)
# =============================================================================

# Safety First
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -I'
alias ln='ln -v'

alias disk_usage='sudo btrfs filesystem usage /' # The TRUTH about BTRFS space
alias df='df -hT'                                # Show filesystem types

# Check if eza is installed
if command -v eza >/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza --icons --group-directories-first -l --git'
    alias la='eza --icons --group-directories-first -la --git'
    alias lt='eza --icons --group-directories-first --tree --level=2'
else
    # Fallback to standard ls if eza is missing
    alias ls='ls --color=auto'
    alias ll='ls -lh'
    alias la='ls -A'
fi

# Auto list contents after changing directory.
# Defined here, AFTER the `ls` alias above: zsh expands aliases at parse time,
# so this must come after the eza block to actually use eza (with icons).
chpwd() { ls }

alias diff='delta --side-by-side'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# alias for using gdu instead of ncdu
alias ncdu='gdu'

alias zed='zeditor'

alias hs='adb kill-server; adb connect $(ip route | awk "/default/ {print \$3; exit}"):5555'
