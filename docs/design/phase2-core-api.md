# Phase 2 — Core API & Control-Flow Specification

> **Status:** This is **Phase 2 of 3** (Core API) of the Masques→Personas evolution, produced by the **persona-core-api workflow** (4 designers → synthesis → 3 critics → finalize). It builds on the **FINALIZED, AUTHORITATIVE Phase 1 data model** (`docs/design/phase1-data-model.md`) and introduces **no data-model changes** — every Phase 1 entity (Persona, Identity, PersonaConfig, CredentialBinding/SecretRef, McpBinding/ClosedConfig, MeasurementPolicy, CapabilityPlan, the SecretPort/McpPort/TelemetryPort boundary, the event-sourced Session/Score/Event/LocalReport/GlobalReport spine) is reused verbatim. This document specifies the function-level API and control flow only; it is a spec, not code, and it evolves the real `core.py`/`session.py`/`server.py`/`cli.py` seams rather than greenfielding them.

**Synthesis decisions (conflicts resolved up front):**
- **Host snapshot is INJECTED, not fetched by the core.** Phase 1 §2 says the CapabilityPlan is "built by the domain core from McpBindings **+ a host-capabilities snapshot**." `build_capability_plan(persona, host_caps)` is a **pure fold**; the single read-only `McpPort.host_snapshot()` call is made by the session-lifecycle `don()` (the composition seam), which passes the snapshot in. `core.compose()`/`core.inspect()` stay pure.
- **The on-demand credential function is `resolve_credential(alias, audience)`** (canonical name; "resolve_secret" is an alias for the same op). It lives in the **session layer** (it needs the live `credential_cache` + donned scope) and is the ONLY path that calls `SecretPort.resolve`.
- **Registry injection: explicit `register(kind, adapter)` at the composition root** (`server.main()` / `cli.main()`), with built-in degrading defaults returned when nothing is registered. `core.py`/`session.py` import only the `ports` module (Protocols + `get_port`), never a concrete adapter.
- **The local→global boundary is a single gate inside `core.report()`** — and `TelemetryPort.contribute` is made structurally unreachable except through that gate (see §6 / Critique Resolutions).

---

## 1. API Surface Map

```
 SURFACES (thin pass-throughs)        CORE FUNCTIONS (pure unless noted)      PORTS (Protocols)        ADAPTERS (edge)
 ──────────────────────────────       ─────────────────────────────────      ─────────────────        ─────────────────

 MCP tool  list_masques ───────────▶  core.list_masques() ◄═ PURE             —                        —
 /list · masque://catalog

 MCP tool  inspect_masque ──────────▶  core.inspect(name) ◄═ PURE             — (NO port; advisory      —
 /inspect · masque://{name}              └▶ resolve(name)->Persona ◄═ PURE      status from sidecar
                                          └▶ build_capability_plan(p, None)     state alone)

 MCP tool  id (NEW) ────────────────▶  session.active() ◄═ PURE (in-mem read) —                        —
 /id  (now shells: masques-cli id)

 MCP tool  don(name,intent) ────────▶  session.don(ref,intent) ── ADAPTER:    McpPort.host_snapshot()  AdvisoryMcp(default)/
 /don                                    └▶ (swap path) outgoing.doff() first   (1 read-only probe,      ConfigWrite/Hook
                                          └▶ core.resolve ◄═ PURE                 degrades→tier 'none')
                                          └▶ core.compose ◄═ PURE                ── NO SecretPort here
                                          └▶ core.build_capability_plan ◄═ PURE  ── on a FRESH don,
                                          └▶ records session, _mirror() ◄═ PURE     ZERO adapter calls

 (a tool needs a secret) ───────────▶  session.resolve_credential ── ADAPTER: SecretPort.resolve()     Keychain(default)/Env/
                                          (lazy, on first use ONLY)                                      Vault/STS/NullSecret

 MCP tool  doff() ──────────────────▶  session.doff() ── ADAPTER (cond.):     SecretPort.revoke()      Vault/STS (dynamic only;
 /doff                                    revoke ONLY rotate:dynamic; zero      McpPort.teardown()       Keychain/Env=noop)
                                          cache always; _mirror() ◄═ PURE       (config-write/hook only)

 MCP tool  capability_plan(name?) ──▶  session.active()+build_capability_plan  McpPort.host_snapshot()  AdvisoryMcp/ConfigWrite/Hook
 (NEW, read-only)                        ── ADAPTER (read-only; degrades)        (optional)

 MCP tool  score(session?) ─────────▶  core.score(session) ── ADAPTER         TelemetryPort.score()    LocalJudge(judge.sh+DuckDB)
 /performance (raw path)                                                                                / NullTelemetry

 MCP tool  report(scope) (NEW) ─────▶  core.report(ref,scope) ── ADAPTER      TelemetryPort.report()   LocalJudge(localreport.sql)
 /performance (read-model)               ║ scope=='global' ⇒ SINGLE GATE       (no public contribute)   / ClickHouse(opt-in,Tier-3)
                                          ║ (k-anon+DP+attest+scope) IN CORE

 CLI: cmd_list/cmd_inspect/cmd_compose/cmd_score + NEW cmd_id/cmd_capability/cmd_report → same core/session functions (1:1)
 CLI WRITE (not an MCP tool): cmd_bind_credential / cmd_toggle_mcp → session.write_sidecar() (etag CAS, no port)
```

`◄═ PURE` = zero adapter calls. A **fresh `don()` from baseline touches ZERO adapters**; a `don()` that *swaps over* an already-active persona first runs that persona's `doff()` teardown (which may call `McpPort.teardown()` / `SecretPort.revoke()` — attributed to the outgoing doff, not the fresh don). The only port a fresh `don()` may touch is the single read-only `McpPort.host_snapshot()`, and only when the persona has McpBindings; it degrades to tier `none`. **No SecretPort call ever happens on a fresh don** (`bound_refs` are seeded from static sidecar fields with no probe — see Critique Resolutions B1). `/sync-manifest` and `/audience` are unchanged. `masque://catalog` and `masque://{name}` map to `list_masques`/`inspect` and inherit additive keys only.

---

## 2. Core Operations

Each function: signature · purpose · inputs · returns (Phase 1 entities) · errors/degradation · ports · control-flow.

### Type shapes (the Masque→Identity+Persona refactor)
- `Identity` = current `Masque` **MINUS `{source, path}`** (Phase 1 §2/§6): `{name, version: Version, lens, context, attributes, rubric, spinner_verbs, raw}`; properties `domain/tagline/has_rubric` preserved; `identity_hash` lazy (computed only when `MeasurementPolicy.scope=='global'`).
- `Persona` (aggregate root) = `{identity: Identity, ref: PersonaRef, config: PersonaConfig|None, identity_source, config_source, path}`. **`Persona` OWNS `{identity_source, config_source, path}`** (the fields lifted off Masque).
- **`Persona` is a strict drop-in for the old `Masque` attribute surface** (Critique Resolutions B2): it exposes **read-through properties** `name/version/lens/context/attributes/rubric/has_rubric/spinner_verbs` that delegate to `self.identity`, **plus a `source` property that aliases `identity_source`** (`source` is a RENAME, so the alias is load-bearing). This makes `persona.source`, `persona.has_rubric`, `persona.lens` etc. resolve exactly as `masque.*` did, so the existing `test_core.py` contract (which reads `m.source`/`m.has_rubric`/`m.lens`/`m.name`/`m.version` directly off the `resolve()` return) passes unchanged. `persona.identity` remains the explicit drop-in for identity-only callers.
- `PersonaRef` (value-object) = `{name, version: Version}`. A **content-addressed/pinned selector** (`Content addressing` §258), NOT an optimistic-lock token — only the sidecar `etag` is the CAS token.
- `Version` (value-object) = `{major, minor, patch, raw}` with `Version.parse(s)` preserving `raw`. **Version string contract (Critique Resolutions B1-version):** `Version.__str__` returns `raw`; `Version.__eq__` compares against a `str` by `raw` (so `m.version == "9.9.9"` stays True). **Every output-facing reader emits `persona.identity.version.raw` (a `str`), never the `Version` object** — `build_identity_block` (core.py:206), `compose` (core.py:228), `inspect` (core.py:280), `list_masques` (core.py:265). The `Version` object stays internal to attribution/cohort logic and **must never reach `yaml.safe_dump`/`json.dumps` in cli.py** (cli.py:30/32/58). A serialization/parity regression test is an acceptance gate.

### `resolve(name: str) -> Persona`  *(evolves core.py:160)*  — PURE
- **Purpose:** Load the pinned **Identity** and, if present, the **PersonaConfig** sidecar, composing them into the **Persona** aggregate. Drop-in for today's `resolve()->Masque`.
- **Inputs:** `name` — case-insensitive filename stem (strips trailing `.masque.yaml`, mirroring lines 168-170).
- **Returns:** `Persona`.
- **Errors/degradation:** `MasqueNotFoundError` (unchanged message/behavior); `MasqueParseError` on malformed identity (unchanged). **A malformed/invalid sidecar DEGRADES, it does not deny the don** (decision, resolving OQ4 — Critique Resolutions M-sidecar): when `<name>.persona.yaml` EXISTS but fails `persona-config.schema.yaml` or the `alias↔audience` in-aggregate invariant, `resolve()` returns `Persona` with **`config=None` plus a surfaced `config_error` warning** (`{path, reason, remediation}`) carried on the Persona and rendered prominently by `/id` and `inspect`. `bound_refs` is then `[]` and `capability_plan.host_apply='none'`. This keeps "every existing pinned identity still resolves" **literally** true even after a user hand-edits or a TUI write races a sidecar — local-first never blocks don over an OPTIONAL decorator. A sidecar whose `persona:` back-reference ≠ `identity.name` is **ignored** (`config=None`, no warning) per Phase 1 §4. A **missing** sidecar is the normal zero-binding path (`config=None`). `PersonaConfigError` is retained as a typed cause attached to the `config_error` warning, but is NOT raised out of `resolve()`.
- **Ports:** none. No secret resolved, no MCP server contacted, no telemetry read — local-first/zero-infra to don.
- **Control flow:** (1) normalize stem; (2) loop `search_paths()` private-then-shared, first matching `<stem>.masque.yaml` → `_parse_identity_file(path, source)`, capturing `identity`+`identity_source`+`path`; raise `MasqueNotFoundError` if none; (3) **always** look up sidecar at `private_dir()/<stem>.persona.yaml`, **source-independent** (a private sidecar may bind a shared identity — Phase 1 §3/§4); never look in `bundled_dir()`; (4) absent ⇒ `config=None, config_source=None`; (5) present ⇒ `_parse_persona_config(path, identity.name)`; back-ref mismatch ⇒ `config=None`; schema/invariant failure ⇒ `config=None` + `config_error` warning; success ⇒ `config_source='private'`; (6) `ref = PersonaRef(identity.name, identity.version)`; (7) return `Persona(...)`. Side-effect-free; the sidecar `etag` is read into `config` for later CAS writes.

### `_parse_identity_file(path, source) -> Identity`  *(renames core.py:125 `_parse_masque_file`)*  — PURE
- Loads+validates one identity YAML into an **Identity** value-object. The ONLY change vs today: no `source/path` embedded (they move to Persona); `version` built via `Version.parse(raw)` preserving `raw` (lenient — trust `masque.schema.yaml` pattern validation). `MasqueParseError` on non-mapping or missing `REQUIRED_FIELDS` — identical to lines 132-139. `masque.schema.yaml` UNCHANGED. The single `list_masques` call to this helper (core.py:260) updates to the new name.

### `_parse_persona_config(path, identity_name) -> tuple[PersonaConfig | None, ConfigError | None]`  *(NEW)*  — PURE
- Loads+validates the sidecar into **PersonaConfig** (`{persona, schema_version, etag, credentials: list[CredentialBinding], mcp: list[McpBinding], measurement: MeasurementPolicy}`). Returns `(None, None)` on back-ref mismatch (stray sidecar silently ignored). Returns `(None, ConfigError)` on schema failure (incl. any inline `value:`/`secret:` under credentials, any free-form string in `McpBinding.config` — closed typed-key allowlist only; Phase 1 §3/§6) **or** `alias↔audience` invariant violation (checkable from sidecar state alone). Parses references only (`SecretRef {scheme, locator, version?}`, server ids) — **never resolves them**. `measurement` defaults to `MeasurementPolicy(enabled=false)` when absent ⇒ absence of sidecar == local-first.

### `build_identity_block(persona: Persona | Identity, intent=None) -> str`  *(evolves core.py:200)*  — PURE
- Builds the exact `<masque-active>` string. Accepts a `Persona` (reads `.identity`) or a bare `Identity` via a tiny normalizer. Interpolates `version=persona.identity.version.raw` (the `str`, not the object) so the line-206 f-string stays byte-identical (`<masque-active name="Firekeeper" version="0.3.0">`). **Byte-identical output to today for any persona with no sidecar.** Does **not** inline credential/MCP material — bindings affect host wiring, not injected prose, keeping the block pinned.

### `compose(persona: Persona, intent=None, *, plan=None) -> dict`  *(evolves core.py:219)*  — PURE
- **Signature simplified (Critique Resolutions m-compose):** accepts ONLY a pre-built `plan` (a pure, already-folded `(CapabilityPlan, bound_refs)` value), NOT a raw `host_caps` snapshot. `compose` never needs the snapshot, only the folded plan — this removes the inconsistent-`(host_caps, plan)`-pair footgun and keeps `compose` a pure projection over already-captured values.
- **Returns** (additive keys vs today): `name/version/lens/context/attributes/spinnerVerbs` off `persona.identity` (`version` emitted as `.raw`); **`'source'` now = `persona.identity_source`** (the **line-229 change**, wire key still `"source"`); NEW `'config_source'` (null when no sidecar); NEW `'config_error'` (null unless a sidecar failed to parse); NEW optional `'capability_plan'` summary + `'bound_refs'` (present only when `plan` injected); `'identity_block'` from `build_identity_block(persona, intent)`. **Never any secret material — only `alias+scheme+status` references.** When `plan is None` the `capability_plan`/`bound_refs` keys are omitted (degrade-by-absence). `scope_label='advisory'` when `plan.host_apply=='none'`, `'least-privilege'` only when `host_apply ∈ {config-write, hook}` (Phase 1 §2/§5). Ports: none.

### `build_capability_plan(persona: Persona, host_caps: HostSnapshot | None) -> tuple[CapabilityPlan, list[BoundRef]]`  *(NEW, in core)*  — PURE
- **Pure fold** of `persona.config.mcp` against the injected `host_caps`. Returns the **CapabilityPlan** (Phase 1 §2: `{host_apply: none|config-write|hook, bindings: [{server, status: applied|unresolved-server|unresolved-credential|disabled, effective_allow, effective_deny, enforced: bool, tier}]}`) and the seeded `bound_refs` (one `{alias, scheme, status}` per `CredentialBinding`). **`bound_refs` is seeded purely from static `CredentialBinding` fields** — `alias` and `scheme` parsed from the `SecretRef`, `status='pending'` (or `'advisory'` at tier none) — with **NO SecretPort call** (Critique Resolutions B1). Per-binding `enforced`/`tier` are stamped from `host_apply`: at `host_apply=='none'` every binding is `enforced=false, tier='advisory'` (the honesty fields are carried in the DATA, not just the renderer — Critique Resolutions M-mirror). Never raises on cross-aggregate gaps: server absent from `host_caps` ⇒ `unresolved-server`; `host_apply` defaults to `'none'` when `host_caps is None`. **Calls no port** — the snapshot was captured by `don()` and passed in. This is the single place the security vocabulary is assigned per binding.

### `inspect(name: str) -> dict`  *(evolves core.py:275)*  — PURE (deterministically; NO port)
- **Deterministically pure (Critique Resolutions m-inspect):** `inspect()` **never calls a port**. It reports binding presence and advisory status from **sidecar state alone** via `build_capability_plan(persona, host_caps=None)` — so the same inputs always yield the same output with zero adapter dependence. The `applied` vs `unresolved-server` enrichment (which needs a live host snapshot) is the job of the `capability_plan(name)` read tool / the `active()` path, NOT `inspect`.
- **Returns:** `name/version/lens/context/attributes/rubric/has_rubric/spinnerVerbs` off `persona.identity` (`version` as `.raw`); **`'source'` = `persona.identity_source`** + **`'path'` = `str(persona.path)`** (the **lines 281-282 change**, wire keys still `"source"`/`"path"`); NEW `'config_source'`, `'has_config'`, `'config_error'`, `'measurement_policy'` (`{enabled, scope, rubric_judge}`), `'capability_plan'` summary (host_apply always `none` here, every binding `enforced:false, tier:advisory`), `'bound_refs'` (status `pending`/`advisory`). Propagates `resolve()`'s errors. No secret bytes — only `alias+scheme+status`.

### `list_masques() -> list[dict]`  *(core.py:244 — CONFIRMED UNAFFECTED)*  — PURE
- Identical entries (`name/version/domain/tagline/has_rubric/source/stem`). Derives `source` from the `search_paths()` loop variable (lines 251/269), **not the dataclass** — so the Masque→Identity move does not touch it. `version` emitted as `.raw`. Only internal change: the renamed parse helper. Optional additive `has_sidecar: bool` (cheap `private_dir()/<name>.persona.yaml` existence check) for `/list`. No call-site change required. Callers (`server.py:52/156/172`, `cli.cmd_list`, both resources) untouched.

### `score(session=None, *, timeout=180) -> dict`  *(core.py:315 — refactor-in-place)*  — ADAPTER (degrades)
- Becomes a one-line `get_port('telemetry').score(session, timeout=timeout)`. Today's subprocess body (lines 323-356) moves verbatim into `LocalJudgeAdapter.score()`. **Return shape byte-identical** (`{status:'ok', report, local_only:True}` / `{status:'unavailable', reason}`). `server.py` score tool (line 133) and `cli.cmd_score` unaffected. Stays LOCAL-ONLY.

### `report(ref: PersonaRef, *, scope='local') -> dict`  *(NEW)*  — ADAPTER (gated, degrades)
- **The read-model accessor behind `/performance`.** `scope='local'` ⇒ `TelemetryPort.report(ref, scope='local')` → **LocalReport** keyed `(persona_identity_hash, task_class)` (`{band_histogram` with judge provenance, `failed_tool_call_lift_summary`, `cohort_sizes`, `freshness`, `local_only:True}`). `scope='global'` ⇒ the **SINGLE local→global GATE** (§6). Degrades to `{status:'unavailable'}` when TelemetryPort off; `{status:'gated', reason}` when global preconditions fail. **`report(scope='local')` is a hard local-only contract on the Protocol** (Critique Resolutions m-localonly): every adapter, including `ClickHouseAdapter`, MUST serve `scope='local'` from the local mirror or return `{status:'unavailable'}` — never a remote read. The local guarantee is per-method, not per-registered-adapter.

---

## 3. Hexagonal Ports

All three are **Protocols** in a new `ports` module imported by the core (`Hexagonal / Ports & Adapters / Clean Architecture` §788; `Plugin / Microkernel` §818 — the three Protocol signatures are a frozen extension contract). The domain core (`core.py`, `session.py`) imports **only** `ports` (the Protocols + `get_port`), never a concrete adapter. `core.py` keeps importing only `os/subprocess/yaml/pathlib/dataclasses` — invariant preserved.

### SecretPort
```
resolve(ref: SecretRef, persona_ref: PersonaRef, *, scope: CredentialScope) -> ResolvedSecret
revoke(handle: SecretHandle) -> RevokeResult
capabilities() -> SecretCapabilities
```
- `resolve` returns a **ResolvedSecret** entity `{alias, scheme, status:'resolved', handle, expires_at?, material}` where `material` is **memory-only**, excluded from `__repr__`/`asdict`/mirror (Critique Resolutions B-secret). Degraded variants `{status:'unresolved-credential'|'scheme-unavailable'|'expired', material=None}` — **never raises for a resolvable-but-absent secret**. `persona_ref` namespaces the keychain locator (`masques/<persona>/<alias>`) and bounds resolvability to the donned persona; `scope.audience` lets the adapter refuse out-of-audience injection (`Principle of least privilege` §1336).
- `revoke` returns `{status:'revoked'|'noop'|'unavailable', reason?}`. Static `keychain://`/`env://` ⇒ `noop`. `sts://` ⇒ `noop` relying on TTL (OQ7). Vault unreachable ⇒ `unavailable` — **cache still zeroed locally**; revoke failure never blocks doff (`Short-lived credentials & rotation` §2213).
- `capabilities()` reports `{available_schemes, degradations}`. **Note (Critique Resolutions B1): `capabilities()` is NOT called on a fresh don** — `bound_refs` status comes from static sidecar fields. `capabilities()` is consulted lazily (first `resolve_credential` or an `/id`/`capability_plan` render), so a fresh don is truly zero-SecretPort.
- **Adapters:** `KeychainAdapter` (`keychain://`, macOS, default), `EnvAdapter` (`env://NAME`), `VaultAdapter` (`vault://path#field`, dynamic lease), `StsAdapter` (`sts://role-arn`, revoke=noop), `NullSecretAdapter` (every resolve → `scheme-unavailable`). **Degradation:** keychain absent (Linux/CI) ⇒ `capabilities()` advertises `{'keychain://':'env-fallback'}` or status `scheme-unavailable` (OQ6). No secret bytes in any returned dict, mirror, or git file — ever.

### McpPort
```
host_snapshot() -> HostSnapshot          # {servers: set[str], achievable_tier: 'none'|'config-write'|'hook'} — read-only
apply(plan: CapabilityPlan, snapshot) -> AppliedPlan   # on-demand only; advisory tier is a no-op
capabilities() -> McpCapabilities        # {max_tier, supports_disable} — static tier ceiling
teardown() -> None                       # remove session overlay/hook at doff (config-write/hook only)
```
- `host_snapshot()` is the **only port method a fresh `don()` may call** — read-only, degrades to `{servers: ∅, achievable_tier:'none'}` if host config unreadable.
- **`apply()` call site is explicit (Critique Resolutions M-apply):** `don()` calls `get_port('mcp').apply(plan, snapshot)` **only when `plan.host_apply != 'none'`** (i.e. only when the host genuinely mediates). This is an McpPort-only touch (no SecretPort), and it is what populates `AppliedPlan.per_binding[*].enforced`. **When `host_apply=='none'`, `apply()` is NOT called** — there is nothing to enforce — and surfaces derive `advisory` from the `host_apply` tier alone (the `enforced=false`/`tier=advisory` fields stamped by `build_capability_plan`). So the `enforced` bool only exists when something actually enforces; otherwise the data already says `advisory`.
- `apply()` returns `AppliedPlan {host_apply, per_binding:[{server, status, enforced:bool}], overlay_path?|hook_id?}`. Overlay/hook write failure **fails OPEN to advisory** (`Fallback / Graceful degradation` §968), never crashes don.
- **Adapters:** `AdvisoryMcpAdapter` (tier `none`, local-first default; `apply` is a no-op; injects prose, enforces nothing), `ConfigWriteMcpAdapter` (session-scoped `.mcp.json` overlay), `HookMcpAdapter` (PreToolUse block). **Until OQ1 is verified against the real host, `capabilities().max_tier` MUST be `'none'`** and all allow/deny is advisory.

### TelemetryPort
```
score(session=None, *, timeout=180) -> dict       # wraps existing judge.sh subprocess
report(ref: PersonaRef, *, scope='local') -> dict  # reads localreport.sql; machine-only; local is a hard contract
contribute(sealed: AttestedAggregate) -> None      # accepts ONLY a gate-sealed value-object (see §6 / B-gate)
capabilities() -> dict
```
- `score`/`report` return the `{status:'ok'|'unavailable', ...}` shape verbatim — telemetry is **never required to don** (Design Principle 6). `report(scope='local')` returns **ONLY machine-local data** (hard Protocol contract). **`contribute` is NOT freely callable (Critique Resolutions B-gate):** its sole argument is an `AttestedAggregate` sealed value-object whose constructor is **module-private to `core.report`'s gate** — no surface, CLI, or adapter can fabricate a valid argument, so the global path is structurally unreachable except through the gate. **Adapters:** `LocalJudgeAdapter` (judge.sh + DuckDB + localreport.sql, the only default sink), `ClickHouseAdapter` (remote, Tier-3, opt-in; its `report(scope='local')` serves local-mirror-or-unavailable, and its `contribute` re-asserts gate preconditions for defense-in-depth), `NullTelemetryAdapter` (`unavailable`).

### Registry / injection
```
ports.register(kind: 'secret'|'mcp'|'telemetry', adapter) -> None   # called ONLY at composition root
ports.get_port(kind) -> SecretPort | McpPort | TelemetryPort        # pure in-process dict lookup
```
- `register()` is invoked **only** in `server.main()` / `cli.main()` (and the TUI's startup) — never from core. `get_port()` returns the registered adapter **or a built-in local-first default** (`KeychainAdapter`+`EnvAdapter` for secret, `AdvisoryMcpAdapter` for mcp, `LocalJudgeAdapter` for telemetry) so the core always has a working, degrading port even with zero registration (`Dependency inversion` / Hexagonal §788). Unknown kind ⇒ `KeyError` (programmer error).
- **Threading / cross-session safety (Critique Resolutions m-threading):** the stdio server is single-process, so a module-level registry is correct. **However, `credential_cache` is bound to the active session record (a per-don object), NOT a bare module global** (§4), so moving to a request/session-scoped registry for a future hosted HTTP server (server.py Phase-B) is a registry-injection change, not a cache-relocation refactor. A loud `TODO` at the cache declaration states: no hosted transport may import `session.py` as-is without per-session scoping, to prevent cross-session secret bleed.

---

## 4. Session Lifecycle

`session.py` gains a **live session record** held in-process. **`credential_cache` lives OUTSIDE the mirrorable record** — a separate module-level `_credential_cache` keyed by the active `PersonaRef`, never a key on `_active`/`_previous` (Critique Resolutions B-secret). `bound_refs` (`alias+scheme+status`) and a `capability_plan` summary **are** safe to mirror.

### `_mirrorable_view(record) -> dict`  *(NEW, allowlist projection)* — PURE
- The mirror is built from an **explicit allowlist**, not a blocklist-by-omission. `_mirror()` serializes `_mirrorable_view(_active)`/`_mirrorable_view(_previous)` — naming exactly the keys `{ref, source, version, config_source, intent, donned_at, bound_refs, capability_plan_summary}` — instead of dumping `_active` wholesale. `_credential_cache` is **structurally unreachable** from this view. Belt-and-suspenders: `ResolvedSecret.material` is excluded from `__repr__`/`asdict`, and the mirror boundary asserts the serialized payload contains no `ResolvedSecret` instances. **Acceptance test:** populate the cache, trigger `_mirror`, grep the session file for `material` — must be absent.

### `don(ref: PersonaRef | str, intent=None) -> dict`  *(evolves session.don(name, source))*
> **Signature note (Critique Resolutions m-donsig):** the second positional parameter changes meaning (`source` → `intent`); `don` is therefore **NOT** source-compatible. The `server.py:90` call `session.don(masque.name, masque.source)` IS a required, enumerated change (see §7 table). The old 2-arg call does not silently keep working — the migration table updates it.

**Control flow (numbered):**
1. **Swap-first (Critique Resolutions M-swap):** if a persona is already active, run the **outgoing persona's `doff()` teardown FIRST** — this is where any `SecretPort.revoke` (for `rotate:dynamic` handles) and `McpPort.teardown()` live, attributed to a doff. The outgoing record rolls to `previous` with `bound_refs[*].status` flipped to `revoked` for any revoked dynamic lease (so `/id` never shows a live-looking ref for a dead lease). **A fresh don from baseline skips this step entirely and touches zero adapters.**
2. If `ref` is a `str` ⇒ `persona = core.resolve(ref)`; if a `PersonaRef` ⇒ resolve and assert the pinned `version` matches `persona.identity.version`.
3. `plan = (CapabilityPlan.empty(), [])` by default. **IF `persona.config` has McpBindings:** `snapshot = get_port('mcp').host_snapshot()` (the ONE read-only port touch on a fresh don; degrades to tier `none`); `plan, bound_refs = core.build_capability_plan(persona, snapshot)`. **ELSE** `plan, bound_refs = core.build_capability_plan(persona, None)` — no port touched at all. **No secret resolved.** `bound_refs` seeded from static sidecar fields (status `pending`/`advisory`), no `SecretPort.capabilities()` probe.
4. `payload = core.compose(persona, intent, plan=(plan, bound_refs))` — **PURE, zero adapters** (`source` now `persona.identity_source`).
5. **IF `plan.host_apply != 'none'`:** `applied = get_port('mcp').apply(plan, snapshot)` (McpPort-only; populates `enforced`). **ELSE** skip — advisory tier needs no apply.
6. Install session record `{ref, intent, donned_at, bound_refs, capability_plan}`; initialize `_credential_cache[ref] = {}` (EMPTY, **outside the record**).
7. `_mirror()` via `_mirrorable_view` (never `_credential_cache`).
→ Identity live with **no vault, no MCP enforcement, no telemetry required**. Re-donning the same pinned ref is an idempotent swap that rebuilds the plan against a fresh snapshot (`Idempotency` §336).

### `resolve_credential(alias: str, audience: str) -> ResolvedSecret`  *(NEW, session layer)* — the ONLY SecretPort.resolve path
- **Scope check order** (`Principle of least privilege` §1336): (a) a persona is donned; (b) `alias ∈` donned persona's `CredentialBinding` aliases; (c) `audience ∈` that binding's `scope.audience`. **Empty-audience semantics are FAIL-CLOSED (Critique Resolutions m-audience):** an empty `audience` list ⇒ resolvable by NO consumer; a binding authored without an `audience` key defaults to **deny-all** (explicit opt-in required); a reserved token `lens` must be explicitly listed for non-mcp (lens-prose) resolution. `ScopeError` on any audience not in the list, including the empty-list case. **Cache hit short-circuits SecretPort.** On miss ⇒ `get_port('secret').resolve(binding.ref, persona.ref, scope=binding.scope)`; cache the `ResolvedSecret` in `_credential_cache[persona.ref]` (memory only); flip `bound_refs[alias].status` to `resolved` (or `unresolved-credential` on failure — `required:false` ⇒ don already succeeded; `required:true` ⇒ already warned at don). **Material never enters any returned dict, mirror, or file.** For `rotate:dynamic` the cached entry retains the issuer `handle` so doff can revoke it.

### `doff() -> dict | None`  *(evolves session.doff)*
**Control flow (numbered):**
1. Capture active record; `None` ⇒ return `None` (preserves today's "No masque was active" branch).
2. For each entry actually in `_credential_cache[ref]`: if `binding.rotate=='dynamic'` ⇒ `get_port('secret').revoke(handle)` (errors caught → collected into `revoke_errors`, **never raised**); **always** ⇒ zero the in-process material.
3. Drop `_credential_cache[ref]` entirely (overwrite + clear — no `ResolvedSecret` survives).
4. Discard the `CapabilityPlan`; for `config-write`/`hook` tiers, **`session.doff()` explicitly calls `get_port('mcp').teardown()`** (Critique Resolutions M-teardown — the domain core owns this port call; it is not "surfaced but unowned").
5. `previous = _mirrorable_view({ref, doffed_at, bound_refs summary, capability_plan summary})`.
6. `_mirror()`.
→ **EXPLICIT (Phase 1 §6.5):** doff does NOT withdraw ambient static secrets — a `github_token` in the OS keychain/env remains present; doff only forgets the in-process copy. Static `keychain://`/`env://` get **no** revoke call.
- **Honest return dict (Critique Resolutions M-doffhonesty):** `{name, version, forgot_in_process:[aliases actually in the cache at doff], revoked:[dynamic aliases whose revoke returned status=='revoked' ONLY], revoke_errors?, note:"underlying keychain/env secrets are untouched and still present"}`. **`forgot_in_process` lists only aliases that were actually resolved this session** (never a declared-but-unresolved alias — that would imply a withdrawal that never happened). **`revoked` lists only leases whose `revoke` returned `'revoked'`** — a Vault-unreachable lease (`'unavailable'`) or a `'noop'` is NOT listed as revoked, so the dict never claims a still-live lease is dead.

### `active() -> dict | None`  *(evolves; NEW surfaces expose it)* — PURE
- Returns the **safe-to-mirror projection only** (`_mirrorable_view`): `{ref:{name,version}, source, intent, donned_at, config_source, config_error?, bound_refs:[{alias,scheme,status}], capability_plan_summary:{host_apply, per_binding:[{server, status, enforced, tier, effective_allow|advisory_allow, effective_deny|advisory_deny}]}}`. `_credential_cache` is **structurally excluded**. **`bound_refs.status` is best-effort/last-mirrored, NOT authoritative live state** (Critique Resolutions m-mirrorcadence): mirroring is **lazy** — `bound_refs` status flips are written on the next `don`/`doff`, not per `resolve_credential` (avoids session-file write amplification). `/id` renders `bound_refs` explicitly as last-mirrored, never over-claiming credential freshness.
- **Surfaces (Critique Resolutions M-id):** `active()` is now reachable. A **NEW read-only MCP `id` tool** in `server.py` and a **NEW `cli.py cmd_id`** subcommand are thin pass-throughs to `session.active()`, and **`commands/id.md` is rewritten to shell out to `masques-cli id --json`** (mirroring how `/don` shells to `compose`) instead of parsing `.claude/masque.session.yaml` directly — otherwise the new `bound_refs`/`capability_plan` keys never reach `/id`.

### `write_sidecar(persona_name, config: PersonaConfig, expected_etag) -> dict`  *(NEW, write path)* — no port
- The CLI/command WRITE seam for TUI+plugin sidecar mutation. `Compare-and-set / Optimistic locking` (§582): compare current file `etag` to `expected_etag`; on mismatch apply **last-write-wins + warning** (single-user local file; Phase 1 OQ7), NOT a hard fail. Schema/invariant violations rejected **before** write. Returns `{status:'written'|'conflict', etag:<new>, warning?}`.

### Evolved `.claude/masque.session.yaml` schema (SUPERSET — backward-compatible)
```yaml
active:                          # null if baseline
  name: Codesmith               # unchanged
  source: shared                # = identity_source (unchanged key, same values)
  version: "1.2.0"              # NEW (additive) — emitted as version.raw (str)
  config_source: private        # NEW: null when no sidecar
  config_error: null            # NEW: {path, reason, remediation} when a sidecar failed to parse
  donned_at: 2026-06-08T12:00:00Z
  bound_refs:                   # NEW additive — alias+scheme+status, NEVER material; last-mirrored
    - {alias: github_token, scheme: "keychain://", status: resolved}
  capability_plan:              # NEW additive — summary only, NO secrets
    host_apply: none            # honest tier
    bindings:
      - server: github
        status: advisory
        enforced: false         # honesty wired into DATA, not just renderer
        tier: advisory
        advisory_allow: [...]    # at tier none, named advisory_* so no reader mistakes it for enforced scoping
        advisory_deny: [...]
previous:
  name: Firekeeper
  source: private
  doffed_at: 2026-06-08T11:00:00Z
  # bound_refs (with revoked status for swapped-out dynamic leases) / capability_plan summary optional
```
At `host_apply ∈ {config-write, hook}` the binding carries `enforced: true` and `effective_allow`/`effective_deny` (the enforced names). At `host_apply: none` it carries `enforced: false`, `tier: advisory`, and `advisory_allow`/`advisory_deny` — so a downstream statusline/TUI reading the YAML cannot misread tier-none allow/deny as enforced least-privilege scoping (Critique Resolutions M-mirror). Readers that ignore unknown keys are unaffected; a sidecar-less persona has `bound_refs: []` and `capability_plan: {host_apply: none, bindings: []}`. **`_credential_cache` is never written here.**

---

## 5. CapabilityPlan & Enforcement Honesty

**Built at don** by `core.build_capability_plan(persona, host_caps)` — a pure fold over `persona.config.mcp` against the injected `host_caps`. Per binding: `{server, status, effective_allow|advisory_allow, effective_deny|advisory_deny, enforced, tier}`. `plan.host_apply = host_caps.achievable_tier` (default `none`).

**host_apply tiers (Phase 1 §2):**
- **`none`** ⇒ plan is **ADVISORY** (injected as prose; the model is *asked* to honor allow/deny). `apply()` is not called; every binding is stamped `enforced:false, tier:advisory` at build time.
- **`config-write`** ⇒ session-scoped `.mcp.json` overlay actually mediates; `don()` calls `apply()`, which sets `enforced:true`.
- **`hook`** ⇒ a `PreToolUse` hook blocks denied tools; `apply()` sets `enforced:true`.

**How `/id`, `inspect`, and `capability_plan` render it — HONESTLY:**
- When `host_apply=='none'`: render label **`advisory`**, surface allow/deny under the **`advisory_allow`/`advisory_deny`** field names, and emit the **confused-deputy warning** verbatim: *"a credential resolved into an MCP server is reachable by every tool of that server regardless of allow/deny"* (`Capability-based sandboxes` §1652). The words **"least-privilege"/"sandbox" are unreachable** at this tier.
- When `host_apply ∈ {config-write, hook}`: render **`least-privilege`** and show `effective_allow/deny` as **ENFORCED** (`per_binding.enforced=true` from `McpPort.apply`).
- The `<masque-active>` block gains a `## Capability (advisory)` section **only when bindings exist**, explicitly tagged advisory unless the host mediates.

The honesty vocabulary is **wired into the data** (the `enforced` bool + `tier` field + the `advisory_*` vs `effective_*` field names, in both the live plan and the serialized mirror), not asserted by a single renderer — so every consumer, including ones that don't carry the §5 rendering rule, sees the truth. Until OQ1 is verified, surfaces MUST render `advisory` and `host_apply` defaults to `none`; surfaces must not be coded to assume a hook/config-write tier exists.

---

## 6. Measurement Read API

Two distinct read paths, both behind `TelemetryPort`, both degrading when telemetry is off:

1. **`score(session?)`** *(unchanged surface)* — the raw two-layer DuckDB judge run. `{status:'ok', report, local_only:True}` / `{status:'unavailable'}`. Stays LOCAL-ONLY (subprocess to judge.sh, never leaves the machine).
2. **`report(ref, scope='local')`** *(NEW)* — the read-model accessor `/performance` reads. `scope='local'` ⇒ `LocalReport` keyed `(persona_identity_hash, task_class)` per Phase 1 §7 — **machine-only, a hard Protocol contract** (no adapter may serve `local` from a remote source).

**The local→global enforcement point (single STRUCTURAL chokepoint):** `core.report(ref, scope='global')` is the ONLY place the boundary is crossed. Inside it, a single gate asserts ALL of: `MeasurementPolicy.scope=='global'` **AND** `k_min` satisfied **AND** DP noise applied **AND** attestation present **AND** non-private (bundled) `identity_hash`; only if all pass does the gate **construct the `AttestedAggregate` sealed value-object** (whose constructor is module-private to this gate) and hand it to `TelemetryPort.contribute(...)`. **No surface, CLI, or adapter can fabricate an `AttestedAggregate`, so `contribute()` is structurally unreachable except through the gate** (Critique Resolutions B-gate) — the "single boundary" is enforced by the type system, not by convention. `ClickHouseAdapter.contribute` additionally re-asserts the preconditions (defense in depth). Activity-fallback bands and self-authored rubric bands are excluded from any global aggregate (Phase 1 §7). `GlobalReport` remains advisory/non-authoritative until attestation exists (Phase 1 OQ9). `report` degrades to `{status:'unavailable'}` when TelemetryPort is the Null adapter — telemetry is never required to don. (`Materialized view / Read model / Projection` §856; `CQRS`/`Event sourcing` §826/§832.) **Acceptance test:** assert no code path reaches `contribute()` / a ClickHouse write without `MeasurementPolicy.scope=='global'` AND `k_min` AND attestation present.

`/performance` migrates from shelling judge.sh directly to `report(scope='local')` as a **superset**, but a parity test against today's judge.sh YAML is required before swapping (OQ8).

---

## 7. Migration & Backward Compatibility

**Existing `*.masque.yaml` + existing callers keep working — total.** `_parse_identity_file` is `_parse_masque_file` minus the path embed; `masque.schema.yaml` is untouched; no sidecar ⇒ `config=None` ⇒ `build_capability_plan` over an empty mcp list returns `host_apply:none` + empty bindings; no port is ever touched ⇒ a legacy don is **byte-for-byte the old behavior**. The 30+ bundled personas resolve unchanged (sidecars are never shipped). **`Persona`'s read-through properties + `source` alias** (§2) make it a strict drop-in for the old `Masque` attribute surface, so `test_core.py` (which reads `m.source`/`m.has_rubric`/`m.lens`/`m.name`/`m.version` off the `resolve()` return) passes without rewrites; the `Version.__str__/__eq__` contract keeps `m.version == "9.9.9"` and the `<masque-active ... version="0.3.0">` parity assertion (test_core.py:80) true.

**The Masque→Identity+Persona field move:** `Identity = Masque MINUS {source, path}`; `Persona OWNS {identity_source, config_source, path}` (Phase 1 §2/§6).

**Exact call sites changed (verified against the files — exhaustive):**
| Site | Today | Phase 2 |
|---|---|---|
| `core.py:160` | `resolve(name) -> Masque` | `-> Persona` (additive return; `.identity` + read-through props are the drop-in) |
| `core.py:125` | `_parse_masque_file -> Masque` | rename `_parse_identity_file -> Identity` (update the one `list_masques` call at line 260) |
| `core.py:200` | `build_identity_block(masque, …)` | accepts `Persona | Identity`; emits `version.raw` at line 206 |
| **`core.py:228-229`** | `"version": masque.version` / `"source": masque.source` | **`version.raw`** / **`persona.identity_source`** + additive `config_source`/`config_error`/`capability_plan`/`bound_refs` |
| **`core.py:280-282`** | `"version"`/`"source"`/`"path"` off `masque` | **`version.raw`** / **`persona.identity_source`** / **`str(persona.path)`** + additive keys; NO port |
| `core.py:265` | `"version": ... ` in list entry | emit `version.raw` (string) |
| `core.py:315` | `score()` body | one-line `get_port('telemetry').score(...)`; body → `LocalJudgeAdapter` (identical return shape) |
| `server.py:86-90` | `masque=core.resolve(name)`; `session.don(masque.name, masque.source)` | `persona=core.resolve(name)`; `session.don(persona, intent)` — the `.source` field move AND the `don` 2-arg→`(ref,intent)` signature change both surface here (required change) |
| `server.py:146-147` | `_make_prompt`: `masque=core.resolve(stem)`; `core.compose(masque)['identity_block']` | `persona=core.resolve(stem)`; `core.compose(persona)['identity_block']` — **structurally unaffected** (compose accepts `Persona`), but enumerated as a third `resolve()->compose()` consumer that runs at import for all 35+ registered prompts; add a prompt-path parity assertion |
| `cli.py:51-56` | `masque=core.resolve(...)`; `core.compose(masque, intent)` | `persona=core.resolve(...)`; `core.compose(persona, intent)` |
| `server.py` (NEW) | — | NEW read-only `id` MCP tool → `session.active()` |
| `cli.py` (NEW) | — | NEW `cmd_id` → `session.active()`; NEW `cmd_capability` → `capability_plan`; NEW `cmd_report` → `report`; write-only `cmd_bind_credential`/`cmd_toggle_mcp` → `write_sidecar` |
| `commands/id.md` | parses `.claude/masque.session.yaml` directly | shells `masques-cli id --json` so new `bound_refs`/`capability_plan` keys reach `/id` |

**CONFIRMED UNAFFECTED:** `core.list_masques()` (core.py:244) derives `source` from the `search_paths()` loop variable (lines 251/269), **not the dataclass**, and its entry dict uses fields (`name/version/domain/tagline/has_rubric`) that all survive on `Identity` — so it needs no change beyond the internal parse-helper rename and emitting `version.raw`. Its callers (`server.py:52/156/172`, `cli.cmd_list`, both resources) are untouched.

**Additivity guarantees:** every returned dict gains only new keys — existing consumers ignore them. The wire key `"source"` is preserved (the internal field rename to `identity_source` does not change the JSON key), so `don.md:60` / `id.md:23` / `inspect.md:23` reads keep working. New MCP tools (`id`, `capability_plan`, `report`) and CLI subcommands are purely additive. The session mirror schema is a strict superset. The 8 slash commands map 1:1; `/id` now reads via `cmd_id`; `/inspect` gains additive capability-tier rendering (shown only when a sidecar exists); `/performance` maps to `report(scope='local')`; `/audience` and `/sync-manifest` are unchanged.

**Credential/MCP binding mutation is CLI/command WRITE-only, deliberately NOT an MCP tool** — no agent-driven credential binding (security posture).

---

## Critique Resolutions

Every blocker and major issue from the three critics is folded in; minor ones are pinned here or under Open Questions.

**Blockers**
- **B-secret — credential_cache could be serialized (cannot be proven safe).** RESOLVED: `_credential_cache` now lives **outside** `_active`/`_previous` as a separate module-level dict keyed by `PersonaRef`; the mirror is built from an explicit **allowlist** `_mirrorable_view()` (not blocklist-by-omission); `ResolvedSecret.material` is excluded from `__repr__`/`asdict`; the mirror boundary asserts no `ResolvedSecret` survives. Acceptance test: cache→mirror→grep for `material` must be empty (§4).
- **B-gate — `TelemetryPort.contribute` reachable, so the "single gate" was conventional, not structural.** RESOLVED: `contribute` takes only an `AttestedAggregate` sealed value-object whose constructor is **module-private to `core.report`'s gate**; no surface/CLI/adapter can build a valid argument, so the global path is structurally unreachable except through the gate; `ClickHouseAdapter` re-asserts preconditions for defense in depth (§3, §6).
- **B1-bound-refs — don() called `SecretPort.capabilities()`, breaking the ZERO-adapter claim.** RESOLVED: `bound_refs` are seeded from **static sidecar fields** (`alias`+`scheme`, `status='pending'`) with **no SecretPort call**; capability probing is deferred to lazy `resolve_credential`/render. A fresh don is truly zero-SecretPort (§3, §4).
- **B1-version — Version object breaks the `version` string contract.** RESOLVED: `Version.__str__` returns `raw`, `Version.__eq__` accepts `str` by `raw`; every output reader emits `version.raw`; the `Version` object never reaches `yaml.safe_dump`/`json.dumps`. Serialization/parity regression test is an acceptance gate (§2).
- **B2-drop-in — tests read `.source`/`.has_rubric`/`.lens` off the resolve() return.** RESOLVED: `Persona` exposes read-through properties for `name/version/lens/context/attributes/rubric/has_rubric/spinner_verbs` and a `source` property aliasing `identity_source` — a strict drop-in; existing `test_core.py` passes unchanged (§2, §7).

**Majors**
- **M-id — `active()`'s rich projection reachable by no surface.** RESOLVED: NEW `id` MCP tool + `cmd_id` CLI subcommand pass through to `session.active()`; `commands/id.md` rewritten to shell `masques-cli id --json` (§4, §7).
- **M-apply / M-enforced-provenance — where `AppliedPlan.enforced` is produced.** RESOLVED: `don()` calls `get_port('mcp').apply(plan, snapshot)` **only when `host_apply != 'none'`** (McpPort-only); at tier none `apply` is skipped and `enforced:false`/`tier:advisory` are stamped by `build_capability_plan` — so the bool exists exactly when something enforces (§3, §4, §5).
- **M-teardown — `McpPort.teardown` ownership was hand-wavy.** RESOLVED: `session.doff()` explicitly calls `get_port('mcp').teardown()` for config-write/hook tiers; the domain core owns the port call (§4).
- **M-swap — don-over-don revoke contradicted "no SecretPort at don".** RESOLVED: a swap runs the **outgoing persona's doff teardown FIRST** (revoke attributed to doff), flips swapped-out dynamic `bound_refs[*].status` to `revoked`; a fresh don from baseline touches zero adapters (§4).
- **M-mirror — mirrored allow/deny at tier none could be misread as enforced.** RESOLVED: the serialized binding carries `enforced:false`/`tier:advisory` and names tier-none lists `advisory_allow`/`advisory_deny` (vs `effective_*` when enforced) — honesty in the field names, not just the renderer (§4, §5).
- **M-doffhonesty — doff return over-claimed `zeroed`/`revoked`.** RESOLVED: `zeroed`→`forgot_in_process` (only aliases actually cached this session), `revoked` lists only leases whose revoke returned `'revoked'`, plus a note that underlying keychain/env secrets are untouched (§4).
- **M-prompt-path — `_make_prompt` not enumerated.** RESOLVED: `server.py:146-147` added to the changed-call-sites table as a third `resolve()->compose()` consumer (source-compatible; parity assertion recommended) (§7).
- **M-sidecar — `PersonaConfigError` hard-fail could brick a pinned identity.** RESOLVED (decision, was OQ4): malformed/invariant-violating sidecar **degrades to `config=None` + surfaced `config_error` warning**, never denies the don; "every existing identity still resolves" stays literally true (§2).
- **M-donsig — claim that old 2-arg `don` keeps compiling was false.** RESOLVED: documented that `don`'s 2nd positional changed meaning (`source`→`intent`); the `server.py:90` caller is a required, enumerated change (§4, §7).

**Minors** (folded where cheap; otherwise Open Questions): m-compose (drop `host_caps` from `compose`, accept only `plan`), m-inspect (inspect deterministically pure, no port), m-threading (cache bound to session record + loud TODO), m-audience (fail-closed empty-audience), m-localonly (`report(scope='local')` hard Protocol contract), m-mirrorcadence (lazy `bound_refs` mirror; `/id` renders best-effort). Remaining minors → Open Questions.

---

## 8. Open Questions (deduped, ranked)

1. **(BLOCKING — Phase 1 OQ1b, host enforcement seam.)** Does Claude Code expose a session-scoped `enabledMcpjsonServers`/`.mcp.json` overlay (`config-write`) or a `PreToolUse` block hook (`hook`), or neither? **Gates whether `McpPort.capabilities().max_tier` can ever exceed `none`.** Until verified, ALL surfaces render `advisory`; `apply()` is never called; surfaces must not assume a tier exists.
2. **(BLOCKING — Phase 1 OQ1a, attribution emission.)** How does `persona.id/version/identity_hash` reach host-emitted events? Until verified, the sidecar-join fallback is authoritative and `report` version-level lift cohorts are not claimed — gates the global seam in §6.
3. **Registry lifecycle for a hosted server.** Module-level registry is correct for single-process stdio; the credential_cache is already bound to the session record, but the Phase-B HTTP server must still scope the registry per-session. Confirm before any hosted transport ships.
4. **`capability_plan` as a separate read tool vs riding inside `don()`'s payload.** The separate tool lets a host re-query the tier mid-session without re-donning, but adds surface area. Confirm with the OQ1 host decision.
5. **Credential scheme registry at v1 (Phase 1 OQ5).** Confirm `env://` + `keychain://` ship; specify the deterministic `keychain://` locator → env-name mapping required before `EnvAdapter` serves as the Linux/CI fallback, else surface `scheme-unavailable`.
6. **STS revoke (Phase 1 OQ4).** `sts://` revoke is `noop` relying on TTL — confirm acceptable, or make `ttl` REQUIRED when `rotate:dynamic` + `sts://` to bound blast radius.
7. **`/performance` migration parity.** Requires a parity test vs the existing judge.sh YAML (the `/performance.md` prose is tightly coupled to it) before swapping the raw path to `report(scope='local')`.
8. **Tool namespace for allow/deny (Phase 1 OQ3).** Fully-qualified (`mcp__server__tool`) vs short — surfaces render whatever the resolver canonicalizes; affects exactly what `/id`/`inspect` print.
9. **Reserved non-mcp audience token.** `lens` is proposed as the explicit token for lens-prose credential resolution; confirm the token name and whether any other non-mcp consumer needs one.

---

## Files grounding this design
Implementation will touch these real seams (with line numbers verified against the repo): `/Users/chris/git/masques/services/mcp/src/masques_mcp/core.py` (`resolve`:160, `_parse_masque_file`:125, `Masque` dataclass:97-98, `build_identity_block`:200/version@206, `compose`:219/version@228/source@229, `list_masques`:244/version@265, `inspect`:275/version@280/source+path@281-282, `score`:315/body@323-356, `search_paths`:87); `/Users/chris/git/masques/services/mcp/src/masques_mcp/session.py` (`don`:48, `doff`:58, `active`:69, `_mirror`:35-45, `_session_file`:30); `/Users/chris/git/masques/services/mcp/src/masques_mcp/server.py` (don tool@86-90, `_make_prompt` compose@146-147, score tool@133, `_register_prompts`@154-161, resources@65/180); `/Users/chris/git/masques/services/mcp/src/masques_mcp/cli.py` (`cmd_compose`@51-56, json/yaml emit@30/32/58); `/Users/chris/git/masques/commands/id.md` (currently parses the session file directly); `/Users/chris/git/masques/docs/design/phase1-data-model.md` (authoritative entities); `/Users/chris/git/engineering-reference/engineering-reference.md` (§258 Content addressing, §296 Canonical encoding, §336 Idempotency, §582 Compare-and-set, §788 Hexagonal/Ports & Adapters, §818 Plugin/Microkernel, §826/§832 CQRS/Event sourcing, §856 Read model, §968 Graceful degradation, §1304 Secrets management, §1336 Least privilege, §1652 Capability-based sandboxes, §2065 Anonymization, §2213 Short-lived credentials).
