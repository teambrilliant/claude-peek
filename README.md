# Claude Peek

A macOS status surface for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that lives at the top edge of your screen. On notched MacBooks it extends from the notch; on other displays it appears as a floating pill. See what your sessions are doing, approve tool permissions, and read conversation history — without switching windows.

Native Swift/SwiftUI. Privacy-first — no analytics, no tracking, no telemetry. Runs locally, data stays on your machine.

Built by [Team Brilliant](https://teambrilliant.com).

## Features

- **Session status** — processing, waiting for input, waiting for approval, compacting
- **Multiple sessions** — track all running Claude Code sessions at a glance
- **Permission handling** — approve, deny, or always-allow tool requests from the UI
- **Conversation viewer** — click a session to read the full conversation history, updated live
- **Terminal focus** — one click to jump to the right terminal window, even across Spaces
- **Session names** — shows `/rename` titles when set, project directory otherwise
- **Reply** (experimental) — send messages to any session directly from the notch
- **Non-intrusive** — never steals focus, runs as a menu bar app (no dock icon)
- **Notch + non-notch** — adapts to MacBook notch or floating pill on external displays

## Install

### Requirements

- macOS 14+ (Apple Silicon)
- Python 3 (ships with macOS)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support

### Download (recommended)

1. Download `ClaudePeek.zip` from the [latest release](https://github.com/teambrilliant/claude-peek/releases/latest)
2. Unzip and move `ClaudePeek.app` to `/Applications`
3. Configure hooks (see below)
4. Open `/Applications/ClaudePeek.app`

The app is signed and notarized — no Gatekeeper warnings.

### Build from source

```bash
git clone https://github.com/teambrilliant/claude-peek.git
cd claude-peek && ./install.sh
```

This builds the app, copies it to `/Applications`, configures Claude Code hooks in `~/.claude/settings.json` (merging with your existing hooks), and launches Claude Peek.

### Hook configuration

If you used `install.sh`, hooks are configured automatically. Otherwise, add to your `~/.claude/settings.json`, merging into your existing `"hooks"` section:

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

Replace `/path/to/claude-peek` with the actual path to the cloned repo (or wherever you placed the hooks directory).

### Launch

```bash
open /Applications/ClaudePeek.app
```

To quit: `pkill ClaudePeek`

### Update

**Pre-built:** download the latest release and replace the app in `/Applications`.

**From source:** `cd claude-peek && git pull && ./install.sh`

## Experimental: Reply from Peek

Reply lets you send messages to Claude Code sessions directly from the notch UI, without switching to the terminal. This uses MCP channels, which are currently in research preview.

### Setup

1. **Install Bun** (if not already): `curl -fsSL https://bun.sh/install | bash`

2. **Install MCP server dependencies:**
```bash
cd claude-peek/mcp && bun install
```

3. **Add MCP server to `~/.claude.json`** (create the `mcpServers` key if it doesn't exist):
```json
{
  "mcpServers": {
    "claude-peek": {
      "type": "stdio",
      "command": "bun",
      "args": ["/path/to/claude-peek/mcp/server.ts"],
      "env": {}
    }
  }
}
```

4. **Auto-approve the reply tool** — add to `permissions.allow` in `~/.claude/settings.json`:
```json
{
  "permissions": {
    "allow": ["mcp__claude-peek__reply"]
  }
}
```

5. **Start Claude Code with channels enabled:**
```bash
claude --dangerously-load-development-channels server:claude-peek
```

Or add an alias to `~/.zshrc` for convenience:
```bash
alias claude='claude --dangerously-load-development-channels server:claude-peek'
```

When channels are active, a "Reply..." input appears at the bottom of the conversation viewer for sessions in "Done" state.

> **Note:** The `--dangerously-load-development-channels` flag is required during the MCP channels research preview. When channels exit preview, this will become zero-config.

## How it works

```
Claude Code hooks → Python script → Unix socket → ClaudePeek → Notch UI
                                   ← permission response (allow/deny/always) ←
```

The Python hook script relays Claude Code events to a Unix socket at `/tmp/claude-peek.sock`. For permission requests, the script blocks until you approve or deny from the UI, then sends the decision back to Claude Code.

The conversation viewer reads JSONL files from `~/.claude/projects/` for live conversation history.

Reply (when enabled) uses an MCP channel server that pushes messages into the running Claude Code session.

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
├── install.sh           # One-command install
├── Sources/
│   ├── App/             # Entry point, app delegate
│   ├── Core/            # Models, geometry, view model, screen tracking
│   ├── Services/        # Socket server, session manager, JSONL parser, channel client
│   └── UI/              # SwiftUI views, window, conversation viewer
├── hooks/               # Python hook script
├── mcp/                 # MCP channel server (Bun/TypeScript) for reply feature
└── scripts/
    ├── build-app.sh     # Dev build (ad-hoc signed)
    └── release.sh       # Release build (signed + notarized)
```

## Releasing

Requires Apple Developer ID certificate and App Store Connect API key.

```bash
export NOTARY_KEY_ID="..."
export NOTARY_KEY_PATH="path/to/AuthKey.p8"
export NOTARY_ISSUER_ID="..."

# Build, sign, notarize, staple
./scripts/release.sh

# Tag and publish
git tag v0.x.0
git push origin main --tags
gh release create v0.x.0 ClaudePeek.zip --title "v0.x.0" --generate-notes
```

## License

MIT
