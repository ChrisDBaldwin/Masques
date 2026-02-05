---
name: don
description: Don a masque - adopt a temporary cognitive identity with bundled lens and context
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

### Step 2: Read Both Masque Paths in Parallel

**IMPORTANT:** Issue BOTH Read tool calls in a single message to check paths simultaneously:

1. **Private path:** `${MASQUES_HOME:-~/.masques}/<name>.masque.yaml`
2. **Shared path:** `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`

Use whichever path succeeds (private takes precedence if both exist).

If neither file exists, list available masques from both paths and report which ones are available.

### Step 3: Parse the YAML

Extract these fields from the YAML:
- `name` - Display name
- `version` - Version string
- `attributes` - Domain, stack, style, philosophy, tagline
- `context` - Project/domain context
- `lens` - The cognitive framing and working style
- `spinnerVerbs` - (Optional) Custom spinner verbs for this masque

### Step 4: Inject the Masque Context

Output a `<masque-active>` block that will shape your behavior:

```
<masque-active name="[name]" version="[version]">
## Lens
[Full lens content from YAML]

## Context
[Full context content from YAML]

## Attributes
- Domain: [domain]
- Stack: [stack]
- Style: [style]
- Philosophy: [philosophy]
</masque-active>
```

### Step 5: Write Session File

Write the session state using the Write tool to `.claude/masque.session.yaml`:

```yaml
# Auto-managed by masques plugin
active:
  name: <name>
  source: <private|shared>
  donned_at: <current-UTC-timestamp>
previous:
  name: null
  source: null
  doffed_at: null
```

Where:
- `active.name` is the display name from the YAML
- `active.source` is `private` if found in `~/.masques/`, or `shared` if found in plugin's `personas/`
- `active.donned_at` is the current UTC timestamp in ISO format (e.g., `2026-01-26T12:00:00Z`)
- `previous` fields preserve the last worn masque (null if this is the first)

**Note:** Do NOT store absolute paths - they break when the plugin version changes. The path can be reconstructed at runtime from name + source.

### Step 5b: Apply Spinner Verbs (if defined)

If the masque defines a `spinnerVerbs` section:

```yaml
spinnerVerbs:
  mode: replace
  verbs:
    - "Codesmith:Forging"
    - "Codesmith:Tempering"
```

Write or update `.claude/settings.local.json` to include the spinner verbs:

1. **Read existing settings** (if file exists) to preserve other fields like `permissions`
2. **Merge** the `spinnerVerbs` field from the masque
3. **Write** the updated JSON

Example result in `.claude/settings.local.json`:
```json
{
  "permissions": { ... },
  "spinnerVerbs": {
    "mode": "replace",
    "verbs": ["Codesmith:Forging", "Codesmith:Tempering", ...]
  }
}
```

If the masque has no `spinnerVerbs` field, leave existing settings unchanged.

### Step 6: Confirm

Confirm with a brief message:
```
✓ Donned [name] v[version]
  [tagline or philosophy]
```

## Error Handling

- If masque file not found: list available masques from both `~/.masques/` and `personas/`
- If YAML is malformed: report the parse error with line number if possible
- If required fields are missing: report which fields are missing
