"""
Sidecar (<name>.persona.yaml) parsing and in-aggregate validation.

The sidecar is the mutable operational half of a Persona: credential bindings,
capability toggles, measurement opt-in. Validation here enforces exactly what
is checkable from sidecar state alone (Phase 1 §2 PersonaConfig invariant):

  * no inline secret material (any `value:`/`secret:` key under credentials)
  * `McpBinding.config` is a closed set of typed non-secret keys (bool/int only)
  * the alias <-> audience symmetry between mcp bindings and credentials

Cross-aggregate references (is the server present in the host? does the secret
resolve?) are NOT invariants — they degrade to `unresolved` in the
CapabilityPlan, never fail parsing.

A schema/invariant failure returns a ConfigError; `resolve()` degrades to
config=None + warning rather than denying the don (Phase 2 §2 M-sidecar).
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import yaml

from .model import (
    ConfigError,
    CredentialBinding,
    CredentialScope,
    McpBinding,
    MeasurementPolicy,
    MemoryBinding,
    PersonaConfig,
    PersonaConfigError,
    SecretRef,
)

PERSONA_SUFFIX = ".persona.yaml"

_FORBIDDEN_CREDENTIAL_KEYS = ("value", "secret", "token", "password")


def parse_persona_config(
    path: Path, identity_name: str
) -> tuple[PersonaConfig | None, ConfigError | None]:
    """Load + validate one sidecar.

    Returns (config, None) on success, (None, None) when the back-reference
    does not match `identity_name` (a stray sidecar is silently ignored,
    Phase 1 §4), and (None, ConfigError) on any schema/invariant failure.
    """
    try:
        config = _parse(path, identity_name)
    except PersonaConfigError as exc:
        return None, ConfigError(path=str(path), reason=str(exc))
    except yaml.YAMLError as exc:
        return None, ConfigError(path=str(path), reason=f"invalid YAML: {exc}")
    return (config, None) if config is not None else (None, None)


def _parse(path: Path, identity_name: str) -> PersonaConfig | None:
    text = path.read_text(encoding="utf-8")
    data = yaml.safe_load(text)
    if not isinstance(data, dict):
        raise PersonaConfigError(f"{path.name}: top-level YAML is not a mapping")

    persona = str(data.get("persona", "")).strip()
    if not persona:
        raise PersonaConfigError(f"{path.name}: missing required `persona:` back-reference")
    if persona.lower() != identity_name.lower():
        return None  # stray sidecar for a different identity — ignore

    credentials = [_credential(c, path.name) for c in _as_list(data.get("credentials"), path.name, "credentials")]
    mcp = [_mcp_binding(m, path.name) for m in _as_list(data.get("mcp"), path.name, "mcp")]
    _check_alias_audience(credentials, mcp, path.name)

    return PersonaConfig(
        persona=persona,
        schema_version=int(data.get("schema_version", 1)),
        etag=hashlib.sha256(text.encode("utf-8")).hexdigest()[:16],
        credentials=credentials,
        mcp=mcp,
        memory=_memory(data.get("memory"), path.name),
        measurement=_measurement(data.get("measurement"), path.name),
    )


def _as_list(value: object, filename: str, key: str) -> list[dict]:
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(v, dict) for v in value):
        raise PersonaConfigError(f"{filename}: `{key}:` must be a list of mappings")
    return value


def _credential(data: dict, filename: str) -> CredentialBinding:
    for key in _FORBIDDEN_CREDENTIAL_KEYS:
        if key in data:
            raise PersonaConfigError(
                f"{filename}: credential carries inline `{key}:` — secrets are "
                "references only (keychain:// env:// vault:// sts://), never material"
            )
    alias = str(data.get("alias", "")).strip()
    if not alias:
        raise PersonaConfigError(f"{filename}: credential missing `alias:`")
    if "ref" not in data:
        raise PersonaConfigError(f"{filename}: credential {alias!r} missing `ref:`")

    scope_data = data.get("scope") or {}
    if not isinstance(scope_data, dict):
        raise PersonaConfigError(f"{filename}: credential {alias!r} `scope:` must be a mapping")
    # No audience key => deny-all (fail-closed, Phase 2 §4 m-audience).
    audience = tuple(str(a) for a in scope_data.get("audience") or ())

    rotate = str(data.get("rotate", "static"))
    if rotate not in ("static", "dynamic"):
        raise PersonaConfigError(f"{filename}: credential {alias!r} rotate must be static|dynamic")

    return CredentialBinding(
        alias=alias,
        ref=SecretRef.parse(data["ref"]),
        scope=CredentialScope(
            audience=audience,
            required=bool(scope_data.get("required", False)),
            availability=str(scope_data.get("availability", "while-donned")),
        ),
        rotate=rotate,
        ttl=str(data["ttl"]) if data.get("ttl") is not None else None,
    )


def _mcp_binding(data: dict, filename: str) -> McpBinding:
    server = str(data.get("server", "")).strip()
    if not server:
        raise PersonaConfigError(f"{filename}: mcp binding missing `server:`")

    config = data.get("config")
    if config is not None:
        if not isinstance(config, dict):
            raise PersonaConfigError(f"{filename}: mcp {server!r} `config:` must be a mapping")
        for key, value in config.items():
            # Closed typed allowlist: bool/int only. A string is a potential
            # credential/DSN sink and is rejected structurally (Phase 1 §2).
            if isinstance(value, bool) or isinstance(value, int):
                continue
            raise PersonaConfigError(
                f"{filename}: mcp {server!r} config key {key!r} has a non-bool/int "
                "value — free-form config strings are rejected; route credential-"
                "bearing values through `uses_credentials`"
            )

    allow = data.get("allow")
    deny = data.get("deny")
    return McpBinding(
        server=server,
        enabled=bool(data.get("enabled", True)),
        allow=tuple(str(t) for t in allow) if allow is not None else None,
        deny=tuple(str(t) for t in deny) if deny is not None else None,
        uses_credentials=tuple(str(a) for a in data.get("uses_credentials") or ()),
        config=dict(config) if config else None,
        required=bool(data.get("required", False)),
    )


def _memory(data: object, filename: str) -> MemoryBinding | None:
    if data is None:
        return None
    if not isinstance(data, dict):
        raise PersonaConfigError(f"{filename}: `memory:` must be a mapping")
    namespace = str(data.get("namespace", "")).strip()
    if not namespace:
        raise PersonaConfigError(f"{filename}: memory binding missing `namespace:`")
    mode = str(data.get("mode", "read-write"))
    if mode not in ("read-write", "read-only", "none"):
        raise PersonaConfigError(
            f"{filename}: memory mode must be read-write|read-only|none, got {mode!r}"
        )
    return MemoryBinding(
        namespace=namespace,
        mode=mode,
        prompt_block=bool(data.get("prompt_block", True)),
        provider=str(data["provider"]) if data.get("provider") is not None else None,
    )


def _measurement(data: object, filename: str) -> MeasurementPolicy:
    if data is None:
        return MeasurementPolicy()  # absent => enabled=false, local-first
    if not isinstance(data, dict):
        raise PersonaConfigError(f"{filename}: `measurement:` must be a mapping")
    scope = str(data.get("scope", "local"))
    if scope not in ("local", "global"):
        raise PersonaConfigError(f"{filename}: measurement scope must be local|global")
    return MeasurementPolicy(
        enabled=bool(data.get("enabled", False)),
        scope=scope,
        rubric_judge=str(data.get("rubric_judge", "activity-fallback")),
        baseline_min=int(data["baseline_min"]) if data.get("baseline_min") is not None else None,
    )


def _check_alias_audience(
    credentials: list[CredentialBinding], mcp: list[McpBinding], filename: str
) -> None:
    """The alias<->audience symmetry — one in-aggregate invariant, two views.

    Every alias an mcp binding consumes must exist AND name that server in its
    audience; checkable entirely from sidecar state, so enforced on load
    (Phase 1 §2 McpBinding).
    """
    by_alias = {c.alias: c for c in credentials}
    for binding in mcp:
        for alias in binding.uses_credentials:
            credential = by_alias.get(alias)
            if credential is None:
                raise PersonaConfigError(
                    f"{filename}: mcp {binding.server!r} uses credential {alias!r} "
                    "which is not declared under `credentials:`"
                )
            if binding.server not in credential.scope.audience:
                raise PersonaConfigError(
                    f"{filename}: mcp {binding.server!r} uses credential {alias!r} "
                    f"but {alias!r} does not list {binding.server!r} in scope.audience "
                    "(alias<->audience symmetry)"
                )
