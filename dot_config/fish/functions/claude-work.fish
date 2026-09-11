function claude-work --description 'Claude Code (work account)'
    # The ~/.local/bin/claude wrapper owns profile resolution and overwrites
    # CLAUDE_CONFIG_DIR from the working directory, so force the profile here.
    # The wrapper turns on Langfuse telemetry for the work profile.
    set -lx CLAUDE_PROFILE work
    command claude --dangerously-skip-permissions $argv
end
