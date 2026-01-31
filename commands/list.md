---
name: list
description: List all available masques
arguments: []
---

# Masque List Command

Display all available masques that can be donned.

## Instructions

1. **Read manifest files** from both locations (priority order):

   **Private manifest:**
   - Path: `${MASQUES_HOME:-~/.masques}/manifest.yaml`

   **Shared manifest:**
   - Path: `${CLAUDE_PLUGIN_ROOT}/personas/manifest.yaml`

2. **Parse each manifest** and extract the `masques` array. Each entry has:
   - `name` - Display name
   - `version` - Version string
   - `ring` - Trust level
   - `domain` - Domain area
   - `tagline` - Brief description

3. **Merge masques from both sources:**
   - Tag private masques with source `[private]`
   - Tag shared masques with source `shared`
   - If a masque name exists in both, the private version wins (skip the shared one)

4. **Check for active masque:**
   - Test if symlink exists: `test -L .claude/active.masque`
   - If exists, read target: `readlink .claude/active.masque`
   - Extract masque name from target path (basename, strip `.masque.yaml`)
   - This determines which masque to mark as "(active)"

   **Fallback:** If `.claude/active.masque` exists as a regular file, read the masque name from it

5. **Format as a table:**

   ```
   Available Masques:

   Name          Version   Ring     Domain                   Source
   ────────────────────────────────────────────────────────────────────
 ★ Mirror        0.1.0     player   masque-creation          shared     ← start here
   Nash          0.1.0     player   architecture             [private]
   Codesmith     0.1.0     player   systems-programming      shared     (active)
   Chartwright   0.1.0     player   frontend-analytics       shared
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

   If no manifests found at all:
   ```
   No manifest found. Run /sync-manifest to generate.
   ```

   If only one manifest exists, use it and note the missing one:
   ```
   Note: Private manifest not found. Run /sync-manifest to include private masques.
   ```

## Usage Hint

After listing, suggest:
```
Use `/don <name>` to adopt a masque identity.

New to masques? Start with `/don mirror` - it's designed to help you create custom masques for your own domains.
```
