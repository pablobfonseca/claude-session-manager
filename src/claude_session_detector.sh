#!/usr/bin/env bash

# Claude Code Session Detector
# Detects and monitors Claude Code AI sessions across tmux environment
# Only detects panes actually running the claude binary

CONFIG_FILE="${HOME}/.config/claude-session-manager/config"

# Status indicators
STATUS_ACTIVE="●"
STATUS_APPROVAL="⏸"
STATUS_IDLE="◯"

# Colors
COLOR_ACTIVE="#00ff41"      # Matrix green
COLOR_APPROVAL="#ffff00"    # Cyber yellow
COLOR_IDLE="#8b93a6"        # Muted gray

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

# Load configuration if exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Check if a pane's process tree contains the claude binary
_pane_has_claude() {
    local pane_pid="$1"
    local all_pids="$pane_pid"

    if command -v pgrep >/dev/null 2>&1; then
        all_pids+=" $(pgrep -P "$pane_pid" 2>/dev/null || true)"
    fi

    for pid in $all_pids; do
        local args
        args=$(ps -p "$pid" -o args= 2>/dev/null) || continue
        if [[ "$args" =~ (^|/)claude( |$) ]] || \
           [[ "$args" =~ npx[[:space:]]+claude ]] || \
           [[ "$args" =~ bunx[[:space:]]+claude ]]; then
            return 0
        fi
    done
    return 1
}

# Find all panes running Claude across all sessions
# Output: session_name|pane_id per line
find_claude_panes() {
    local sessions
    sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null) || return

    for session in $sessions; do
        local pane_info
        pane_info=$(tmux list-panes -t "$session" -s -F "#{pane_id} #{pane_pid}" 2>/dev/null) || continue

        while read -r pane_id pane_pid; do
            [[ -z "$pane_id" ]] && continue
            if _pane_has_claude "$pane_pid"; then
                echo "$session|$pane_id"
            fi
        done <<< "$pane_info"
    done
}

# Analyze a single Claude pane's terminal output to determine status
# Returns: active, approval, idle
analyze_pane_status() {
    local pane_id="$1"

    # Capture the last 20 lines of pane output
    local output
    output=$(tmux capture-pane -t "$pane_id" -p -S -20 2>/dev/null) || {
        echo "idle"
        return
    }

    # Strip empty lines from the bottom to find the last meaningful content
    # The status bar is the very last line; content is above it
    local last_lines
    last_lines=$(echo "$output" | sed '/^[[:space:]]*$/d' | tail -10)

    # 1. Check for approval/permission prompts (highest priority)
    #    Claude Code shows these when waiting for tool approval
    #    Exclude the status bar line (contains "accept edits" mode indicator)
    local content_lines
    content_lines=$(echo "$output" | sed '/^[[:space:]]*$/d' | sed '$ d' | tail -5)
    if echo "$content_lines" | grep -qiE '(Allow|Approve|Do you want|permission|Yes.*No.*All)'; then
        echo "approval"
        return
    fi

    # 2. Check for active work (spinner, tool execution)
    #    Claude Code shows ✳ spinner when thinking/working
    #    Also shows ⏺ when executing tools
    if echo "$last_lines" | grep -qE '(✳|⏺.*Running|⏺.*Bash|⏺.*Read|⏺.*Write|⏺.*Edit|⏺.*Glob|⏺.*Grep|⏺.*Agent)'; then
        echo "active"
        return
    fi

    # 3. Check for the idle prompt ❯
    #    When Claude is waiting for user input, the prompt line shows ❯
    #    It appears near the bottom, above the status bar
    if echo "$last_lines" | grep -qE '^❯[[:space:]]*$'; then
        echo "idle"
        return
    fi

    # 4. Fallback: check session activity timestamp
    local session_name
    session_name=$(tmux display-message -t "$pane_id" -p "#{session_name}" 2>/dev/null)
    local last_activity
    last_activity=$(tmux display-message -t "$pane_id" -p "#{session_activity}" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local age=$((now - last_activity))

    if [[ $age -lt 5 ]]; then
        echo "active"
    else
        echo "idle"
    fi
}

# Get all Claude sessions with aggregated status
# Output: session_name|status|pane_count per line
get_claude_sessions() {
    if ! tmux list-sessions >/dev/null 2>&1; then
        return
    fi

    local claude_panes
    claude_panes=$(find_claude_panes)

    if [[ -z "$claude_panes" ]]; then
        return
    fi

    # Collect statuses per session
    # Use temp files to aggregate since bash associative arrays
    # don't preserve insertion order reliably
    local tmpdir="/tmp/claude_detect.$$"
    mkdir -p "$tmpdir"

    while IFS='|' read -r session pane_id; do
        [[ -z "$session" ]] && continue
        local status
        status=$(analyze_pane_status "$pane_id")
        echo "$status" >> "$tmpdir/$session"
    done <<< "$claude_panes"

    # Aggregate: pick highest priority status per session
    # Priority: approval > active > idle
    for session_file in "$tmpdir"/*; do
        [[ -f "$session_file" ]] || continue
        local session_name
        session_name=$(basename "$session_file")
        local pane_count
        pane_count=$(wc -l < "$session_file" | tr -d ' ')

        local final_status="idle"
        if grep -q "approval" "$session_file"; then
            final_status="approval"
        elif grep -q "active" "$session_file"; then
            final_status="active"
        fi

        echo "$session_name|$final_status|$pane_count"
    done

    rm -rf "$tmpdir"
}

# Format session for display
format_session_display() {
    local session_name="$1"
    local status="$2"
    local pane_count="$3"
    local max_width="${4:-25}"
    local format="${5:-tmux}"

    local indicator="" color="" label=""

    case "$status" in
        "active")   indicator="$STATUS_ACTIVE";   color="$COLOR_ACTIVE";   label="working" ;;
        "approval") indicator="$STATUS_APPROVAL";  color="$COLOR_APPROVAL"; label="needs approval" ;;
        "idle")     indicator="$STATUS_IDLE";      color="$COLOR_IDLE";     label="idle" ;;
        *)          indicator="$STATUS_IDLE";      color="$COLOR_IDLE";     label="$status" ;;
    esac

    local display_name="$session_name"
    if [[ ${#session_name} -gt $((max_width - 3)) ]]; then
        display_name="${session_name:0:$((max_width - 6))}..."
    fi

    local pane_suffix=""
    if [[ "$pane_count" -gt 1 ]]; then
        pane_suffix=" (${pane_count})"
    fi

    if [[ "$format" == "ansi" ]]; then
        local ansi_color
        ansi_color=$(hex_to_ansi "$color")
        echo "${ansi_color}${indicator} ${display_name}${pane_suffix} — ${label}${ANSI_RESET}"
    else
        echo "#[fg=$color]$indicator $display_name$pane_suffix — $label#[default]"
    fi
}

# Generate popup/sidebar content
generate_sidebar_content() {
    local format="tmux"
    if [[ "$1" == "--ansi" ]]; then
        format="ansi"
    fi

    local sessions_data
    sessions_data=$(get_claude_sessions)
    local content=""
    local session_count=0

    # Header
    if [[ "$format" == "ansi" ]]; then
        local header_color
        header_color=$(hex_to_ansi "#00ffff")
        local dim_color
        dim_color=$(hex_to_ansi "$COLOR_IDLE")
        content+="${ANSI_BOLD}${header_color}🤖 Claude Code Sessions${ANSI_RESET}"$'\n'
        content+="${dim_color}───────────────────────${ANSI_RESET}"$'\n'
    else
        content+="#[fg=#00ffff,bold]🤖 Claude Code Sessions#[default]"$'\n'
        content+="#[fg=$COLOR_IDLE]───────────────────────#[default]"$'\n'
    fi

    # Sessions
    if [[ -n "$sessions_data" ]]; then
        while IFS='|' read -r session status pane_count; do
            [[ -z "$session" ]] && continue
            content+="$(format_session_display "$session" "$status" "$pane_count" 25 "$format")"$'\n'
            ((session_count++))
        done <<< "$sessions_data"
    fi

    if [[ $session_count -eq 0 ]]; then
        if [[ "$format" == "ansi" ]]; then
            local dim_color
            dim_color=$(hex_to_ansi "$COLOR_IDLE")
            content+="${dim_color}No Claude sessions found${ANSI_RESET}"$'\n'
        else
            content+="#[fg=$COLOR_IDLE]No Claude sessions found#[default]"$'\n'
        fi
    fi

    # Legend
    content+=""$'\n'
    if [[ "$format" == "ansi" ]]; then
        local dim_color
        dim_color=$(hex_to_ansi "$COLOR_IDLE")
        local green
        green=$(hex_to_ansi "$COLOR_ACTIVE")
        local yellow
        yellow=$(hex_to_ansi "$COLOR_APPROVAL")
        content+="${green}${STATUS_ACTIVE} working${ANSI_RESET}  "
        content+="${yellow}${STATUS_APPROVAL} needs approval${ANSI_RESET}  "
        content+="${dim_color}${STATUS_IDLE} idle${ANSI_RESET}"$'\n'
    else
        content+="#[fg=$COLOR_ACTIVE]$STATUS_ACTIVE working#[default]  "
        content+="#[fg=$COLOR_APPROVAL]$STATUS_APPROVAL needs approval#[default]  "
        content+="#[fg=$COLOR_IDLE]$STATUS_IDLE idle#[default]"$'\n'
    fi

    echo "$content"
}

# Main
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
                # Find claude panes in this specific session
                local panes
                panes=$(tmux list-panes -t "$session" -s -F "#{pane_id} #{pane_pid}" 2>/dev/null) || {
                    echo "unknown"
                    return
                }
                while read -r pane_id pane_pid; do
                    [[ -z "$pane_id" ]] && continue
                    if _pane_has_claude "$pane_pid"; then
                        analyze_pane_status "$pane_id"
                        return
                    fi
                done <<< "$panes"
                echo "no claude pane found"
            else
                echo "Usage: $0 status <session_name>"
                exit 1
            fi
            ;;
        "list")
            get_claude_sessions | while IFS='|' read -r session status pane_count; do
                [[ -z "$session" ]] && continue
                local suffix=""
                [[ "$pane_count" -gt 1 ]] && suffix=" (${pane_count} panes)"
                echo "$session: $status$suffix"
            done
            ;;
        *)
            echo "Usage: $0 {detect|sidebar|status|list}"
            echo "  detect   - Get all Claude sessions data"
            echo "  sidebar  - Generate popup content"
            echo "  status   - Get specific session status"
            echo "  list     - List all Claude sessions with status"
            exit 1
            ;;
    esac
}

main "$@"
