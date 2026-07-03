export const meta = {
  name: 'persona-core-api',
  description: 'Phase 2 — design the evolved core API (resolve→Persona + sidecar, hexagonal ports, session lifecycle, surface adapters, measurement API) on top of the Phase 1 data model',
  whenToUse: 'Evolving Masques: design the function-level core API and control flow AFTER the Phase 1 data model is finalized and BEFORE Phase 3 measurement mechanics.',
  phases: [
    { title: 'Design', detail: '4 parallel designers: resolve/compose API, hexagonal ports, session lifecycle, surface + measurement API' },
    { title: 'Synthesize', detail: 'merge the 4 API designs into one coherent core API + control-flow spec' },
    { title: 'Critique', detail: 'adversarial review for hexagonal purity, backward-compat, enforcement/measurement honesty' },
    { title: 'Finalize', detail: 'fold critique into the final Phase 2 API design doc (markdown)' },
  ],
}

// ---------------------------------------------------------------------------
// Shared grounding handed to every agent. Phase 2 EVOLVES the real core.py /
// session.py / server.py / cli.py API on top of the FINALIZED Phase 1 data
// model. This is an API + control-flow design, NOT a re-litigation of the data
// model and NOT an implementation.
// ---------------------------------------------------------------------------
const GROUNDING = `
You are designing PHASE 2 (Core API) of the Masques→Personas evolution (/Users/chris/git/masques).
This is a DESIGN task — produce a function-level API and control-flow spec, NOT code, NOT a re-design
of the data model. The Phase 1 DATA MODEL is FINALIZED and AUTHORITATIVE — build on it, do not re-open it.

READ FIRST (ground every decision in the real repo + the finalized Phase 1 doc):
- /Users/chris/git/masques/docs/design/phase1-data-model.md — the AUTHORITATIVE Phase 1 data model.
  Honor its entities verbatim: Persona (aggregate root) = Identity (pinned <name>.masque.yaml) + optional
  PersonaConfig sidecar (<name>.persona.yaml); CredentialBinding/SecretRef; McpBinding/ClosedConfig;
  MeasurementPolicy; CapabilityPlan (host_apply: none|config-write|hook); the SecretPort/McpPort/TelemetryPort
  port boundary; event-sourced measurement (Session/Score/Event/LocalReport/GlobalReport). Reuse its names exactly.
- /Users/chris/git/masques/services/mcp/src/masques_mcp/core.py — the CURRENT core API you must EVOLVE:
  resolve(name)->Masque (line 160), _parse_masque_file (125), Masque dataclass (98), build_identity_block (200),
  compose(masque,intent) (219; returns "source": masque.source at line 229), list_masques (244),
  inspect(name) (275; returns "source"/"path" at lines 281-282), score(session) (315), search_paths (87).
- /Users/chris/git/masques/services/mcp/src/masques_mcp/session.py — CURRENT session: don(name,source) (48),
  doff() (58; today ONLY sets _active=None + _mirror()), active() (69), _mirror() (35), _session_file() (30).
- /Users/chris/git/masques/services/mcp/src/masques_mcp/server.py — MCP tool surface: list_masques, inspect_masque,
  don, doff, score tools; masque:// resources; prompts. NOTE don tool "returns content; does not enforce".
- /Users/chris/git/masques/services/mcp/src/masques_mcp/cli.py — the CLI surface adapter.
- /Users/chris/git/masques/CLAUDE.md — Design Principles, the 8 slash commands, session state schema.
- /Users/chris/git/engineering-reference/engineering-reference.md — cite specific sections by name.

WHAT PHASE 2 MUST DELIVER (function-level, with signatures and control flow):
- The EVOLVED resolve path: resolve(name) -> Persona, composing Identity + optional sidecar, with precedence,
  validation, and the Masque->Identity+Persona field move (source/path lift to Persona). Backward-compatible:
  existing *.masque.yaml load with config=None.
- The HEXAGONAL PORT interfaces: SecretPort, McpPort, TelemetryPort — conceptual method signatures, the registry
  that selects concrete adapters, and the "domain core depends only on the port abstraction" rule. don() composes
  identity+config with ZERO adapter calls; adapters are touched only on demand and degrade like score()'s
  {"status":"unavailable"} pattern.
- The SESSION LIFECYCLE API: evolved don()/doff(); in-process credential_cache (never mirrored/serialized);
  bound_refs (alias+scheme+status, safe to mirror); CapabilityPlan built at don from McpBindings + a host-capabilities
  snapshot; doff zeroes the cache and, for rotate:dynamic schemes only, calls SecretPort.revoke; sidecar writes use
  the etag optimistic lock.
- The SURFACE ADAPTERS + MEASUREMENT API: how the MCP tools (server.py), CLI (cli.py), and the 8 slash commands map
  onto the core; how /id and inspect surface the CapabilityPlan host_apply tier HONESTLY (advisory vs least-privilege);
  the measurement read API (score/report) and its local-vs-global boundary.

KEY CONSTRAINTS to honor (do not violate; flag if a requirement forces a violation):
- Hexagonal: the domain core imports NO concrete adapter. Ports are interfaces; adapters plug in at the edge.
- Local-first / zero-infra to don: no vault, no MCP server, no telemetry is EVER required to don a persona.
- Pinned identities, additive/backward-compatible schema evolution; every existing *.masque.yaml still resolves.
- No secret material in any returned dict, mirror, or git-tracked file — only references (alias+scheme+status).
- Enforcement honesty: when CapabilityPlan.host_apply == "none" the plan is ADVISORY; the API/surfaces must not
  call an advisory binding "least-privilege"/"sandbox" (Phase 1 §2/§5/§8 OQ1b).
- Evolve, don't greenfield: name the exact call sites that change (compose() line 229, inspect() lines 281-282)
  and confirm list_masques() is unaffected.
`

const API_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['area', 'summary', 'operations', 'ports', 'controlFlow', 'backwardCompat', 'refCitations', 'separationNotes', 'openQuestions'],
  properties: {
    area: { type: 'string' },
    summary: { type: 'string', description: '3-5 sentence overview of the API design decision' },
    operations: {
      type: 'array',
      description: 'the functions/methods this area defines or changes',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['signature', 'purpose', 'inputs', 'returns', 'errors', 'adapterCalls', 'notes'],
        properties: {
          signature: { type: 'string', description: 'e.g. resolve(name: str) -> Persona' },
          purpose: { type: 'string' },
          inputs: { type: 'string' },
          returns: { type: 'string', description: 'shape of the return value (entity from Phase 1, or dict shape)' },
          errors: { type: 'string', description: 'raised/handled errors and degradation behavior' },
          adapterCalls: { type: 'string', description: 'which ports (if any) it touches; "none" if pure-core' },
          notes: { type: 'string', description: 'control-flow, ordering, idempotency, or call-site-change notes' },
        },
      },
    },
    ports: {
      type: 'array',
      description: 'hexagonal port interfaces this area introduces or consumes (may be empty)',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'methods', 'concreteAdapters', 'degradation'],
        properties: {
          name: { type: 'string', description: 'SecretPort | McpPort | TelemetryPort | other' },
          methods: { type: 'array', items: { type: 'string' }, description: 'method signatures' },
          concreteAdapters: { type: 'array', items: { type: 'string' } },
          degradation: { type: 'string', description: 'how the core behaves when the adapter is absent/unavailable' },
        },
      },
    },
    controlFlow: { type: 'string', description: 'step-by-step control flow for the area’s primary path (e.g. don/doff sequence)' },
    backwardCompat: { type: 'string', description: 'how existing *.masque.yaml + existing call sites keep working; exact sites changed' },
    refCitations: { type: 'array', items: { type: 'string' }, description: 'engineering-reference sections cited by name' },
    separationNotes: { type: 'string', description: 'how this keeps the core hexagonal / local-first / identity-owning' },
    openQuestions: { type: 'array', items: { type: 'string' } },
  },
}

const DESIGNERS = [
  {
    key: 'resolve-compose',
    prompt: `${GROUNDING}

YOUR AREA: The resolve + compose API — turning files on disk into an in-memory Persona.
Design the evolved, function-level API for loading and composing identity. Decide and specify:
- resolve(name) -> Persona: the control flow that loads the Identity (existing _parse_masque_file seam, private-over-shared
  precedence per search_paths) AND, if present, the <name>.persona.yaml sidecar, composing the Persona (identity + config|None).
  Specify sidecar lookup (always at private_dir, independent of identity source), the persona: back-reference check,
  persona-config.schema.yaml validation, and the alias<->audience in-aggregate invariant check on load (reject on violation).
- The Masque -> Identity + Persona refactor at the API level: Identity = current Masque MINUS {source,path};
  Persona owns {identity_source, config_source, path, identity, ref, config}. Give the new dataclass-level shapes and the
  PersonaRef/Version helpers. Name EXACTLY the call sites that change: compose() (returns masque.source, core.py line 229)
  and inspect() (lines 281-282); confirm list_masques() is unaffected (derives source from the loop, not the dataclass).
- compose(persona, intent) and build_identity_block(persona|identity): what they read off persona.identity; what compose's
  returned dict gains (config_source, a CapabilityPlan summary?) without leaking secrets.
- Backward compat: no sidecar => config=None => identity-only callers unaffected; the 30+ bundled personas resolve unchanged.
Return operations with full signatures + control flow. Ports here are minimal (resolve is pure-core, zero adapter calls).`,
  },
  {
    key: 'ports',
    prompt: `${GROUNDING}

YOUR AREA: The hexagonal port interfaces — SecretPort, McpPort, TelemetryPort.
Ground HARD in engineering-reference §"Hexagonal / Ports & Adapters", §"Dependency inversion", §"Plugin / Microkernel"
(extension contract as permanent API), §"Secrets management", §"Short-lived credentials & rotation". Design:
- SecretPort: the conceptual interface (e.g. resolve(ref: SecretRef, persona_ref) -> ResolvedSecret, revoke(handle),
  capabilities()) and the concrete adapters that plug in per SecretRef scheme (keychain://, env://, vault://, sts://).
  The local-first default adapter and how the resolver degrades where Keychain is absent (Linux/CI -> env:// fallback or
  a clear bound_refs status). ResolvedSecret lives in process memory only, never serialized.
- McpPort: apply(plan: CapabilityPlan, host_snapshot) -> applied result, and host_snapshot/capabilities() that report which
  host_apply tier (none|config-write|hook) is achievable. Be explicit that "none" means ADVISORY (no enforcement) and the
  port must report that truthfully — do not let the API claim least-privilege it cannot deliver.
- TelemetryPort: the read seam the measurement API uses (e.g. score()/report()), mirroring core.score()'s existing
  subprocess+{"status":"unavailable"} degradation. Telemetry is optional and never required to don.
- The ADAPTER REGISTRY / selection: how the domain core obtains a port implementation WITHOUT importing a concrete
  (dependency inversion / a registry or injected provider), so core.py depends on nothing concrete. Define the rule:
  don() composes identity+config with ZERO port calls; ports are invoked only on demand (tool needs a secret; host applies
  a plan; judge runs) and every port degrades gracefully.
Return the three ports with method signatures, concrete adapters, and degradation behavior; plus the registry operation.`,
  },
  {
    key: 'session-lifecycle',
    prompt: `${GROUNDING}

YOUR AREA: The session lifecycle API — don, doff, and live session state.
Today session.py: don(name,source) sets _active + _mirror(); doff() only nulls _active + _mirror(); active() reads state.
Design the EVOLVED lifecycle (Phase 1 §6.5), function-level:
- don(persona_ref|name, intent) control flow: resolve -> compose identity block -> build the CapabilityPlan from the
  Persona's McpBindings + a host-capabilities snapshot (McpPort.capabilities) -> set _active with a session record. Specify
  what the session record holds: the active Persona ref, an in-process credential_cache (NEVER mirrored/serialized), and
  bound_refs (alias + scheme + status: pending|resolved|unresolved-credential|advisory) which IS safe to mirror.
  don performs ZERO secret resolution by default (lazy: SecretPort.resolve only when a tool actually needs the alias).
- Credential resolution on demand: the function a tool/adapter calls to get a ResolvedSecret for an alias (checks scope:
  resolvable only while THIS persona is donned and only for the named audience MCP server ids), populating credential_cache.
- doff() control flow: zero the credential_cache; for rotate:dynamic schemes only, call SecretPort.revoke(handle); for
  static keychain://env:// there is nothing to revoke (only the in-process copy is zeroed); clear CapabilityPlan; set
  previous; _mirror(). Be explicit doff does NOT withdraw ambient static secrets.
- The session mirror schema evolution: extend .claude/masque.session.yaml (active/previous) with bound_refs + a CapabilityPlan
  SUMMARY (host_apply tier, per-binding status) — NEVER any secret material. Keep backward-compatible with the current schema.
- Sidecar writes: when a surface mutates the sidecar (toggle MCP, bind credential), use the etag optimistic lock
  (Phase 1 §13 / engineering-reference §"Compare-and-set / Optimistic locking") with last-write-wins + warning fallback.
Return operations with signatures + the don/doff control-flow sequences; cite engineering-reference sections.`,
  },
  {
    key: 'surfaces-measurement',
    prompt: `${GROUNDING}

YOUR AREA: The surface adapters (MCP tools, CLI, slash commands) + the measurement read API.
The core must stay surface-agnostic; surfaces are thin adapters over it. Design:
- The MCP tool surface (server.py): how don/doff/inspect_masque/list_masques/score tools map to the evolved core. The don
  tool returns content and DOES NOT enforce (PRD D5) — show how CapabilityPlan + bound_refs ride along in the returned dict
  WITHOUT secrets. Add any new tool/resource needed (e.g. surfacing CapabilityPlan, or binding/toggling — or argue these stay
  CLI/command-only). masque:// resources updated for Persona.
- The CLI surface (cli.py) and the 8 slash commands (/don /doff /id /list /inspect /sync-manifest /audience /performance):
  which map 1:1 to a core op; what /id and /inspect must render — the CapabilityPlan host_apply TIER shown live and HONESTLY
  (host_apply==none => render "advisory" + the confused-deputy warning that any tool of a bound server can reach the credential;
  "least-privilege"/"sandbox" wording reserved for hook/config-write). Show the <masque-active> identity block additions.
- The measurement READ API: score(session) (already subprocess+degrades) plus the report read-model accessors implied by
  Phase 1 — a LOCAL report accessor (/performance: per-(identity_hash,task_class) band histogram + failed_tool_call_lift,
  local-only) and the gated GLOBAL contribution/read seam (scope==global only; k-anon+DP+attestation gate). Define the API
  shape, the local->global boundary enforcement point, and that everything stays behind TelemetryPort + degrades when off.
- A clean mapping table: surface op -> core function -> ports touched -> what it returns. Keep surfaces dumb; logic in core.
Return operations (the surface->core mappings as operations) + the measurement read operations; note what is advisory.`,
  },
]

phase('Design')
const designs = await parallel(
  DESIGNERS.map((d) => () =>
    agent(d.prompt, { label: `design:${d.key}`, phase: 'Design', schema: API_SCHEMA })
  )
)
const ok = designs.filter(Boolean)
log(`API designs complete: ${ok.map((d) => d.area).join(', ')}`)

// --- Synthesize ------------------------------------------------------------
phase('Synthesize')
const synthesis = await agent(
  `${GROUNDING}

You are the SYNTHESIS architect for Phase 2. Four area designs were produced (JSON below). Merge them into ONE
coherent core API + control-flow spec that sits cleanly on the Phase 1 data model. Resolve overlaps and conflicts
(especially: where credential resolution is triggered, who builds the CapabilityPlan, how surfaces stay thin, and
how the registry injects ports without the core importing concretes). Produce MARKDOWN with these sections:

1. ## API Surface Map — an ASCII diagram: surfaces (MCP tools / CLI / slash commands) -> core functions -> ports
   (SecretPort/McpPort/TelemetryPort) -> adapters. Mark which calls are pure-core (zero adapter) vs adapter-touching.
2. ## Core Operations — for each function: signature, purpose, inputs, returns (cite Phase 1 entities), errors/degradation,
   ports touched, and control-flow/call-site notes. Cover at least: resolve, compose, build_identity_block, don, doff,
   resolve_credential (on-demand), inspect, list_masques, score, and the report accessors.
3. ## Hexagonal Ports — SecretPort, McpPort, TelemetryPort: method signatures, concrete adapters, degradation behavior,
   and the registry/injection mechanism that keeps core.py free of concrete imports.
4. ## Session Lifecycle — the don and doff control-flow sequences (numbered), the live session record (credential_cache
   never serialized; bound_refs + CapabilityPlan summary safe to mirror), and the evolved .claude/masque.session.yaml schema.
5. ## CapabilityPlan & Enforcement Honesty — how the plan is built at don, the host_apply tiers, and exactly how /id and
   inspect render advisory vs least-privilege (with the confused-deputy warning under host_apply==none).
6. ## Measurement Read API — score + LocalReport accessor (/performance) + the gated global seam; the local->global
   enforcement point; everything behind TelemetryPort and degrading when telemetry is off.
7. ## Migration & Backward Compatibility — the Masque->Identity+Persona field move, the exact call sites changed
   (compose() line 229, inspect() lines 281-282), list_masques() unaffected, no-sidecar => config=None, session-schema
   additivity. Existing *.masque.yaml + existing callers keep working.
8. ## Open Questions — deduped, ranked (carry forward Phase 1 OQ1a/OQ1b host-seam dependencies that gate this API).

Be concrete and decisive. Prefer additive, backward-compatible signatures. Cite engineering-reference sections inline.
Reuse Phase 1 entity names verbatim. This is an API spec, not code and not a data-model redesign.

THE FOUR DESIGNS:
${JSON.stringify(ok, null, 2)}`,
  { label: 'synthesize', phase: 'Synthesize' }
)

// --- Critique (adversarial) ------------------------------------------------
phase('Critique')
const CRITIQUE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['verdict', 'issues', 'strengths'],
  properties: {
    verdict: { type: 'string', description: 'ship | revise | reject' },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'area', 'problem', 'fix'],
        properties: {
          severity: { type: 'string', description: 'blocker | major | minor' },
          area: { type: 'string' },
          problem: { type: 'string' },
          fix: { type: 'string' },
        },
      },
    },
    strengths: { type: 'array', items: { type: 'string' } },
  },
}
const critiques = await parallel(
  [
    `Lens: HEXAGONAL PURITY & API ergonomics. Does the domain core (core.py/session.py) import ANY concrete adapter, or
     only port abstractions via the registry/injection? Does don() truly perform ZERO adapter calls (lazy credential
     resolution)? Are ports real seams with clean signatures, or leaky? Is each surface a THIN adapter, or is logic
     leaking into server.py/cli.py? Are degradation paths consistent with score()'s {"status":"unavailable"} pattern?
     Flag any function that would force the core to depend on keychain/host/DuckDB concretes.`,
    `Lens: BACKWARD-COMPAT & MIGRATION rigor. Does every existing *.masque.yaml still resolve with config=None? Are the
     EXACT changed call sites correct (compose() line 229 returns masque.source; inspect() lines 281-282 return source/path;
     list_masques() unaffected)? Is the Masque->Identity+Persona move handled at every reader? Is the session-schema change
     additive (old .claude/masque.session.yaml still readable)? Does resolve() validate the sidecar (schema + alias<->audience
     invariant) and reject/degrade correctly without ever blocking don for the no-sidecar case? Any signature that breaks a caller?`,
    `Lens: ENFORCEMENT & MEASUREMENT HONESTY (and secret safety). Does ANY returned dict, mirror, or log carry secret
     material (only alias+scheme+status allowed)? Is credential_cache provably never serialized? Does doff revoke correctly
     PER SCHEME (dynamic only) and not over-claim withdrawing static secrets? Does the API/surfaces render host_apply==none
     as ADVISORY with the confused-deputy warning, and reserve "least-privilege"/"sandbox" for hook/config-write? Is the
     measurement read API local-first with a single, enforced local->global boundary (no global path reachable when scope!=global)?
     What API claim is unfalsifiable or unsafe?`,
  ].map((lens) => () =>
    agent(
      `${GROUNDING}\n\nAdversarially review this synthesized Phase 2 core API. Be a skeptic — default to finding real problems.\n${lens}\n\nDESIGN:\n${synthesis}`,
      { label: 'critique', phase: 'Critique', schema: CRITIQUE_SCHEMA }
    )
  )
)
const allIssues = critiques.filter(Boolean).flatMap((c) => c.issues || [])
log(`Critique: ${allIssues.filter((i) => i.severity === 'blocker').length} blockers, ${allIssues.filter((i) => i.severity === 'major').length} major`)

// --- Finalize --------------------------------------------------------------
phase('Finalize')
const final = await agent(
  `${GROUNDING}

You are finalizing the Phase 2 core-API design doc. Below is the synthesized design and an adversarial critique (JSON).
Produce the FINAL markdown design document that FOLDS IN every blocker and major fix, and notes minor ones under Open
Questions. Keep all 8 sections from the synthesis. Add a short "## Critique Resolutions" section listing each
blocker/major issue and how the final API resolves it. Open with a one-paragraph status line noting this is Phase 2 of 3,
built on the finalized Phase 1 data model, and produced by the persona-core-api workflow (4 designers -> synthesis ->
3 critics -> finalize). End with a "## Files grounding this design" line citing the real core.py/session.py/server.py/
cli.py seams (with the line numbers) that implementation will touch.

Output ONLY the final markdown document (it will be saved to docs/design/phase2-core-api.md).

SYNTHESIZED DESIGN:
${synthesis}

ADVERSARIAL CRITIQUE:
${JSON.stringify(critiques.filter(Boolean), null, 2)}`,
  { label: 'finalize', phase: 'Finalize' }
)

return { final, issues: allIssues, designs: ok.map((d) => ({ area: d.area, openQuestions: d.openQuestions })) }
