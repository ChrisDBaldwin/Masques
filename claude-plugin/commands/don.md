---
name: masques:don
description: Don a masque - adopt a temporary cognitive identity with bundled lens, context, and intent boundaries
arguments:
  - name: masque-name
    description: Name of the masque to don (e.g., chartwright)
    required: true
  - name: intent
    description: Optional intent describing what you want to accomplish
    required: false
---

# Don Masque Command

You are donning the masque: **$ARGUMENTS**

## Instructions

### Step 1: Check for Masque Binary

First, check if a compiled masque binary exists:

```bash
MASQUE_NAME=$(echo "$ARGUMENTS" | awk '{print $1}')
MASQUE_BINARY="$HOME/.masques/bin/$MASQUE_NAME"

if [ -f "$MASQUE_BINARY" ] && [ -x "$MASQUE_BINARY" ]; then
    echo "BINARY_EXISTS=true"
else
    echo "BINARY_EXISTS=false"
fi
```

### Step 2A: If Binary Exists - Invoke It

If the binary exists, invoke it with the don command and user intent:

```bash
MASQUE_NAME=$(echo "$ARGUMENTS" | awk '{print $1}')
USER_INTENT=$(echo "$ARGUMENTS" | cut -d' ' -f2-)
MASQUE_BINARY="$HOME/.masques/bin/$MASQUE_NAME"

# If no intent provided in arguments, use a default
if [ -z "$USER_INTENT" ] || [ "$USER_INTENT" = "$MASQUE_NAME" ]; then
    USER_INTENT="general assistance"
fi

"$MASQUE_BINARY" don --intent "$USER_INTENT"
```

Parse the JSON output from the binary. The binary returns:

```json
{
  "status": "success",
  "session_id": "codesmith-1234567890-abc123",
  "masque": "Codesmith",
  "version": "0.1.0",
  "ring": "player",
  "intent": "user intent here",
  "started_at": 1234567890,
  "lens": "full lens content...",
  "context": "full context content...",
  "intent_allowed": ["code/*", "refactor/*"],
  "intent_denied": ["deploy/*"],
  "domain": "Software Engineering",
  "stack": "Zig, TypeScript, Python",
  "philosophy": "..."
}
```

Extract these fields from the JSON response:
- `masque` - The masque name
- `version` - Version string
- `ring` - Trust ring level
- `session_id` - Unique session identifier
- `lens` - The cognitive framing and working style
- `context` - Project/domain context
- `intent_allowed` - Array of allowed intent patterns
- `intent_denied` - Array of denied intent patterns
- `domain` - Domain attribute
- `stack` - Stack attribute
- `philosophy` - Philosophy attribute

### Step 2B: If No Binary - Fallback to JSON File

If no binary exists, fall back to reading the JSON file:

Read from `entities/masques/$MASQUE_NAME.masque.json`

Extract the key components:
- `lens` - The cognitive framing and working style
- `context` - Project/domain context
- `intent.allowed` - What this masque is permitted to do
- `intent.denied` - What this masque must not do
- `attributes` - Domain, stack, style, philosophy

### Step 3: Inject the Masque Context

Output a `<masque-active>` block with the extracted information:

```
<masque-active name="[name]" version="[version]" ring="[ring]" session="[session_id]">
## Lens
[Full lens content]

## Context
[Full context content]

## Intent Boundaries
**Allowed:** [list allowed patterns]
**Denied:** [list denied patterns]

## Attributes
- Domain: [domain]
- Stack: [stack]
- Philosophy: [philosophy]
</masque-active>
```

### Step 4: Persist State

Write to `.claude/masques.local.md`:

```yaml
---
active_masque: [name]
version: [version]
session_id: [session_id]
donned_at: [ISO timestamp]
ring: [ring]
source: [binary|json]
---

Masque [name] is active.
```

Include `session_id` if obtained from binary, omit if using JSON fallback.
Set `source` to `binary` or `json` depending on which method was used.

### Step 5: Confirm

Confirm with a brief message acknowledging the masque is now active, including:
- Masque name and version
- Trust ring level
- Session ID (if from binary)
- Source (binary or JSON fallback)

## Error Handling

- If binary exists but returns non-zero exit code, report the error and fall back to JSON
- If binary returns JSON with `"status": "error"`, report the error message
- If the masque JSON file doesn't exist (and no binary), list available masques from `entities/masques/`
- If the JSON is malformed, report the parse error
