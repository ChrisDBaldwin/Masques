---
name: list
description: List all available masques
arguments: []
---

# Masque List Command

Display all available masques that can be donned.

## Instructions

1. **List masques via the `masque` CLI** — the one authoritative catalog shared
   by this plugin and the Masques MCP server (PRD v1.2 M7). Do not read the
   manifests directly; the CLI merges private over bundled for you.

   Locate the CLI (`$MASQUE`): use `masque` if on `PATH` (installed via
   `uv tool install "${CLAUDE_PLUGIN_ROOT}/services/mcp"`), otherwise
   `uv run --project "${CLAUDE_PLUGIN_ROOT}/services/mcp" masque`.

   ```bash
   $MASQUE list --json
   ```

2. **Each entry** has `name`, `version`, `domain`, `tagline`, `has_rubric`, and
   `source` (`private` or `shared`). The CLI has already merged the two
   locations — private wins on a name collision; there is nothing to dedupe.

   _(If the CLI is unavailable, fall back to reading the manifests at
   `${MASQUES_HOME:-~/.masques}/manifest.yaml` and
   `${CLAUDE_PLUGIN_ROOT}/personas/manifest.yaml`.)_

4. **Check for active masque:**
   - Read `.claude/masque.session.yaml` if it exists
   - Extract `active.name` from the YAML
   - This determines which masque to mark as "(active)"
   - If the file doesn't exist or `active.name` is null, no masque is active

5. **Format as a table:**

   ```
   Available Masques:

   Name          Version   Domain                   Source
   ────────────────────────────────────────────────────────────────────
 ★ Mirror        0.1.0     masque-creation          shared     ← start here
   Nash          0.1.0     architecture             [private]
   Codesmith     0.1.0     systems-programming      shared     (active)
   Chartwright   0.1.0     frontend-analytics       shared
   ```

   - Mark the active masque with `(active)` if one is donned
   - Show `[private]` for masques from the private manifest
   - Show `shared` for masques from the shared manifest
   - Always show Mirror first with ★ marker and "← start here" hint (it's the meta-masque for creating others)

6. **Show taglines** below the table:
   ```
   • Codesmith: "every line should teach"
   • Chartwright: "every chart should answer a question before the user asks it"
   ```

7. **Handle missing manifests:**

   **If no manifests found at all:**
   ```
   No masque manifests found.

   Run /sync-manifest to generate manifest files from your masque YAML files.
   ```

   **If only the shared manifest exists** (private manifest missing or `~/.masques/` directory missing):
   - List shared masques normally
   - Append note: `Note: No private manifest found at ~/.masques/manifest.yaml. Run /sync-manifest to include private masques.`

   **If only the private manifest exists** (shared manifest missing):
   - List private masques normally
   - Append note: `Note: No shared manifest found at personas/manifest.yaml. Run /sync-manifest to regenerate.`

## Usage Hint

After listing, suggest:
```
Use `/don <name>` to adopt a masque identity.

New to masques? Start with `/don mirror` - it's designed to help you create custom masques for your own domains.
```
