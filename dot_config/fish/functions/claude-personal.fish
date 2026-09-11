function claude-personal --description 'Claude Code (personal account)'
    # Force the profile: the ~/.local/bin/claude wrapper overwrites
    # CLAUDE_CONFIG_DIR from the working directory, so setting the dir alone
    # would land on the work profile inside a work-mapped repo.
    set -lx CLAUDE_PROFILE personal
    command claude --dangerously-skip-permissions $argv
end
