---
name: id
description: Show the currently active masque identity
arguments: []
---

# Masque ID Command

Display the current masque identity status.

## Instructions

### Step 1: Read Session File

Read `.claude/masque.session.yaml` to check current state.

If file doesn't exist, report: "No masque state found. Use `/don <name>` to adopt a masque."

### Step 2: Check State

Parse the session file as YAML with structure:
- `active.path` - Path to active masque YAML (null if none active)
- `active.name` - Display name of active masque
- `active.donned_at` - When current masque was donned
- `previous.name` - Name of last worn masque
- `previous.path` - Path to last worn masque
- `previous.doffed_at` - When last masque was doffed

**If `active.path` is null (no active masque):**
- Report: "No masque active. You are operating as baseline Claude."
- If `previous.name` is set:
  - Show: "Last worn: [previous.name] (doffed [previous.doffed_at])"
- Suggest: "Use `/list` to see available masques, `/don <name>` to adopt one."
- Stop here.

**If `active.path` has a value (masque is active):**
- Read the masque YAML from `active.path`
- Determine source from path (private if contains `/.masques/` or `$MASQUES_HOME`, otherwise shared)

### Step 3: Display Active Masque

Extract details from the masque YAML and display:

```
Active Masque: [name] v[version] [private]
Ring: [ring]
Donned: [donned_at]

Domain: [domain]
Stack: [stack]
Philosophy: [philosophy]
```

Note: Show `[private]` indicator if the path points to the private masques directory.

### Step 4: Suggest Next Actions

- "Use `/inspect` to see full masque details"
- "Use `/don <name>` to switch to a different masque"
- "Use `/doff` to remove the masque and return to baseline"

## Tool Calls Summary

This command requires:
- 1 tool call if no masque is active
- 2 tool calls if a masque is active (read session YAML + read masque YAML)
