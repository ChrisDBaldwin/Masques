---
name: masques:doff
description: Doff the current masque - release the active identity and return to baseline
arguments: []
---

# Doff Masque Command

You are doffing (removing) the current masque.

## Instructions

1. **Read current state** from `.claude/masques.local.md`

2. **If no masque is active:**
   - Report "No masque is currently active."
   - Exit

3. **If a masque is active:**
   - Note the masque name and how long it was worn
   - Clear the state file by writing:

```yaml
---
active_masque: null
version: null
donned_at: null
doffed_at: [ISO timestamp]
ring: null
---

No masque active.
```

4. **Confirm** the masque has been doffed with a brief message:
   - "[Masque name] has been doffed. Returning to baseline identity."
