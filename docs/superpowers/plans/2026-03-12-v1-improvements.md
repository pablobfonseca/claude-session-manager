# v1 Bash Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish session manager into a usable v1 with ANSI colors, fzf picker, smarter detection, and complete config.

**Architecture:** Four independent improvements to existing bash scripts. No new files. Changes touch `src/claude_session_detector.sh` (ANSI output + detection), `src/tmux_integration.sh` (fzf picker + ANSI rendering), `claude-session-manager` (fzf dep + config template), and `config/example-config` (pattern arrays).

**Tech Stack:** Bash 4.0+, tmux 3.0+, fzf (new required dep)

**Spec:** `docs/superpowers/specs/2026-03-12-v1-improvements-design.md`

---

## Task 1: ANSI Color Support in Detector

**Files:**
- Modify: `src/claude_session_detector.sh`

- [ ] **Step 1: Add `hex_to_ansi()` helper function**

Add after the color variable declarations (after line 24), before the pattern arrays:

```bash
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
```

- [ ] **Step 2: Add `--ansi` flag to `format_session_display()`**

Replace the current `format_session_display()` function (lines 174-218) to accept a 4th parameter for output format:

```bash
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
```

- [ ] **Step 3: Add `--ansi` flag to `generate_sidebar_content()`**

Replace the current `generate_sidebar_content()` function (lines 221-250) to accept an `--ansi` argument:

```bash
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
```

- [ ] **Step 4: Update `main()` to route `--ansi` flag**

Replace the sidebar case in `main()` (line 261):

```bash
        "sidebar")
            shift
            generate_sidebar_content "$@"
            ;;
```

- [ ] **Step 5: Verify syntax**

Run: `bash -n src/claude_session_detector.sh`
Expected: no output (clean parse)

- [ ] **Step 6: Commit**

```bash
git add src/claude_session_detector.sh
git commit -m "feat: add ANSI color output with --ansi flag to detector"
```

---

## Task 2: ANSI Sidebar Rendering in Integration

**Files:**
- Modify: `src/tmux_integration.sh`

- [ ] **Step 1: Update `update_sidebar_content()` to use ANSI output**

Replace lines 124-140 with:

```bash
update_sidebar_content() {
    if ! is_sidebar_active; then
        return 1
    fi

    local content
    content=$("$DETECTOR_SCRIPT" sidebar --ansi 2>/dev/null) || return 1

    local tmpfile="/tmp/claude_sidebar_content.$$"
    printf '%s\n' "$content" > "$tmpfile"

    tmux send-keys -t "$SIDEBAR_PANE_ID" "clear && printf '%b\n' \"\$(cat '$tmpfile')\" && rm -f '$tmpfile'" Enter
}
```

Key changes: calls `sidebar --ansi`, removes sed stripping, uses `printf '%b'` to interpret ANSI escapes.

- [ ] **Step 2: Verify syntax**

Run: `bash -n src/tmux_integration.sh`
Expected: no output (clean parse)

- [ ] **Step 3: Commit**

```bash
git add src/tmux_integration.sh
git commit -m "feat: render ANSI-colored sidebar content"
```

---

## Task 3: fzf Session Picker

**Files:**
- Modify: `src/tmux_integration.sh`
- Modify: `claude-session-manager`

- [ ] **Step 1: Add fzf to dependency check**

In `claude-session-manager`, add after the pgrep warning (after line 292):

```bash
    if ! command -v fzf >/dev/null 2>&1; then
        missing_deps+=("fzf")
    fi
```

Move this inside the `missing_deps` block, before the `${#missing_deps[@]} -gt 0` check. The full updated section should be:

```bash
check_dependencies() {
    local missing_deps=()

    if ! command -v tmux >/dev/null 2>&1; then
        missing_deps+=("tmux")
    else
        local tmux_version
        tmux_version=$(tmux -V | sed 's/[^0-9.]//g')
        local tmux_major="${tmux_version%%.*}"
        if [[ "$tmux_major" -lt 3 ]] 2>/dev/null; then
            echo "⚠️  tmux 3.0+ required (found: $tmux_version)"
            exit 1
        fi
    fi

    if ! command -v bash >/dev/null 2>&1; then
        missing_deps+=("bash")
    else
        local bash_major="${BASH_VERSINFO[0]:-0}"
        if [[ "$bash_major" -lt 4 ]]; then
            echo "⚠️  bash 4.0+ required (found: $BASH_VERSION)"
            exit 1
        fi
    fi

    if ! command -v fzf >/dev/null 2>&1; then
        missing_deps+=("fzf")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "❌ Missing dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi

    if ! command -v pgrep >/dev/null 2>&1; then
        echo "⚠️  pgrep not found — process-based session detection will be limited"
    fi
}
```

- [ ] **Step 2: Replace `show_session_picker()` with fzf version**

Replace the entire `show_session_picker()` function (lines 221-247 of tmux_integration.sh) with:

```bash
show_session_picker() {
    local sessions_data
    sessions_data=$("$DETECTOR_SCRIPT" detect)

    if [[ -z "$sessions_data" || "$sessions_data" == "[]" ]]; then
        echo "No Claude Code sessions found"
        return 1
    fi

    # Build ANSI-colored lines for fzf: "icon session_name (status)"
    local fzf_input=""
    while IFS='|' read -r session status activity; do
        if [[ -n "$session" ]]; then
            local icon="" color=""
            case "$status" in
                "active")   icon="●"; color="\033[38;2;0;255;65m" ;;
                "waiting")  icon="⏸"; color="\033[38;2;255;255;0m" ;;
                "complete") icon="✓"; color="\033[38;2;0;255;255m" ;;
                "error")    icon="❌"; color="\033[38;2;255;0;127m" ;;
                "starting") icon="⚡"; color="\033[38;2;191;0;255m" ;;
                *)          icon=" "; color="\033[38;2;139;147;166m" ;;
            esac
            fzf_input+="$(printf '%b%s %s (%s)\033[0m' "$color" "$icon" "$session" "$status")"$'\n'
        fi
    done <<< "$sessions_data"

    local selected
    selected=$(printf '%s' "$fzf_input" | fzf \
        --ansi \
        --header="Claude Code Sessions (enter to switch)" \
        --preview="tmux capture-pane -t {2} -p -S -30 2>/dev/null || echo 'Preview unavailable'" \
        --preview-window="right:50%" \
        --no-sort \
        --reverse)

    if [[ -n "$selected" ]]; then
        # Extract session name: "icon session_name (status)" → session_name
        local session_name
        session_name=$(echo "$selected" | sed 's/^[^ ]* //' | sed 's/ ([^)]*)$//')
        switch_to_session "$session_name"
    fi
}
```

- [ ] **Step 3: Verify syntax on both files**

Run: `bash -n claude-session-manager && bash -n src/tmux_integration.sh`
Expected: no output (clean parse)

- [ ] **Step 4: Commit**

```bash
git add claude-session-manager src/tmux_integration.sh
git commit -m "feat: fzf-powered session picker with pane preview"
```

---

## Task 4: Smarter Claude Detection

**Files:**
- Modify: `src/claude_session_detector.sh`

- [ ] **Step 1: Add `has_claude_binary()` function**

Add after `has_claude_processes()` (after line 82):

```bash
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
```

- [ ] **Step 2: Update detection order in `get_claude_sessions()`**

Replace the detection logic inside the for loop (lines 159-167):

```bash
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
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n src/claude_session_detector.sh`
Expected: no output (clean parse)

- [ ] **Step 4: Commit**

```bash
git add src/claude_session_detector.sh
git commit -m "feat: smarter detection via claude binary process matching"
```

---

## Task 5: Config Template with Pattern Arrays

**Files:**
- Modify: `claude-session-manager` (install_manager heredoc)
- Modify: `config/example-config`

- [ ] **Step 1: Update install_manager() default config**

Replace the config heredoc in `install_manager()` (lines 85-106) with:

```bash
        cat > "$CONFIG_FILE" << 'EOF'
# Claude Code Session Manager Configuration
# Customize these settings for your workflow

# Sidebar configuration
SIDEBAR_WIDTH="25%"
SIDEBAR_POSITION="right"  # left, right, top, bottom

# Monitoring settings
UPDATE_INTERVAL="3"
AUTO_HIDE_TIMEOUT="30"

# Detection patterns (add your own)
CLAUDE_PATTERNS=("claude" "anthropic" "ai-session" "claude-code" "cc-")

# Color theme (cyberpunk style)
COLOR_ACTIVE="#00ff41"      # Matrix green
COLOR_WAITING="#ffff00"     # Cyber yellow
COLOR_COMPLETE="#00ffff"    # Electric cyan
COLOR_ERROR="#ff007f"       # Neon pink
COLOR_STARTING="#bf00ff"    # Electric purple

# Status detection patterns (customize for your Claude Code output)
ERROR_PATTERNS=("error" "failed" "exception" "traceback" "fatal")
WAITING_PATTERNS=("waiting" "input" "prompt" "continue" "press" "enter")
COMPLETE_PATTERNS=("complete" "done" "finished" "success" "✓" "✅")
ACTIVE_PATTERNS=("thinking" "processing" "working" "analyzing" "generating")
STARTING_PATTERNS=("starting" "initializing" "loading" "connecting")
EOF
```

- [ ] **Step 2: Add STARTING_PATTERNS to example-config**

Add after line 52 (after the ACTIVE_PATTERNS line) in `config/example-config`:

```bash
STARTING_PATTERNS=("starting" "initializing" "loading" "connecting")
```

- [ ] **Step 3: Verify syntax on both files**

Run: `bash -n claude-session-manager && bash -n config/example-config`
Expected: no output (clean parse)

- [ ] **Step 4: Commit**

```bash
git add claude-session-manager config/example-config
git commit -m "feat: add pattern arrays to config template and example"
```

---

## Task 6: Final Verification + Version Bump

**Files:**
- Modify: `claude-session-manager` (version)

- [ ] **Step 1: Syntax check all scripts**

Run: `bash -n claude-session-manager && bash -n src/claude_session_detector.sh && bash -n src/tmux_integration.sh && bash -n config/example-config && bash -n install.sh`
Expected: no output (all clean)

- [ ] **Step 2: Bump version to 1.1.0**

In `claude-session-manager` line 8, change:

```bash
VERSION="1.1.0"
```

- [ ] **Step 3: Commit**

```bash
git add claude-session-manager
git commit -m "chore: bump version to 1.1.0"
```
