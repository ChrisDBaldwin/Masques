---
name: masque:id
description: Show the currently active masque identity
arguments: []
---

# Masque ID Command

Display the current masque identity status.

## Instructions

1. **Read state** from `.claude/masque.local.md`

2. **If no masque is active** (active_masque is null or file doesn't exist):
   - Report: "No masque active. You are operating as baseline Claude."

3. **If a masque is active:**
   - Display:
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

4. **Optionally**, if the user wants more detail, they can run `/don [name]` again to see the full lens.
