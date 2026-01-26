---
name: masques:don
description: Don a masque - adopt a temporary cognitive identity with bundled lens, context, and intent boundaries
arguments:
  - name: masque-name
    description: Name of the masque to don (e.g., codesmith, chartwright)
    required: true
  - name: intent
    description: Optional intent describing what you want to accomplish
    required: false
---

# Don Masque Command

You are donning the masque: **$ARGUMENTS**

## Instructions

### Step 1: Parse Arguments

Extract the masque name from arguments:
- First word is the masque name (case-insensitive)
- Remaining words (if any) are the user's intent

**If no arguments provided:**
Report an error and exit:
```
✗ Missing masque name

Usage: /don <masque-name> [intent]

Run /list to see available masques.
```
Do not proceed to subsequent steps.

### Step 2: Read the Masque YAML

Look for the masque in this order (first match wins):

1. **Private path:** `${MASQUES_HOME:-~/.masques}/<name>.masque.yaml`
2. **Shared path:** `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`

Track which path the masque was found at — you'll need this for the symlink in Step 5.

If the file doesn't exist in either location, list available masques from both paths and report which ones are available.

### Step 3: Parse the YAML

Extract these fields from the YAML:
- `name` - Display name
- `version` - Version string
- `ring` - Trust ring level (admin, player, guest, outsider)
- `attributes` - Domain, stack, style, philosophy, tagline
- `intent.allowed` - Array of allowed intent patterns
- `intent.denied` - Array of denied intent patterns
- `context` - Project/domain context
- `knowledge` - Array of MCP URIs (mcp://...)
- `skills` - Array of skill URIs with levels
- `lens` - The cognitive framing and working style
- `mcp` - (Optional) MCP server definitions for bundled tools

### Step 4: Inject the Masque Context

Output a `<masque-active>` block that will shape your behavior:

```
<masque-active name="[name]" version="[version]" ring="[ring]">
## Lens
[Full lens content from YAML]

## Context
[Full context content from YAML]

## Intent Boundaries
**Allowed:**
[List each allowed pattern as bullet]

**Denied:**
[List each denied pattern as bullet]

## Attributes
- Domain: [domain]
- Stack: [stack]
- Style: [style]
- Philosophy: [philosophy]

## Knowledge Sources
[List each mcp:// URI]

## Skills
[List each skill URI with level]
</masque-active>
```

### Step 5: Create State Symlink

Create a symlink to track the active masque, using the actual path where the masque was found:

```bash
# Use the path from Step 2 (private or shared)
ln -sf "<actual-masque-path>" .claude/active.masque
```

For example:
- Private masque: `ln -sf ~/.masques/nash.masque.yaml .claude/active.masque`
- Shared masque: `ln -sf "${CLAUDE_PLUGIN_ROOT}/personas/codesmith.masque.yaml" .claude/active.masque`

- The `-f` flag handles replacing an existing symlink (if switching masques)
- Ensure `.claude/` directory exists first
- The symlink points to the absolute path of the masque YAML (wherever it was found)

**Fallback (rare):** If symlinks fail, write the masque name as plain text:
```bash
echo "<name>" > .claude/active.masque
```

### Step 5b: Write Session File

Write the session file with timestamp:

```bash
cat > .claude/masque.session << EOF
donned_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
doffed_at=
masque=<name>
EOF
```

This tracks when the masque was donned for display in `/id`.

### Step 6: Handle MCP Servers (if defined)

If the masque defines an `mcp` section with server configurations:

```yaml
mcp:
  servers:
    - name: server-name
      type: stdio
      command: npx
      args: ["-y", "@package/name"]
```

Output instructions for the user:
```
📡 This masque bundles MCP servers:

• [server-name]: [command] [args...]

To enable these capabilities, add to your .mcp.json or run:
claude mcp add [server-name] -- [command] [args...]
```

### Step 7: Confirm

Confirm with a brief message:
```
✓ Donned [name] v[version] (ring: [ring])
  [tagline or philosophy]
```

## Error Handling

- If masque file not found: list available masques from both `~/.masques/` and `personas/`
- If YAML is malformed: report the parse error with line number if possible
- If required fields are missing: report which fields are missing
