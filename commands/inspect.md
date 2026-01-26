---
name: masques:inspect
description: Inspect full details of a masque (current or named)
arguments:
  - name: target
    description: Masque name to inspect, or "self" for current (default: self)
    required: false
---

# Masque Inspect Command

Display the complete details of a masque — all components plus attributes.

## Instructions

1. **Determine target:**
   - If no argument or `self` → inspect the currently active masque
   - If a name is provided → inspect that masque directly

2. **If inspecting self (no arg or "self"):**
   - Check if symlink exists: `test -L .claude/active.masque`
   - If symlink exists, read target: `readlink .claude/active.masque`
   - Extract masque name from target path (basename, strip `.masque.yaml`)
   - If no symlink exists: report "No masque active. Use `/don <name>` to adopt one."
   - Otherwise, use that name to find the YAML file

   **Fallback:** If `.claude/active.masque` exists as a regular file, read the masque name from it

3. **Read the masque file:**
   - If inspecting self: use the symlink target directly (it already points to the correct location)
   - If inspecting by name: look up in this order (first match wins):
     1. `${MASQUES_HOME:-~/.masques}/<name>.masque.yaml`
     2. `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`
   - If not found in either location, report: "Masque '<name>' not found." and list available masques from both paths

4. **Display the full masque:**

   ```
   ═══════════════════════════════════════════════════════════════
   [Name] v[version]                                    ring: [ring]
   ═══════════════════════════════════════════════════════════════

   [tagline]

   ── Attributes ──────────────────────────────────────────────────
   Domain:     [domain]
   Stack:      [stack]
   Style:      [style]
   Philosophy: [philosophy]

   ── Intent ──────────────────────────────────────────────────────
   Allowed:
     • [pattern]
     • [pattern]

   Denied:
     • [pattern]
     • [pattern]

   ── Context ─────────────────────────────────────────────────────
   [context block - full content]

   ── Knowledge ───────────────────────────────────────────────────
     • [mcp://uri]
     • [mcp://uri]

   ── Skills ──────────────────────────────────────────────────────
     • [skill://uri] ([level])
     • [skill://uri] ([level])

   ── Lens ────────────────────────────────────────────────────────
   [full lens content]
   ```

5. **If masque has MCP server definitions**, show them:
   ```
   ── MCP Servers ─────────────────────────────────────────────────
     • [name]: [command] [args...]
   ```

6. **Omit empty sections** — if a masque lacks knowledge, skills, or MCP servers, skip those headers.
