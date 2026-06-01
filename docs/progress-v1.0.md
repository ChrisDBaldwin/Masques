# Masques v1.0 Core Loop — Progress Log

## Current State
- [x] C1: Shared manifest lists all 35 masques
- [x] C2: Private manifest lists all private masques
- [x] C3: /sync-manifest spec produces correct output
- [x] C4: /don handles all edge cases
- [x] C5: /don preserves previous session state on re-don
- [x] C6: /doff handles all edge cases
- [x] C7: /id handles all edge cases
- [x] C8: /list handles all edge cases
- [x] C9: Session state format consistent across all commands
- [x] C10: Session file path consistent across all commands
- [x] P1: Codesmith eval prompt matches /don output
- [x] P2: All eval configs reference existing files
- [x] P3: All eval prompts match their persona YAML
- [x] P4: getting-started.md has no stale schema references
- [x] P5: CLAUDE.md command list is accurate
- [x] N1: Version bumped to 1.0.0

## Iteration Log

### Iteration 1 — C1: Shared manifest lists all 35 masques
- **Status:** PASS
- **Changed:** `personas/manifest.yaml` — added 5 missing entries (Architect, Familiar, Grinder, Retro, Reviewer) in alphabetical order. Updated `generated_at` timestamp.
- **Verification:** `grep -c '  - name:' personas/manifest.yaml` returns 35; cross-checked every `.masque.yaml` file name against manifest entries — all match.
- **Decisions:** Extracted name/version/domain/tagline from each persona YAML to match the existing manifest entry format.

### Iteration 2 — C2: Private manifest lists all private masques
- **Status:** PASS
- **Changed:** `~/.masques/manifest.yaml` — added 2 missing entries (qq, Shy Guy) in alphabetical order. Updated `generated_at` timestamp. Now 4/4 files matched.
- **Verification:** File count (4) matches manifest entry count (4). Cross-checked all `.masque.yaml` filenames against manifest names.
- **Note:** Private manifest is outside the repo (`~/.masques/`), so it won't appear in the jj commit diff. The change is real but not version-controlled.

### Iteration 3 — C3: /sync-manifest spec produces correct output
- **Status:** PASS
- **Changed:** `commands/sync-manifest.md` — clarified extraction rules: name/version are required (skip with warning if missing), domain defaults to "unknown", tagline falls back to philosophy then empty string. Added explicit "use current ISO 8601 timestamp" note for `generated_at`.
- **Verification:** Mentally executed the spec against current file state (35 shared masques, 4 private masques). Output format matches existing manifests. All edge cases documented: missing directory, malformed YAML, no masque files, missing fields.

### Iteration 4 — C4: /don handles all edge cases
- **Status:** PASS
- **Changed:** `commands/don.md` — (1) Made "not found" error in Step 2 explicit with checked paths and manifest-based listing. (2) Added YAML parse error handling in Step 3 with error template. (3) Defined required fields (name, version, lens) in Step 3 with missing-field error template. (4) Replaced generic Error Handling section with summary table linking each error to its step.
- **Verification:** All 5 edge cases from the criterion have explicit instructions and example output: (a) no arguments → Step 1, (b) not found → Step 2, (c) both paths → Step 2 private wins, (d) malformed YAML → Step 3, (e) missing fields → Step 3.

### Iteration 5 — C5: /don preserves previous session state on re-don
- **Status:** PASS
- **Changed:** `commands/don.md` Step 5 — rewrote to first read existing session file. If `active.name` is non-null, copies current active to `previous` with `doffed_at` timestamp. If no active masque, writes null previous. Two explicit code templates for each case.
- **Verification:** The spec now explicitly handles "already wearing a masque" with clear instructions to read-then-write. The old active becomes previous. Fresh dons get null previous.

### Iteration 6 — C6: /doff handles all edge cases
- **Status:** PASS
- **Changed:** `commands/doff.md` Step 2b — expanded spinner verb cleanup to explicitly handle three cases: file doesn't exist (skip), file exists but no spinnerVerbs (skip), file exists with spinnerVerbs (remove and preserve other fields).
- **Verification:** All 3 edge cases covered: (a) no masque active → Step 2 first branch, (b) masque active with spinner verbs → Step 2 + Step 2b, (c) masque active without spinner verbs → Step 2 + Step 2b skip.

### Iteration 7 — C7: /id handles all edge cases
- **Status:** PASS
- **Changed:** `commands/id.md` Step 2 — made path reconstruction unambiguous: explicit "lowercase the name, replace spaces with hyphens" rule with examples (Codesmith → codesmith.masque.yaml, Shy Guy → shy-guy.masque.yaml). Added handling for missing masque file at constructed path.
- **Verification:** All 4 edge cases covered: (a) no session file → Step 1, (b) session exists but no active → Step 2 first branch, (c) active source=shared → Step 2 with CLAUDE_PLUGIN_ROOT path, (d) active source=private → Step 2 with MASQUES_HOME path. Path reconstruction is unambiguous with lowercase+hyphen rule and examples.

### Iteration 8 — C8: /list handles all edge cases
- **Status:** PASS
- **Changed:** `commands/list.md` Step 7 — expanded missing manifest handling to explicitly cover all three cases: no manifests at all, only shared manifest (note about private), only private manifest (note about shared). Previously only showed the "private missing" example.
- **Verification:** All 6 edge cases covered: (a) both manifests → Steps 1-3, (b) only shared → Step 7 second case, (c) only private → Step 7 third case, (d) no manifests → Step 7 first case, (e) active masque marked → Steps 4-5, (f) private overrides shared → Step 3.

### Iteration 9 — C9: Session state format consistent across all commands
- **Status:** PASS (no changes needed)
- **Changed:** Nothing. All commands use the same 6-field structure: `active.{name,source,donned_at}` and `previous.{name,source,doffed_at}`.
- **Verification:** Traced write format in `/don` (two templates: fresh don and re-don) against read expectations in `/doff` (checks `active.name`, writes all 6 fields), `/id` (reads `active.name`, `active.source`, `active.donned_at`, `previous.name`, `previous.doffed_at`), and `/list` (reads `active.name`). No field name mismatches, no format differences.

### Iteration 10 — C10: Session file path consistent across all commands
- **Status:** PASS (no changes needed)
- **Changed:** Nothing. Grep across all commands confirms every reference uses `.claude/masque.session.yaml`.
- **Verification:** Searched `commands/` for `masque.session` and `session.yaml`. All 4 core commands (don, doff, id, list) plus inspect and performance use the identical path `.claude/masque.session.yaml`. No command uses a different path or assumes a different working directory.

### Iteration 11 — P1: Codesmith eval prompt matches /don output
- **Status:** PASS
- **Changed:** `evals/codesmith/prompt.txt` — rewrote to use the `<masque-active>` XML block format that `/don` produces. Lens, context, and attributes now exactly match the content from `personas/codesmith.masque.yaml`. Old prompt was a flat text rendering with "Intent Boundaries" that didn't match the YAML's "Boundaries" section.
- **Verification:** Compared prompt.txt lens content against YAML `lens` field — identical. Compared context against YAML `context` field — identical. Attributes match domain/style/philosophy from YAML.

### Iteration 12 — P2: All eval configs reference existing files
- **Status:** PASS (no changes needed)
- **Changed:** Nothing. All `file://` references in all 4 eval configs resolve to existing files.
- **Verification:** Checked every `file://prompt.txt` and `file://tests/*.yaml` reference across codesmith, chartwright, firekeeper, mirror. All 16 references (4 prompt.txt + 12 test files) resolve to existing files.

### Iteration 13 — P3: All eval prompts match their persona YAML
- **Status:** PASS
- **Changed:** `evals/chartwright/prompt.txt`, `evals/firekeeper/prompt.txt`, `evals/mirror/prompt.txt` — all three rewritten to use the `<masque-active>` XML block format matching `/don` output. Lens, context, and attributes now exactly match their respective persona YAML files.
- **Verification:** Diff comparison of lens content (YAML vs prompt.txt) shows MATCH for all 3. Diff comparison of context content shows MATCH for all 3. Old prompts had simplified contexts, different section headings ("The Five Phases" vs "The Interview Phases"), and "Intent Boundaries" instead of "Boundaries".

### Iteration 14 — P4: getting-started.md has no stale schema references
- **Status:** PASS
- **Changed:** `docs/getting-started.md` — removed 7 stale schema fields: `index`, `ring`, `intent.allowed`, `intent.denied`, `knowledge`, `access`, `skills`, `mcp`. Updated Quick Start example, Template, required/optional fields list, confirmation message format, and Troubleshooting section. All fields now match `schemas/masque.schema.yaml`.
- **Verification:** Every YAML field in the doc checked against schema: name, version, lens (required), attributes, context, spinnerVerbs (optional). No references to non-existent fields remain.

### Iteration 15 — P5: CLAUDE.md command list is accurate
- **Status:** PASS (no changes needed)
- **Changed:** Nothing. CLAUDE.md accurately lists all 8 commands matching the 8 files in `commands/`.
- **Verification:** Compared CLAUDE.md command section (8 commands) against `ls commands/` (8 files). Names, argument patterns, and descriptions all match. Directory structure section also lists all 8 files correctly.

### Iteration 16 — N1: Version bumped to 1.0.0
- **Status:** PASS
- **Changed:** `.claude-plugin/plugin.json` version → 1.0.0, `.claude-plugin/marketplace.json` version → 1.0.0, `CHANGELOG.md` added v1.0.0 entry documenting all core loop hardening changes.
- **Verification:** Both plugin files show `"version": "1.0.0"` and match. CHANGELOG entry lists all changes from C1-P5.
