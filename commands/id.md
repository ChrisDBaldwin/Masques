---
name: masques:id
description: Show the currently active masque identity
arguments: []
---

# Masque ID Command

Display the current masque identity status.

## Instructions

1. **Read state** from `.claude/masques.local.md`

2. **If no masque is active** (file doesn't exist or `active_masque` is missing/null):
   - Report: "No masque active. You are operating as baseline Claude."
   - Suggest: "Use `/list` to see available masques, `/don <name>` to adopt one."

3. **If a masque is active**, display from the frontmatter:
   - Masque name and version
   - Trust ring
   - When it was donned
   - Key attributes (domain, stack, philosophy)

   Format:
   ```
   Active Masque: [name] v[version]
   Ring: [ring]
   Donned: [timestamp]

   Domain: [domain]
   Stack: [stack]
   Philosophy: [philosophy]
   ```

4. **Suggest next actions:**
   - "Use `/inspect` to see full masque details"
   - "Use `/don <name>` to switch to a different masque"
