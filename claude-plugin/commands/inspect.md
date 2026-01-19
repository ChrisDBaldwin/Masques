---
name: masque:inspect
description: Inspect full details of a masque (current or named)
arguments:
  - name: target
    description: Masque name to inspect, or "self" for current (default: self)
    required: false
---

# Masque Inspect Command

Display the complete details of a masque — all five components plus attributes.

## Instructions

1. **Determine target:**
   - If no argument or `self` → inspect the currently active masque
   - If a name is provided → inspect that masque directly

2. **If inspecting self (no arg or "self"):**
   - Read `.claude/masque.local.md` to get the active masque name
   - If no masque is active: report "No masque active." and stop
   - Otherwise, load `entities/masques/<name>.masque.json`

3. **If inspecting by name:**
   - Load `entities/masques/<name>.masque.json`
   - If not found, report: "Masque '<name>' not found."

4. **Display the full masque:**

   ```
   ═══════════════════════════════════════════════════════════════
   [Name] v[version]                                    ring: [ring]
   ═══════════════════════════════════════════════════════════════

   [tagline or philosophy]

   ── Attributes ──────────────────────────────────────────────────
   Domain:     [domain]
   Stack:      [stack]
   Style:      [style]

   ── Intent ──────────────────────────────────────────────────────
   Allowed:
     • [pattern]
     • [pattern]

   Denied:
     • [pattern]
     • [pattern]

   ── Context ─────────────────────────────────────────────────────
   [context block]

   ── Knowledge ───────────────────────────────────────────────────
     • [mcp://uri]
     • [mcp://uri]

   ── Access ──────────────────────────────────────────────────────
   Vault Role: [vault_role]
   TTL:        [ttl]

   ── Skills ──────────────────────────────────────────────────────
     • [uri] ([level])
     • [uri] ([level])

   ── Lens ────────────────────────────────────────────────────────
   [full lens content]
   ```

5. **If masque has performance data**, optionally show:
   ```
   ── Performance ─────────────────────────────────────────────────
   Score: [score or "not rated"]
   ```

6. **Omit empty sections** — if a masque lacks knowledge or skills, skip those headers.
