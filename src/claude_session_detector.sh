#!/usr/bin/env bash

# Claude Code Session Detector
# Detects panes running the claude binary and determines their status
# Uses hook-written status files when available, falls back to terminal scraping

CONFIG_FILE="${HOME}/.config/claude-session-manager/config"
HOOK_STATUS_DIR="/tmp/claude-session-manager"

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

# Get status from hook-written file, matched by cwd
# Hook files: /tmp/claude-session-manager/<session_id>
# Format: status|cwd|timestamp
_get_hook_status() {
    local pane_cwd="$1"
    [[ -d "$HOOK_STATUS_DIR" ]] || return 1

    local now
    now=$(date +%s)

    for status_file in "$HOOK_STATUS_DIR"/*; do
        [[ -f "$status_file" ]] || continue
        local file_status file_cwd file_ts
        IFS='|' read -r file_status file_cwd file_ts < "$status_file"

        # Match by cwd
        if [[ "$file_cwd" == "$pane_cwd" ]]; then
            # Only trust if recent (< 120s)
            local age=$((now - file_ts))
            if [[ $age -lt 120 ]]; then
                echo "$file_status"
                return 0
            fi
        fi
    done
    return 1
}

# Analyze a single Claude pane's terminal output to determine status
# Returns: active, approval, idle
analyze_pane_status() {
    local pane_id="$1"

    # First: check hook-written status files (most reliable)
    local pane_cwd
    pane_cwd=$(tmux display-message -t "$pane_id" -p "#{pane_current_path}" 2>/dev/null)
    if [[ -n "$pane_cwd" ]]; then
        local hook_status
        hook_status=$(_get_hook_status "$pane_cwd") && {
            echo "$hook_status"
            return
        }
    fi

    # Fallback: scrape terminal output
    local output
    output=$(tmux capture-pane -t "$pane_id" -p -S -20 2>/dev/null) || {
        echo "idle"
        return
    }

    local last_lines
    last_lines=$(echo "$output" | sed '/^[[:space:]]*$/d' | tail -10)

    # Check for active work (spinner, tool execution)
    if echo "$last_lines" | grep -qE '(✳|⏺.*Running|⏺.*Bash|⏺.*Read|⏺.*Write|⏺.*Edit|⏺.*Glob|⏺.*Grep|⏺.*Agent)'; then
        echo "active"
        return
    fi

    # Check for approval/permission prompts
    local content_lines
    content_lines=$(echo "$output" | sed '/^[[:space:]]*$/d' | sed '$ d' | tail -5)
    if echo "$content_lines" | grep -qiE '(Allow|Approve|Do you want|permission|Yes.*No.*All)'; then
        echo "approval"
        return
    fi

    # Check for idle prompt
    if echo "$last_lines" | grep -qE '^❯[[:space:]]*$'; then
        echo "idle"
        return
    fi

    # Fallback: activity timestamp
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

# Find all Claude panes with their status
# Output: session|pane_id|project|status per line
get_claude_panes() {
    if ! tmux list-sessions >/dev/null 2>&1; then
        return
    fi

    local sessions
    sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null) || return

    for session in $sessions; do
        local pane_info
        pane_info=$(tmux list-panes -t "$session" -s -F "#{pane_id} #{pane_pid}" 2>/dev/null) || continue

        while read -r pane_id pane_pid; do
            [[ -z "$pane_id" ]] && continue
            if _pane_has_claude "$pane_pid"; then
                local status
                status=$(analyze_pane_status "$pane_id")
                local pane_cwd
                pane_cwd=$(tmux display-message -t "$pane_id" -p "#{pane_current_path}" 2>/dev/null || echo "unknown")
                local project
                project=$(basename "$pane_cwd")
                echo "$session|$pane_id|$project|$status"
            fi
        done <<< "$pane_info"
    done
}

# Write status from a Claude hook notification
# Called by hook commands with: write-status <notification_type>
# Reads JSON payload from stdin
write_hook_status() {
    local notification_type="$1"
    mkdir -p "$HOOK_STATUS_DIR"

    local payload
    payload=$(cat)

    local session_id cwd
    session_id=$(echo "$payload" | jq -r '.session_id // empty')
    cwd=$(echo "$payload" | jq -r '.cwd // empty')

    [[ -z "$session_id" || -z "$cwd" ]] && return 1

    local status
    case "$notification_type" in
        "permission_prompt") status="approval" ;;
        "idle_prompt")       status="idle" ;;
        *)                   status="idle" ;;
    esac

    local now
    now=$(date +%s)
    echo "${status}|${cwd}|${now}" > "$HOOK_STATUS_DIR/$session_id"
}

# Format a single pane entry for display
format_pane_display() {
    local session="$1"
    local project="$2"
    local status="$3"
    local format="${4:-ansi}"

    local indicator="" color="" label=""

    case "$status" in
        "active")   indicator="$STATUS_ACTIVE";   color="$COLOR_ACTIVE";   label="working" ;;
        "approval") indicator="$STATUS_APPROVAL";  color="$COLOR_APPROVAL"; label="needs approval" ;;
        "idle")     indicator="$STATUS_IDLE";      color="$COLOR_IDLE";     label="idle" ;;
        *)          indicator="$STATUS_IDLE";      color="$COLOR_IDLE";     label="$status" ;;
    esac

    if [[ "$format" == "ansi" ]]; then
        local ansi_color
        ansi_color=$(hex_to_ansi "$color")
        local dim
        dim=$(hex_to_ansi "$COLOR_IDLE")
        echo "${ansi_color}${indicator} ${project}${ANSI_RESET} ${dim}[${session}]${ANSI_RESET} ${ansi_color}— ${label}${ANSI_RESET}"
    else
        echo "#[fg=$color]$indicator $project#[default] #[fg=$COLOR_IDLE][$session]#[default] #[fg=$color]— $label#[default]"
    fi
}

# Generate popup content
generate_sidebar_content() {
    local format="tmux"
    if [[ "$1" == "--ansi" ]]; then
        format="ansi"
    fi

    local panes_data
    panes_data=$(get_claude_panes)
    local content=""
    local count=0

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

    if [[ -n "$panes_data" ]]; then
        while IFS='|' read -r session pane_id project status; do
            [[ -z "$session" ]] && continue
            content+="$(format_pane_display "$session" "$project" "$status" "$format")"$'\n'
            ((count++))
        done <<< "$panes_data"
    fi

    if [[ $count -eq 0 ]]; then
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
            get_claude_panes
            ;;
        "sidebar")
            shift
            generate_sidebar_content "$@"
            ;;
        "write-status")
            write_hook_status "$2"
            ;;
        "status")
            local session="${2:-}"
            if [[ -n "$session" ]]; then
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
            get_claude_panes | while IFS='|' read -r session pane_id project status; do
                [[ -z "$session" ]] && continue
                echo "$project [$session] — $status"
            done
            ;;
        *)
            echo "Usage: $0 {detect|sidebar|status|list|write-status}"
            echo "  detect        - Get all Claude panes data"
            echo "  sidebar       - Generate popup content"
            echo "  status        - Get specific session status"
            echo "  list          - List all Claude instances with status"
            echo "  write-status  - Write status from hook (stdin: JSON)"
            exit 1
            ;;
    esac
}

main "$@"
