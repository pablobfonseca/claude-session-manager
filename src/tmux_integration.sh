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
    local picker_script="/tmp/claude_picker_script.$$"
    local generate_script="/tmp/claude_picker_generate.$$"
    local action_script="/tmp/claude_picker_action.$$"

    # Build the generate script (used for initial input and reload)
    cat > "$generate_script" << 'GENERATE_EOF'
#!/usr/bin/env bash
detector="$1"
panes_data=$("$detector" detect)
[[ -z "$panes_data" ]] && exit 0
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
    printf '%s\t%b%s %s %b[%s]%b — %s%b\n' \
        "$pane_id:$status" "$color" "$icon" "$project" "$dim" "$session" "$color" "$label" "$reset"
done <<< "$panes_data"
GENERATE_EOF
    chmod +x "$generate_script"

    # Build the action script (handles approve, reject, write)
    cat > "$action_script" << 'ACTION_EOF'
#!/usr/bin/env bash
action="$1"
field="$2"
pane_id="${field%%:*}"
status="${field##*:}"

case "$action" in
    approve)
        if [[ "$status" == "approval" ]]; then
            tmux send-keys -t "$pane_id" Enter
        fi
        ;;
    reject)
        if [[ "$status" == "approval" ]]; then
            tmux send-keys -t "$pane_id" Escape
        fi
        ;;
    write)
        if [[ "$status" == "idle" ]]; then
            printf '\033[38;2;139;147;166mesc=cancel enter=send\033[0m\n'
            printf '\033[38;2;0;255;65m❯ \033[0m'
            input=""
            while IFS= read -rsn1 char; do
                # Escape key (0x1b)
                if [[ "$char" == $'\x1b' ]]; then
                    # Drain any remaining escape sequence bytes
                    read -rsn2 -t 0.01 _ 2>/dev/null || true
                    printf '\n\033[38;2;139;147;166mcancelled\033[0m\n'
                    sleep 0.5
                    exit 0
                fi
                # Enter key (empty char from read)
                if [[ -z "$char" ]]; then
                    printf '\n'
                    break
                fi
                # Backspace (0x7f or 0x08)
                if [[ "$char" == $'\x7f' || "$char" == $'\x08' ]]; then
                    if [[ -n "$input" ]]; then
                        input="${input%?}"
                        printf '\b \b'
                    fi
                    continue
                fi
                input+="$char"
                printf '%s' "$char"
            done
            if [[ -n "$input" ]]; then
                tmux send-keys -t "$pane_id" -l "$input"
                tmux send-keys -t "$pane_id" Enter
            fi
        else
            printf '\033[38;2;255;255;0m⚠ Pane is not idle (status: %s)\033[0m\n' "$status"
            sleep 1
        fi
        ;;
esac
ACTION_EOF
    chmod +x "$action_script"

    # Build the fzf picker script
    cat > "$picker_script" << 'PICKER_EOF'
#!/usr/bin/env bash
detector="$1"
selection_file="$2"
generate_script="$3"
action_script="$4"

fzf_input=$(bash "$generate_script" "$detector")
if [[ -z "$fzf_input" ]]; then
    echo "No Claude Code sessions found"
    sleep 2
    exit 0
fi

selected=$(printf '%s' "$fzf_input" | fzf \
    --ansi \
    --with-nth=2.. \
    --delimiter=$'\t' \
    --header="enter=switch │ C-y=approve │ C-x=reject │ C-w=write │ C-d/C-u=scroll │ esc=close" \
    --preview="tmux capture-pane -e -t \$(echo {1} | cut -d: -f1) -p -S -30 2>/dev/null || echo 'Preview unavailable'" \
    --preview-window="right:50%" \
    --no-sort \
    --reverse \
    --bind="ctrl-y:execute-silent(bash $action_script approve {1})+reload(bash $generate_script $detector)" \
    --bind="ctrl-x:execute-silent(bash $action_script reject {1})+reload(bash $generate_script $detector)" \
    --bind="ctrl-w:execute(bash $action_script write {1})+reload(bash $generate_script $detector)" \
    --bind="ctrl-d:preview-half-page-down" \
    --bind="ctrl-u:preview-half-page-up")

if [[ -n "$selected" ]]; then
    pane_id=$(echo "$selected" | cut -f1 | cut -d: -f1)
    echo "$pane_id" > "$selection_file"
fi
PICKER_EOF
    chmod +x "$picker_script"

    # Run picker in popup — popup closes when fzf exits
    tmux display-popup \
        -w "$POPUP_WIDTH" -h "$POPUP_HEIGHT" \
        -T " 🤖 Claude Code Picker " \
        -E "bash '$picker_script' '$detector' '$selection_file' '$generate_script' '$action_script'"

    # Clean up all temp scripts
    rm -f "$picker_script" "$generate_script" "$action_script"

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
