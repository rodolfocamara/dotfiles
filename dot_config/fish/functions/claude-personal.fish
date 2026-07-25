function claude-personal --description 'Claude Code (personal account)'
    set -lx CLAUDE_CONFIG_DIR $HOME/.claude-personal
    command claude --dangerously-skip-permissions $argv
end
