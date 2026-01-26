---
name: masques:doff
description: Doff the current masque and return to baseline Claude
arguments: []
---

# Doff Masque Command

Remove the active masque and return to baseline.

## Instructions

### Step 1: Read Session File

Read `.claude/masque.session.yaml` to check current state.

### Step 2: Check State and Update

**If file doesn't exist or `active.path` is null:**
- Report: "No masque is currently active."
- If `previous.name` is set, show: "Last worn: [previous.name]"
- Suggest: "Use `/don <name>` to adopt a masque."
- Stop here.

**If `active.path` has a value (masque is active):**

Write updated session file using the Write tool to `.claude/masque.session.yaml`:

```yaml
# Auto-managed by masques plugin
active:
  path: null
  name: null
  donned_at: null
previous:
  name: <previous-active-name>
  path: <previous-active-path>
  doffed_at: <current-UTC-timestamp>
```

Where:
- `previous.doffed_at` is the current UTC timestamp in ISO format
- `previous.name` preserves the name of the masque being doffed
- `previous.path` preserves the path for potential re-donning

### Step 3: Confirm

Report: `✓ Doffed [name]. Back to baseline.`

## Tool Calls Summary

This command requires exactly 2 tool calls:
1. Read `.claude/masque.session.yaml`
2. Write `.claude/masque.session.yaml` (if masque was active)

Or 1 tool call if no masque is active.
