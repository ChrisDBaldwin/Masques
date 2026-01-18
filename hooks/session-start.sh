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
