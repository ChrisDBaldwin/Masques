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

### Step 2: Compose the identity via the `masque` CLI (single source of truth)

The masque is resolved and composed by the **`masque` CLI** — the one
authoritative implementation shared by this plugin and the Masques MCP server
(PRD v1.2 M7). Do **not** re-derive the identity block in prose; that is how the
two surfaces used to drift. Run the CLI and inject its output verbatim.

**Locate the CLI** (the `$MASQUE` invocation used in this and later steps):
- If `masque` is on `PATH` (installed via `uv tool install "${CLAUDE_PLUGIN_ROOT}/services/mcp"`),
  use `masque`.
- Otherwise fall back to: `uv run --project "${CLAUDE_PLUGIN_ROOT}/services/mcp" masque`

Compose the identity block — this both resolves the masque (private
`${MASQUES_HOME:-~/.masques}` over bundled `personas/`) and builds the block:

```bash
$MASQUE compose <name> [intent...]
```

The CLI exits non-zero and prints a diagnostic to stderr if the masque is not
found, the YAML is malformed, or a required field (`name`, `version`, `lens`)
is missing. **If it fails**, report that diagnostic and stop — do not proceed to
subsequent steps. For a not-found error, also suggest `/list`.

To capture the masque's `name`, `version`, `source`, and `spinnerVerbs` for the
steps below (session file, spinner verbs), additionally run:

```bash
$MASQUE compose <name> --json
```

### Step 4: Inject the Masque Context

Inject the **stdout of `$MASQUE compose <name> [intent...]` verbatim** — it is
already the `<masque-active>` block (lens + context + attributes + optional
intent). Do not reformat or regenerate it; emitting it verbatim is what
guarantees the plugin and the MCP server compose identically.

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
- `active.name` is the `name` from `$MASQUE compose <name> --json`
- `active.source` is the `source` from that JSON (`private` or `shared`)
- `active.donned_at` is the current UTC timestamp in ISO format (e.g., `2026-01-26T12:00:00Z`)
- `previous.name` / `previous.source` come from the old `active` block (if there was one)
- `previous.doffed_at` is the current UTC timestamp (the moment the old masque was implicitly doffed)

Write the session state using the Write tool to `.claude/masque.session.yaml`.

**Note:** Do NOT store absolute paths - they break when the plugin version changes. The path can be reconstructed at runtime from name + source.

### Step 5a: Record audience attribution (session → masque map)

So the always-on audience can tell masque sessions from baseline ones (and
flag mid-session masque switches), append one line to the attribution sidecar
the judge reads. The OTEL telemetry session id is available as the
`CLAUDE_CODE_SESSION_ID` env var and matches the `session.id` on every captured
event, so this is a clean join key — no extra plumbing.

Append (do NOT overwrite — multiple dons in one session is how a `mixed`
session is detected, PRD D2) to
`${CLAUDE_PLUGIN_ROOT}/services/collector/data/sessions.attribution.jsonl`:

```bash
printf '{"session_id":"%s","masque":"%s","donned_at":"%s"}\n' \
  "$CLAUDE_CODE_SESSION_ID" "<MasqueName>" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >> "${CLAUDE_PLUGIN_ROOT}/services/collector/data/sessions.attribution.jsonl"
```

This is the only thing that makes a session attributable to a masque; baseline
sessions (no `/don`) simply never get a line, so the judge reads them as
`masque: null`. The file stays on the machine — it is local attribution
metadata, never forwarded (the Tier-2 contract carries only derived scores).

### Step 5b: Apply Spinner Verbs (if defined)

Use the `spinnerVerbs` field from `$MASQUE compose <name> --json`. If it is
non-null:

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
| Masque not found | Step 2 | Relay the CLI's not-found diagnostic; suggest `/list` |
| Malformed YAML | Step 2 | Relay the CLI's parse-error diagnostic |
| Missing required fields (name, version, lens) | Step 2 | Relay the CLI's missing-fields diagnostic |
| Masque found in both paths | Step 2 | Private wins (CLI handles this; not an error) |
