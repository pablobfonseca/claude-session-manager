#!/bin/bash

# tmux Integration for Claude Session Manager
# Handles sidebar display, session switching, and key bindings
# Author: Shikamaru <shikamarunaraclaw@gmail.com>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTOR_SCRIPT="$SCRIPT_DIR/claude_session_detector.sh"
SIDEBAR_PANE_ID=""
MONITORING_PID=""
CONFIG_FILE="${HOME}/.config/claude-session-manager/config"

# Default configuration
SIDEBAR_WIDTH="25%"
UPDATE_INTERVAL="3"
AUTO_HIDE_TIMEOUT="30"
SIDEBAR_POSITION="right"  # left, right, top, bottom

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Check if sidebar is currently displayed
is_sidebar_active() {
    if [[ -n "$SIDEBAR_PANE_ID" ]] && tmux list-panes -F "#{pane_id}" | grep -q "$SIDEBAR_PANE_ID"; then
        return 0
    fi
    return 1
}

# Create the Claude Code sidebar
create_sidebar() {
    local current_session=$(tmux display-message -p "#{session_name}")
    
    # Check if sidebar already exists
    if is_sidebar_active; then
        return 0
    fi
    
    # Create the sidebar split based on position
    case "$SIDEBAR_POSITION" in
        "left")
            tmux split-window -h -l "$SIDEBAR_WIDTH" -b
            ;;
        "right")
            tmux split-window -h -l "$SIDEBAR_WIDTH"
            ;;
        "top")
            tmux split-window -v -l "$SIDEBAR_WIDTH" -b
            ;;
        "bottom")
            tmux split-window -v -l "$SIDEBAR_WIDTH"
            ;;
        *)
            tmux split-window -h -l "$SIDEBAR_WIDTH"
            ;;
    esac
    
    # Get the new pane ID
    SIDEBAR_PANE_ID=$(tmux display-message -p "#{pane_id}")
    
    # Configure the sidebar pane
    tmux select-pane -t "$SIDEBAR_PANE_ID" -P "bg=black"
    
    # Start the monitoring loop in the sidebar
    start_sidebar_monitoring
    
    # Return focus to main pane
    tmux last-pane
    
    echo "Claude Code sidebar created (pane: $SIDEBAR_PANE_ID)"
}

# Remove the sidebar
remove_sidebar() {
    if is_sidebar_active; then
        stop_monitoring
        tmux kill-pane -t "$SIDEBAR_PANE_ID"
        SIDEBAR_PANE_ID=""
        echo "Claude Code sidebar removed"
    fi
}

# Toggle sidebar visibility
toggle_sidebar() {
    if is_sidebar_active; then
        remove_sidebar
    else
        create_sidebar
    fi
}

# Update sidebar content
update_sidebar_content() {
    if ! is_sidebar_active; then
        return 1
    fi
    
    # Generate the sidebar content
    local content=$("$DETECTOR_SCRIPT" sidebar)
    
    # Clear the pane and display new content
    tmux send-keys -t "$SIDEBAR_PANE_ID" "clear" Enter
    
    # Send content line by line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            tmux send-keys -t "$SIDEBAR_PANE_ID" "echo '$line'" Enter
        else
            tmux send-keys -t "$SIDEBAR_PANE_ID" "echo ''" Enter
        fi
    done <<< "$content"
}

# Start monitoring loop
start_sidebar_monitoring() {
    # Kill any existing monitoring process
    stop_monitoring
    
    # Start background monitoring
    (
        while is_sidebar_active; do
            update_sidebar_content
            sleep "$UPDATE_INTERVAL"
        done
    ) &
    
    MONITORING_PID=$!
    
    # Save PID for cleanup
    echo "$MONITORING_PID" > "/tmp/claude_session_monitor.pid"
}

# Stop monitoring
stop_monitoring() {
    if [[ -n "$MONITORING_PID" ]]; then
        kill "$MONITORING_PID" 2>/dev/null || true
        MONITORING_PID=""
    fi
    
    # Clean up any orphaned monitoring processes
    if [[ -f "/tmp/claude_session_monitor.pid" ]]; then
        local saved_pid=$(cat "/tmp/claude_session_monitor.pid")
        kill "$saved_pid" 2>/dev/null || true
        rm -f "/tmp/claude_session_monitor.pid"
    fi
}

# Switch to a Claude Code session
switch_to_session() {
    local session_name="$1"
    
    if [[ -z "$session_name" ]]; then
        echo "Usage: switch_to_session <session_name>"
        return 1
    fi
    
    # Check if session exists
    if tmux list-sessions -F "#{session_name}" | grep -q "^$session_name$"; then
        tmux switch-client -t "$session_name"
        echo "Switched to session: $session_name"
    else
        echo "Session not found: $session_name"
        return 1
    fi
}

# Jump to sessions with specific status
jump_to_status() {
    local target_status="$1"
    local sessions_data=$("$DETECTOR_SCRIPT" detect)
    local matching_sessions=()
    
    # Find sessions with matching status
    while IFS='|' read -r session status activity; do
        if [[ -n "$session" && "$status" == "$target_status" ]]; then
            matching_sessions+=("$session")
        fi
    done <<< "$sessions_data"
    
    # Switch to first matching session
    if [[ ${#matching_sessions[@]} -gt 0 ]]; then
        switch_to_session "${matching_sessions[0]}"
    else
        echo "No sessions found with status: $target_status"
    fi
}

# Show session picker for Claude Code sessions
show_session_picker() {
    local sessions_data=$("$DETECTOR_SCRIPT" detect)
    local session_list=""
    
    # Build session list for fzf or simple selection
    while IFS='|' read -r session status activity; do
        if [[ -n "$session" ]]; then
            local status_icon=""
            case "$status" in
                "active") status_icon="●" ;;
                "waiting") status_icon="⏸" ;;
                "complete") status_icon="✓" ;;
                "error") status_icon="❌" ;;
                "starting") status_icon="⚡" ;;
                *) status_icon=" " ;;
            esac
            session_list+="$status_icon $session ($status)"$'\n'
        fi
    done <<< "$sessions_data"
    
    if [[ -n "$session_list" ]]; then
        echo "Claude Code Sessions:"
        echo "$session_list"
    else
        echo "No Claude Code sessions found"
    fi
}

# Install tmux key bindings
install_key_bindings() {
    local prefix=$(tmux show-options -g prefix | cut -d' ' -f2)
    
    # Key bindings for Claude Code session management
    tmux bind-key "C-c" run-shell "'$0' toggle"
    tmux bind-key "C-l" run-shell "'$0' list-sessions"
    tmux bind-key "C-w" run-shell "'$0' jump-waiting"
    tmux bind-key "C-e" run-shell "'$0' jump-error"
    tmux bind-key "C-a" run-shell "'$0' jump-active"
    tmux bind-key "C-r" run-shell "'$0' refresh"
    
    echo "Claude Code key bindings installed:"
    echo "  $prefix + C-c   Toggle sidebar"
    echo "  $prefix + C-l   List Claude sessions"
    echo "  $prefix + C-w   Jump to waiting sessions"
    echo "  $prefix + C-e   Jump to error sessions"
    echo "  $prefix + C-a   Jump to active sessions"
    echo "  $prefix + C-r   Refresh sidebar"
}

# Uninstall key bindings
uninstall_key_bindings() {
    tmux unbind-key "C-c" 2>/dev/null || true
    tmux unbind-key "C-l" 2>/dev/null || true
    tmux unbind-key "C-w" 2>/dev/null || true
    tmux unbind-key "C-e" 2>/dev/null || true
    tmux unbind-key "C-a" 2>/dev/null || true
    tmux unbind-key "C-r" 2>/dev/null || true
    
    echo "Claude Code key bindings removed"
}

# Enhanced integration with sessionx
enhance_sessionx() {
    # Check if sessionx is available
    if ! tmux list-keys | grep -q "sessionx"; then
        echo "Warning: sessionx plugin not detected"
        return 1
    fi
    
    # Add Claude Code session filtering to sessionx
    # This would require sessionx configuration modifications
    echo "TODO: Enhanced sessionx integration"
}

# Main function
main() {
    load_config
    
    case "${1:-help}" in
        "create"|"show")
            create_sidebar
            ;;
        "remove"|"hide")
            remove_sidebar
            ;;
        "toggle")
            toggle_sidebar
            ;;
        "refresh"|"update")
            update_sidebar_content
            ;;
        "list-sessions")
            show_session_picker
            ;;
        "jump-waiting")
            jump_to_status "waiting"
            ;;
        "jump-error")
            jump_to_status "error"
            ;;
        "jump-active")
            jump_to_status "active"
            ;;
        "jump-complete")
            jump_to_status "complete"
            ;;
        "switch")
            switch_to_session "$2"
            ;;
        "install-keys")
            install_key_bindings
            ;;
        "uninstall-keys")
            uninstall_key_bindings
            ;;
        "start-monitoring")
            start_sidebar_monitoring
            ;;
        "stop-monitoring")
            stop_monitoring
            ;;
        "status")
            if is_sidebar_active; then
                echo "Sidebar active (pane: $SIDEBAR_PANE_ID)"
            else
                echo "Sidebar not active"
            fi
            ;;
        "help"|*)
            echo "Claude Code Session Manager - tmux Integration"
            echo ""
            echo "Usage: $0 <command> [args]"
            echo ""
            echo "Sidebar Commands:"
            echo "  create, show      Create and show the sidebar"
            echo "  remove, hide      Remove the sidebar"
            echo "  toggle            Toggle sidebar visibility"
            echo "  refresh, update   Refresh sidebar content"
            echo ""
            echo "Navigation Commands:"
            echo "  list-sessions     Show all Claude Code sessions"
            echo "  jump-waiting      Jump to sessions waiting for input"
            echo "  jump-error        Jump to sessions with errors"
            echo "  jump-active       Jump to active sessions"
            echo "  jump-complete     Jump to completed sessions"
            echo "  switch <session>  Switch to specific session"
            echo ""
            echo "Management Commands:"
            echo "  install-keys      Install tmux key bindings"
            echo "  uninstall-keys    Remove tmux key bindings"
            echo "  start-monitoring  Start sidebar monitoring loop"
            echo "  stop-monitoring   Stop sidebar monitoring"
            echo "  status            Show current status"
            echo ""
            exit 1
            ;;
    esac
}

# Cleanup on exit
trap 'stop_monitoring' EXIT

# Run main function
main "$@"