export const meta = {
  name: 'persona-data-model',
  description: 'Phase 1 — design the Persona-centric data model (aggregate, credentials, MCP config, measurement) grounded in the Engineering Reference and existing core.py',
  whenToUse: 'Evolving Masques: design the core data model with Persona as the central aggregate, before touching the API or measurement implementation.',
  phases: [
    { title: 'Design', detail: '4 parallel designers: Persona aggregate, Credentials, MCP config, Measurement model' },
    { title: 'Synthesize', detail: 'merge the 4 designs into one coherent data model + migration path' },
    { title: 'Critique', detail: 'adversarial review for separation-of-concerns, consistency, ref-grounding' },
    { title: 'Finalize', detail: 'fold critique into the final design doc (markdown)' },
  ],
}

// ---------------------------------------------------------------------------
// Shared grounding handed to every agent. Keeps designs anchored to the REAL
// repo (evolve core.py, don't greenfield) and to the separation-of-concerns
// philosophy in CLAUDE.md.
// ---------------------------------------------------------------------------
const GROUNDING = `
You are designing the evolution of the Masques project (/Users/chris/git/masques).
This is a DESIGN task — produce a data model, not code.

READ FIRST (ground every decision in the real repo + reference):
- /Users/chris/git/masques/CLAUDE.md — esp. the "What Masques Own (and Don't)" table and Design Principles.
- /Users/chris/git/masques/services/mcp/src/masques_mcp/core.py — the CURRENT data model (Masque dataclass) and core API. Your design must EVOLVE this, not replace it wholesale.
- /Users/chris/git/masques/services/mcp/src/masques_mcp/session.py — current soft session state.
- /Users/chris/git/masques/schemas/masque.schema.yaml — current YAML schema.
- /Users/chris/git/masques/services/judge/sessions.sql and score.sql — the CURRENT measurement model (Layer A 7-band "house reaction", Layer B "lift" vs baseline corpus per task_class; attribution clean/mixed/baseline). Read these before designing measurement.
- /Users/chris/git/engineering-reference/engineering-reference.md — cite specific sections by name.

THE NEW VISION (what we are evolving toward):
- Persona (formerly "masque") is the CENTRAL AGGREGATE.
- Each persona can manage its own credentials (scoped per persona).
- Each persona can enable/disable MCP servers.
- Personas are MEASURABLE across sessions, with BOTH local and global/aggregate reporting. (This is THE differentiator.)

KEY DESIGN TENSION you must resolve, not ignore:
CLAUDE.md says "Masques own cognitive identity — nothing else" (Vaults own credentials, MCP owns tools).
The new vision says the persona owns its credentials and MCP toggles. Reconcile this cleanly:
the persona should own the BINDING and SCOPE (which credential ref, which MCP, what policy) — the
REFERENCE — while the secret material still lives in a vault/keychain adapter and tools still live in
MCP servers. Persona = the scoping/aggregate root that BINDS identity → capability, not the storage.
State your reconciliation explicitly.

Constraints to honor:
- Local-first / zero-infra to don a persona (telemetry + vault are optional adapters, never required to don).
- Versioned, pinned identities. Backward-compatible with existing *.masque.yaml files on disk.
- Hexagonal: domain core depends on nothing; storage/secrets/telemetry are adapter ports.
- No secrets in plaintext config; reference secrets, never inline them.
`

const DESIGN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['area', 'summary', 'entities', 'storage', 'refCitations', 'separationNotes', 'openQuestions'],
  properties: {
    area: { type: 'string' },
    summary: { type: 'string', description: '3-5 sentence overview of the design decision' },
    entities: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'role', 'owns', 'fields', 'relationships'],
        properties: {
          name: { type: 'string' },
          role: { type: 'string', description: 'aggregate-root | entity | value-object | projection | event' },
          owns: { type: 'string', description: 'what this entity is the authoritative owner of' },
          fields: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['name', 'type', 'notes'],
              properties: {
                name: { type: 'string' },
                type: { type: 'string' },
                notes: { type: 'string' },
              },
            },
          },
          relationships: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    storage: {
      type: 'object',
      additionalProperties: false,
      required: ['where', 'format', 'rationale'],
      properties: {
        where: { type: 'string', description: 'on-disk location / store, grounded in current repo layout' },
        format: { type: 'string' },
        rationale: { type: 'string', description: 'cite the engineering-reference tradeoff that justifies this' },
      },
    },
    refCitations: { type: 'array', items: { type: 'string' }, description: 'engineering-reference sections cited by name' },
    separationNotes: { type: 'string', description: 'how this respects masque-owns-identity while delivering the new capability' },
    openQuestions: { type: 'array', items: { type: 'string' } },
  },
}

const DESIGNERS = [
  {
    key: 'persona-aggregate',
    prompt: `${GROUNDING}

YOUR AREA: The Persona aggregate root and its identity core.
Design how today's Masque dataclass (name, version, lens, context, attributes, rubric, spinnerVerbs)
becomes the Persona AGGREGATE ROOT that also references credentials, MCP bindings, and measurement config —
WITHOUT bloating the identity. Decide:
- The aggregate boundary (DDD §19): what is inside Persona vs referenced by id?
- Identity vs configuration split: the immutable, versioned, pinned identity (lens/context/attributes) vs
  the mutable per-persona config (credential bindings, MCP toggles, measurement opt-in). Should these be
  ONE versioned file or identity-file + sidecar config? Justify via schema evolution (§5) and the
  "versioned, pin deliberately" principle.
- Natural vs surrogate key (§4) for persona identity; how versions are addressed.
- Backward compat: existing *.masque.yaml must still load.
Return the Persona aggregate, any value objects (PersonaRef, Version), and the identity/config boundary.`,
  },
  {
    key: 'credentials',
    prompt: `${GROUNDING}

YOUR AREA: Per-persona credential scoping and storage.
Ground HARD in engineering-reference §"Secrets management", §"Secret zero & the bootstrap problem",
§"Short-lived credentials & rotation", §"Principle of least privilege", and §"Federated cloud workload identity".
Design:
- The CredentialBinding entity a persona owns: it REFERENCES a secret (by vault path / keychain ref / env name),
  it never stores the material. Show the reference shape.
- Scoping: how a credential is scoped to a persona (and only available while that persona is donned) — least privilege.
- The vault/secret ADAPTER PORT (hexagonal): what the port interface conceptually is, and which concrete
  adapters plug in (OS keychain, env, HashiCorp Vault, cloud STS). Local-first default adapter.
- Secret-zero / bootstrap handling and short-lived-credential strategy where relevant.
- What happens on doff (credential access revoked / cache cleared).
Be explicit that secret MATERIAL never lands in the persona file or any git-tracked file.`,
  },
  {
    key: 'mcp-config',
    prompt: `${GROUNDING}

YOUR AREA: Per-persona MCP server configuration (enable/disable).
The persona declares which MCP servers it enables and with what policy. Ground in §"Plugin / Microkernel"
(extension contract as permanent API), §"Principle of least privilege", and the CLAUDE.md "MCP owns knowledge/tools" row.
Design:
- The McpBinding entity a persona owns: server id/ref, enabled flag, optional scoped config/allowed-tools, and
  HOW it references (not duplicates) the actual MCP server definition (which lives in Claude Code .mcp.json / host config).
- How enable/disable maps onto the host (Claude Code) at don/doff time — persona as the policy layer that
  toggles capability, host as the executor. Note what Masques can and cannot enforce here (it's advisory to the host).
- Tool-permission scoping per persona (least privilege): allow/deny lists.
- Relationship to credentials (an MCP server often needs a credential the persona also binds).
Keep the separation clean: persona owns the BINDING/policy; the MCP server itself is external.`,
  },
  {
    key: 'measurement',
    prompt: `${GROUNDING}

YOUR AREA: The measurement & reporting DATA MODEL (the differentiator). DATA MODEL ONLY — Phase 3 covers mechanics.
Read services/judge/sessions.sql and score.sql FIRST; preserve the existing two-layer model
(Layer A 7-band house reaction; Layer B lift vs baseline corpus per task_class; attribution clean/mixed/baseline).
Ground in §"Observability" — esp. "Structured / wide events (the unifying model)", "Cardinality",
"Cardinality-aware metric design (RED & USE)", "SLI/SLO", "OpenTelemetry", and §"Event sourcing" / "Materialized view / Read model / Projection".
Design these entities and how they relate to Persona:
- Session (the unit of measurement): boundaries, persona attribution, task_class, the wide-event attributes carried.
- The raw signal layer (wide events / OTEL logs) vs derived Metric/Score projections (CQRS read model §20).
- Report entities: LOCAL report (per-machine, per-persona, across that user's sessions) AND
  GLOBAL/AGGREGATE report (a persona's reputation pooled across users/machines) — define BOTH as distinct
  read models. Address cardinality (keep persona id low-card; push session id / user id into events).
- What identifies a persona ACROSS machines for global pooling (content hash of identity? §6 content addressing)
  and the privacy boundary (local-first: what, if anything, leaves the machine, and in what aggregated/anonymized shape).
Return entities: Session, Event/Signal, Score, LocalReport, GlobalReport (+ any value objects like Band, Lift, TaskClass).`,
  },
]

phase('Design')
const designs = await parallel(
  DESIGNERS.map((d) => () =>
    agent(d.prompt, { label: `design:${d.key}`, phase: 'Design', schema: DESIGN_SCHEMA })
  )
)
const ok = designs.filter(Boolean)
log(`Designs complete: ${ok.map((d) => d.area).join(', ')}`)

// --- Synthesize ------------------------------------------------------------
phase('Synthesize')
const synthesis = await agent(
  `${GROUNDING}

You are the SYNTHESIS architect. Four area designs were produced (as JSON below). Merge them into ONE
coherent Persona-centric data model. Resolve overlaps and conflicts (especially the identity-vs-config
boundary and the credential<->MCP relationship). Produce MARKDOWN with:

1. ## Entity-Relationship Overview — an ASCII ER diagram with Persona as the aggregate root, plus a one-line
   role for each entity (aggregate-root / entity / value-object / projection / event).
2. ## Entities — for each entity: purpose, ownership, fields (name : type — note), relationships.
3. ## On-Disk / Storage Layout — concrete paths evolving the current repo layout (personas/*.masque.yaml,
   ~/.masques/, services/judge/, collector JSONL). Make explicit what is git-tracked vs local-only vs never-stored.
4. ## Identity vs Configuration — the versioned/pinned identity file vs mutable per-persona config; how they bind.
5. ## Separation of Concerns — the reconciliation table: what Persona OWNS (binding/scope) vs what adapters own
   (secret material, MCP tools, telemetry storage). Evolve the CLAUDE.md table.
6. ## Migration Path — how existing *.masque.yaml files load unchanged; what's additive; schema-evolution notes.
7. ## Measurement Data Model — Session, Event, Score, LocalReport, GlobalReport and the local→global boundary.
8. ## Open Questions — deduped, ranked.

Be concrete and decisive. Prefer additive, backward-compatible choices. Cite engineering-reference sections inline.

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
    `Lens: SEPARATION OF CONCERNS & philosophy drift. Does the model keep Persona as identity+binding without
     absorbing secret storage or tool execution? Does it violate any CLAUDE.md Design Principle? Is "local-first,
     zero-infra to don" preserved? Flag any place the persona file could leak a secret.`,
    `Lens: DATA-MODELING & engineering-reference rigor. Aggregate boundary correct (DDD)? Keys (§4) sound?
     Schema evolution / backward-compat (§5) actually additive? Measurement: cardinality discipline (low-card persona id,
     high-card in events)? Is the local vs global read-model split (CQRS §20) coherent? Are cited sections used correctly?`,
    `Lens: MEASUREMENT VALIDITY (the differentiator). Does the model preserve Layer A house reaction + Layer B lift +
     attribution? Is global/aggregate reporting statistically meaningful (baseline cohorts, anonymization, gaming
     resistance) and is the privacy boundary explicit? What measurement claim is unfalsifiable or game-able?`,
  ].map((lens) => () =>
    agent(
      `${GROUNDING}\n\nAdversarially review this synthesized data model. Be a skeptic — default to finding real problems.\n${lens}\n\nDESIGN:\n${synthesis}`,
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

You are finalizing the Phase 1 data-model design doc. Below is the synthesized design and an adversarial
critique (JSON). Produce the FINAL markdown design document that FOLDS IN every blocker and major fix, and
notes minor ones under Open Questions. Keep all 8 sections from the synthesis. Add a short "## Critique
Resolutions" section listing each blocker/major issue and how the final model resolves it.

Output ONLY the final markdown document (it will be saved to docs/design/phase1-data-model.md).

SYNTHESIZED DESIGN:
${synthesis}

ADVERSARIAL CRITIQUE:
${JSON.stringify(critiques.filter(Boolean), null, 2)}`,
  { label: 'finalize', phase: 'Finalize' }
)

return { final, issues: allIssues, designs: ok.map((d) => ({ area: d.area, openQuestions: d.openQuestions })) }
