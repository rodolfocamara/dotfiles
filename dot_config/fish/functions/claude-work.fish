function claude-work --description 'Claude Code (work account)'
    set -lx CLAUDE_CONFIG_DIR $HOME/.claude-work
    command claude --dangerously-skip-permissions $argv
end
