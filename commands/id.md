---
name: masques:id
description: Show the currently active masque identity
arguments: []
---

# Masque ID Command

Display the current masque identity status.

## Instructions

1. **Check for active masque symlink:**
   - Test if symlink exists: `test -L .claude/active.masque`
   - If symlink exists, read target: `readlink .claude/active.masque`

2. **If no symlink exists** (or readlink fails):
   - Report: "No masque active. You are operating as baseline Claude."
   - Suggest: "Use `/list` to see available masques, `/don <name>` to adopt one."

3. **If symlink exists:**
   - Extract masque name from symlink target (basename, strip `.masque.yaml`)
   - Read the masque YAML file from the symlink target path
   - Display:
     - Masque name and version
     - Trust ring
     - Key attributes (domain, stack, philosophy)

   Format:
   ```
   Active Masque: [name] v[version]
   Ring: [ring]

   Domain: [domain]
   Stack: [stack]
   Philosophy: [philosophy]
   ```

4. **Suggest next actions:**
   - "Use `/inspect` to see full masque details"
   - "Use `/don <name>` to switch to a different masque"
   - "Use `/doff` to remove the masque and return to baseline"

## Fallback Handling

If `readlink` fails but `.claude/active.masque` exists as a regular file:
- Read the masque name from the file: `cat .claude/active.masque`
- Load the masque from `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`
