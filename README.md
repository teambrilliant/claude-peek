# Claude Peek

A macOS status surface for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that lives at the top edge of your screen. On notched MacBooks it extends from the notch; on other displays it appears as a floating pill. See what your sessions are doing, approve tool permissions, and read conversation history — without switching windows.

Built by [Team Brilliant](https://teambrilliant.com).

## Features

- **Session status** — processing, waiting for input, waiting for approval, compacting
- **Multiple sessions** — track all running Claude Code sessions at a glance
- **Permission handling** — approve, deny, or always-allow tool requests from the notch
- **Conversation viewer** — click a session to read the full conversation history, updated live
- **Session names** — shows `/rename` titles when set, project directory otherwise
- **Non-intrusive** — never steals focus, runs as a menu bar app (no dock icon)
- **Notch + non-notch** — adapts to MacBook notch or floating pill on external displays

## Install

### Requirements

- macOS 14+
- Python 3 (ships with macOS)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support

### Quick install

```bash
git clone https://github.com/teambrilliant/claude-peek.git
cd claude-peek && ./install.sh
```

This builds the app, copies it to `/Applications`, configures Claude Code hooks in `~/.claude/settings.json` (merging with your existing hooks), and launches Claude Peek.

### Manual install

If you prefer to set things up yourself:

1. **Build and install the app:**

```bash
git clone https://github.com/teambrilliant/claude-peek.git
cd claude-peek
./scripts/build-app.sh
cp -r ClaudePeek.app /Applications/
```

2. **Configure hooks** — add to your `~/.claude/settings.json`, merging into your existing `"hooks"` section:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ],
    "PreToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ],
    "PermissionRequest": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py", "timeout": 86400 }] }
    ],
    "Notification": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ],
    "SubagentStop": [
      { "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ],
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ],
    "PreCompact": [
      { "matcher": "auto", "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] },
      { "matcher": "manual", "hooks": [{ "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }] }
    ]
  }
}
```

Replace `/path/to/claude-peek` with the actual path to the cloned repo.

3. **Launch:**

```bash
open /Applications/ClaudePeek.app
```

To quit: `pkill ClaudePeek`

## How it works

```
Claude Code hooks → Python script → Unix socket → ClaudePeek → Notch UI
                                   ← permission response (allow/deny/always) ←
```

The Python hook script relays Claude Code events to a Unix socket at `/tmp/claude-peek.sock`. For permission requests, the script blocks until you approve or deny from the UI, then sends the decision back to Claude Code.

The conversation viewer reads JSONL files from `~/.claude/projects/` for live conversation history.

## Testing without hooks

Send events directly to the socket:

```bash
# Start processing
echo '{"session_id":"s1","cwd":"/tmp/project","event":"UserPromptSubmit","status":"processing","pid":1234}' | nc -U /tmp/claude-peek.sock

# Done
echo '{"session_id":"s1","cwd":"/tmp/project","event":"Stop","status":"waiting_for_input","pid":1234}' | nc -U /tmp/claude-peek.sock
```

## Project structure

```
├── Package.swift
├── Info.plist
├── install.sh           # One-command install via claude -p
├── Sources/
│   ├── App/             # Entry point, app delegate
│   ├── Core/            # Models, geometry, view model, screen tracking
│   ├── Services/        # Socket server, session manager, JSONL parser
│   └── UI/              # SwiftUI views, window, conversation viewer
├── hooks/               # Python hook script
├── mcp/                 # MCP server for Claude Peek
└── scripts/             # Build scripts
```

## License

MIT
