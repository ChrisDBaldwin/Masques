---
name: masques:doff
description: Doff the current masque and return to baseline Claude
arguments: []
---

# Doff Masque Command

Remove the active masque and return to baseline.

## Instructions

1. **Check if a masque is active:**
   - Test if symlink exists: `.claude/active.masque`
   - Use: `test -L .claude/active.masque`

2. **If symlink exists:**
   - Read the symlink target: `readlink .claude/active.masque`
   - Extract the masque name from the target path (basename without `.masque.yaml`)
   - Update the session file with doff timestamp:
     ```bash
     cat > .claude/masque.session << EOF
     donned_at=
     doffed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
     masque=
     last_masque=<name>
     EOF
     ```
   - Remove the symlink: `rm .claude/active.masque`
   - Confirm: `✓ Doffed [name]. Back to baseline.`

3. **If no symlink exists:**
   - Report: "No masque is currently active."
   - Suggest: "Use `/don <name>` to adopt a masque."

## Fallback Handling

If `readlink` fails (rare, defensive):
- Try `cat .claude/active.masque` to read as plain file
- Delete with `rm .claude/active.masque`
