#!/bin/bash
# SessionStart hook - re-inject active masque on session resume/compaction
#
# This hook checks for an active masque in .claude/masque.local.md
# and re-injects its context into the session.

set -e

STATE_FILE=".claude/masque.local.md"
MASQUE_DIR="entities/masques"

# Check if state file exists
if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# Extract active_masque from YAML frontmatter
ACTIVE_MASQUE=$(grep "^active_masque:" "$STATE_FILE" 2>/dev/null | sed 's/active_masque: *//' | tr -d '"' | tr -d "'")

# If no active masque or null, exit silently
if [[ -z "$ACTIVE_MASQUE" || "$ACTIVE_MASQUE" == "null" ]]; then
    exit 0
fi

# Convert to lowercase for filename (portable)
MASQUE_LOWER=$(echo "$ACTIVE_MASQUE" | tr '[:upper:]' '[:lower:]')
MASQUE_FILE="$MASQUE_DIR/${MASQUE_LOWER}.masque.json"

# Check if masque file exists
if [[ ! -f "$MASQUE_FILE" ]]; then
    echo "Warning: Active masque '$ACTIVE_MASQUE' not found at $MASQUE_FILE"
    exit 0
fi

# Extract components using basic tools (avoiding jq dependency)
# Read the entire file
MASQUE_JSON=$(cat "$MASQUE_FILE")

# Use python for JSON parsing if available, otherwise provide basic info
if command -v python3 &> /dev/null; then
    LENS=$(python3 -c "import json,sys; d=json.load(open('$MASQUE_FILE')); print(d.get('lens',''))" 2>/dev/null || echo "")
    VERSION=$(python3 -c "import json,sys; d=json.load(open('$MASQUE_FILE')); print(d.get('version',''))" 2>/dev/null || echo "")
    RING=$(python3 -c "import json,sys; d=json.load(open('$MASQUE_FILE')); print(d.get('ring',''))" 2>/dev/null || echo "")
    CONTEXT=$(python3 -c "import json,sys; d=json.load(open('$MASQUE_FILE')); print(d.get('context',''))" 2>/dev/null || echo "")
else
    # Fallback: just note the masque is active
    echo "<masque-active name=\"$ACTIVE_MASQUE\">"
    echo "Masque $ACTIVE_MASQUE is active. Run /don $ACTIVE_MASQUE to see full details."
    echo "</masque-active>"
    exit 0
fi

# Output the masque context for injection
cat << EOF
<masque-active name="$ACTIVE_MASQUE" version="$VERSION" ring="$RING">
## Lens
$LENS

## Context
$CONTEXT

---
*Masque re-injected on session resume*
</masque-active>
EOF

# --- Mesh Announcement Logic ---

# Check if session file exists in ~/.masque/sessions/
SESSION_FILE=$(ls -t "$HOME/.masque/sessions/$MASQUE_LOWER-"*.json 2>/dev/null | head -1)
if [ -n "$SESSION_FILE" ]; then
    echo "Active session: $(basename "$SESSION_FILE" .json)" >&2
fi

# Announce presence to mesh if binary exists
MASQUE_BINARY="$HOME/.masque/bin/$MASQUE_LOWER"
if [ -x "$MASQUE_BINARY" ]; then
    # Announce to local network
    "$MASQUE_BINARY" announce 2>/dev/null || true

    # Discover peers
    PEERS=$("$MASQUE_BINARY" discover 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(p.get('name','') for p in d.get('peers',[])))" 2>/dev/null || echo "")
    if [ -n "$PEERS" ]; then
        echo "Mesh peers discovered: $PEERS" >&2
    fi
fi

echo "Session resumed with masque: $ACTIVE_MASQUE" >&2
