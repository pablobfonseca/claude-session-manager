# Claude Code Session Manager

Monitor and manage Claude Code sessions across tmux.

Detects panes running the `claude` binary, analyzes their terminal output to determine status, and provides popup-based UI for quick navigation.

![tmux](https://img.shields.io/badge/tmux-3.0%2B-green) ![bash](https://img.shields.io/badge/bash-4.0%2B-blue) ![fzf](https://img.shields.io/badge/fzf-required-orange)

## Status Indicators

| Indicator | Status | Meaning |
|-----------|--------|---------|
| ● green | **active** | Claude is working (spinner, tool execution) |
| ⏸ yellow | **approval** | Claude needs permission to proceed |
| ◯ gray | **idle** | Waiting for user input at `❯` prompt |

## Installation

```bash
git clone https://github.com/shikamarunaraclaw/claude-session-manager.git
cd claude-session-manager
./install.sh
```

Requires: `tmux 3.0+`, `bash 4.0+`, `fzf`

> **macOS note**: System bash is 3.2. Install bash 5 via Homebrew: `brew install bash`

## Usage

```bash
# Show session status popup
claude-session-manager show

# Open fzf session picker with preview
claude-session-manager picker

# List all Claude sessions
claude-session-manager list

# Jump to sessions by status
claude-session-manager jump approval    # needs your attention
claude-session-manager jump active      # currently working
claude-session-manager jump idle        # waiting for input

# Check specific session
claude-session-manager status <session>

# Switch to session
claude-session-manager switch <session>
```

### Recommended tmux.conf bindings

```tmux
bind-key g run-shell 'claude-session-manager show'
bind-key G run-shell 'claude-session-manager picker'
```

## Detection

The detector scans all tmux panes (across all windows and sessions) for the `claude` binary in the process tree. No session naming conventions required — it finds Claude wherever it's running.

Each Claude instance is shown individually by **project name** (basename of cwd) with its tmux session in brackets.

### Status detection (two sources)

**1. Claude Code hooks (preferred)** — Add Notification hooks to `~/.claude/settings.json` that write status via `claude-session-manager hook-status`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [{
          "type": "command",
          "command": "input=$(cat); echo \"$input\" | claude-session-manager hook-status idle_prompt"
        }]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [{
          "type": "command",
          "command": "input=$(cat); echo \"$input\" | claude-session-manager hook-status permission_prompt"
        }]
      }
    ]
  }
}
```

Status files are written to `/tmp/claude-session-manager/` and matched to tmux panes by `cwd`.

**2. Terminal scraping (fallback)** — When no hook status is available, analyzes the pane's terminal output:
- **active**: Spinner (`✳`) or tool execution markers
- **approval**: Permission prompts (`Allow?`, `Do you want to proceed?`)
- **idle**: Input prompt (`❯`) with no pending input

## Configuration

```bash
claude-session-manager configure
```

Config file: `~/.config/claude-session-manager/config`

```bash
# Popup dimensions
POPUP_WIDTH="60%"
POPUP_HEIGHT="60%"

# Colors
COLOR_ACTIVE="#00ff41"      # working
COLOR_APPROVAL="#ffff00"    # needs approval
COLOR_IDLE="#8b93a6"        # idle
```

## Project Structure

```
claude-session-manager/
├── claude-session-manager          # Main entry point
├── src/
│   ├── claude_session_detector.sh  # Detection + status analysis
│   └── tmux_integration.sh        # Popup display + fzf picker
├── config/
│   └── example-config              # Example configuration
└── install.sh                      # Installer (symlinks to ~/.local/bin)
```

## License

MIT
