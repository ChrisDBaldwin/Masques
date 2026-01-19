---
name: masque:list
description: List all available masques
arguments: []
---

# Masque List Command

Display all available masques that can be donned.

## Instructions

1. **List masque files** from `entities/masques/*.masque.json`

2. **For each masque**, extract and display:
   - Name
   - Version
   - Ring (trust level)
   - Brief description from attributes (domain or philosophy)

3. **Format as a table:**

   ```
   Available Masques:

   Name          Version   Ring     Domain
   ─────────────────────────────────────────
   Chartwright   0.1.0     player   Data Visualization
   Codesmith     0.1.0     player   Software Engineering
   ```

4. **If no masques found:**
   - Report: "No masques found in entities/masques/"
   - Suggest checking that masque JSON files exist

5. **Indicate current masque** (if any) by checking `.claude/masque.local.md`:
   - Mark the active masque with `*` or `(active)`
