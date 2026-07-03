"""
Tool-agnostic Masques core — the pure functions (Phase 2 §2).

This module is the ONE authoritative implementation of the operations that
*use* a persona: resolve, compose, build_identity_block, build_capability_plan,
list_masques, inspect. Every function here is PURE — no port, no adapter, no
subprocess. No vault, MCP server, or telemetry is ever required to don.

Discovery (private takes precedence):
  1. Private:  ${MASQUES_HOME:-~/.masques}/<name>.masque.yaml
  2. Bundled:  <repo-or-plugin>/personas/<name>.masque.yaml

Sidecars are ALWAYS looked up in the private dir regardless of identity
source — a private sidecar may bind a shared identity (Phase 1 §3).
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml

from .model import (
    BoundRef,
    CapabilityPlan,
    HostSnapshot,
    Identity,
    MasqueError,
    MasqueNotFoundError,
    MasqueParseError,
    Persona,
    PersonaRef,
    PlanBinding,
    PlanMemory,
    Version,
)
from .sidecar import PERSONA_SUFFIX, parse_persona_config

REQUIRED_FIELDS = ("name", "version", "lens")
MASQUE_SUFFIX = ".masque.yaml"

__all__ = [
    "MASQUE_SUFFIX",
    "PERSONA_SUFFIX",
    "REQUIRED_FIELDS",
    "MasqueError",
    "MasqueNotFoundError",
    "MasqueParseError",
    "build_capability_plan",
    "build_identity_block",
    "bundled_dir",
    "compose",
    "inspect",
    "list_masques",
    "private_dir",
    "resolve",
    "search_paths",
]


# =============================================================================
# Search paths
# =============================================================================


def private_dir() -> Path:
    """Private masque directory: ${MASQUES_HOME:-~/.masques}."""
    home = os.environ.get("MASQUES_HOME")
    if home:
        return Path(home).expanduser()
    return Path.home() / ".masques"


def bundled_dir() -> Path:
    """
    Bundled personas directory.

    Resolution order:
      1. $MASQUES_PERSONAS_DIR (explicit override)
      2. $CLAUDE_PLUGIN_ROOT/personas (running inside the installed plugin)
      3. <repo>/personas computed relative to this file (running from source)
    """
    override = os.environ.get("MASQUES_PERSONAS_DIR")
    if override:
        return Path(override).expanduser()

    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root:
        candidate = Path(plugin_root) / "personas"
        if candidate.is_dir():
            return candidate

    # services/core/src/masques_core/core.py -> repo root is parents[4]
    return Path(__file__).resolve().parents[4] / "personas"


def search_paths() -> list[tuple[str, Path]]:
    """Ordered (source, directory) pairs; private first (wins on conflict)."""
    return [("private", private_dir()), ("shared", bundled_dir())]


# =============================================================================
# Parsing
# =============================================================================


def _parse_identity_file(path: Path, source: str) -> tuple[Identity, str]:
    """Load + validate a single identity YAML file. Returns (identity, source);
    source/path travel on the Persona, not the Identity (Phase 1 §6)."""
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise MasqueParseError(f"failed to parse {path.name}: {exc}") from exc

    if not isinstance(data, dict):
        raise MasqueParseError(f"{path.name}: top-level YAML is not a mapping")

    missing = [f for f in REQUIRED_FIELDS if not data.get(f)]
    if missing:
        raise MasqueParseError(
            f"{path.name} is missing required fields: {', '.join(missing)}"
        )

    identity = Identity(
        name=str(data["name"]),
        version=Version.parse(data["version"]),
        lens=str(data["lens"]),
        context=data.get("context"),
        attributes=data.get("attributes") or {},
        rubric=data.get("rubric"),
        spinner_verbs=data.get("spinnerVerbs"),
        raw=data,
    )
    return identity, source


# =============================================================================
# resolve
# =============================================================================


def resolve(name: str) -> Persona:
    """
    Resolve a persona by name (case-insensitive on the filename stem).

    Loads the pinned Identity (private over bundled) and, if present, the
    PersonaConfig sidecar (always from the private dir). A malformed sidecar
    DEGRADES — config=None plus a surfaced `config_error` — it never denies
    the don (Phase 2 §2). Raises MasqueNotFoundError / MasqueParseError for
    the identity file exactly as before.
    """
    stem = name.strip().lower()
    if stem.endswith(MASQUE_SUFFIX):
        stem = stem[: -len(MASQUE_SUFFIX)]

    identity: Identity | None = None
    identity_source = ""
    identity_path: Path | None = None
    checked: list[str] = []
    for source, directory in search_paths():
        candidate = directory / f"{stem}{MASQUE_SUFFIX}"
        checked.append(str(candidate))
        if candidate.is_file():
            identity, identity_source = _parse_identity_file(candidate, source)
            identity_path = candidate
            break

    if identity is None or identity_path is None:
        raise MasqueNotFoundError(
            f'masque "{name}" not found. Checked:\n  ' + "\n  ".join(checked)
        )

    # Sidecar: always the private dir, independent of identity source.
    config = None
    config_source = None
    config_error = None
    sidecar_path = private_dir() / f"{stem}{PERSONA_SUFFIX}"
    if sidecar_path.is_file():
        config, config_error = parse_persona_config(sidecar_path, identity.name)
        if config is not None:
            config_source = "private"

    return Persona(
        identity=identity,
        ref=PersonaRef(identity.name, identity.version),
        identity_source=identity_source,
        path=identity_path,
        config=config,
        config_source=config_source,
        config_error=config_error,
    )


# =============================================================================
# compose
# =============================================================================


def _render_attributes(attributes: dict[str, Any]) -> str:
    """Render attributes as `- Key: value` lines (all keys, title-cased)."""
    if not attributes:
        return ""
    lines = []
    for key, value in attributes.items():
        label = str(key).replace("_", " ").title()
        lines.append(f"- {label}: {value}")
    return "\n".join(lines)


def build_identity_block(persona: Persona | Identity, intent: str | None = None) -> str:
    """
    Build the `<masque-active>` identity block — the exact string a host
    injects to adopt the persona. Byte-identical to the pre-Persona output for
    any persona without a sidecar; bindings affect host wiring, never this
    pinned prose (Phase 2 §2).
    """
    identity = persona.identity if isinstance(persona, Persona) else persona
    sections = [
        f'<masque-active name="{identity.name}" version="{identity.version.raw}">'
    ]
    sections.append("## Lens\n" + identity.lens.rstrip())
    if identity.context:
        sections.append("## Context\n" + identity.context.rstrip())
    attrs = _render_attributes(identity.attributes)
    if attrs:
        sections.append("## Attributes\n" + attrs)
    if intent:
        sections.append("## Intent\n" + intent.strip())
    return "\n\n".join(sections) + "\n</masque-active>"


def compose(
    persona: Persona,
    intent: str | None = None,
    *,
    plan: tuple[CapabilityPlan, list[BoundRef]] | None = None,
) -> dict[str, Any]:
    """
    Compose a persona into the identity payload an agent adopts.

    Accepts only a pre-built `plan` (an already-folded (CapabilityPlan,
    bound_refs) pair), never a raw host snapshot (Phase 2 §2 m-compose). Keys
    are additive over the pre-Persona payload; the wire key "source" is
    preserved (= identity_source). Never any secret material.
    """
    payload: dict[str, Any] = {
        "name": persona.identity.name,
        "version": persona.identity.version.raw,
        "source": persona.identity_source,
        "config_source": persona.config_source,
        "config_error": _config_error_dict(persona),
        "intent": intent,
        "lens": persona.identity.lens,
        "context": persona.identity.context,
        "attributes": persona.identity.attributes,
        "spinnerVerbs": persona.identity.spinner_verbs,
        "identity_block": build_identity_block(persona, intent),
    }
    if plan is not None:
        capability_plan, bound_refs = plan
        payload["capability_plan"] = capability_plan.to_dict()
        payload["bound_refs"] = [r.to_dict() for r in bound_refs]
    return payload


def _config_error_dict(persona: Persona) -> dict[str, str] | None:
    if persona.config_error is None:
        return None
    return {
        "path": persona.config_error.path,
        "reason": persona.config_error.reason,
        "remediation": persona.config_error.remediation,
    }


# =============================================================================
# build_capability_plan — pure fold, no port (Phase 2 §2)
# =============================================================================


def build_capability_plan(
    persona: Persona, host_caps: HostSnapshot | None
) -> tuple[CapabilityPlan, list[BoundRef]]:
    """
    Fold the persona's McpBindings against an injected host snapshot.

    Calls NO port — the snapshot is captured by the session layer's don() and
    passed in; `host_caps=None` (inspect, or a host with no registry) folds to
    tier "none". `bound_refs` are seeded purely from static CredentialBinding
    fields — no SecretPort probe (Phase 2 B1). This is the single place the
    security vocabulary (enforced/tier) is assigned per binding.
    """
    host_apply = host_caps.achievable_tier if host_caps else "none"
    enforcing = host_apply != "none"

    bindings: list[PlanBinding] = []
    credentials = persona.config.credentials if persona.config else []
    mcp = persona.config.mcp if persona.config else []

    for binding in mcp:
        if not binding.enabled:
            status = "disabled"
        elif host_caps is not None and binding.server not in host_caps.servers:
            status = "unresolved-server"
        elif enforcing:
            status = "applied"
        else:
            status = "advisory"
        bindings.append(
            PlanBinding(
                server=binding.server,
                status=status,
                enforced=enforcing and status == "applied",
                tier=host_apply if enforcing else "advisory",
                allow=binding.allow,
                deny=binding.deny,
            )
        )

    # Memory: only a host with a memory seam can enforce scope/mode (Phase 3 §3).
    memory = None
    memory_binding = persona.config.memory if persona.config else None
    if memory_binding is not None:
        if host_caps is None:
            memory_status = "advisory"
        elif host_caps.memory_seam:
            memory_status = "applied"
        else:
            memory_status = "unresolved-host"
        memory = PlanMemory(
            namespace=memory_binding.namespace,
            mode=memory_binding.mode,
            status=memory_status,
            provider=memory_binding.provider,
        )

    ref_status = "pending" if enforcing else "advisory"
    bound_refs = [
        BoundRef(alias=c.alias, scheme=c.ref.scheme, status=ref_status) for c in credentials
    ]
    return (
        CapabilityPlan(host_apply=host_apply, bindings=tuple(bindings), memory=memory),
        bound_refs,
    )


# =============================================================================
# list / inspect
# =============================================================================


def list_masques() -> list[dict[str, Any]]:
    """
    Catalog of available masques, merging private over bundled (private wins
    on a filename-stem collision). Each entry: name, version, domain, tagline,
    has_rubric, source, stem, has_sidecar. Malformed files are skipped.
    """
    by_stem: dict[str, dict[str, Any]] = {}
    for source, directory in search_paths():
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob(f"*{MASQUE_SUFFIX}")):
            stem = path.name[: -len(MASQUE_SUFFIX)].lower()
            if stem in by_stem:
                # earlier source (private) already claimed this stem
                continue
            try:
                identity, _ = _parse_identity_file(path, source)
            except MasqueError:
                continue
            by_stem[stem] = {
                "name": identity.name,
                "version": identity.version.raw,
                "domain": identity.domain,
                "tagline": identity.tagline,
                "has_rubric": identity.has_rubric,
                "source": source,
                "stem": stem,
                "has_sidecar": (private_dir() / f"{stem}{PERSONA_SUFFIX}").is_file(),
            }
    return sorted(by_stem.values(), key=lambda m: m["name"].lower())


def inspect(name: str) -> dict[str, Any]:
    """
    Full fields for one masque — deterministically pure, NO port (Phase 2 §2
    m-inspect). Binding presence and advisory status come from sidecar state
    alone via build_capability_plan(persona, host_caps=None); live host
    enrichment is the session layer's job.
    """
    persona = resolve(name)
    plan, bound_refs = build_capability_plan(persona, host_caps=None)
    result: dict[str, Any] = {
        "name": persona.identity.name,
        "version": persona.identity.version.raw,
        "source": persona.identity_source,
        "path": str(persona.path),
        "lens": persona.identity.lens,
        "context": persona.identity.context,
        "attributes": persona.identity.attributes,
        "rubric": persona.identity.rubric,
        "has_rubric": persona.identity.has_rubric,
        "spinnerVerbs": persona.identity.spinner_verbs,
        "config_source": persona.config_source,
        "has_config": persona.config is not None,
        "config_error": _config_error_dict(persona),
    }
    if persona.config is not None:
        result["measurement_policy"] = {
            "enabled": persona.config.measurement.enabled,
            "scope": persona.config.measurement.scope,
            "rubric_judge": persona.config.measurement.rubric_judge,
        }
        result["capability_plan"] = plan.to_dict()
        result["bound_refs"] = [r.to_dict() for r in bound_refs]
    return result
