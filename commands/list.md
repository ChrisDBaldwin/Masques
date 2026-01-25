---
name: masques:list
description: List all available masques
arguments: []
---

# Masque List Command

Display all available masques that can be donned.

## Instructions

1. **List masque files** by globbing `${CLAUDE_PLUGIN_ROOT}/personas/*.masque.yaml`

2. **For each masque file**, read and extract:
   - `name` - Display name
   - `version` - Version string
   - `ring` - Trust level
   - `attributes.tagline` or `attributes.philosophy` - Brief description
   - `attributes.domain` - Domain area

3. **Check current state** by reading `.claude/masques.local.md`:
   - If file exists and has `active_masque` in frontmatter, note which masque is active

4. **Format as a table:**

   ```
   Available Masques:

   Name          Version   Ring     Domain
   ─────────────────────────────────────────
 ★ Mirror        0.1.0     admin    masque-creation         ← start here
   Codesmith     0.1.0     player   systems-programming     (active)
   Chartwright   0.1.0     player   frontend-analytics
   ```

   - Mark the active masque with `(active)` if one is donned
   - Always show Mirror first with ★ marker and "← start here" hint (it's the meta-masque for creating others)

5. **Show taglines** below the table:
   ```
   • Codesmith: "every line should teach"
   • Chartwright: "every chart should answer a question before the user asks it"
   ```

6. **If no masques found:**
   - Report: "No masques found in personas/"
   - Suggest creating a masque YAML file

## Usage Hint

After listing, suggest:
```
Use `/don <name>` to adopt a masque identity.

New to masques? Start with `/don mirror` - it's designed to help you create custom masques for your own domains.
```
