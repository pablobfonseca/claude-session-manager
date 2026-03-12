#!/usr/bin/env bash

# Claude Code Session Detector
# Detects and monitors Claude Code AI sessions across tmux environment
# Author: Shikamaru <shikamarunaraclaw@gmail.com>

# Configuration
CLAUDE_PATTERNS=("claude" "anthropic" "ai-session" "claude-code" "cc-")
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

ANSI_RESET="\033[0m"
ANSI_BOLD="\033[1m"

# Convert hex color (#RRGGBB) to ANSI 24-bit escape
hex_to_ansi() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Default status detection patterns (overridable via config)
ERROR_PATTERNS=("error" "failed" "exception" "traceback" "fatal")
WAITING_PATTERNS=("waiting" "input" "prompt" "continue" "press" "enter")
COMPLETE_PATTERNS=("complete" "done" "finished" "success" "✓" "✅")
ACTIVE_PATTERNS=("thinking" "processing" "working" "analyzing" "generating")
STARTING_PATTERNS=("starting" "initializing" "loading" "connecting")

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
    local panes=$(tmux list-panes -t "$session_name" -F "#{pane_id}" 2>/dev/null) || return 1
    
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

# Check if any pane is running the claude CLI binary
has_claude_binary() {
    local session_name="$1"
    local panes
    panes=$(tmux list-panes -t "$session_name" -F "#{pane_pid}" 2>/dev/null) || return 1

    for pane_pid in $panes; do
        # Check pane process and children for claude binary
        local all_pids="$pane_pid"
        if command -v pgrep >/dev/null 2>&1; then
            all_pids+=" $(pgrep -P "$pane_pid" 2>/dev/null || true)"
        fi

        for pid in $all_pids; do
            local args
            args=$(ps -p "$pid" -o args= 2>/dev/null) || continue
            # Match: claude, npx claude, node .../claude, bunx claude
            if [[ "$args" =~ (^|/)claude( |$) ]] || [[ "$args" =~ npx[[:space:]]+claude ]] || [[ "$args" =~ bunx[[:space:]]+claude ]]; then
                return 0
            fi
        done
    done
    return 1
}

# Analyze session output to determine status
analyze_session_status() {
    local session_name="$1"

    # Build regex from pattern arrays
    local error_regex waiting_regex complete_regex active_regex starting_regex
    error_regex=$(IFS='|'; echo "${ERROR_PATTERNS[*]}")
    waiting_regex=$(IFS='|'; echo "${WAITING_PATTERNS[*]}")
    complete_regex=$(IFS='|'; echo "${COMPLETE_PATTERNS[*]}")
    active_regex=$(IFS='|'; echo "${ACTIVE_PATTERNS[*]}")
    starting_regex=$(IFS='|'; echo "${STARTING_PATTERNS[*]}")

    # Get the most recent output from all panes
    local recent_output=""
    local panes
    panes=$(tmux list-panes -t "$session_name" -F "#{pane_id}" 2>/dev/null) || true

    for pane in $panes; do
        local pane_output
        pane_output=$(tmux capture-pane -t "$pane" -p -S -10 2>/dev/null) || continue
        recent_output+="$pane_output"$'\n'
    done

    # Fall back to timestamp-based detection if no output captured
    if [[ -z "${recent_output// /$'\n'}" ]]; then
        _detect_status_by_activity "$session_name"
        return
    fi

    local output_lower
    output_lower=$(echo "$recent_output" | tr '[:upper:]' '[:lower:]')

    if [[ "$output_lower" =~ ($error_regex) ]]; then
        echo "error"
    elif [[ "$output_lower" =~ ($waiting_regex) ]]; then
        echo "waiting"
    elif [[ "$output_lower" =~ ($complete_regex) ]]; then
        echo "complete"
    elif [[ "$output_lower" =~ ($starting_regex) ]]; then
        echo "starting"
    elif [[ "$output_lower" =~ ($active_regex) ]]; then
        echo "active"
    else
        _detect_status_by_activity "$session_name"
    fi
}

# Timestamp-based fallback for status detection
_detect_status_by_activity() {
    local session_name="$1"
    local last_activity
    last_activity=$(tmux display-message -t "$session_name" -p "#{session_activity}" 2>/dev/null || echo "0")
    local current_time
    current_time=$(date +%s)
    local activity_age=$((current_time - last_activity))

    if [[ $activity_age -lt 30 ]]; then
        echo "active"
    else
        echo "waiting"
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
        local detected=false

        # Fast path: name-based detection
        if is_claude_session "$session"; then
            detected=true
        # Precise: check for claude binary
        elif has_claude_binary "$session"; then
            detected=true
        # Fallback: fuzzy process matching
        elif has_claude_processes "$session"; then
            detected=true
        fi

        if [[ "$detected" == true ]]; then
            local status
            status=$(analyze_session_status "$session")
            local last_activity
            last_activity=$(tmux display-message -t "$session" -p "#{session_activity}" 2>/dev/null || echo "0")
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
    local format="${4:-tmux}"

    local indicator="" color=""

    case "$status" in
        "active")   indicator="$STATUS_ACTIVE";   color="$COLOR_ACTIVE" ;;
        "waiting")  indicator="$STATUS_WAITING";   color="$COLOR_WAITING" ;;
        "complete") indicator="$STATUS_COMPLETE";  color="$COLOR_COMPLETE" ;;
        "error")    indicator="$STATUS_ERROR";     color="$COLOR_ERROR" ;;
        "starting") indicator="$STATUS_STARTING";  color="$COLOR_STARTING" ;;
        *)          indicator=" ";                  color="$COLOR_INACTIVE" ;;
    esac

    local display_name="$session_name"
    if [[ ${#session_name} -gt $((max_width - 3)) ]]; then
        display_name="${session_name:0:$((max_width - 6))}..."
    fi

    if [[ "$format" == "ansi" ]]; then
        local ansi_color
        ansi_color=$(hex_to_ansi "$color")
        echo "${ansi_color}${indicator} ${display_name}${ANSI_RESET}"
    else
        echo "#[fg=$color]$indicator $display_name#[default]"
    fi
}

# Generate tmux sidebar content
generate_sidebar_content() {
    local format="tmux"
    if [[ "$1" == "--ansi" ]]; then
        format="ansi"
    fi

    local sessions_data
    sessions_data=$(get_claude_sessions)
    local sidebar_content=""
    local session_count=0

    # Header
    if [[ "$format" == "ansi" ]]; then
        local header_color
        header_color=$(hex_to_ansi "$COLOR_COMPLETE")
        local inactive_color
        inactive_color=$(hex_to_ansi "$COLOR_INACTIVE")
        sidebar_content+="${ANSI_BOLD}${header_color}🤖 Claude Code${ANSI_RESET}"$'\n'
        sidebar_content+="${inactive_color}───────────────${ANSI_RESET}"$'\n'
    else
        sidebar_content+="#[fg=$COLOR_COMPLETE,bold]🤖 Claude Code#[default]"$'\n'
        sidebar_content+="#[fg=$COLOR_INACTIVE]───────────────#[default]"$'\n'
    fi

    # Sessions
    if [[ -n "$sessions_data" && "$sessions_data" != "[]" ]]; then
        while IFS='|' read -r session status activity; do
            if [[ -n "$session" ]]; then
                sidebar_content+="$(format_session_display "$session" "$status" 15 "$format")"$'\n'
                ((session_count++))
            fi
        done <<< "$sessions_data"
    fi

    # Footer
    if [[ $session_count -eq 0 ]]; then
        if [[ "$format" == "ansi" ]]; then
            local inactive_color
            inactive_color=$(hex_to_ansi "$COLOR_INACTIVE")
            sidebar_content+="${inactive_color}No active sessions${ANSI_RESET}"$'\n'
        else
            sidebar_content+="#[fg=$COLOR_INACTIVE]No active sessions#[default]"$'\n'
        fi
    fi

    sidebar_content+=""$'\n'
    if [[ "$format" == "ansi" ]]; then
        local inactive_color
        inactive_color=$(hex_to_ansi "$COLOR_INACTIVE")
        sidebar_content+="${inactive_color}[picker: C-l]${ANSI_RESET}"$'\n'
        sidebar_content+="${inactive_color}[refresh: C-r]${ANSI_RESET}"
    else
        sidebar_content+="#[fg=$COLOR_INACTIVE][picker: C-l]#[default]"$'\n'
        sidebar_content+="#[fg=$COLOR_INACTIVE][refresh: C-r]#[default]"
    fi

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
            shift
            generate_sidebar_content "$@"
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