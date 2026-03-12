#!/bin/bash

# Claude Code Session Detector
# Detects and monitors Claude Code AI sessions across tmux environment
# Author: Shikamaru <shikamarunaraclaw@gmail.com>

# Configuration
CLAUDE_PATTERNS=("claude" "anthropic" "ai-session" "claude-code" "cc-")
STATUS_FILE="/tmp/claude_sessions_status"
CONFIG_FILE="${HOME}/.config/claude-session-manager/config"

# Status indicators
STATUS_ACTIVE="●"
STATUS_WAITING="⏸"
STATUS_COMPLETE="✓"
STATUS_ERROR="❌"
STATUS_STARTING="⚡"

# Colors for tmux display
COLOR_ACTIVE="#00ff41"      # Matrix green
COLOR_WAITING="#ffff00"     # Cyber yellow  
COLOR_COMPLETE="#00ffff"    # Electric cyan
COLOR_ERROR="#ff007f"       # Neon pink
COLOR_STARTING="#bf00ff"    # Electric purple
COLOR_INACTIVE="#8b93a6"    # Muted gray

# Load configuration if exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Detect if session name suggests Claude Code usage
is_claude_session() {
    local session_name="$1"
    local session_name_lower=$(echo "$session_name" | tr '[:upper:]' '[:lower:]')
    
    for pattern in "${CLAUDE_PATTERNS[@]}"; do
        if [[ "$session_name_lower" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Check if session has Claude Code processes
has_claude_processes() {
    local session_name="$1"
    
    # Get all panes in the session
    local panes=$(tmux list-panes -t "$session_name" -a -F "#{pane_id}")
    
    for pane in $panes; do
        # Get the command running in the pane
        local pane_command=$(tmux display-message -t "$pane" -p "#{pane_current_command}")
        local pane_pid=$(tmux display-message -t "$pane" -p "#{pane_pid}")
        
        # Check if it's running Claude Code or similar AI tools
        if [[ "$pane_command" =~ (claude|anthropic|ai|python.*claude|node.*claude) ]]; then
            return 0
        fi
        
        # Check child processes
        if command -v pgrep >/dev/null 2>&1; then
            local child_procs=$(pgrep -P "$pane_pid" 2>/dev/null || true)
            for child_pid in $child_procs; do
                local child_cmd=$(ps -p "$child_pid" -o comm= 2>/dev/null || true)
                if [[ "$child_cmd" =~ (claude|anthropic) ]]; then
                    return 0
                fi
            done
        fi
    done
    return 1
}

# Analyze session output to determine status
analyze_session_status() {
    local session_name="$1"
    
    # Get the most recent output from all panes
    local recent_output=""
    local panes=$(tmux list-panes -t "$session_name" -a -F "#{pane_id}")
    
    for pane in $panes; do
        # Capture last 10 lines from pane
        local pane_output=$(tmux capture-pane -t "$pane" -p -S -10 2>/dev/null || true)
        recent_output+="$pane_output"$'\n'
    done
    
    # Convert to lowercase for pattern matching
    local output_lower=$(echo "$recent_output" | tr '[:upper:]' '[:lower:]')
    
    # Check for various status patterns
    if [[ "$output_lower" =~ (error|failed|exception|traceback|fatal) ]]; then
        echo "error"
    elif [[ "$output_lower" =~ (waiting|input|prompt|\?|continue|press|enter) ]]; then
        echo "waiting"
    elif [[ "$output_lower" =~ (complete|done|finished|success|✓|✅) ]]; then
        echo "complete"
    elif [[ "$output_lower" =~ (starting|initializing|loading|connecting) ]]; then
        echo "starting"
    elif [[ "$output_lower" =~ (thinking|processing|working|analyzing|generating) ]]; then
        echo "active"
    else
        # Check if there's recent activity (output in last 30 seconds)
        local last_activity=$(tmux display-message -t "$session_name" -p "#{session_activity}")
        local current_time=$(date +%s)
        local activity_age=$((current_time - last_activity))
        
        if [[ $activity_age -lt 30 ]]; then
            echo "active"
        else
            echo "waiting"
        fi
    fi
}

# Get all Claude Code sessions with their status
get_claude_sessions() {
    local sessions_data=""
    
    # Get all tmux sessions
    if ! tmux list-sessions >/dev/null 2>&1; then
        echo "[]"
        return
    fi
    
    local sessions=$(tmux list-sessions -F "#{session_name}")
    
    for session in $sessions; do
        # Check if this is a Claude Code session
        if is_claude_session "$session" || has_claude_processes "$session"; then
            local status=$(analyze_session_status "$session")
            local last_activity=$(tmux display-message -t "$session" -p "#{session_activity}" 2>/dev/null || echo "0")
            
            # Create session entry
            sessions_data+="$session|$status|$last_activity"$'\n'
        fi
    done
    
    echo "$sessions_data"
}

# Format session for display
format_session_display() {
    local session_name="$1"
    local status="$2"
    local max_width="${3:-20}"
    
    # Choose status indicator and color
    local indicator=""
    local color=""
    
    case "$status" in
        "active")
            indicator="$STATUS_ACTIVE"
            color="$COLOR_ACTIVE"
            ;;
        "waiting")
            indicator="$STATUS_WAITING"
            color="$COLOR_WAITING"
            ;;
        "complete")
            indicator="$STATUS_COMPLETE"
            color="$COLOR_COMPLETE"
            ;;
        "error")
            indicator="$STATUS_ERROR"
            color="$COLOR_ERROR"
            ;;
        "starting")
            indicator="$STATUS_STARTING"
            color="$COLOR_STARTING"
            ;;
        *)
            indicator=" "
            color="$COLOR_INACTIVE"
            ;;
    esac
    
    # Truncate session name if too long
    local display_name="$session_name"
    if [[ ${#session_name} -gt $((max_width - 3)) ]]; then
        display_name="${session_name:0:$((max_width - 6))}..."
    fi
    
    # Format with tmux color codes
    echo "#[fg=$color]$indicator $display_name#[default]"
}

# Generate tmux sidebar content
generate_sidebar_content() {
    local sessions_data=$(get_claude_sessions)
    local sidebar_content=""
    local session_count=0
    
    # Header
    sidebar_content+="#[fg=$COLOR_COMPLETE,bold]🤖 Claude Code#[default]"$'\n'
    sidebar_content+="#[fg=$COLOR_INACTIVE]───────────────#[default]"$'\n'
    
    # Process sessions
    if [[ -n "$sessions_data" && "$sessions_data" != "[]" ]]; then
        while IFS='|' read -r session status activity; do
            if [[ -n "$session" ]]; then
                sidebar_content+="$(format_session_display "$session" "$status" 15)"$'\n'
                ((session_count++))
            fi
        done <<< "$sessions_data"
    fi
    
    # Footer with controls
    if [[ $session_count -eq 0 ]]; then
        sidebar_content+="#[fg=$COLOR_INACTIVE]No active sessions#[default]"$'\n'
    fi
    
    sidebar_content+=""$'\n'
    sidebar_content+="#[fg=$COLOR_INACTIVE][sessionx: o]#[default]"$'\n'
    sidebar_content+="#[fg=$COLOR_INACTIVE][refresh: r]#[default]"
    
    echo "$sidebar_content"
}

# Main function
main() {
    load_config
    
    case "${1:-sidebar}" in
        "detect")
            get_claude_sessions
            ;;
        "sidebar")
            generate_sidebar_content
            ;;
        "status")
            local session="${2:-}"
            if [[ -n "$session" ]]; then
                analyze_session_status "$session"
            else
                echo "Usage: $0 status <session_name>"
                exit 1
            fi
            ;;
        "list")
            get_claude_sessions | while IFS='|' read -r session status activity; do
                if [[ -n "$session" ]]; then
                    echo "$session: $status"
                fi
            done
            ;;
        *)
            echo "Usage: $0 {detect|sidebar|status|list}"
            echo "  detect   - Get all Claude sessions data"
            echo "  sidebar  - Generate tmux sidebar content"
            echo "  status   - Get specific session status"
            echo "  list     - List all Claude sessions with status"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"