# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
./scripts/build-app.sh          # Dev build → installs to /Applications
./install.sh                    # Build + configure hooks + launch
./scripts/release.sh            # Signed + notarized release (needs NOTARY_* env vars)
```

No test suite. Test manually by sending events to the socket:
```bash
echo '{"session_id":"s1","cwd":"/tmp","event":"UserPromptSubmit","status":"processing","pid":1234}' | nc -U /tmp/claude-peek.sock
```

MCP server (optional): `cd mcp && bun install && bun run server.ts`

## Architecture

```
Claude Code hooks → Python hook script → Unix socket → Swift app → Notch UI
                                        ← permission response (allow/deny) ←
```

**Hook script** (`hooks/claude-peek-hook.py`): relays Claude Code hook events as single-line JSON over `/tmp/claude-peek.sock`. For PermissionRequest, holds socket open waiting for the UI's decision.

**SocketServer** (`Services/SocketServer.swift`): non-blocking Unix socket listener. Parses events, caches tool_use_ids (PreToolUse events may arrive before PermissionRequest with the same tool), holds client sockets open for pending permission responses.

**SessionManager** (`Services/SessionManager.swift`): source of truth for session state. Receives events from SocketServer, manages `SessionPhase` transitions, resolves approvals by writing responses back through held sockets.

**SessionPhase**: `idle → processing → waitingForInput | waitingForApproval(PermissionContext) | compacting | ended`. Transitions validated by `canTransition(to:)`.

**NotchViewModel** (`Core/NotchViewModel.swift`): UI state machine (open/closed/popping). Manages mouse tracking, hover timers, selected session.

**ConversationView**: reads JSONL from `~/.claude/projects/` for live conversation history. Keeps last 50 messages.

**ChannelClient** (`Services/ChannelClient.swift`): sends replies to MCP server via HTTP. Port registered dynamically when MCP server connects via ChannelRegistration event.

**TerminalFocuser**: walks process tree from Claude Code PID to find owning terminal app. IDE apps: opens cwd. Plain terminals: just activates (avoids spawning new window).

## Key Patterns

- `@MainActor` on all UI-touching classes. `NSLock` protects shared state on SocketServer's background queue.
- Permission flow holds the Unix socket open until the user decides — the hook script blocks on read.
- Tool use ID cache bridges PreToolUse → PermissionRequest when they arrive as separate events keyed by `(sessionId, toolName, sortedToolInput)`.
- Notch geometry adapts to physical notch (from NSScreen model metadata) vs floating pill on non-notch displays.
- Sessions auto-removed 30s after `.ended` phase.
