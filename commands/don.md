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

**If neither file exists**, report an error and list available masques from the manifests:
```
✗ Masque "<name>" not found

Checked:
  Private: ~/.masques/<name>.masque.yaml — not found
  Shared:  personas/<name>.masque.yaml — not found

Available masques (run /list for full details):
  [Read personas/manifest.yaml and ~/.masques/manifest.yaml, list names]
```
Do not proceed to subsequent steps.

### Step 3: Parse and Validate the YAML

Parse the masque YAML file. **If the YAML is malformed** (syntax errors, invalid structure), report the error and stop:
```
✗ Failed to parse <name>.masque.yaml

Error: [describe the parse error, with line number if available]

The masque file may be corrupted. Try opening it directly to inspect.
```
Do not proceed to subsequent steps.

Extract these fields from the YAML:
- `name` - Display name **(required)**
- `version` - Version string **(required)**
- `lens` - The cognitive framing and working style **(required)**
- `attributes` - Domain, stack, style, philosophy, tagline (optional)
- `context` - Project/domain context (optional)
- `spinnerVerbs` - Custom spinner verbs for this masque (optional)

**If any required field (`name`, `version`, `lens`) is missing**, report the error and stop:
```
✗ Masque "<name>" is missing required fields: [list missing fields]

Required fields: name, version, lens
```
Do not proceed to subsequent steps.

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

**First**, read the existing session file `.claude/masque.session.yaml` (if it exists) to check whether a masque is currently active.

**If a masque is already active** (the existing session file has `active.name` set to a non-null value), the current active masque becomes `previous`:

```yaml
# Auto-managed by masques plugin
active:
  name: <new-masque-name>
  source: <new-masque-source>
  donned_at: <current-UTC-timestamp>
previous:
  name: <old-active-name>
  source: <old-active-source>
  doffed_at: <current-UTC-timestamp>
```

**If no masque is currently active** (no session file, or `active.name` is null), write with null previous:

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
- `previous.name` / `previous.source` come from the old `active` block (if there was one)
- `previous.doffed_at` is the current UTC timestamp (the moment the old masque was implicitly doffed)

Write the session state using the Write tool to `.claude/masque.session.yaml`.

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

## Error Handling Summary

Each error case is handled inline at the step where it occurs. All errors stop execution:

| Error | Step | Action |
|-------|------|--------|
| No arguments provided | Step 1 | Show usage, suggest `/list` |
| Masque not found in either path | Step 2 | Show checked paths, list available masques from manifests |
| Malformed YAML | Step 3 | Report parse error with details |
| Missing required fields (name, version, lens) | Step 3 | List which required fields are missing |
| Masque found in both paths | Step 2 | Private wins (not an error) |
