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
   - If `active.name` has a value, construct path from name + source:
     - If `source` is `private`: `${MASQUES_HOME:-~/.masques}/<name>.masque.yaml`
     - If `source` is `shared`: `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`
   - If `active.name` is null or file doesn't exist: report "No masque active. Use `/don <name>` to adopt one."

3. **If inspecting by name:**
   - Read BOTH paths in parallel (single message with two Read calls):
     1. `${MASQUES_HOME:-~/.masques}/<name>.masque.yaml`
     2. `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`
   - Use whichever path succeeds (private takes precedence if both exist)
   - If not found in either location, report: "Masque '<name>' not found." and list available masques

4. **Display the full masque:**

   ```
   ═══════════════════════════════════════════════════════════════
   [Name] v[version]
   ═══════════════════════════════════════════════════════════════

   [tagline]

   ── Attributes ──────────────────────────────────────────────────
   Domain:     [domain]
   Stack:      [stack]
   Style:      [style]
   Philosophy: [philosophy]

   ── Context ─────────────────────────────────────────────────────
   [context block - full content]

   ── Lens ────────────────────────────────────────────────────────
   [full lens content]
   ```

5. **If masque has spinner verbs**, show them:
   ```
   ── Spinner Verbs ───────────────────────────────────────────────
   Mode: [mode]
   • [verb]
   • [verb]
   ```

6. **Omit empty sections** — if a masque lacks context or spinner verbs, skip those headers.
