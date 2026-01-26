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

2. **Read session file (if exists):**
   - Check for `.claude/masque.session`
   - Parse key=value pairs to get `donned_at`, `doffed_at`, `last_masque`

3. **If no symlink exists** (or readlink fails):
   - Report: "No masque active. You are operating as baseline Claude."
   - If session file has `last_masque` and `doffed_at`:
     - Show: "Last worn: [last_masque] (doffed [doffed_at])"
   - Suggest: "Use `/list` to see available masques, `/don <name>` to adopt one."

4. **If symlink exists:**
   - Extract masque name from symlink target (basename, strip `.masque.yaml`)
   - Read the masque YAML file from the symlink target path
   - Display:
     - Masque name and version
     - Trust ring
     - Donned timestamp (from session file, with relative time if possible)
     - Key attributes (domain, stack, philosophy)

   Format:
   ```
   Active Masque: [name] v[version]
   Ring: [ring]
   Donned: [donned_at]

   Domain: [domain]
   Stack: [stack]
   Philosophy: [philosophy]
   ```

5. **Suggest next actions:**
   - "Use `/inspect` to see full masque details"
   - "Use `/don <name>` to switch to a different masque"
   - "Use `/doff` to remove the masque and return to baseline"

## Fallback Handling

If `readlink` fails but `.claude/active.masque` exists as a regular file:
- Read the masque name from the file: `cat .claude/active.masque`
- Load the masque from `${CLAUDE_PLUGIN_ROOT}/personas/<name>.masque.yaml`
