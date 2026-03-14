#!/bin/bash
# direnv dotenv library
# This file provides functions to load .env files in direnv

# Load environment variables from .env file
dotenv() {
    local env_file="${1:-.env}"
    
    if [[ -f "$env_file" ]]; then
        echo "Loading environment from $env_file"
        export $(cat "$env_file" | grep -v '^#' | xargs)
    else
        echo "Warning: $env_file not found"
    fi
}

# Load multiple .env files
dotenv_all() {
    for env_file in .env*; do
        if [[ -f "$env_file" ]]; then
            dotenv "$env_file"
        fi
    done
} 