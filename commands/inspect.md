---
name: inspect
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
   - Read `.claude/masque.session.yaml` to check current state
   - If `active.path` has a value, use that path to read the masque YAML
   - If `active.path` is null or file doesn't exist: report "No masque active. Use `/don <name>` to adopt one."

3. **If inspecting by name:**
   - Read BOTH paths in parallel (single message with two Read calls):
     1. `${MASQUES_HOME:-~/.masques}/<name>.masque.yaml`
     2. `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`
   - Use whichever path succeeds (private takes precedence if both exist)
   - If not found in either location, report: "Masque '<name>' not found." and list available masques

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
