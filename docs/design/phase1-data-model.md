# Masques → Personas: Phase 1 Data Model

> **Status:** Design — Phase 1 of 3 (Data Model). Produced by the `persona-data-model`
> workflow: 4 parallel area designers → synthesis → 3 adversarial critics → finalize.
> All 18 critique findings (3 blocker, 9 major, 6 minor) are resolved below
> (see [Critique Resolutions](#critique-resolutions)). Phases 2 (Core API) and 3
> (Measurement System) build on this.

The **Persona** is the aggregate root that binds *identity → capability → measurement*. Its consistency boundary holds only **bindings and scopes** (which credential ref, which MCP server, what policy) — never secret bytes, never tool implementations, never raw telemetry. This is the explicit reconciliation of the CLAUDE.md tension ("Masques own cognitive identity — nothing else"): **Persona owns the REFERENCE and SCOPE; adapters own the MATERIAL.**

A decision the design space splits on — *one merged file* (inline `credentials:`/`mcp:` on the masque) vs. *identity file + mutable sidecar* — is resolved decisively in favor of **the sidecar split** (§4). Reason: Design Principle 3 (pinned, deliberate upgrade) is violated if a credential rotation or MCP toggle silently mutates a "pinned" identity artifact or forces a spurious semver bump. The identity file stays byte-stable; operational config is hot-mutable. This is `Externalized configuration` + `Dynamic / hot-reload configuration` (§29).

---

## 1. Entity-Relationship Overview

```
                          ┌──────────────────────────────────────┐
                          │            Persona                    │  aggregate-root
                          │  (in-memory: Identity + Config)       │  binds identity→capability→measurement
                          │  owns: source, path                   │
                          └──────────────────────────────────────┘
                             │ composes 1:1        │ composes 0..1
              ┌──────────────┘                     └───────────────┐
              ▼                                                     ▼
   ┌────────────────────┐  identity file               ┌────────────────────────┐  sidecar (mutable)
   │  Identity          │  value-object (immutable)     │  PersonaConfig         │  entity (mutable, optional)
   │  name·version·lens │  <name>.masque.yaml           │  <name>.persona.yaml   │
   │  context·attrs     │  ── PINNED                     │  ── NOT semver-pinned  │
   │  rubric·spinner    │  (NO source/path)             └────────────────────────┘
   └────────────────────┘                                   │            │            │
              │ embeds                            owns many  │   owns many│      owns 1 │
              ▼                                               ▼            ▼            ▼
      ┌──────────────┐                          ┌──────────────────┐ ┌────────────┐ ┌──────────────────┐
      │  Version     │ value-object             │ CredentialBinding│ │ McpBinding │ │MeasurementPolicy │
      │  major.minor │                          │  value-object    │ │value-object│ │  value-object    │
      │  .patch·raw  │                          │  alias·ref·scope │ │server·tools│ │ enabled·scope    │
      └──────────────┘                          └──────────────────┘ └────────────┘ └──────────────────┘
                                                     │ ref (URI)         │ ref (id)        │ read by
   ┌──────────────┐ value-object                     ▼ resolved by       ▼ applied by      ▼
   │  PersonaRef  │ (name + Version) ─── addresses   ╎SecretPort adapter ╎McpPort adapter  ╎TelemetryPort
   │              │     the aggregate                ╎(keychain/env/vault)╎(host .mcp.json) ╎(collector/judge)
   └──────────────┘                                  ╎ → ResolvedSecret  ╎ → CapabilityPlan╎
                                                       (in-memory only)   (ephemeral)
                                                  ═══════════ hexagonal port boundary ═══════════
                                                  (adapters live OUTSIDE the domain core)

   MEASUREMENT (event-sourced CQRS — pure folds over the event log):

   ┌────────┐   N:1    ┌─────────┐   1:1    ┌────────┐   N:1   ┌─────────────┐  opt-in  ┌──────────────┐
   │ Event  │────────▶ │ Session │────────▶ │ Score  │───────▶ │ LocalReport │─────────▶│ GlobalReport │
   │ event  │ (write   │projection│ scored  │project.│ rolled  │ read-model  │ k-anon + │ read-model   │
   │ (only  │  model)  │          │  by     │        │  up     │(per-machine,│ DP + attest│(per identity │
   │ truth) │          │          │         │        │         │ hash-keyed) │          │  hash, remote)│
   └────────┘          └─────────┘          └────────┘         └─────────────┘          └──────────────┘
   attribution: event-carried persona.id/version/identity_hash, with sidecar-join FALLBACK for pre-cutover logs
```

**Roles at a glance:** Persona = *aggregate-root*. Identity, PersonaRef, Version, CredentialBinding, McpBinding, MeasurementPolicy, Band, Lift, TaskClass = *value-objects*. PersonaConfig, ResolvedSecret = *entities*. Session, Score = *projections*. LocalReport, GlobalReport = *read-models*. Event = *event*. CapabilityPlan = *projection* (ephemeral). McpServerDefinition, SecretPort/McpPort/TelemetryPort = *external / port* (named only to mark the ownership boundary).

---

## 2. Entities

### Persona — aggregate-root
- **Purpose:** The unit you `don`. Composes the pinned cognitive identity with the mutable operational config into one in-memory object at resolve time. The consistency boundary for "what may this identity reach, and how is it measured."
- **Ownership:** Owns the **binding and scope** — never secret material, tool implementations, or telemetry storage. Also owns **`source` and `path`** (lifted off the old `Masque` dataclass — see §6).
- **Fields:**
  - `identity : Identity` — the pinned core, loaded verbatim from `<name>.masque.yaml`. What `compose()`/`build_identity_block()` read today.
  - `ref : PersonaRef` — natural key `(name, version)`; `Natural vs surrogate key` (§4).
  - `config : PersonaConfig | None` — operational sidecar; **absent ⇒ zero-binding persona** (backward compat).
  - `identity_source : "private" | "shared"` — source of the *identity* file; private `~/.masques` wins (current `resolve()` precedence, core.py lines 173-177).
  - `config_source : "private" | None` — source of the *sidecar*. Sidecars are **always local/private** (they hold per-user credential refs); a private sidecar may bind a shared identity, so the two sources can differ (resolves the privacy-posture ambiguity — §4).
  - `path : Path` — identity file path; sidecar path derived (`<name>.persona.yaml`).
- **Relationships:** composes one Identity (1:1), zero-or-one PersonaConfig; references many CredentialBinding / McpBinding by ref; declares one MeasurementPolicy; is the attribution subject for Session/Score.

### Identity — value-object (immutable, pinned)
- **Purpose:** The answer to "how to think." Authoritative source is the existing `<name>.masque.yaml`. Changing any field is a new Version, never an in-place edit (`Schema-on-write`, §5).
- **Ownership:** The masque file.
- **Fields (= current `Masque` dataclass MINUS `{source, path}` — those move to Persona):**
  - `name : str` — natural key, minLength 1. Unchanged.
  - `version : Version` — semver, pattern-validated as today.
  - `lens : str` — required, the identity core. Unchanged.
  - `context : str | None` — optional grounding. Unchanged.
  - `attributes : dict[str, Any]` — open metadata, `additionalProperties: true`. Unchanged.
  - `rubric : str | None` — **stays in the identity file**: it is part of what the identity *claims to be good at*, must version with the lens, and feeds the Layer-A rubric judge (matches masque.schema.yaml's own rationale). Self-authored is fine **locally**; global pooling of rubric-judged bands is gated (§7).
  - `spinner_verbs : dict | None` — presentation. Unchanged.
  - `identity_hash : str` (derived, lazy) — sha-256 of the canonical encoding (§7). Computed only when `MeasurementPolicy.scope == "global"`; the default don path never touches it.
- **Relationships:** verbatim parse of `<name>.masque.yaml`; consumed by `compose()`.

### Version — value-object
- **Purpose:** Make "pin deliberately, upgrade consciously" a typed concept. This is a **content-addressed / pinned selector** (`Content addressing` §4, immutable pin §5) — NOT an optimistic-lock column. Nobody does a compare-and-set write against the immutable file.
- **Fields:** `major : int`, `minor : int`, `patch : int`, `raw : str` (preserved for round-trip — `Canonical / deterministic encoding`, §5).

### PersonaRef — value-object
- **Purpose:** How a persona is addressed and pinned; the stable handle Sessions and telemetry cite.
- **Fields:** `name : str` (case-insensitive on filename stem, matching `resolve()`), `version : Version` (pinned snapshot).
- **Relationships:** names the aggregate in `don()`/`doff()` and in measurement attribution. **Decision: attribution keys on `(name, version)`, not name alone** (§7). `name` is a natural key and is rename-fragile (`Natural vs surrogate key`, §4) — see the rename note in §7.

### PersonaConfig — entity (mutable, non-versioned, optional)
- **Purpose:** The mutable operational half. Home of everything the new vision adds — credential bindings, MCP toggles, measurement opt-in — kept OUT of the identity so toggling a server never bumps an identity version.
- **Ownership:** The `<name>.persona.yaml` sidecar.
- **Fields:**
  - `persona : str` — back-reference to the identity by name (self-describing; a stray sidecar with no matching identity is ignored).
  - `schema_version : int` — config-file format version (NOT identity semver); lets the sidecar evolve via additive fields (`Schema evolution rules`, §5).
  - `etag : str | None` — content hash / generation for `Compare-and-set / Optimistic locking` (§13) against concurrent TUI+plugin writes. **(§13 applies here, to the mutable sidecar — not to the immutable identity Version.)**
  - `credentials : list[CredentialBinding]` — per-persona credential scopes (references only).
  - `mcp : list[McpBinding]` — per-persona MCP toggles (references only).
  - `measurement : MeasurementPolicy` — telemetry opt-in. Default: zero-value (`enabled: false`) ⇒ absence of sidecar == local-first, zero-infra.
- **Aggregate invariant (enforced on write):** the `alias ↔ audience` symmetry (§ CredentialBinding/McpBinding) is checkable entirely from sidecar state, so it is a true **in-aggregate invariant** — validated by `persona-config.schema.yaml` plus a load-time check. A sidecar that violates it is **rejected**, not silently degraded. Cross-aggregate references (server present in host, secret ref resolvable) are NOT invariants and degrade to `unresolved` (§ CapabilityPlan).
- **Relationships:** owned by exactly one Persona (composition); absent ⇒ empty bindings.

### CredentialBinding — value-object
- **Purpose:** ONE reference + scope tying this persona to a secret that lives elsewhere. Persona owns the **reference**, vault owns the **material**.
- **Ownership:** The binding (alias, ref URI, scope, policy) — never the secret bytes.
- **Fields:**
  - `alias : str` — logical handle the lens/MCP refer to (e.g. `github_token`). Stable across rotation.
  - `ref : SecretRef` — `{scheme, locator, version?}` discriminated by scheme: `keychain://` (default, local-first; locator `masques/<persona>/<alias>`), `env://NAME` (the name, never the value), `vault://path#field`, `sts://role-arn`. **Never inline plaintext** (`Secrets management`, §29).
  - `scope : {audience: list[str] (mcp server ids), required: bool, availability: "while-donned"|"on-demand"}` — `Principle of least privilege` (§30): resolvable only while this persona is donned, injectable only into the named MCP servers. **NB (enforcement honesty):** when `CapabilityPlan.host_apply == "none"` this scope is **advisory** — see § CapabilityPlan and §8.
  - `rotate : "static" | "dynamic"` + `ttl : duration | None` — `dynamic` lets Vault/STS adapters mint per-session credentials (`Short-lived credentials & rotation`, **§49 Workload Identity**); revocation behavior is scheme-dependent (see doff below).
- **Relationships:** resolved through `SecretPort` (hexagonal); referenced by `McpBinding.uses_credentials` via `alias`. `required: false` ⇒ unresolvable refs degrade gracefully (don never blocks).

### McpBinding — value-object
- **Purpose:** ONE per-persona MCP server toggle + tool-permission scope. Persona owns the enable/disable decision and the allow/deny scope; the host owns the server definition and tool implementations.
- **Ownership:** The policy toward one server — never the server's command/transport/tools.
- **Fields:**
  - `server : str (id)` — stable id matching a key in the host's `.mcp.json` (`Anti-corruption layer`, §21: a reference, not a copy). Missing in host ⇒ binding reported `unresolved`, not fatal.
  - `enabled : bool` (default true) — per-persona request to enable/disable; disable lets a persona deliberately *shed* an ambient capability.
  - `allow : list[str] | None` — allow-list of tool names (deny-by-default when present); supports globs. `Capability-based sandboxes` (§36) **only when host-enforced** (§8).
  - `deny : list[str] | None` — applied after allow; deny wins (fail-closed) **when host-enforced**.
  - `uses_credentials : list[str] (aliases)` — which CredentialBinding aliases this server may consume.
  - `config : ClosedConfig | None` — **NOT a free-form string sink.** A closed, schema-allowlisted set of non-secret typed keys per server (bool / int / enum only). Arbitrary strings are rejected. **All credential-bearing values route through `uses_credentials → SecretRef`**; `config` can never express a secret (resolves the DSN/bearer-in-base_url leak path — see Critique Resolutions).
  - `required : bool` (default false) — if true and unsatisfiable, don warns loudly; never hard-fails (local-first).
- **Relationships:** applied through `McpPort`; references CredentialBinding by alias; references McpServerDefinition by id. `uses_credentials` and `CredentialBinding.scope.audience` are **two views of one in-aggregate invariant** — both lists live in the sidecar, so the symmetry is enforced **on write** (schema + load-time check), not merely at resolve.

### MeasurementPolicy — value-object
- **Purpose:** This persona's opt-in to being measured and where reports may flow.
- **Ownership:** The policy (opt-in, local vs global). The collector/DuckDB/ClickHouse own the actual signals.
- **Fields:**
  - `enabled : bool` (default false) — telemetry never required to don (Design Principle 6).
  - `scope : "local" | "global"` — `local` ⇒ only local DuckDB judge reads sessions; `global` ⇒ consent to contribute a normalized, anonymized aggregate. **The differentiator — gated by attestation, k-anonymity, and DP (§7).**
  - `rubric_judge : "activity-fallback" | "rubric" | "witness"` — maps to `score.sql`'s `rubric_band` input; `rubric` requires `identity.rubric`. **Judge provenance is recorded per band** and constrains global pooling (§7).
  - `baseline_min : int | None` — override for the Layer-B lift gate.

### CapabilityPlan — projection (ephemeral, per-session)
- **Purpose:** Computed-at-don view of what the donned persona is *requesting* from the host: per binding, `{status: applied|unresolved-server|unresolved-credential|disabled, effective_allow, effective_deny}`. Discarded at doff.
- **Ownership:** Nothing persistent. Built by the domain core from McpBindings + a host-capabilities snapshot; surfaced in `/id`, `inspect`, and the `<masque-active>` block.
- **Key field — `host_apply : "none" | "config-write" | "hook"` — honesty about enforcement, wired into the security vocabulary itself:**
  - `host_apply == "none"` ⇒ the plan is **advisory** (injected as prose; the model is *asked* to honor allow/deny). In this tier the model **does NOT use the words "least-privilege" or "sandbox"**: `/id` and `inspect` render the scope as `advisory`, and explicitly warn that **a credential resolved into an MCP server is reachable by every tool of that server regardless of allow/deny** (the confused-deputy reality, `Capability-based sandboxes` §36). A user must not bind a live secret believing an advisory allow-list confines it.
  - `host_apply ∈ {"config-write", "hook"}` ⇒ a session-scoped `.mcp.json` overlay or a `PreToolUse` hook actually *mediates* the tool boundary. Only here are `allow/deny` true capability scoping and `scope` genuinely **least-privilege**.
  - The **active tier is surfaced live** in `/id` and `inspect` so a live secret is never over-trusted under an advisory binding. Which tier is achievable is host-dependent and a **blocking open question** (§8 OQ1).

### Measurement entities — Session · Score · Event · Band · Lift · TaskClass
See §7. These preserve the current `sessions.sql`/`score.sql` two-layer model; the data-model additions are the version + identity-hash attribution keys, the sidecar-join fallback, judge-provenance tagging, and the contribution-integrity boundary.

---

## 3. On-Disk / Storage Layout

```
~/.masques/                              (private; ${MASQUES_HOME}, NOT git-tracked)
├── manifest.yaml                        local-only listing cache (/sync-manifest)
├── codesmith.masque.yaml                IDENTITY — pinned, validated vs masque.schema.yaml      [local]
├── codesmith.persona.yaml               CONFIG sidecar — bindings + policy (ALWAYS private)      [local]
└── codesmith.team.yaml                  team composition (TUI)                                   [local]

masques/                                 (plugin repo; ${CLAUDE_PLUGIN_ROOT})
├── personas/
│   ├── manifest.yaml                                                                       [GIT-TRACKED]
│   ├── codesmith.masque.yaml            IDENTITY — bundled, pinned                          [GIT-TRACKED]
│   └── *.masque.yaml                    (sidecars NOT shipped — config is per-user/local)
├── schemas/
│   ├── masque.schema.yaml               UNCHANGED                                           [GIT-TRACKED]
│   └── persona-config.schema.yaml       NEW — validates sidecar; rejects inline secrets &
│                                              free-form config strings; enforces alias↔audience [GIT-TRACKED]
└── services/
    ├── collector/data/logs.jsonl        EVENTS — append-only OTLP write model (local sink)  [LOCAL ONLY, gitignored]
    ├── collector/data/sessions.attribution.jsonl  RETAINED — read-time fallback for pre-cutover logs [LOCAL]
    └── judge/                           sessions.sql, score.sql + NEW localreport.sql       [GIT-TRACKED]

OS keychain / env / Vault / cloud STS    SECRET MATERIAL                                     [NEVER STORED in repo or ~/.masques]
process memory (running MCP server)      ResolvedSecret cache                                [NEVER SERIALIZED]
remote ClickHouse (opt-in, Tier-3)       GlobalReport aggregate (post-attestation/k-anon/DP)  [REMOTE, opt-in only]
```

**Resolution.** `core.resolve()` reads the identity file (the existing `_parse_masque_file` seam) and, if present, the sidecar, composing the in-memory `Persona`. A **private sidecar may bind a shared identity** — sidecar resolution is independent of identity source: *identity uses private-over-shared as today; the sidecar is always looked up at `<private_dir>/<name>.persona.yaml`*. Because identity and config sources can differ, the Persona carries **both** `identity_source` and `config_source`, and credential-bearing sidecars are **always treated as private** for git-tracking and privacy posture.

**Tracked vs local vs never-stored:**
- **Git-tracked:** bundled identities, schemas, judge SQL, collector config. All references only.
- **Local-only:** private identities, **all sidecars**, manifests, event log, attribution-fallback map, DuckDB projections, LocalReport.
- **Never stored anywhere:** secret bytes (behind `SecretPort`), the ResolvedSecret cache (process memory, zeroed on doff). The session mirror records `bound_refs` (alias + scheme + status) but **never material**.

`Polyglot persistence` (§20) is deliberately avoided for the core: YAML files only. DuckDB/ClickHouse remain optional projection stores.

---

## 4. Identity vs Configuration

| | **Identity** (`<name>.masque.yaml`) | **Config** (`<name>.persona.yaml`) |
|---|---|---|
| Mutability | Immutable; edit = new Version | Hot-mutable; edit freely |
| Versioning | Semver, pinned, **content-addressed selector** (§4/§5) | `schema_version` (format only), `etag` optimistic lock (§13) |
| Lifecycle | `Schema-on-write` (§5) | `Dynamic / hot-reload configuration` (§29) |
| Contents | lens, context, attributes, rubric, spinnerVerbs | credentials, mcp, measurement |
| Shipped? | Bundled ones are git-tracked | **Never shipped — per-user, local, always private** |
| On change | Re-don to adopt | Takes effect on next resolve, no version bump |

**How they bind.** `resolve(name)` produces a `Persona` = `Identity` (from the masque file) + `PersonaConfig` (from the sidecar, or empty). `Persona.ref` pins `(name, identity.version)`. The sidecar's `persona:` back-reference must match `identity.name` or the sidecar is ignored. The two files are bound by **co-location and name**, not by a foreign key in the immutable file — so the identity stays byte-stable across any number of config edits. **Capability changes are config changes, and config is never under the version pin.**

**Source/privacy resolution.** `source` is split into `identity_source` and `config_source` precisely because a private sidecar can override a shared identity. The git-tracking/privacy posture is **never inferred from a single ambiguous field**: any persona carrying a sidecar is private with respect to its bindings.

---

## 5. Separation of Concerns (evolved CLAUDE.md table)

CLAUDE.md held "Masques own cognitive identity — nothing else." It is preserved by sharpening **what "own" means**: the Persona owns the *binding and scope (the reference + policy)*; the underlying material/tools/storage stay with the adapters.

| Need | Persona OWNS (binding / scope — the reference) | Adapter OWNS (material / impl / storage) |
|------|-----------------------------------------------|------------------------------------------|
| Identity & framing | lens + context + attributes + rubric (the Identity value-object) | — (the masque IS the identity) |
| Credentials | `CredentialBinding`: alias → `SecretRef` URI + scope + rotate/ttl | **SecretPort** (keychain/env/Vault/STS) holds & mints the bytes |
| MCP / tools | `McpBinding`: server id + enabled + allow/deny + uses_credentials | **McpPort** / host `.mcp.json` — server definition + tool implementations |
| Knowledge lookup | declares need via an MCP binding | MCP servers |
| Measurement | `MeasurementPolicy`: opt-in + local/global scope + judge choice | **TelemetryPort** — collector / DuckDB / ClickHouse hold signals & reports |
| Performance tracking | declares interest (policy) | Observability (OTEL) |

**The hexagonal cut** (`Hexagonal / Ports & Adapters`, §19): the domain core (`core.py`) depends only on the abstract `SecretPort`, `McpPort`, `TelemetryPort` interfaces — never on keychain/Vault/host/DuckDB concretes. So the core "depends on nothing," and **don composes Identity (+ optional config) with ZERO adapter calls.** Adapters are touched only on demand (a tool needs a secret; a host applies a plan; the judge runs) and degrade gracefully, mirroring `score()`'s existing `{"status": "unavailable"}` pattern. No vault, no MCP server, and no telemetry is ever required to don a persona — local-first preserved.

**Enforcement caveat (Design Principle 5 honesty):** "slaps on top of any agent" is true for *identity*. For *capability scoping*, an advisory plan (`host_apply == "none"`) mediates nothing at the tool boundary — it is a request to a cooperative model, not a sandbox. The security vocabulary in §2 and §8 is tied to the `host_apply` tier, not asserted unconditionally.

---

## 6. Migration Path

**Existing `*.masque.yaml` files load 100% unchanged.** Every additive change uses optional fields with defaults (`Schema evolution rules`, §5 — forward/backward compatible).

1. **`Masque` → `Identity` + `Persona`, with an explicit field move.** `Identity = current Masque MINUS {source, path}`; `Persona OWNS {identity_source, config_source, path}`. `resolve()` returns a `Persona`; `persona.identity` is the drop-in for identity-only callers. **Two call sites must change** (verified against core.py): `compose()` returns `"source": masque.source` (core.py line 229) → `persona.identity_source`; `inspect()` returns `"source"`/`"path"` (core.py lines 281-282) → `persona.identity_source` / `persona.path`. `list_masques()` is **unaffected** — it derives `source` from the `search_paths()` loop variable, not the dataclass. `name/version/lens/context/attributes/rubric/spinner_verbs` resolve off `persona.identity`.
2. **Sidecar is purely additive.** No sidecar ⇒ `config = None` ⇒ empty bindings, `measurement.enabled = false`. The 30+ bundled personas keep working with zero edits.
3. **New schema `persona-config.schema.yaml`** validates sidecars independently; `masque.schema.yaml` is untouched. Defense-in-depth: the schema **rejects any inline `value:`/`secret:` key** under credentials AND **rejects free-form / credential-bearing strings in `McpBinding.config`** (closed allowlist of typed non-secret keys only).
4. **Measurement attribution is a FORWARD-ONLY cutover, not expand-contract.** New events carry `persona.id`/`persona.version`/`persona.identity_hash`. Historical events were written without these attributes and **cannot be backfilled by replay** (events are immutable). So the existing sidecar-join attribution path (`sessions.attribution.jsonl` → `attribution` table → `session_attr` LEFT JOIN, sessions.sql lines 109-117) is **RETAINED as a read-time fallback**, not killed: attribution resolves as `COALESCE(event-carried persona.id, sidecar-joined masque)`. This is `Parallel change` over the *event schema*; there is no contraction of historical data, so the design does **not** claim "no replay break." Version-level lift cohorts only work once the host actually emits the new OTLP attributes on don (§8 OQ1a).
5. **`session.py` gains NEW capabilities (current doff only sets `_active=None` + `_mirror()`).** Adds an in-process `credential_cache` (never mirrored) and `bound_refs` (alias+scheme+status, safe to mirror). `doff()` additionally **zeroes the cache** and, **for `rotate: dynamic` schemes only**, calls `SecretPort.revoke`. For `static keychain://`/`env://` there is nothing to revoke — the material lives in the keychain/env by definition; doff only zeroes the in-process copy. The design does **not** imply doff withdraws ambient static secrets.

---

## 7. Measurement Data Model

Event-sourced CQRS (`Event sourcing` + `CQRS`, §20): the append-only OTLP JSONL log is the **only write model**; everything else is a fold, rebuildable by replay (`Materialized view / Read model / Projection`, §20). The existing two-layer judge is preserved verbatim — Layer A 7-band house reaction, Layer B lift vs the user's own baseline corpus per `task_class`, attribution clean/mixed/baseline.

**Honest framing of what is measured.** Layer-A activity bands derive from `0.35·s_success + 0.20·s_throughput + 0.20·s_cost + 0.25·s_friction` (score.sql line 57) — **all agent-controllable behaviors**, not outcomes. A persona doing many trivial Reads and few Edits scores near-perfect while accomplishing little. Therefore **activity-fallback bands are an "activity-shape distribution," never a reputation/quality signal**, and are **excluded from any global reputation aggregate** (see GlobalReport). Layer-B lift is the only quality-adjacent signal, and even it is narrow (below).

- **Event** *(event — write model):* the raw OTLP logRecord (`event_type`, `event_time`, `attributes`). New events carry three LOW-cardinality persona attributes: `persona.id`, `persona.version`, `persona.identity_hash`. `session.id`/`user_id`/`machine_id` stay in the HIGH-cardinality body, never metric labels (`Cardinality`, `Structured / wide events`, §27). **How identity reaches host-emitted events is host-dependent and a blocking open question (§8 OQ1a)** — until confirmed, the sidecar-join fallback (§6.4) is authoritative.
- **Session** *(projection):* one row per `session.id` — the existing `sessions` table, with `masque → persona_id` plus `persona_version`, `persona_identity_hash`, resolved via `COALESCE(event-carried, sidecar-joined)`. **Attribution under mixed schemas:** a session with ANY un-attributed events during the transition is classed **conservatively** — `n_masques` counts distinct attributed personas, and any ambiguity (some events attributed, some not) is treated as **non-clean and excluded from lift**, never silently `baseline` (matching the judge's existing bias against misleading numbers). `task_class` still reads only tool-mix.
- **Score** *(projection):* the two-layer verdict for one session — `score.sql` output unchanged. `Band` (7-point ordinal) and `Lift` are immutable value-objects. **Lift is precisely `failed_tool_call_lift`** — the only metric `score.sql` computes (`(base_fail - masque_fail)/base_fail`, line 112). It is named `failed_tool_call_lift_pct` **everywhere, including GlobalReport** — no general-quality claim is made. **Guard against "lift by doing less":** positive lift is suppressed when the persona's total tool count or change-share is materially below the baseline cohort's, so a persona cannot show lift merely by being timid. `Lift.status ∈ {shown, not_yet, n/a, excluded}` never emits a misleading number.
- **LocalReport** *(read-model, LOCAL ONLY):* per-machine reputation. **Keyed on `(persona_identity_hash, task_class)`** (carrying `persona_id`/`persona_version` as display labels) so a masque rename does not fork local reputation — aligning the local and global key (`Natural vs surrogate key` §4 fragility, resolved). Holds `band_histogram` (with **judge provenance per band**), `failed_tool_call_lift_summary` vs this user's own baseline, cohort sizes, freshness. **What `/performance` shows. Never leaves the machine.**
- **GlobalReport** *(read-model, remote, opt-in):* pooled reputation keyed by `persona_identity_hash` (`Content addressing`, §4 — only byte-identical pinned identities pool; a forked lens hashes differently). Carries `persona_id`/`persona_version` as a display label. Holds `pooled_failed_tool_call_lift` (distribution of per-machine **within-user deltas** — pooling deltas avoids cross-user baseline incomparability) and `pooled_band_distribution`. Constraints:
  - **Activity-fallback bands are EXCLUDED** from the global distribution (they measure activity hygiene, not value). **Judge type is part of the global aggregation key** — bands are never merged across judge types.
  - **Self-authored rubric bands are EXCLUDED** until the OQ7 normalization contract exists (a persona grading its own homework with a prompt it wrote must not flow into a cross-author aggregate). Only `witness`/independently-judged bands (post-normalization) are eligible.
  - Published only above a `k_min` floor, **with differential-privacy noise** on lift/band counts, and **only for non-private (bundled) identity hashes** — a rare private persona's hash is a quasi-identifier (`Anonymization` — "anonymized is a frequent lie"; ZIP+gender+DOB re-identifies ~87%). Private-persona hashes are forbidden from global contribution, or require a much higher `k`.
  - **Contribution integrity:** `persona.identity_hash` is self-reported by the client; content-addressing proves two identities are byte-identical, **not** that the measured behavior actually ran under that identity. GlobalReport is therefore **advisory / non-authoritative — explicitly unsuitable for marketplace ranking until attestation exists.** The attestation path (signed sessions, server-side recomputation of bands/lift from anonymized raw signals rather than client-submitted scores, per-contributor rate-limiting + outlier detection, and a sybil plan since one `machine_id` can mint unlimited within-user deltas) is specified as a precondition for any authoritative use (§8 OQ9). Without it, `pooled_lift` can be poisoned by a single motivated contributor — stated, not hidden.

**The local→global boundary (privacy spine).** Raw Events and Layer-A Scores are machine-local (the collector's only default sink is local JSONL; `score()` is documented `local_only`). Only a **derived, k-anonymized, DP-noised, judge-typed, attested aggregate** — per-`(persona_identity_hash, task_class)` within-user lift deltas + eligible band counts, with **no session_id / user_id / machine_id / prompt / code** — is eligible to leave, and **only when `MeasurementPolicy.scope == "global"`**. The remote ClickHouse exporter stays commented/Tier-3 — never required.

**Attribution & comparability.** Lift cohorts key on `(persona_id, persona_version)`, never name alone, so a v1.1→v1.2 upgrade does not silently pool different identities. **`task_class` comparability is an explicit, testable assumption, not a given:** it is derived from tool-mix thresholds (sessions.sql) that are codebase/workflow-dependent, and one signal (`fail_rate`) feeds **both** the `debug` classifier AND the lift metric — a circularity where reducing failures can shift a session out of its cohort. Mitigations: (1) document `task_class` as a heuristic stratum with known instability; (2) decouple the lift metric from any `task_class`-deriving signal, or compute lift within a `task_class` definition independent of the lift metric; (3) before publishing a pooled global row, show baseline `fail_rate` variance across machines per `task_class` as a comparability check. Mixed-attribution sessions remain excluded from lift. An optional `lineage` rollup across versions of one name is for trend *display* only; the authoritative cohort stays per pinned version.

**Canonical encoding for `persona_identity_hash` (pinned, not deferred).** `identity_hash = sha256` over a **canonical-JSON** of the fixed field set `{name, version, lens, context, rubric}` with **sorted keys and normalized line-endings (LF)** (`Canonical / deterministic encoding`, §5 — "most default serializers are NOT deterministic (map ordering!)"). Computed **lazily, only when `MeasurementPolicy.scope == "global"`**, so the default don path is unaffected.

---

## 8. Open Questions (deduped, ranked)

1. **(Blocking, host-dependent) Host integration seam — covers BOTH enforcement and attribution emission.**
   - **(1a) Attribution emission.** How does `persona.id/version/identity_hash` reach *host-emitted* events (`claude_code.tool_result`, `api_request`)? Options: a plugin-owned `SessionStart`/`PreToolUse` hook that writes the attribution record, or an OTEL resource attribute the plugin sets. **Until verified against real host instrumentation, the sidecar-join fallback (§6.4) is authoritative and version-level lift cohorts are not claimed.**
   - **(1b) Enforcement.** Does Claude Code expose a session-scoped `enabledMcpjsonServers`/`.mcp.json` overlay `don` can write, or a `PreToolUse` hook that blocks denied tools, or neither? `CapabilityPlan.host_apply` strength — and whether allow/deny is enforced vs advisory — depends entirely on this. Must be verified against the real host, not assumed.

2. **k-anonymity floor, DP epsilon, and private-persona policy for GlobalReport.** Choose `k_min`, the DP noise epsilon, and the higher `k` (or outright ban) for non-bundled hashes. State residual re-identification risk explicitly.

3. **Tool namespace for allow/deny globs.** Confirm fully-qualified (`mcp__discord__discord_send_message`) vs short (`discord_send_message`) names, and whether `server:` is an implicit prefix.

4. **STS doff revocation.** STS tokens are not revocable; design relies on short TTL + cache zeroing. Confirm acceptable, or **require `ttl` when `rotate: dynamic`** for the `sts://` scheme.

5. **Credential ref scheme registry at launch.** Which `SecretPort` schemes ship v1 (`env://`, `keychain://` on macOS) and how the resolver degrades on Linux/CI where Keychain is absent (fall back to `env://`? fail with a clear `bound_refs` status?).

6. **Rubric normalization for the global pool.** Define the normalization contract that makes self-authored Layer-A rubric bands comparable across authors — a **precondition** for any global rubric contribution, not a deferred nicety.

7. **Concurrent sidecar writes.** TUI + plugin both writing `<name>.persona.yaml`: `etag` optimistic locking (§13) with last-write-wins fallback and a warning. Confirm acceptable for a single-user local file.

8. **`task_class` comparability validation.** Operationalize the cross-machine variance check and the lift/`task_class` decoupling described in §7 — what variance threshold blocks publishing a pooled row?

9. **Contribution attestation roadmap.** Sequence the signed-session / server-side recomputation / rate-limiting / sybil-resistance work that moves GlobalReport from advisory to authoritative. Until then, no marketplace ranking is built on it.

---

## Critique Resolutions

| # | Severity | Issue | Resolution in final model |
|---|----------|-------|---------------------------|
| 1 | **blocker** | Attribution mechanism unproven — design claimed it "replaces" the sidecar join, but host-emitted events have no established identity-tagging path. | §6.4 reframed as a **forward-only cutover**; the sidecar-join is **RETAINED as a read-time fallback** (`COALESCE`), not killed. Host emission of the new OTLP attributes is raised as **blocking OQ1a**. Expand-contract miscitation dropped — labeled `Parallel change` over event *schema*, with no "no replay break" claim. |
| 2 | **blocker** | Layer-A bands are self-gameable activity hygiene, pooled globally as "reputation." | §7: activity-fallback bands are an **"activity-shape distribution," EXCLUDED from global reputation aggregates**; judge type is part of the global key; only outcome-based (witness/normalized-rubric) bands are eligible. |
| 3 | **blocker** | Global reputation spoofable — `identity_hash` is self-reported; nothing binds measured behavior to claimed identity. | §7: GlobalReport declared **advisory / non-authoritative, unsuitable for marketplace ranking until attestation exists**. Attestation mechanism (signed sessions, server-side recomputation, rate-limiting/outlier detection, sybil plan) specified; poisoning risk stated. OQ9 added. |
| 4 | **major** | `McpBinding.config` free-form dict is a plaintext-secret hole; heuristic detection is weak. | §2/§3/§6: `config` constrained to a **closed, schema-allowlisted set of typed non-secret keys (bool/int/enum)**; arbitrary/credential-bearing strings rejected by schema; all secrets route through `uses_credentials → SecretRef`. Structural fix, not heuristic. |
| 5 | **major** | Security vocabulary ("least-privilege"/"sandbox") used even when enforcement is advisory. | §2 CapabilityPlan + §5: vocabulary **tied to `host_apply` tier**. `none` ⇒ rendered `advisory` with an explicit "all tools of the server can reach the credential" warning; "least-privilege"/"sandbox" reserved for `hook`/`config-write`. Active tier surfaced in `/id`/`inspect`. |
| 6 | **major** | "Lift" presented as general quality, but is a single `lift_fail_pct` and itself gameable (be timid). | §7: renamed **`failed_tool_call_lift` everywhere incl. GlobalReport**; added a **"lift by doing less" guard** (suppress when tool count / change-share materially below baseline). No general-quality claim. |
| 7 | **major** | `Identity` claimed "unchanged" but `Masque` carries `source`/`path` that move to `Persona`; two call sites read them. | §2/§6: stated explicitly — **`Identity = Masque MINUS {source, path}`; Persona owns `{identity_source, config_source, path}`**. Named the two sites to change (`compose()` line 229, `inspect()` lines 281-282) and noted `list_masques()` is unaffected. |
| 8 | **major** | Aggregate boundary conflated in-aggregate invariant (alias↔audience) with cross-aggregate refs. | §2 PersonaConfig/McpBinding: **alias↔audience is an in-aggregate invariant enforced on WRITE** (schema + load-time; sidecar rejected on violation). Cross-aggregate refs (server in host, secret resolvable) are **not invariants** and degrade to `unresolved`. |
| 9 | **major** | `task_class` comparability across machines assumed; `fail_rate` feeds both classifier and lift (circularity). | §7: comparability made an **explicit testable assumption** with a pre-publish variance check; lift decoupled from `task_class`-deriving signals; `task_class` documented as an unstable heuristic stratum. OQ8 added. |
| 10 | **major** | Global band distribution silently mixes incommensurable judge types. | §7: **judge type is part of the global aggregation key**; bands never merged across judge types; self-authored rubric bands excluded pending OQ6 normalization. |
| 11 | **major** | Quasi-identifier re-identification of rare/private personas ignored. | §7: private (non-bundled) `identity_hash` treated as a **quasi-identifier — forbidden from global contribution (or higher `k`)**; **DP noise** added to pooled lift/band counts; residual risk stated. OQ2 expanded. |
| 12 | **minor** | `persona_identity_hash` canonical encoding left as an open question. | §7: **pinned** — `sha256` over canonical-JSON of `{name, version, lens, context, rubric}`, sorted keys, LF-normalized; computed lazily only for `scope == global`. |
| 13 | **minor** | Private sidecar over shared identity makes the pinned identity an incomplete description; auditability gap. | §2/§3/§4: `Persona` carries **both `identity_source` and `config_source`**; "identity: shared, config: private" is a distinct flagged state; `/id`/`inspect` show source-of-config alongside source-of-identity; `bound_refs` surfaces it. |
| 14 | **minor** | Engineering-reference miscitations (§30 vs §49; §13 applied to immutable Version). | §2: "Short-lived credentials & rotation" cited as **§49 Workload Identity**; **§13 reserved for the sidecar `etag` only**; identity Version cited as **content-addressed/pinned selector (§4/§5)**. |
| 15 | **minor** | Doff "calls SecretPort.revoke" overstated; not current behavior and scheme-dependent. | §6.5: framed as a **NEW** capability; revocation **scheme-dependent** — static `keychain://`/`env://` only zero the in-process cache; only `rotate: dynamic` gets real revocation. Doff does not withdraw ambient static secrets. |
| 16 | **minor** | LocalReport name-keyed while GlobalReport hash-keyed → rename forks local but not global. | §7: **LocalReport re-keyed on `(persona_identity_hash, task_class)`** (name/version as display labels), aligning local and global so a rename does not fork local reputation. |
| 17 | **minor** | Self-authored rubric bands flow into the same surface as independent bands. | §7: **every pooled band tagged with judge provenance**; self-authored-rubric bands never enter a cross-author aggregate; OQ6 normalization is a precondition for global rubric contribution. |
| 18 | **minor** | Mixed-schema attribution continuity (clean/mixed) during transition unspecified. | §7 Session: sessions with **any un-attributed events are classed conservatively** (non-clean, excluded from lift, never silently baseline); a parity test (sidecar-derived vs attribute-carried) is required before cutover. |

**Files grounding this design:** `/Users/chris/git/masques/services/mcp/src/masques_mcp/core.py` (`Masque` dataclass lines 97-110 → `Identity`/`Persona`; affected sites `compose()` line 229, `inspect()` lines 281-282), `/Users/chris/git/masques/services/mcp/src/masques_mcp/session.py` (session extension — doff currently only `_active=None` + `_mirror()`), `/Users/chris/git/masques/schemas/masque.schema.yaml` (unchanged; new sibling `persona-config.schema.yaml`), `/Users/chris/git/masques/services/judge/sessions.sql` (attribution LEFT JOIN lines 109-117 retained as fallback; new attribution keys) and `/Users/chris/git/masques/services/judge/score.sql` (single `lift_fail_pct` line 112 → `failed_tool_call_lift`; activity composite line 57; new `localreport.sql`).