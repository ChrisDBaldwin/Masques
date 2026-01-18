---
name: don
description: Don a masque - adopt a temporary cognitive identity with bundled lens, context, and intent boundaries
arguments:
  - name: masque-name
    description: Name of the masque to don (e.g., chartwright)
    required: true
---

# Don Masque Command

You are donning the masque: **$ARGUMENTS**

## Instructions

1. **Resolve the masque** by reading from `entities/masques/$ARGUMENTS.masque.json`

2. **Extract the key components:**
   - `lens` - The cognitive framing and working style
   - `context` - Project/domain context
   - `intent.allowed` - What this masque is permitted to do
   - `intent.denied` - What this masque must not do
   - `attributes` - Domain, stack, style, philosophy

3. **Inject the masque context** by outputting a `<masque-active>` block:

```
<masque-active name="[name]" version="[version]" ring="[ring]">
## Lens
[Full lens content]

## Context
[Full context content]

## Intent Boundaries
**Allowed:** [list allowed patterns]
**Denied:** [list denied patterns]

## Attributes
- Domain: [domain]
- Stack: [stack]
- Philosophy: [philosophy]
</masque-active>
```

4. **Persist state** by writing to `.claude/masque.local.md`:

```yaml
---
active_masque: [name]
version: [version]
donned_at: [ISO timestamp]
ring: [ring]
---

Masque [name] is active.
```

5. **Confirm** with a brief message acknowledging the masque is now active.

## Error Handling

- If the masque file doesn't exist, list available masques from `entities/masques/`
- If the JSON is malformed, report the parse error
