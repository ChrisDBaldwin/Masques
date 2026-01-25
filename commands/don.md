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

Read the masque definition from `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`

If the file doesn't exist, list available masques from `${CLAUDE_PLUGIN_ROOT}/personas/*.masque.yaml` and report which ones are available.

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

### Step 5: Handle MCP Servers (if defined)

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

### Step 6: Persist State

Write to `.claude/masques.local.md`:

```yaml
---
active_masque: [name]
version: [version]
donned_at: [ISO timestamp]
ring: [ring]
domain: [domain]
stack: [stack]
philosophy: [philosophy]
---

Masque [name] is active.
```

### Step 7: Confirm

Confirm with a brief message:
```
✓ Donned [name] v[version] (ring: [ring])
  [tagline or philosophy]
```

## Error Handling

- If masque file not found: list available masques from `personas/`
- If YAML is malformed: report the parse error with line number if possible
- If required fields are missing: report which fields are missing
