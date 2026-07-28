# CachyOS ships the distro-wide fish config (eza aliases, fastfetch greeting,
# pacman helpers, ../... shortcuts). Guarded so this file also works on WSL and
# other distros where the package is absent.
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end

set -gx SHELL (status fish-path)
set -gx EDITOR nvim
set -gx VISUAL nvim
fish_add_path --prepend $HOME/.npm-global/bin

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

if status is-interactive
    command -q starship; and starship init fish | source
    command -q mise; and mise activate fish | source
    command -q direnv; and direnv hook fish | source

    # Wave's sidebar follows the focused shell's path. Foreground agents can
    # temporarily replace it; the next prompt restores the path automatically.
    function __wave_sync_path_title --on-event fish_prompt
        test "$TERM_PROGRAM" = waveterm; or return
        test "$WAVETERM" = 1; or return
        test -x "$HOME/.local/bin/codex-terminal-title"; or return

        set -l title "$PWD"
        if test "$PWD" = "$HOME"
            set title '~'
        else if string match -q -- "$HOME/*" "$PWD"
            set title '~/'(string replace -- "$HOME/" '' "$PWD")
        end

        command "$HOME/.local/bin/codex-terminal-title" wave-path-title "$title" \
            >/dev/null 2>&1 &
        disown $last_pid
    end

    abbr -a docker podman
    abbr -a dc podman-compose
    abbr -a y yazi
    abbr -a n nvim

    # chezmoi
    abbr -a cma 'chezmoi apply'

    # git — mirrors the aliases in dot_zshrc
    abbr -a gs 'git status'
    abbr -a ga 'git add'
    abbr -a gc 'git commit'
    abbr -a gp 'git push'
    abbr -a gb 'git branch'
    abbr -a gd 'git diff'
    abbr -a gco 'git checkout'
    abbr -a gl 'git log --oneline --graph --decorate'

    # navigation — ls/ll/la/lt and .. / ... already come from cachyos-config.fish
    abbr -a c clear
    abbr -a repos 'cd ~/Repos'
end
