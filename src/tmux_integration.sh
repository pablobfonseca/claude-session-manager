#!/usr/bin/env bash

# tmux Integration for Claude Session Manager
# Handles popup display, session switching, and fzf picker

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

# Switch to a specific tmux pane
switch_to_pane() {
    local target="$1"

    # If target looks like a pane_id (%NNN), switch to that pane
    if [[ "$target" == %* ]]; then
        local session
        session=$(tmux display-message -t "$target" -p "#{session_name}" 2>/dev/null) || {
            echo "Pane not found: $target"
            return 1
        }
        local window
        window=$(tmux display-message -t "$target" -p "#{window_id}" 2>/dev/null)
        tmux switch-client -t "$session"
        tmux select-window -t "$window"
        tmux select-pane -t "$target"
    else
        # Treat as session name
        if tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -qxF "$target"; then
            tmux switch-client -t "$target"
        else
            echo "Session not found: $target"
            return 1
        fi
    fi
}

# Jump to first pane with specific status
jump_to_status() {
    local target_status="$1"
    local panes_data
    panes_data=$("$DETECTOR_SCRIPT" detect)

    while IFS='|' read -r session pane_id project status; do
        if [[ -n "$pane_id" && "$status" == "$target_status" ]]; then
            switch_to_pane "$pane_id"
            return 0
        fi
    done <<< "$panes_data"

    echo "No panes found with status: $target_status"
    return 1
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

panes_data=$("$detector" detect)
if [[ -z "$panes_data" ]]; then
    echo "No Claude Code sessions found"
    sleep 2
    exit 0
fi

fzf_input=""
while IFS="|" read -r session pane_id project status; do
    [[ -z "$session" ]] && continue
    icon="" color="" label=""
    case "$status" in
        "active")   icon="●"; color="\033[38;2;0;255;65m";   label="working" ;;
        "approval") icon="⏸"; color="\033[38;2;255;255;0m";  label="needs approval" ;;
        "idle")     icon="◯"; color="\033[38;2;139;147;166m"; label="idle" ;;
        *)          icon="◯"; color="\033[38;2;139;147;166m"; label="$status" ;;
    esac
    dim="\033[38;2;139;147;166m"
    reset="\033[0m"
    # Format: "pane_id\ticon project [session] — label" with ANSI colors
    fzf_input+="$(printf '%s\t%b%s %s %b[%s]%b — %s%b' \
        "$pane_id" "$color" "$icon" "$project" "$dim" "$session" "$color" "$label" "$reset")"$'\n'
done <<< "$panes_data"

selected=$(printf '%s' "$fzf_input" | fzf \
    --ansi \
    --with-nth=2.. \
    --delimiter=$'\t' \
    --header="enter=switch, esc=close" \
    --preview="tmux capture-pane -e -t {1} -p -S -30 2>/dev/null || echo 'Preview unavailable'" \
    --preview-window="right:50%" \
    --no-sort \
    --reverse)

if [[ -n "$selected" ]]; then
    # Extract pane_id (first tab-separated field)
    pane_id=$(echo "$selected" | cut -f1)
    echo "$pane_id" > "$selection_file"
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

    # After popup closes, switch to selected pane
    if [[ -f "$selection_file" ]]; then
        local pane_id
        pane_id=$(cat "$selection_file")
        rm -f "$selection_file"
        if [[ -n "$pane_id" ]]; then
            switch_to_pane "$pane_id"
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
            switch_to_pane "$2"
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
            echo "  jump-approval     Jump to pane needing approval"
            echo "  jump-active       Jump to active pane"
            echo "  jump-idle         Jump to idle pane"
            echo "  switch <pane_id>  Switch to specific pane"
            echo ""
            echo "Example tmux.conf bindings:"
            echo "  bind-key g run-shell 'claude-session-manager show'"
            echo "  bind-key G run-shell 'claude-session-manager picker'"
            echo ""
            ;;
    esac
}

main "$@"
