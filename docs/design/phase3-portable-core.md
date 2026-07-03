# Phase 3 — Portable Core & Reference Host (loon-agent)

> **Status:** Design — Phase 3 of the Masques→Personas evolution. Builds on the
> finalized Phase 1 data model (`phase1-data-model.md`) and Phase 2 core API
> (`phase2-core-api.md`). This phase repositions the project: masques becomes a
> **spec + portable core library** with two reference hosts at opposite ends of the
> enforcement spectrum, and the **primitive itself** (prompt + access + memory in one
> don) replaces the managed observability stack as the keystone.

## 1. Strategic Reframing

The original vision (`vision.md`) named five components — intent, context, knowledge,
access, lens — fused into one "become this" primitive. Phases 1–2 designed the data
model and API for that primitive, but both stalled on the same wall: **Claude Code is
a host we don't control.** Its two blocking open questions (OQ1b: does the host expose
an enforcement seam? OQ1a: how does identity reach host-emitted telemetry?) are
unanswerable from the outside, so the entire capability story degraded to
`host_apply: none` — advisory prose, honestly labeled.

**loon-agent** (`~/git/agents/loon-agent`) dissolves the wall. It is a hand-rolled
LangGraph ReAct agent where we own every seam the Phase 1/2 design needs:

| Phase 1/2 need | Claude Code | loon-agent |
|---|---|---|
| Tool enforcement seam (OQ1b) | Unverified; advisory only | **Owned** — tools are bound at graph compile (`graph.py:89` `llm.bind_tools`, `:98` `ToolNode`) |
| Attribution emission (OQ1a) | Unverified; sidecar-join fallback | **Owned** — `telemetry.py` sets OTEL resource attributes directly |
| Memory scoping | No seam exists | **Owned** — `MemoryProvider` ABC (`memory/provider.py`), already `session_id`-namespaced |
| Prompt assembly | Injected block only | **Owned** — `_build_messages` composes system + persona + memory per turn |

The reframing, in one line: **Claude Code is the host you don't control (identity
only, advisory tier); loon-agent is the host you do control (the full five-component
primitive, structurally enforced).** Masques stops being "a Claude Code plugin with
aspirations" and becomes a spec + core library, with loon-agent as the reference
implementation that proves "slaps on top of any agent" on a second agent.

loon already consumes the compatible subset: its `masques.py` loads `name`/`lens`/
`context` from masques-schema files (`*.masque.yaml` accepted) and dons them per
skill step. Phase 3 extends that from "system prompt block" to "full persona."

## 2. `masques-core`: the Portable Library

**Deliverable:** a dependency-light pip package (PyYAML only) extracted from
`services/mcp/src/masques_mcp/`, containing everything Phase 2 marked PURE:

```
masques-core  (dist)  →  masques_core  (module)
├── model.py       Persona, Identity, PersonaRef, Version, PersonaConfig,
│                  CredentialBinding/SecretRef, McpBinding, MemoryBinding (NEW, §3),
│                  MeasurementPolicy, CapabilityPlan
├── core.py        resolve() → Persona, compose(), build_identity_block(),
│                  build_capability_plan(), list_masques(), inspect()   — all pure
├── sidecar.py     _parse_persona_config + persona-config.schema.yaml validation
├── ports.py       SecretPort / McpPort / TelemetryPort Protocols + registry
│                  (EnvAdapter ships in core; keychain/vault/telemetry adapters
│                   live with the surfaces that need them)
└── schemas/       masque.schema.yaml + persona-config.schema.yaml (package data)
```

- `masques-mcp` (the FastMCP server) becomes a consumer: it depends on
  `masques-core` and keeps only the MCP surface, session mirror, and judge adapter.
- **loon-agent depends on `masques-core`** and deletes most of its own loader;
  `MasqueLoader` becomes a thin shim mapping loon's lenient-lookup semantics
  (missing masque ⇒ warn + run bare) onto `resolve()`'s errors.
- Packaging: hatchling, same layout as `services/mcp`; lives at `services/core/`
  in this repo. Version starts at `0.1.0`, independent of the plugin version.

This is what makes masques "a tool that enables loon-agent" rather than a sibling
project loon imitates: one resolver, one schema, one Persona shape, two hosts.

## 3. MemoryBinding — the Missing Third Binding

Phase 1 bound credentials and MCP servers but not memory. The original intent —
"couple access controls and system prompts **and memory capabilities** into one
single obvious primitive" — needs a third binding type. It slots into
`PersonaConfig` alongside the other two, with the identical ownership split:
**the persona owns the scope and mode; the memory provider owns the storage.**

### MemoryBinding — value-object (sidecar-resident)
- `namespace : str` — partition key. The host prefixes its memory-store key
  (loon: the `session_id` passed to `prefetch`/`sync_turn`) with
  `persona/<namespace>/`. Two personas sharing a namespace share recall;
  distinct namespaces are structurally isolated.
- `mode : "read-write" | "read-only" | "none"` (default `read-write`) —
  `read-only` ⇒ recall works, write-back is a no-op (an Analyst that learns
  nothing); `none` ⇒ full amnesia (a guest masque).
- `prompt_block : bool` (default true) — whether the provider's static
  `system_prompt_block()` is injected while this persona is donned.
- `provider : str | None` — optional named provider selection for hosts with
  more than one (loon: `sqlite` today, OpenViking later). `None` = host default.

**Why sidecar, not identity file:** memory scope is operational config — you may
widen the Briefer's namespace or flip the Analyst to read-only without that being
a new cognitive identity. Same argument that put credentials in the sidecar
(Phase 1 §4). The lens may still *describe* memory habits; the binding *enforces*
them.

**Degradation:** on a host with no memory seam (Claude Code), MemoryBinding
resolves to status `unresolved-host` in the CapabilityPlan — same degrade
vocabulary as a missing MCP server, never fatal. The binding is only meaningful
at the `bind` tier (§4).

**Enforcement (loon):** a `ScopedMemory(MemoryProvider)` decorator, ~40 lines:

```python
class ScopedMemory(MemoryProvider):
    def __init__(self, inner: MemoryProvider, binding: MemoryBinding): ...
    def system_prompt_block(self):  # "" unless binding.prompt_block
    def prefetch(self, query, session_id):
        if self.binding.mode == "none": return ""
        return self.inner.prefetch(query, f"persona/{self.binding.namespace}/{session_id}")
    def sync_turn(self, user, assistant, session_id):
        if self.binding.mode != "read-write": return
        self.inner.sync_turn(user, assistant, f"persona/{self.binding.namespace}/{session_id}")
```

Like tool binding, this is structural: a `read-only` persona has no code path to
write memory. No honesty caveats needed.

## 4. The `bind` Enforcement Tier

Phase 1/2 defined `host_apply: none | config-write | hook`. loon introduces a
fourth, strongest tier:

- **`bind`** — denied capabilities are **structurally absent**: tools not in the
  allow-list are never passed to `llm.bind_tools()` / `ToolNode`, so they do not
  exist in the model's tool schema; memory outside the binding's mode has no code
  path. `enforced: true`, and the confused-deputy warning does not apply to
  *unbound* tools (there is nothing to confuse). Credential `audience` scoping
  within a bound tool still applies as at other tiers.

Tier ordering: `none < config-write < hook < bind`. Only a host that owns its
agent loop can offer `bind`; loon's adapter reports
`McpPort.capabilities().max_tier == 'bind'`. **This resolves Phase 1/2 OQ1b for
the loon host** (Claude Code's tier remains an open question, unchanged).

**Native tools vs MCP servers.** Phase 1's `McpBinding` assumed MCP servers, but
loon's tools are native Python functions. Rather than a new entity, the reserved
server id **`host`** denotes the host's native tool registry; `allow`/`deny`
apply at tool-name granularity within it. When loon later adds real MCP servers,
those use ordinary per-server bindings in the same block. One shape, both worlds:

```yaml
# ~/.masques/analyst.persona.yaml — or loon-local masques/analyst.persona.yaml
persona: Analyst
schema_version: 1
mcp:
  - server: host                      # loon's native tool registry
    allow: [web_search, fetch_page, get_current_time]
    uses_credentials: [search_api]
memory:
  namespace: research
  mode: read-only
credentials:
  - alias: search_api
    ref: env://TAVILY_API_KEY
    scope: {audience: [host], required: false}
measurement:
  enabled: false
```

## 5. loon-agent Integration (reference-host plan)

Work in `~/git/agents/loon-agent`, sequenced:

1. **Depend on `masques-core`**; shrink `masques.py` to a compatibility shim
   (lenient lookup + `system_block()` preserved for skill steps).
2. **Runtime don/doff.** Today the persona is fixed at `build_runtime`
   (`app.py:74`) and baked into the compiled graph. Add to `LoonRuntime`:

   ```python
   def don(self, name: str, intent: str | None = None) -> Persona:
       persona = resolve(name)                                   # masques-core, pure
       plan, _ = build_capability_plan(persona, self.host_snapshot())  # tier: bind
       tools   = [t for t in self.all_tools if allowed(t.name, plan)]  # structural
       memory  = ScopedMemory(self.base_memory, persona.config.memory) \
                     if persona.config and persona.config.memory else self.base_memory
       block   = compose(persona, intent, plan=plan)["identity_block"]
       self.agent = LoonAgent(self.llm, tools, checkpointer=self.checkpointer,
                              memory=memory, persona=block)
       return persona
   ```

   Graph recompilation is cheap; the shared `SqliteSaver` checkpointer keeps
   thread continuity across don/doff. `doff()` rebuilds with `DEFAULT_TOOLS`,
   unscoped memory, no persona block, and zeroes any resolved credentials
   (Phase 2 doff semantics; `env://` is static ⇒ cache-zero only).
3. **`/don <name> [intent]` and `/doff` chat commands** in both adapters (CLI +
   Telegram), next to the existing `/new`. The don path is the vision doc's
   promise verbatim: one command, and the agent becomes someone.
4. **`ScopedMemory`** as in §3.
5. **Credentials:** `EnvAdapter` from masques-core resolving `env://` refs
   lazily at first tool use (`resolve_credential` semantics from Phase 2 §4);
   keychain later if needed.
6. **Session mirror:** loon writes the Phase 2 `.claude/masque.session.yaml`
   superset schema (as `data/masque.session.yaml`) so `/id`-style introspection
   and any future audience tooling read one format across hosts. Its
   `capability_plan.host_apply` is `bind` and bindings carry `enforced: true` /
   `effective_allow` — the first mirror ever written at an enforced tier.
7. **Attribution (two lines, §6):** at don, set OTEL resource attributes
   `persona.id` / `persona.version` on loon's existing gen_ai spans.

Skill-step masques (Analyst/Briefer donned per step) keep working unchanged —
steps use `system_block()` only. A follow-on may let a skill step declare a full
persona (scoped tools per step), but that is not v1.

## 6. Observability Repositioned: Contract, not Stack

`vision.md` claims "observability is the core — a masque without an audience is
just a system prompt." That thesis was written when the only host was Claude
Code, where masques had to *bring its own audience* (collector, ClickHouse,
DuckDB judge) because it controlled nothing. With a host we own, the calculus
inverts: **loon already emits gen_ai-semconv OTEL spans; its operator already
owns the o11y pipeline.** Masques bringing a parallel managed stack there is
redundant infrastructure.

Phase 3 therefore splits observability into two parts with opposite fates:

- **The attribution contract — KEEP, it is the part only masques can provide.**
  Three OTEL resource attributes (`persona.id`, `persona.version`,
  `persona.identity_hash` — Phase 1 §7's low-cardinality trio) plus a
  `persona.otel_attributes()` helper in masques-core. The host emits them on
  whatever pipeline it already runs. This is ~cheap, host-agnostic, and is what
  makes any future per-identity analysis (or cross-host comparison) possible.
  Dropping it would orphan identity from every trace forever; keeping it costs
  two lines per host.
- **The managed stack — DEMOTE to an optional "audience profile."** The
  collector/ClickHouse/DuckDB pipeline, `/performance` scoring, LocalReport/
  GlobalReport, and the global-pool machinery (Phase 1 §7) remain designed and
  valid but move from keystone to opt-in profile for hosts with no o11y of
  their own (Claude Code). Nothing is deleted; the Phase 1 measurement model is
  unchanged. It is simply no longer on the critical path, and no Phase 3 work
  item depends on it.

Consequence for `vision.md`: the thesis line is revised — **the keystone is the
primitive** (one don = prompt + access + memory, enforced where the host
allows); *measurable* identity is what the primitive enables when an audience is
seated, not the precondition for the primitive mattering. This also resolves
Phase 1/2 OQ1a *for the loon host*: attribution is event-carried from day one
(loon sets the attributes at don), no sidecar-join fallback needed there.

## 7. Sequencing & Compatibility

Priority order (masques repo first — loon consumes it):

| # | Repo | Work | Depends on |
|---|------|------|-----------|
| 1 | masques | Extract `masques-core` package (`services/core/`) from `masques_mcp` purs; `masques-mcp` consumes it | — |
| 2 | masques | `persona-config.schema.yaml` + sidecar parsing incl. **MemoryBinding** and reserved `server: host`; Phase 1 doc addendum | 1 |
| 3 | masques | `bind` tier in CapabilityPlan vocabulary + `persona.otel_attributes()` helper | 1 |
| 4 | loon | Adopt masques-core; runtime `don`/`doff` + `/don` `/doff` commands | 1–3 |
| 5 | loon | `ScopedMemory` + tool selection at graph rebuild (bind tier) | 4 |
| 6 | loon | `env://` lazy credential resolution; OTEL persona attributes; session mirror | 4 |
| 7 | masques | Revise `vision.md` (keystone = primitive; audience = optional profile; loon listed as reference host) | 4–6 shipped |

**Backward compatibility:** unchanged from Phase 2 — identity files load
verbatim; no sidecar ⇒ zero-binding persona; Claude Code plugin behavior is
untouched (still advisory tier, still identity-only). loon's existing
`analyst.yaml`/`briefer.yaml` keep working with no sidecar; adding one is
opt-in per persona.

## 8. Open Questions

1. **Package boundary:** does `masques-core` ship the ports *Protocols* only, or
   also the degrading default adapters (Env yes; Advisory-MCP probably;
   LocalJudge no)? Leaning: Protocols + Env + Null adapters in core, everything
   else with its surface.
2. **Namespace collision semantics:** two personas with `namespace: research` —
   feature (shared team memory) or footgun? v1: allowed and documented as
   deliberate sharing.
3. **Reserved id `host`:** confirm the token (`host` vs `native` vs `_local`)
   and that no real MCP server id can collide (schema-reserve it).
4. **Skill-step personas:** should a loon skill step be able to don a *full*
   persona (scoped tools per step) rather than lens-only? Deferred; needs
   per-step tool wiring in `SkillRunner`.
5. **Doff-to-what in loon:** baseline = `DEFAULT_TOOLS` + unscoped memory, or a
   configurable "house" persona? v1: hard baseline, matching masques semantics.
6. **Mirror location for non-Claude hosts:** `data/masque.session.yaml` in loon
   vs honoring `MASQUES_HOME`. v1: host-local data dir.

---

**Files grounding this design:** masques repo — `services/mcp/src/masques_mcp/core.py`
(pure functions to extract), `services/mcp/pyproject.toml` (packaging pattern),
`docs/design/phase1-data-model.md` §2/§4/§7, `docs/design/phase2-core-api.md`
§2–§5; loon-agent — `src/loon_agent/masques.py` (compatible loader to shim),
`src/loon_agent/graph.py:31-102` (prompt assembly + tool binding seam),
`src/loon_agent/memory/provider.py` (MemoryProvider ABC), `src/loon_agent/app.py:46-102`
(composition root; persona fixed at line 74), `src/loon_agent/telemetry.py`
(OTEL emission), `masques/analyst.yaml`, `masques/briefer.yaml`.
