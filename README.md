# 🤖 Claude Code Session Manager

> **Visual monitoring and management system for Claude Code AI sessions in tmux**

A tmux-integrated dashboard that provides real-time visibility into active Claude Code sessions, showing their status and alerting when they need interaction. Built specifically for developers using Claude Code with tmux and sessionx.

![Cyberpunk Theme](https://img.shields.io/badge/theme-cyberpunk-ff007f) ![tmux](https://img.shields.io/badge/tmux-3.0%2B-green) ![bash](https://img.shields.io/badge/bash-4.0%2B-blue)

## ✨ Features

- 🎯 **Real-time monitoring** of Claude Code AI sessions
- 📊 **Visual status indicators** with cyberpunk aesthetics  
- ⚡ **Quick navigation** to sessions needing attention
- 🔗 **sessionx integration** for enhanced session management
- ⌨️ **Custom key bindings** for efficient workflow
- 🎨 **Customizable themes** and sidebar positioning
- 🔍 **Smart detection** of Claude Code processes

## 🎮 Status Indicators

- **● Active** (green) - Claude Code is actively working
- **⏸ Waiting** (yellow) - Session needs user input  
- **✓ Complete** (cyan) - Task finished, ready for review
- **❌ Error** (pink) - Session has error, needs attention
- **⚡ Starting** (purple) - Claude Code initializing

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/shikamarunaraclaw/claude-session-manager.git
cd claude-session-manager

# Install system-wide (requires sudo)
sudo ./install.sh

# OR install to user directory
./install.sh

# Setup the manager
claude-session-manager install
```

### Basic Usage

```bash
# Show the Claude Code sidebar
claude-session-manager sidebar show

# Jump to sessions waiting for input
claude-session-manager jump waiting

# List all Claude Code sessions
claude-session-manager list

# Quick toggle sidebar
# PREFIX + C-c (in tmux)
```

## 📋 Commands

### Sidebar Management
```bash
claude-session-manager sidebar show      # Create and show sidebar
claude-session-manager sidebar hide      # Remove sidebar
claude-session-manager sidebar toggle    # Toggle visibility
claude-session-manager sidebar refresh   # Update content
```

### Session Navigation
```bash
claude-session-manager list              # List all Claude sessions
claude-session-manager jump waiting      # Jump to waiting sessions
claude-session-manager jump active       # Jump to active sessions
claude-session-manager jump error        # Jump to error sessions
claude-session-manager switch <session>  # Switch to specific session
```

### Key Bindings (after installation)
| Binding | Action |
|---------|--------|
| `PREFIX + C-c` | Toggle sidebar |
| `PREFIX + C-w` | Jump to waiting sessions |
| `PREFIX + C-e` | Jump to error sessions |
| `PREFIX + C-a` | Jump to active sessions |
| `PREFIX + C-r` | Refresh sidebar |

## 🎨 Sidebar Display

```
┌─────────────────────────┬─────────────────┐
│                         │ 🤖 Claude Code  │
│                         │ ───────────────  │
│   Your Main Terminal    │ ● coding-api     │
│                         │ ⏸ web-frontend   │
│   (Current Work)        │ ✓ bug-fix-auth   │
│                         │ ❌ refactor-db   │
│                         │ ⚡ ml-pipeline   │
│                         │                 │
│                         │ [sessionx: o]   │
│                         │ [refresh: r]    │
└─────────────────────────┴─────────────────┘
```

## ⚙️ Configuration

Configuration file: `~/.config/claude-session-manager/config`

```bash
# Sidebar settings
SIDEBAR_WIDTH="25%"
SIDEBAR_POSITION="right"  # left, right, top, bottom

# Update frequency
UPDATE_INTERVAL="3"       # seconds

# Detection patterns
CLAUDE_PATTERNS=("claude" "anthropic" "ai-session" "claude-code" "cc-")

# Cyberpunk color theme
COLOR_ACTIVE="#00ff41"    # Matrix green
COLOR_WAITING="#ffff00"   # Cyber yellow
COLOR_COMPLETE="#00ffff"  # Electric cyan
COLOR_ERROR="#ff007f"     # Neon pink
COLOR_STARTING="#bf00ff"  # Electric purple
```

## 🔍 Session Detection

The manager detects Claude Code sessions through:

1. **Session name patterns**: Sessions with "claude", "anthropic", "ai-session", etc.
2. **Process analysis**: Active Claude Code processes in tmux panes
3. **Output analysis**: Content analysis to determine session status

### Naming Conventions

For best detection, name your Claude Code sessions:
- `claude-code-[project]`
- `claude-[task-type]`
- `cc-[description]`
- `ai-session-[name]`

## 🔧 Integration with sessionx

Works seamlessly with [omerxx/tmux-sessionx](https://github.com/omerxx/tmux-sessionx):

1. Use `sessionx` (PREFIX + o) for session switching
2. Claude sessions show with status indicators
3. Quick navigation to sessions needing attention
4. Enhanced workflow without disruption

## 📊 Status Detection Logic

The manager analyzes tmux pane output for:

- **Error patterns**: "error", "failed", "exception", "traceback"
- **Waiting patterns**: "waiting", "input", "prompt", "continue"
- **Complete patterns**: "complete", "done", "finished", "success"
- **Active patterns**: "thinking", "processing", "working", "analyzing"

## 🛠️ Development

### Project Structure
```
claude-session-manager/
├── claude-session-manager          # Main entry point
├── src/
│   ├── claude_session_detector.sh  # Core detection logic
│   └── tmux_integration.sh         # tmux sidebar integration
├── config/                         # Configuration examples
├── docs/                          # Documentation
├── tests/                         # Test scripts
└── install.sh                    # Installation script
```

### Running Tests
```bash
# Test session detection
./src/claude_session_detector.sh detect

# Test sidebar generation
./src/claude_session_detector.sh sidebar

# Test tmux integration
./src/tmux_integration.sh status
```

## 🐛 Troubleshooting

### Sidebar not showing
```bash
# Check if tmux is running
echo $TMUX

# Check sidebar status
claude-session-manager status

# Manually refresh
claude-session-manager sidebar refresh
```

### Sessions not detected
```bash
# List current sessions
tmux list-sessions

# Check detection manually
claude-session-manager list

# Verify session naming patterns in config
claude-session-manager configure
```

### Key bindings not working
```bash
# Reinstall key bindings
claude-session-manager keys install

# Check tmux key bindings
tmux list-keys | grep "C-"
```

## 🎯 Workflow Examples

### Daily Development
1. Start Claude Code sessions with descriptive names
2. Show sidebar: `claude-session-manager sidebar show`
3. Work normally - sidebar updates automatically
4. When sessions need attention, indicators change
5. Quick jump: `PREFIX + C-w` to sessions waiting for input

### Project Management
```bash
# Start project sessions
tmux new-session -d -s "claude-api-refactor"
tmux new-session -d -s "claude-frontend-bugs"
tmux new-session -d -s "cc-documentation"

# Monitor all sessions
claude-session-manager sidebar show

# Quick navigation as needed
claude-session-manager jump waiting
```

## 🤝 Contributing

Contributions welcome! Areas for improvement:
- Additional status detection patterns
- Enhanced sessionx integration
- Alternative display modes (status bar, floating)
- Configuration GUI
- Session analytics

### Development Setup
```bash
git clone https://github.com/shikamarunaraclaw/claude-session-manager.git
cd claude-session-manager
chmod +x claude-session-manager src/*.sh
./claude-session-manager install
```

## 📝 License

MIT License - feel free to fork and enhance!

## 🙏 Acknowledgments

- Built for developers using Claude Code with tmux
- Inspired by modern development workflows
- Compatible with [sessionx](https://github.com/omerxx/tmux-sessionx) plugin
- Cyberpunk aesthetic inspired by futuristic development environments

---

**"Bringing AI session management to the command line"** 🤖⚡

For issues or suggestions: https://github.com/shikamarunaraclaw/claude-session-manager/issues