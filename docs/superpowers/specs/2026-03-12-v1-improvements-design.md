# Design: v1 Bash Improvements

## Goal

Polish the bash session manager into a usable v1 before the planned Go TUI rewrite. Four improvements: ANSI colored sidebar, fzf session picker, smarter Claude detection, and complete config template.

## Acceptance Criteria

- [ ] Sidebar displays colored status indicators and session names using ANSI 24-bit escapes
- [ ] `--ansi` flag on detector sidebar command; default keeps tmux format
- [ ] fzf-powered session picker with pane preview, bound to PREFIX + C-l
- [ ] fzf is a required dependency (checked at startup)
- [ ] `has_claude_binary()` detects `claude` CLI processes via `ps -o args=`
- [ ] Detection order: name match (fast) → binary check (precise) → fuzzy process check (fallback)
- [ ] Default config template and example-config include all pattern arrays
- [ ] No new files — all changes in existing scripts

## Design

### 1. ANSI Color Sidebar

**Files:** `src/claude_session_detector.sh`, `src/tmux_integration.sh`

Add `hex_to_ansi()` helper converting `#RRGGBB` → `\033[38;2;R;G;Bm`. Add `--ansi` flag to `generate_sidebar_content()` and `format_session_display()`. When set, emit ANSI escapes instead of tmux color codes. Default (no flag) preserves tmux format for future status bar use.

Integration script calls `sidebar --ansi` and uses `printf '%b'` to render escapes. Remove sed stripping logic.

### 2. fzf Session Picker

**Files:** `src/tmux_integration.sh`, `claude-session-manager`

Replace `show_session_picker()` with fzf-powered version. Pipe session list (ANSI icon + name + status) into `fzf --ansi` with `--preview` showing last 30 lines of selected session's pane (`tmux capture-pane -t {session} -p -S -30`). Preview window right:50%. On selection, switch to session. Bound to PREFIX + C-l.

Add fzf to `check_dependencies()` as required.

### 3. Smarter Claude Detection

**Files:** `src/claude_session_detector.sh`

Add `has_claude_binary()` — checks pane PIDs and children via `ps -o args=` for `claude` binary invocations. Catches `claude`, `claude chat`, `npx claude`, etc.

Detection order in `get_claude_sessions()`: name match (short-circuit, skip process checks) → binary check → fuzzy process check.

### 4. Config Template with Pattern Arrays

**Files:** `claude-session-manager`, `config/example-config`

Add all pattern arrays (ERROR, WAITING, COMPLETE, ACTIVE, STARTING) to `install_manager()` heredoc and example config. Add missing `STARTING_PATTERNS` to example config.

## Constraints

- No new files
- Future Go TUI rewrite planned — don't over-invest in bash complexity
- No tests in bash — testing deferred to Go rewrite
- fzf is a hard dependency
