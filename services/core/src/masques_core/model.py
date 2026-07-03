"""
The Persona data model (Phase 1, docs/design/phase1-data-model.md).

Persona is the aggregate root binding identity -> capability -> measurement. It
owns REFERENCES and SCOPES (which credential ref, which server, what policy) —
never secret bytes, never tool implementations, never raw telemetry.

Two halves, two files:
  Identity      <name>.masque.yaml   — pinned, immutable, semver-versioned
  PersonaConfig <name>.persona.yaml  — mutable operational sidecar, never shipped

`Persona` is a strict drop-in for the old `Masque` dataclass (Phase 2 §2 B2):
read-through properties delegate to `.identity`, and `.source` aliases
`.identity_source`, so `persona.lens` / `persona.source` / `persona.version`
resolve exactly as `masque.*` did.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


# =============================================================================
# Errors
# =============================================================================


class MasqueError(Exception):
    """Base class for masque resolution/parsing errors."""


class MasqueNotFoundError(MasqueError):
    """No masque file matched the requested name in any search path."""


class MasqueParseError(MasqueError):
    """A masque file exists but is malformed or missing required fields."""


class PersonaConfigError(MasqueError):
    """A sidecar exists but is malformed or violates an in-aggregate invariant.

    Never raised out of `resolve()` — carried as the typed cause on the
    Persona's `config_error` warning (Phase 2 §2 M-sidecar).
    """


# =============================================================================
# Version — pinned selector, str-compatible (Phase 2 §2 B1-version)
# =============================================================================


@dataclass(frozen=True)
class Version:
    """Semver as a typed pin. NOT an optimistic-lock token (that is the sidecar etag).

    Contract: `str(v)` returns the raw string; `v == "1.2.0"` compares by raw.
    Output-facing readers emit `.raw` — the Version object itself must never
    reach yaml.safe_dump/json.dumps.
    """

    major: int
    minor: int
    patch: int
    raw: str

    @classmethod
    def parse(cls, raw: str) -> Version:
        """Lenient parse (schema pattern-validation is the real gate): non-numeric
        or short segments degrade to 0 rather than raising."""
        raw = str(raw)
        parts = raw.split(".")
        nums = []
        for i in range(3):
            try:
                nums.append(int(parts[i]))
            except (IndexError, ValueError):
                nums.append(0)
        return cls(nums[0], nums[1], nums[2], raw)

    def __str__(self) -> str:
        return self.raw

    def __eq__(self, other: object) -> bool:
        if isinstance(other, str):
            return self.raw == other
        if isinstance(other, Version):
            return self.raw == other.raw
        return NotImplemented

    def __hash__(self) -> int:
        return hash(self.raw)


@dataclass(frozen=True)
class PersonaRef:
    """How a persona is addressed and pinned: the natural key (name, version)."""

    name: str
    version: Version


# =============================================================================
# Identity — the pinned cognitive core (= old Masque MINUS {source, path})
# =============================================================================


@dataclass
class Identity:
    """Verbatim parse of <name>.masque.yaml. Changing any field is a new Version."""

    name: str
    version: Version
    lens: str
    context: str | None = None
    attributes: dict[str, Any] = field(default_factory=dict)
    rubric: str | None = None
    spinner_verbs: dict[str, Any] | None = None
    raw: dict[str, Any] = field(default_factory=dict)

    @property
    def domain(self) -> str | None:
        return self.attributes.get("domain")

    @property
    def tagline(self) -> str | None:
        return self.attributes.get("tagline")

    @property
    def has_rubric(self) -> bool:
        return bool(self.rubric and self.rubric.strip())


# =============================================================================
# Sidecar value-objects — references and scopes only, never material
# =============================================================================


@dataclass(frozen=True)
class SecretRef:
    """A reference to a secret that lives elsewhere: scheme://locator[#fragment].

    Schemes: keychain:// env:// vault:// sts:// — never inline plaintext.
    """

    scheme: str  # e.g. "env" (stored without the "://")
    locator: str
    fragment: str | None = None

    @classmethod
    def parse(cls, uri: str) -> SecretRef:
        scheme, sep, rest = str(uri).partition("://")
        if not sep or not scheme or not rest:
            raise PersonaConfigError(f"credential ref is not a scheme://locator URI: {uri!r}")
        locator, _, fragment = rest.partition("#")
        return cls(scheme=scheme, locator=locator, fragment=fragment or None)

    @property
    def uri(self) -> str:
        base = f"{self.scheme}://{self.locator}"
        return f"{base}#{self.fragment}" if self.fragment else base


@dataclass(frozen=True)
class CredentialScope:
    """Where a resolved secret may be injected. Empty audience = deny-all
    (fail-closed, Phase 2 §4 m-audience)."""

    audience: tuple[str, ...] = ()
    required: bool = False
    availability: str = "while-donned"  # "while-donned" | "on-demand"


@dataclass(frozen=True)
class CredentialBinding:
    """ONE reference + scope tying this persona to a secret that lives elsewhere."""

    alias: str
    ref: SecretRef
    scope: CredentialScope = field(default_factory=CredentialScope)
    rotate: str = "static"  # "static" | "dynamic"
    ttl: str | None = None


# Reserved server id: a host's native (non-MCP) tool registry (Phase 3 §4).
# loon-agent's built-in tools bind under this id; real MCP servers use their own.
HOST_NATIVE_SERVER = "host"


@dataclass(frozen=True)
class McpBinding:
    """ONE per-persona capability toggle + tool-permission scope.

    `server` is a stable id in the host's registry; the reserved id
    HOST_NATIVE_SERVER ("host") denotes the host's native (non-MCP) tool
    registry (Phase 3 §4).
    """

    server: str
    enabled: bool = True
    allow: tuple[str, ...] | None = None
    deny: tuple[str, ...] | None = None
    uses_credentials: tuple[str, ...] = ()
    config: dict[str, bool | int] | None = None  # closed typed keys only
    required: bool = False


@dataclass(frozen=True)
class MemoryBinding:
    """This persona's memory scope — the third binding type (Phase 3 §3).

    The persona owns the scope and mode; the memory provider owns the storage.
    Only meaningful on a host with a memory seam (loon-agent's MemoryProvider);
    elsewhere it folds to `unresolved-host` in the CapabilityPlan.
    """

    namespace: str  # partition key; personas sharing it share recall (deliberate)
    mode: str = "read-write"  # "read-write" | "read-only" | "none"
    prompt_block: bool = True  # inject the provider's static block while donned?
    provider: str | None = None  # named provider; None = host default


@dataclass(frozen=True)
class MeasurementPolicy:
    """Opt-in to being measured. Default zero-value: telemetry never required to don."""

    enabled: bool = False
    scope: str = "local"  # "local" | "global"
    rubric_judge: str = "activity-fallback"  # "activity-fallback" | "rubric" | "witness"
    baseline_min: int | None = None


@dataclass
class PersonaConfig:
    """The mutable operational half, from <name>.persona.yaml. Always private/local."""

    persona: str  # back-reference to identity name
    schema_version: int = 1
    etag: str | None = None
    credentials: list[CredentialBinding] = field(default_factory=list)
    mcp: list[McpBinding] = field(default_factory=list)
    memory: MemoryBinding | None = None
    measurement: MeasurementPolicy = field(default_factory=MeasurementPolicy)

    def credential(self, alias: str) -> CredentialBinding | None:
        return next((c for c in self.credentials if c.alias == alias), None)


@dataclass(frozen=True)
class ConfigError:
    """A surfaced sidecar failure: the don proceeds with config=None, this warns."""

    path: str
    reason: str
    remediation: str = "fix or delete the sidecar; the identity donned without bindings"


# =============================================================================
# CapabilityPlan — ephemeral, computed at don, honesty wired into the data
# =============================================================================

# host_apply tiers, weakest to strongest (Phase 1 §2 + Phase 3 §4).
HOST_APPLY_TIERS = ("none", "config-write", "hook", "bind")


@dataclass(frozen=True)
class HostSnapshot:
    """Read-only view of what the host offers, captured by don() and passed in."""

    servers: frozenset[str] = frozenset()
    achievable_tier: str = "none"
    memory_seam: bool = False  # host exposes a scoped MemoryProvider (Phase 3 §3)


@dataclass(frozen=True)
class PlanBinding:
    """One McpBinding folded against the host snapshot.

    At an enforcing tier the lists are `effective_*` and `enforced` is True; at
    tier `none` they are `advisory_*` — field names carry the honesty so no
    reader can mistake an advisory list for enforced scoping (Phase 2 §5).
    """

    server: str
    status: str  # applied | advisory | unresolved-server | disabled
    enforced: bool
    tier: str  # "advisory" | the enforcing host_apply tier
    allow: tuple[str, ...] | None = None
    deny: tuple[str, ...] | None = None

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "server": self.server,
            "status": self.status,
            "enforced": self.enforced,
            "tier": self.tier,
        }
        prefix = "effective" if self.enforced else "advisory"
        if self.allow is not None:
            d[f"{prefix}_allow"] = list(self.allow)
        if self.deny is not None:
            d[f"{prefix}_deny"] = list(self.deny)
        return d


@dataclass(frozen=True)
class PlanMemory:
    """The MemoryBinding folded against the host: scope + whether anything
    actually enforces it (applied | advisory | unresolved-host)."""

    namespace: str
    mode: str
    status: str  # applied | advisory | unresolved-host
    provider: str | None = None

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "namespace": self.namespace,
            "mode": self.mode,
            "status": self.status,
        }
        if self.provider is not None:
            d["provider"] = self.provider
        return d


@dataclass(frozen=True)
class CapabilityPlan:
    """What the donned persona requests from the host. Discarded at doff."""

    host_apply: str = "none"
    bindings: tuple[PlanBinding, ...] = ()
    memory: PlanMemory | None = None

    @classmethod
    def empty(cls) -> CapabilityPlan:
        return cls()

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "host_apply": self.host_apply,
            "bindings": [b.to_dict() for b in self.bindings],
        }
        if self.memory is not None:
            d["memory"] = self.memory.to_dict()
        return d


@dataclass(frozen=True)
class BoundRef:
    """alias + scheme + status — safe to mirror; NEVER carries material."""

    alias: str
    scheme: str
    status: str  # pending | advisory | resolved | unresolved-credential | revoked

    def to_dict(self) -> dict[str, str]:
        return {"alias": self.alias, "scheme": f"{self.scheme}://", "status": self.status}


# =============================================================================
# Persona — the aggregate root
# =============================================================================


@dataclass
class Persona:
    """The unit you don: pinned Identity + optional mutable PersonaConfig.

    Owns bindings and scopes plus {identity_source, config_source, path} — the
    fields lifted off the old Masque dataclass.
    """

    identity: Identity
    ref: PersonaRef
    identity_source: str  # "private" | "shared"
    path: Path
    config: PersonaConfig | None = None
    config_source: str | None = None  # "private" | None (sidecars are always private)
    config_error: ConfigError | None = None

    # --- read-through drop-in surface for the old Masque (Phase 2 §2 B2) ----

    @property
    def source(self) -> str:
        """Alias for identity_source — the old Masque field name (load-bearing)."""
        return self.identity_source

    @property
    def name(self) -> str:
        return self.identity.name

    @property
    def version(self) -> Version:
        return self.identity.version

    @property
    def lens(self) -> str:
        return self.identity.lens

    @property
    def context(self) -> str | None:
        return self.identity.context

    @property
    def attributes(self) -> dict[str, Any]:
        return self.identity.attributes

    @property
    def rubric(self) -> str | None:
        return self.identity.rubric

    @property
    def spinner_verbs(self) -> dict[str, Any] | None:
        return self.identity.spinner_verbs

    @property
    def raw(self) -> dict[str, Any]:
        return self.identity.raw

    @property
    def domain(self) -> str | None:
        return self.identity.domain

    @property
    def tagline(self) -> str | None:
        return self.identity.tagline

    @property
    def has_rubric(self) -> bool:
        return self.identity.has_rubric
