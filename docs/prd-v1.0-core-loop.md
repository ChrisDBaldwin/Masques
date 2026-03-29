# PRD: Masques v1.0 — Core Loop

**Project:** /Users/chris/git/masques
**Author:** Chris Baldwin + Claude
**Date:** 2026-03-28
**Loop Mode:** Recursive single-goal convergence
**Exit Condition:** All acceptance criteria pass

---

## Problem Statement

Masques is a Claude Code plugin that lets agents temporarily adopt cognitive identities — "AssumeRole for Agents." It has 35 well-designed personas, a polished TUI, and working telemetry infrastructure. But the core plugin loop — the four commands a user actually interacts with (`/don`, `/doff`, `/id`, `/list`) — doesn't work reliably.

The commands exist as markdown specs in `commands/`. Claude reads them and follows them. This is the correct Claude Code plugin architecture — there's no MCP server to build. The problem is that the specs have gaps, the manifests are stale (5 personas missing), edge cases are unhandled, and there's no automated verification that the loop works end-to-end.

**Current state:**
- 35 personas (valid YAML), but manifest only lists 30 — architect, familiar, grinder, retro, reviewer were added without running `/sync-manifest`
- Private manifest lists 2 of 4 private masques (qq and shy-guy missing)
- Session file exists at `.claude/masque.session.yaml` (last doffed Firekeeper, Feb 7)
- Command specs are detailed but have no verification step — Claude follows them on good faith
- 4 eval suites exist (codesmith, chartwright, firekeeper, mirror) but haven't been validated recently
- `/sync-manifest` spec exists but hasn't been run since Feb 10

**Success looks like:** A user installs the masques plugin, runs `/list`, sees all masques, runs `/don codesmith`, gets a reliable identity injection, works in that identity, runs `/doff`, returns to baseline. Every time. Verified by evals.

### Audience

- **Primary:** Chris (plugin author) — needs the core loop bulletproof before any public release
- **Secondary:** Future masques users — expect `/don` to work first try without debugging

### Constraints

- Plugin architecture is markdown command specs — no MCP server, no code runtime
- jj colocated for version control (prefer `jj` commands over `git`)
- Evals require `promptfoo` installed and Anthropic API key
- Must not break the TUI, telemetry, or existing persona YAML

### Scope Boundary — What We Are NOT Doing

- Payment infrastructure (TigerBeetle, ClickHouse ledger, 402 gating, SQL migrations)
- `/audience` or `/performance` commands (telemetry layer)
- New personas or modifying existing persona content
- TUI changes
- MCP knowledge/credentials/access bundling
- Schema changes to `masque.schema.yaml`
- Documentation beyond what's needed to fix accuracy (no new docs)
- CHANGELOG or version bump (that happens after all criteria pass)

---

## Architecture Constraints

**Plugin pattern:** Commands are markdown files in `commands/` with YAML frontmatter. Claude Code loads the markdown as the command's prompt. The "implementation" is the quality and specificity of the instructions in that markdown.

**File layout that matters:**
```
commands/don.md           — /don command spec
commands/doff.md          — /doff command spec
commands/id.md            — /id command spec
commands/list.md          — /list command spec
commands/sync-manifest.md — /sync-manifest command spec
personas/manifest.yaml    — shared masque index (auto-generated)
personas/*.masque.yaml    — 35 shared personas
~/.masques/manifest.yaml  — private masque index (auto-generated)
~/.masques/*.masque.yaml  — private personas
.claude/masque.session.yaml — session state
schemas/masque.schema.yaml  — YAML schema for validation
evals/*/promptfooconfig.yaml — behavioral eval configs
```

**Conventions:**
- YAML for all data files
- Markdown for command specs
- Session state in `.claude/masque.session.yaml`
- Manifests are generated artifacts — never hand-edited
- Private masques at `${MASQUES_HOME:-~/.masques}/`
- Shared masques at `${CLAUDE_PLUGIN_ROOT}/personas/`

---

## Acceptance Criteria

### Tier 1: Manifest Integrity (Priority 1)

- [ ] **C1:** Shared manifest (`personas/manifest.yaml`) lists exactly 35 masques, matching the 35 `.masque.yaml` files in `personas/`. Verify by comparing `ls personas/*.masque.yaml | wc -l` against the count of entries in the manifest. Every file has a corresponding entry with correct name, version, domain, and tagline.

- [ ] **C2:** Private manifest (`~/.masques/manifest.yaml`) lists all `.masque.yaml` files in `~/.masques/`. Verify by comparing `ls ~/.masques/*.masque.yaml | wc -l` against manifest entry count.

- [ ] **C3:** The `/sync-manifest` command spec (`commands/sync-manifest.md`) produces correct manifests when followed. Verify by reading the spec, mentally executing it against the current file state, and confirming the output format matches the existing manifest structure. Fix any gaps in the spec that would cause incorrect output.

### Tier 2: Command Spec Robustness (Priority 1)

- [ ] **C4:** `/don` command spec (`commands/don.md`) handles all edge cases: (a) no arguments provided, (b) masque name not found in either path, (c) masque found in both paths (private wins), (d) malformed YAML in masque file, (e) missing required fields. Each edge case has explicit instructions and example output. Verify by reading the spec and confirming each case is covered with unambiguous instructions.

- [ ] **C5:** `/don` command spec correctly preserves `previous` session state when donning over an existing masque. If a masque is already active, the current active masque becomes `previous` before the new one is written. Verify the spec explicitly handles the "already wearing a masque" case.

- [ ] **C6:** `/doff` command spec (`commands/doff.md`) handles: (a) no masque active, (b) masque active with spinner verbs to clean up, (c) masque active without spinner verbs. Verify each case has explicit instructions.

- [ ] **C7:** `/id` command spec (`commands/id.md`) handles: (a) no session file exists, (b) session file exists but no active masque, (c) active masque with source=shared, (d) active masque with source=private. Verify path reconstruction from name+source is unambiguous.

- [ ] **C8:** `/list` command spec (`commands/list.md`) handles: (a) both manifests present, (b) only shared manifest, (c) only private manifest, (d) no manifests at all, (e) active masque marked in listing, (f) private masque overrides shared masque with same name. Verify each case has explicit instructions.

### Tier 3: Session State Integrity (Priority 1)

- [ ] **C9:** The `/don` spec writes session state that `/doff`, `/id`, and `/list` can all correctly read. The YAML structure is consistent across all four commands. Verify by tracing the write format in `/don` against the read expectations in `/doff`, `/id`, and `/list`. No field name mismatches, no format differences.

- [ ] **C10:** Session file path is consistent across all commands. Every command references `.claude/masque.session.yaml` using the same path resolution. No command uses a different path or assumes a different working directory.

### Tier 4: Eval Verification (Priority 2)

- [ ] **P1:** The `evals/codesmith/prompt.txt` file contains the full Codesmith lens+context that would be injected by `/don codesmith`. Verify by comparing `prompt.txt` content against the `<masque-active>` block that `/don` would produce from `personas/codesmith.masque.yaml`. They should match — the eval tests the same identity the command injects.

- [ ] **P2:** All four eval suites (codesmith, chartwright, firekeeper, mirror) have valid `promptfooconfig.yaml` files that reference existing test files and existing prompt files. Verify by checking all `file://` references resolve to actual files.

- [ ] **P3:** Eval prompt files for chartwright, firekeeper, and mirror match their respective persona YAML files (same lens+context content). Verify parity between each `evals/*/prompt.txt` and the `<masque-active>` block that `/don` would produce.

### Tier 5: Documentation Accuracy (Priority 2)

- [ ] **P4:** `docs/getting-started.md` does not reference `intent.allowed/denied` or any other schema fields that don't exist in the current `schemas/masque.schema.yaml`. Verify by reading the doc and checking every YAML field mentioned against the schema.

- [ ] **P5:** `CLAUDE.md` command list matches actual commands in `commands/`. The count, names, descriptions, and usage examples are accurate. Verify by comparing CLAUDE.md's command section against `ls commands/`.

### Tier 6: Version Bump (Priority 3)

- [ ] **N1:** After all above criteria pass: bump version to 1.0.0 in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. Add CHANGELOG.md entry documenting "v1.0.0 — Core loop hardened: manifest sync, command spec robustness, eval verification."

---

## Recursive Loop Prompt

```
You are working on the Masques Claude Code plugin at /Users/chris/git/masques. Your goal is convergence toward the acceptance criteria defined in docs/prd-v1.0-core-loop.md.

This repo uses jj (colocated with git). Use jj commands for version control.

On each iteration:

1. Read the acceptance criteria in docs/prd-v1.0-core-loop.md.
2. Read progress.md for context on what's been done.
3. Assess the current state against unchecked criteria.
4. Identify the single highest-priority unchecked criterion.
   - Priority order: C1-C10 (Tier 1-3), then P1-P5 (Tier 4-5), then N1 (Tier 6).
   - Within a tier, work sequentially unless a later criterion is trivially satisfiable.
5. Implement the minimum change to satisfy that criterion.
6. Verify the criterion passes by the method described in the criterion itself.
7. Update progress.md with:
   - Which criterion was addressed
   - What was changed (files, approach)
   - Any decisions made and why
   - Any new risks or blockers discovered
8. Commit with: jj describe -m "masques-v1: <criterion-id>: <short description>"
   Then: jj new
9. If all criteria are checked, output EXIT_SIGNAL.
   If a criterion cannot be satisfied due to a blocker outside your control,
   document it in progress.md and move to the next criterion.

Do NOT:
- Modify persona YAML content (personas/*.masque.yaml) — only modify manifests
- Change the TUI code (tui/)
- Touch payment/telemetry infrastructure (sql/, services/)
- Add new commands beyond the 5 in scope (don, doff, id, list, sync-manifest)
- Introduce any runtime dependencies — this is a markdown-spec plugin, not code
- Modify the masque schema (schemas/masque.schema.yaml)
- Skip verification before committing
```

---

## Progress Log

Create `progress.md` at the project root:

```markdown
# Masques v1.0 Core Loop — Progress Log

## Current State
- [ ] C1: Shared manifest lists all 35 masques
- [ ] C2: Private manifest lists all private masques
- [ ] C3: /sync-manifest spec produces correct output
- [ ] C4: /don handles all edge cases
- [ ] C5: /don preserves previous session state on re-don
- [ ] C6: /doff handles all edge cases
- [ ] C7: /id handles all edge cases
- [ ] C8: /list handles all edge cases
- [ ] C9: Session state format consistent across all commands
- [ ] C10: Session file path consistent across all commands
- [ ] P1: Codesmith eval prompt matches /don output
- [ ] P2: All eval configs reference existing files
- [ ] P3: All eval prompts match their persona YAML
- [ ] P4: getting-started.md has no stale schema references
- [ ] P5: CLAUDE.md command list is accurate
- [ ] N1: Version bumped to 1.0.0

## Iteration Log
```

---

## CLAUDE.md Additions

No additions needed — the existing CLAUDE.md is comprehensive. The PRD and progress.md provide the working context for the grind loop.

---

## Getting Started

1. PRD is at `docs/prd-v1.0-core-loop.md` (this file).
2. Create `progress.md` at the repo root from the template above.
3. For interactive execution: open Claude Code in `/Users/chris/git/masques`, paste the recursive loop prompt.
4. For autonomous execution: run via ralph or `/loop` with the recursive loop prompt.
5. First iteration will be assessment — reading current state, populating progress.md. Convergence starts on iteration 2.
