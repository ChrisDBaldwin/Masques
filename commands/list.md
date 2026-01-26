---
name: masques:list
description: List all available masques
arguments: []
---

# Masque List Command

Display all available masques that can be donned.

## Instructions

1. **List masque files** from both discovery paths (priority order):

   **Private masques (user's personal):**
   - Path: `${MASQUES_HOME:-~/.masques}/*.masque.yaml`
   - These are the user's private masques, stored outside any repo

   **Shared masques (project/plugin):**
   - Path: `${CLAUDE_PLUGIN_ROOT}/personas/*.masque.yaml`
   - These are bundled with the plugin or shared in the project

   **Merge logic:**
   - If a masque name exists in both locations, the private version wins
   - Track which location each masque came from for display

2. **For each masque file**, read and extract:
   - `name` - Display name
   - `version` - Version string
   - `ring` - Trust level
   - `attributes.tagline` or `attributes.philosophy` - Brief description
   - `attributes.domain` - Domain area

3. **Check for active masque:**
   - Test if symlink exists: `test -L .claude/active.masque`
   - If exists, read target: `readlink .claude/active.masque`
   - Extract masque name from target path (basename, strip `.masque.yaml`)
   - This determines which masque to mark as "(active)"

   **Fallback:** If `.claude/active.masque` exists as a regular file, read the masque name from it

4. **Format as a table:**

   ```
   Available Masques:

   Name          Version   Ring     Domain                   Source
   ────────────────────────────────────────────────────────────────────
 ★ Mirror        0.1.0     admin    masque-creation          shared     ← start here
   Nash          0.1.0     player   architecture             [private]
   Codesmith     0.1.0     player   systems-programming      shared     (active)
   Chartwright   0.1.0     player   frontend-analytics       shared
   ```

   - Mark the active masque with `(active)` if one is donned
   - Show `[private]` for masques from `${MASQUES_HOME:-~/.masques}/`
   - Show `shared` for masques from `${CLAUDE_PLUGIN_ROOT}/personas/`
   - Always show Mirror first with ★ marker and "← start here" hint (it's the meta-masque for creating others)

5. **Show taglines** below the table:
   ```
   • Codesmith: "every line should teach"
   • Chartwright: "every chart should answer a question before the user asks it"
   ```

6. **If no masques found:**
   - Report: "No masques found."
   - Suggest: "Create a masque in `~/.masques/` (private) or `personas/` (shared)"

## Usage Hint

After listing, suggest:
```
Use `/don <name>` to adopt a masque identity.

New to masques? Start with `/don mirror` - it's designed to help you create custom masques for your own domains.
```
