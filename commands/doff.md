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

### Step 2b: Clear Spinner Verbs

If `.claude/settings.local.json` exists and contains a `spinnerVerbs` field:

1. **Read** the existing settings
2. **Remove** the `spinnerVerbs` key
3. **Write** the updated JSON (or delete file if now empty/only has empty objects)

This returns the spinner to Claude Code defaults.

### Step 3: Confirm

Report: `✓ Doffed [name]. Back to baseline.`

## Tool Calls Summary

This command requires:
1. Read `.claude/masque.session.yaml`
2. Write `.claude/masque.session.yaml` (if masque was active)
3. Read `.claude/settings.local.json` (if exists)
4. Write `.claude/settings.local.json` (to remove spinnerVerbs)

Or fewer calls if no masque is active or no settings file exists.
