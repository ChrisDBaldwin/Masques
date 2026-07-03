"""
Hexagonal ports (Phase 2 §3): the frozen extension contract between the pure
core and everything at the edge.

The domain core imports ONLY this module — never a concrete adapter. Adapters
register at the composition root (a server's/CLI's main(), an agent's
build_runtime()); `get_port()` falls back to built-in local-first defaults so
the core always has a working, degrading port with zero registration.

Ships in masques-core: the three Protocols, the registry, and the
dependency-free default adapters (Env + Advisory + Null). Keychain, Vault,
and judge/telemetry adapters live with the surfaces that need them.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Any, Protocol, runtime_checkable

from .model import (
    CapabilityPlan,
    CredentialScope,
    HostSnapshot,
    PersonaRef,
    SecretRef,
)

__all__ = [
    "AdvisoryMcpAdapter",
    "EnvAdapter",
    "McpPort",
    "NullSecretAdapter",
    "NullTelemetryAdapter",
    "ResolvedSecret",
    "SecretPort",
    "TelemetryPort",
    "get_port",
    "register",
    "reset_ports",
]


# =============================================================================
# ResolvedSecret — material is memory-only, never serialized
# =============================================================================


@dataclass
class ResolvedSecret:
    """A resolved credential. `material` is excluded from repr and MUST never
    reach a mirror, log, or returned payload — only alias+scheme+status do
    (Phase 2 B-secret). Do not pass this through dataclasses.asdict."""

    alias: str
    scheme: str
    status: str  # resolved | unresolved-credential | scheme-unavailable | expired
    handle: str | None = None
    expires_at: str | None = None
    material: str | None = field(default=None, repr=False, compare=False)

    def to_safe_dict(self) -> dict[str, Any]:
        """The mirror-safe projection — structurally excludes material."""
        return {"alias": self.alias, "scheme": f"{self.scheme}://", "status": self.status}


# =============================================================================
# Protocols
# =============================================================================


@runtime_checkable
class SecretPort(Protocol):
    def resolve(
        self, ref: SecretRef, persona_ref: PersonaRef, *, scope: CredentialScope
    ) -> ResolvedSecret:
        """Resolve a reference to material (memory-only). Never raises for a
        resolvable-but-absent secret — returns a degraded status instead."""
        ...

    def revoke(self, handle: str) -> dict[str, Any]:
        """Returns {status: revoked|noop|unavailable, reason?}. Static schemes
        are noop; revoke failure never blocks doff."""
        ...

    def capabilities(self) -> dict[str, Any]:
        """{available_schemes, degradations} — consulted lazily, never at don."""
        ...


@runtime_checkable
class McpPort(Protocol):
    def host_snapshot(self) -> HostSnapshot:
        """Read-only view of the host registry — the only port method a fresh
        don may call. Degrades to {servers: (), achievable_tier: 'none'}."""
        ...

    def apply(self, plan: CapabilityPlan, snapshot: HostSnapshot) -> dict[str, Any]:
        """Mediate the tool boundary. Called ONLY when plan.host_apply != 'none';
        write failure fails OPEN to advisory, never crashes don."""
        ...

    def capabilities(self) -> dict[str, Any]:
        """{max_tier, supports_disable} — the static tier ceiling."""
        ...

    def teardown(self) -> None:
        """Remove any session overlay/hook at doff (enforcing tiers only)."""
        ...


@runtime_checkable
class TelemetryPort(Protocol):
    def score(self, session: str | None = None, *, timeout: int = 180) -> dict[str, Any]:
        """Local two-layer judge. {status: ok|unavailable, ...} — never required to don."""
        ...

    def report(self, ref: PersonaRef, *, scope: str = "local") -> dict[str, Any]:
        """Read-model accessor. scope='local' is a hard machine-only contract
        on every adapter (Phase 2 m-localonly)."""
        ...

    def capabilities(self) -> dict[str, Any]: ...


# =============================================================================
# Default adapters — dependency-free, local-first, degrading
# =============================================================================


class EnvAdapter:
    """SecretPort over env:// refs. Other schemes degrade to scheme-unavailable."""

    def resolve(
        self, ref: SecretRef, persona_ref: PersonaRef, *, scope: CredentialScope
    ) -> ResolvedSecret:
        if ref.scheme != "env":
            return ResolvedSecret(alias=ref.locator, scheme=ref.scheme, status="scheme-unavailable")
        material = os.environ.get(ref.locator)
        if material is None:
            return ResolvedSecret(
                alias=ref.locator, scheme=ref.scheme, status="unresolved-credential"
            )
        return ResolvedSecret(
            alias=ref.locator, scheme=ref.scheme, status="resolved", material=material
        )

    def revoke(self, handle: str) -> dict[str, Any]:
        return {"status": "noop"}  # env vars are ambient; nothing to revoke

    def capabilities(self) -> dict[str, Any]:
        return {"available_schemes": ["env://"], "degradations": {}}


class NullSecretAdapter:
    """Every resolve degrades — for hosts with no secret backend at all."""

    def resolve(
        self, ref: SecretRef, persona_ref: PersonaRef, *, scope: CredentialScope
    ) -> ResolvedSecret:
        return ResolvedSecret(alias=ref.locator, scheme=ref.scheme, status="scheme-unavailable")

    def revoke(self, handle: str) -> dict[str, Any]:
        return {"status": "noop"}

    def capabilities(self) -> dict[str, Any]:
        return {"available_schemes": [], "degradations": {}}


class AdvisoryMcpAdapter:
    """Tier 'none' — the local-first default. Injects prose, enforces nothing."""

    def host_snapshot(self) -> HostSnapshot:
        return HostSnapshot(servers=frozenset(), achievable_tier="none")

    def apply(self, plan: CapabilityPlan, snapshot: HostSnapshot) -> dict[str, Any]:
        return {"host_apply": "none", "per_binding": []}  # advisory: nothing to do

    def capabilities(self) -> dict[str, Any]:
        return {"max_tier": "none", "supports_disable": False}

    def teardown(self) -> None:
        return None


class NullTelemetryAdapter:
    """Telemetry off — everything degrades to unavailable."""

    def score(self, session: str | None = None, *, timeout: int = 180) -> dict[str, Any]:
        return {"status": "unavailable", "reason": "no telemetry adapter registered"}

    def report(self, ref: PersonaRef, *, scope: str = "local") -> dict[str, Any]:
        return {"status": "unavailable", "reason": "no telemetry adapter registered"}

    def capabilities(self) -> dict[str, Any]:
        return {}


# =============================================================================
# Registry — explicit injection at the composition root
# =============================================================================

_PORT_KINDS = ("secret", "mcp", "telemetry")
_registry: dict[str, Any] = {}


def _defaults(kind: str) -> Any:
    if kind == "secret":
        return EnvAdapter()
    if kind == "mcp":
        return AdvisoryMcpAdapter()
    return NullTelemetryAdapter()


def register(kind: str, adapter: Any) -> None:
    """Install an adapter. Call ONLY at the composition root (a main() or an
    agent's build_runtime()) — never from core code."""
    if kind not in _PORT_KINDS:
        raise KeyError(f"unknown port kind {kind!r}; expected one of {_PORT_KINDS}")
    _registry[kind] = adapter


def get_port(kind: str) -> Any:
    """Return the registered adapter or the built-in degrading default."""
    if kind not in _PORT_KINDS:
        raise KeyError(f"unknown port kind {kind!r}; expected one of {_PORT_KINDS}")
    adapter = _registry.get(kind)
    if adapter is None:
        adapter = _defaults(kind)
        _registry[kind] = adapter
    return adapter


def reset_ports() -> None:
    """Clear all registrations (tests)."""
    _registry.clear()
