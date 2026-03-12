#!/usr/bin/env bash

# tmux Integration for Claude Session Manager
# Handles popup display, session switching, and fzf picker
# Author: Shikamaru <shikamarunaraclaw@gmail.com>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTOR_SCRIPT="$SCRIPT_DIR/claude_session_detector.sh"
CONFIG_FILE="${HOME}/.config/claude-session-manager/config"

# Default configuration
POPUP_WIDTH="60%"
POPUP_HEIGHT="60%"

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Show session status in a tmux popup
show_popup() {
    local tmpfile="/tmp/claude_popup_content.$$"

    "$DETECTOR_SCRIPT" sidebar --ansi > "$tmpfile" 2>/dev/null

    if [[ ! -s "$tmpfile" ]]; then
        echo "No Claude Code sessions detected" > "$tmpfile"
    fi

    tmux display-popup \
        -w "$POPUP_WIDTH" -h "$POPUP_HEIGHT" \
        -T " 🤖 Claude Code Sessions " \
        -E "bash -c 'printf \"%b\\n\" \"\$(cat \"$tmpfile\")\"; rm -f \"$tmpfile\"; echo; echo \"Press any key to close\"; read -rsn1'"
}

# Switch to a Claude Code session
switch_to_session() {
    local session_name="$1"

    if [[ -z "$session_name" ]]; then
        echo "Usage: switch_to_session <session_name>"
        return 1
    fi

    if tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -qxF "$session_name"; then
        tmux switch-client -t "$session_name"
    else
        echo "Session not found: $session_name"
        return 1
    fi
}

# Jump to sessions with specific status
jump_to_status() {
    local target_status="$1"
    local sessions_data
    sessions_data=$("$DETECTOR_SCRIPT" detect)
    local matching_sessions=()

    while IFS='|' read -r session status pane_count; do
        if [[ -n "$session" && "$status" == "$target_status" ]]; then
            matching_sessions+=("$session")
        fi
    done <<< "$sessions_data"

    if [[ ${#matching_sessions[@]} -gt 0 ]]; then
        switch_to_session "${matching_sessions[0]}"
    else
        echo "No sessions found with status: $target_status"
    fi
}

# fzf-powered session picker inside a tmux popup
show_session_picker() {
    local detector="$DETECTOR_SCRIPT"
    local selection_file="/tmp/claude_picker_selection.$$"

    # Build the fzf picker script
    local picker_script="/tmp/claude_picker_script.$$"
    cat > "$picker_script" << 'PICKER_EOF'
#!/usr/bin/env bash
detector="$1"
selection_file="$2"

sessions_data=$("$detector" detect)
if [[ -z "$sessions_data" ]]; then
    echo "No Claude Code sessions found"
    sleep 2
    exit 0
fi

fzf_input=""
while IFS="|" read -r session status pane_count; do
    [[ -z "$session" ]] && continue
    icon="" color="" label=""
    case "$status" in
        "active")   icon="●"; color="\033[38;2;0;255;65m";   label="working" ;;
        "approval") icon="⏸"; color="\033[38;2;255;255;0m";  label="needs approval" ;;
        "idle")     icon="◯"; color="\033[38;2;139;147;166m"; label="idle" ;;
        *)          icon="◯"; color="\033[38;2;139;147;166m"; label="$status" ;;
    esac
    suffix=""
    [[ "$pane_count" -gt 1 ]] && suffix=" (${pane_count})"
    fzf_input+="$(printf '%b%s %s%s — %s\033[0m' "$color" "$icon" "$session" "$suffix" "$label")"$'\n'
done <<< "$sessions_data"

selected=$(printf '%s' "$fzf_input" | fzf \
    --ansi \
    --header="enter=switch, esc=close" \
    --preview="tmux capture-pane -e -t {2} -p -S -30 2>/dev/null || echo 'Preview unavailable'" \
    --preview-window="right:50%" \
    --no-sort \
    --reverse)

if [[ -n "$selected" ]]; then
    # Extract session name: "icon session_name[suffix] — label" → session_name
    session_name=$(echo "$selected" | sed 's/^[^ ]* //' | sed 's/ ([0-9]*)//;s/ — .*//')
    echo "$session_name" > "$selection_file"
fi
PICKER_EOF
    chmod +x "$picker_script"

    # Run picker in popup — popup closes when fzf exits
    tmux display-popup \
        -w "$POPUP_WIDTH" -h "$POPUP_HEIGHT" \
        -T " 🤖 Claude Code Picker " \
        -E "bash '$picker_script' '$detector' '$selection_file'"

    # Clean up script
    rm -f "$picker_script"

    # After popup closes, switch to selected session
    if [[ -f "$selection_file" ]]; then
        local session_name
        session_name=$(cat "$selection_file")
        rm -f "$selection_file"
        if [[ -n "$session_name" ]]; then
            tmux switch-client -t "$session_name"
        fi
    fi
}

# Main function
main() {
    load_config

    case "${1:-help}" in
        "show"|"popup")
            show_popup
            ;;
        "picker"|"list-sessions")
            show_session_picker
            ;;
        "jump-approval")
            jump_to_status "approval"
            ;;
        "jump-active")
            jump_to_status "active"
            ;;
        "jump-idle")
            jump_to_status "idle"
            ;;
        "switch")
            switch_to_session "$2"
            ;;
        "help"|*)
            echo "Claude Code Session Manager - tmux Integration"
            echo ""
            echo "Usage: $0 <command> [args]"
            echo ""
            echo "Display Commands:"
            echo "  show, popup       Show session status popup"
            echo "  picker            Open fzf session picker"
            echo ""
            echo "Navigation Commands:"
            echo "  jump-approval     Jump to sessions needing approval"
            echo "  jump-active       Jump to active sessions"
            echo "  jump-idle         Jump to idle sessions"
            echo "  switch <session>  Switch to specific session"
            echo ""
            echo "Example tmux.conf bindings:"
            echo "  bind-key g run-shell 'claude-session-manager show'"
            echo "  bind-key G run-shell 'claude-session-manager picker'"
            echo ""
            ;;
    esac
}

main "$@"
