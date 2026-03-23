#!/bin/bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Build and install app
"$REPO_DIR/scripts/build-app.sh"
cp -r "$REPO_DIR/ClaudePeek.app" /Applications/

# Configure hooks via Claude
claude -p "Use /update-config to add Claude Peek hooks to ~/.claude/settings.json. Merge with existing hooks, don't overwrite.

Hook command for ALL events: python3 $REPO_DIR/hooks/claude-peek-hook.py

Add these hook events:
- UserPromptSubmit (no matcher)
- PreToolUse (matcher: \"*\")
- PostToolUse (matcher: \"*\")
- PermissionRequest (matcher: \"*\", timeout: 86400)
- Notification (matcher: \"*\")
- Stop (no matcher)
- SubagentStop (no matcher)
- SessionStart (no matcher)
- SessionEnd (no matcher)
- PreCompact: two entries, matcher \"auto\" and matcher \"manual\"

Skip pipe-testing and proof steps — just read the file, merge hooks, write it, and validate JSON syntax." \
  --allowedTools 'Read(~/.claude/settings.json)' 'Edit(~/.claude/settings.json)' 'Bash(jq*)'

# Launch
open /Applications/ClaudePeek.app
echo "Claude Peek installed and running."
