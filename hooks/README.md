# Claude Peek Hooks

## Installation

Add the following to `~/.claude/settings.json` under `"hooks"`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py", "timeout": 86400 }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "auto",
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      },
      {
        "matcher": "manual",
        "hooks": [
          { "type": "command", "command": "python3 /path/to/claude-peek/hooks/claude-peek-hook.py" }
        ]
      }
    ]
  }
}
```

Replace `/path/to/claude-peek` with the actual path to this repo.

## Testing

With the app running, send test events via socket:

```bash
# Session starts processing
echo '{"session_id":"test1","cwd":"/Users/you/project","event":"UserPromptSubmit","status":"processing","pid":1234}' | nc -U /tmp/claude-peek.sock

# Tool running
echo '{"session_id":"test1","cwd":"/Users/you/project","event":"PreToolUse","status":"running_tool","tool":"Bash","tool_input":{"command":"ls"},"tool_use_id":"tu_123","pid":1234}' | nc -U /tmp/claude-peek.sock

# Session done
echo '{"session_id":"test1","cwd":"/Users/you/project","event":"Stop","status":"waiting_for_input","pid":1234}' | nc -U /tmp/claude-peek.sock

# Session ended
echo '{"session_id":"test1","cwd":"/Users/you/project","event":"SessionEnd","status":"ended","pid":1234}' | nc -U /tmp/claude-peek.sock
```

## Protocol

Events are JSON sent to Unix socket at `/tmp/claude-peek.sock`.

For `PermissionRequest` events, the hook script blocks waiting for a response from the app. The app writes back:

```json
{"decision": "allow", "reason": null}
```

or

```json
{"decision": "deny", "reason": "Denied via Claude Peek"}
```
