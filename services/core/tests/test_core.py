"""
Tests for masques-core — ported from masques_mcp/tests/test_core.py (those
double as the spec for resolve/compose/list/inspect) plus the Persona
aggregate, drop-in compatibility, and capability-plan guarantees.

They run against the repo's bundled `personas/` and an isolated temp dir for
private-precedence cases (never the real ~/.masques).
"""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

import masques_core as core
from masques_core import HostSnapshot, Version


# --- fixtures ---------------------------------------------------------------


@pytest.fixture
def private(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """An isolated private masque dir wired in via $MASQUES_HOME."""
    monkeypatch.setenv("MASQUES_HOME", str(tmp_path))
    return tmp_path


def _write(dir_: Path, stem: str, body: str, suffix: str = ".masque.yaml") -> Path:
    path = dir_ / f"{stem}{suffix}"
    path.write_text(textwrap.dedent(body), encoding="utf-8")
    return path


PRIVATE_CODESMITH = """\
    name: Codesmith
    version: "9.9.9"
    lens: |
      private shadow
    """

VALID_SIDECAR = """\
    persona: Codesmith
    schema_version: 1
    credentials:
      - alias: github_token
        ref: env://GITHUB_TOKEN
        scope: {audience: [github]}
    mcp:
      - server: github
        allow: [get_issue, create_pr]
        uses_credentials: [github_token]
    """


# --- resolve (ported spec) ----------------------------------------------------


def test_resolve_bundled_is_case_insensitive() -> None:
    a = core.resolve("Firekeeper")
    b = core.resolve("firekeeper")
    assert a.name == b.name == "Firekeeper"
    assert a.source == "shared"
    assert a.has_rubric  # Firekeeper ships a rubric


def test_resolve_unknown_raises_not_found() -> None:
    with pytest.raises(core.MasqueNotFoundError):
        core.resolve("no-such-masque-xyz")


def test_private_takes_precedence(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    m = core.resolve("Codesmith")
    assert m.source == "private"
    assert m.version == "9.9.9"  # Version.__eq__ str contract (Phase 2 B1-version)


def test_missing_required_field_raises_parse_error(private: Path) -> None:
    _write(private, "broken", 'name: Broken\nversion: "1.0.0"\n')  # no lens
    with pytest.raises(core.MasqueParseError):
        core.resolve("broken")


# --- Persona aggregate & drop-in surface --------------------------------------


def test_resolve_returns_persona_with_identity_and_ref() -> None:
    p = core.resolve("Codesmith")
    assert isinstance(p, core.Persona)
    assert p.identity.name == "Codesmith"
    assert p.ref.name == "Codesmith"
    assert p.ref.version == p.identity.version
    assert p.identity_source == "shared"
    assert p.config is None  # bundled personas ship no sidecar
    assert p.config_source is None
    assert p.config_error is None


def test_persona_read_through_properties_are_drop_in() -> None:
    p = core.resolve("Firekeeper")
    # The old Masque attribute surface, verbatim (Phase 2 B2).
    assert p.name == p.identity.name
    assert p.source == p.identity_source
    assert p.lens == p.identity.lens
    assert p.context == p.identity.context
    assert p.attributes is p.identity.attributes
    assert p.has_rubric and p.rubric
    assert isinstance(p.path, Path)


def test_version_str_and_eq_contract() -> None:
    v = Version.parse("1.2.3")
    assert str(v) == "1.2.3"
    assert v == "1.2.3"
    assert v == Version.parse("1.2.3")
    assert (v.major, v.minor, v.patch) == (1, 2, 3)


# --- sidecar ------------------------------------------------------------------


def test_sidecar_composes_into_persona(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(private, "codesmith", VALID_SIDECAR, suffix=".persona.yaml")
    p = core.resolve("Codesmith")
    assert p.config is not None
    assert p.config_source == "private"
    assert [c.alias for c in p.config.credentials] == ["github_token"]
    assert p.config.credentials[0].ref.scheme == "env"
    assert p.config.credentials[0].ref.locator == "GITHUB_TOKEN"
    assert [m.server for m in p.config.mcp] == ["github"]
    assert p.config.measurement.enabled is False  # absent => local-first


def test_private_sidecar_binds_shared_identity(private: Path) -> None:
    # No private identity — the bundled Codesmith + a private sidecar.
    _write(private, "codesmith", VALID_SIDECAR, suffix=".persona.yaml")
    p = core.resolve("Codesmith")
    assert p.identity_source == "shared"
    assert p.config_source == "private"  # the two sources differ (Phase 1 §4)
    assert p.config is not None


def test_malformed_sidecar_degrades_never_denies_don(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(private, "codesmith", "persona: Codesmith\ncredentials: notalist\n",
           suffix=".persona.yaml")
    p = core.resolve("Codesmith")  # must NOT raise (Phase 2 M-sidecar)
    assert p.config is None
    assert p.config_error is not None
    assert "credentials" in p.config_error.reason


def test_stray_sidecar_for_other_identity_is_ignored(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(private, "codesmith", "persona: SomeoneElse\n", suffix=".persona.yaml")
    p = core.resolve("Codesmith")
    assert p.config is None
    assert p.config_error is None  # silently ignored, no warning


def test_sidecar_rejects_inline_secret_material(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(
        private,
        "codesmith",
        """\
        persona: Codesmith
        credentials:
          - alias: github_token
            ref: env://GITHUB_TOKEN
            value: ghp_plaintextleak
        """,
        suffix=".persona.yaml",
    )
    p = core.resolve("Codesmith")
    assert p.config is None
    assert "inline" in p.config_error.reason


def test_sidecar_rejects_freeform_config_strings(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(
        private,
        "codesmith",
        """\
        persona: Codesmith
        mcp:
          - server: db
            config: {dsn: "postgres://user:hunter2@host/db"}
        """,
        suffix=".persona.yaml",
    )
    p = core.resolve("Codesmith")
    assert p.config is None  # the DSN leak path is closed structurally


def test_sidecar_enforces_alias_audience_symmetry(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(
        private,
        "codesmith",
        """\
        persona: Codesmith
        credentials:
          - alias: github_token
            ref: env://GITHUB_TOKEN
            scope: {audience: [other_server]}
        mcp:
          - server: github
            uses_credentials: [github_token]
        """,
        suffix=".persona.yaml",
    )
    p = core.resolve("Codesmith")
    assert p.config is None
    assert "symmetry" in p.config_error.reason


# --- compose (ported spec + additive keys) ------------------------------------


def test_compose_identity_block_carries_lens_and_context() -> None:
    m = core.resolve("Firekeeper")
    payload = core.compose(m)
    block = payload["identity_block"]
    assert block.startswith('<masque-active name="Firekeeper" version="0.3.0">')
    assert "## Lens" in block
    assert m.lens.strip().splitlines()[0] in block
    assert "## Context" in block  # Firekeeper has context
    assert block.rstrip().endswith("</masque-active>")


def test_compose_includes_intent_when_given() -> None:
    m = core.resolve("Codesmith")
    payload = core.compose(m, intent="ship the parser")
    assert "## Intent" in payload["identity_block"]
    assert "ship the parser" in payload["identity_block"]
    assert payload["intent"] == "ship the parser"


def test_compose_omits_intent_section_when_absent() -> None:
    m = core.resolve("Codesmith")
    assert "## Intent" not in core.compose(m)["identity_block"]


def test_compose_version_is_a_plain_string() -> None:
    payload = core.compose(core.resolve("Codesmith"))
    assert type(payload["version"]) is str  # Version must never reach a serializer


def test_compose_plan_keys_present_only_when_plan_injected(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(private, "codesmith", VALID_SIDECAR, suffix=".persona.yaml")
    p = core.resolve("Codesmith")
    bare = core.compose(p)
    assert "capability_plan" not in bare  # degrade-by-absence
    plan = core.build_capability_plan(p, None)
    payload = core.compose(p, plan=plan)
    assert payload["capability_plan"]["host_apply"] == "none"
    assert payload["bound_refs"] == [
        {"alias": "github_token", "scheme": "env://", "status": "advisory"}
    ]


# --- build_capability_plan ------------------------------------------------------


def test_plan_advisory_at_tier_none(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(private, "codesmith", VALID_SIDECAR, suffix=".persona.yaml")
    p = core.resolve("Codesmith")
    plan, refs = core.build_capability_plan(p, None)
    assert plan.host_apply == "none"
    binding = plan.bindings[0].to_dict()
    assert binding["status"] == "advisory"
    assert binding["enforced"] is False
    assert binding["tier"] == "advisory"
    assert "advisory_allow" in binding and "effective_allow" not in binding
    assert refs[0].status == "advisory"


def test_plan_enforced_at_bind_tier(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(private, "codesmith", VALID_SIDECAR, suffix=".persona.yaml")
    p = core.resolve("Codesmith")
    snapshot = HostSnapshot(servers=frozenset({"github"}), achievable_tier="bind")
    plan, refs = core.build_capability_plan(p, snapshot)
    assert plan.host_apply == "bind"
    binding = plan.bindings[0].to_dict()
    assert binding["status"] == "applied"
    assert binding["enforced"] is True
    assert "effective_allow" in binding and "advisory_allow" not in binding
    assert refs[0].status == "pending"


def test_plan_marks_missing_server_unresolved(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(private, "codesmith", VALID_SIDECAR, suffix=".persona.yaml")
    p = core.resolve("Codesmith")
    snapshot = HostSnapshot(servers=frozenset({"other"}), achievable_tier="bind")
    plan, _ = core.build_capability_plan(p, snapshot)
    binding = plan.bindings[0].to_dict()
    assert binding["status"] == "unresolved-server"  # degrades, never fatal
    assert binding["enforced"] is False


def test_plan_empty_for_sidecar_less_persona() -> None:
    p = core.resolve("Codesmith")
    plan, refs = core.build_capability_plan(p, None)
    assert plan.host_apply == "none"
    assert plan.bindings == ()
    assert refs == []


# --- list / inspect (ported spec + additive keys) -------------------------------


def test_list_returns_full_bundled_catalog() -> None:
    catalog = core.list_masques()
    assert len(catalog) >= 35  # at least the bundled set
    names = {m["name"] for m in catalog}
    assert {"Firekeeper", "Codesmith"} <= names


def test_list_dedupes_by_stem_private_wins(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    catalog = core.list_masques()
    codesmiths = [m for m in catalog if m["name"] == "Codesmith"]
    assert len(codesmiths) == 1
    assert codesmiths[0]["source"] == "private"
    assert codesmiths[0]["version"] == "9.9.9"


def test_list_reports_sidecar_presence(private: Path) -> None:
    _write(private, "codesmith", VALID_SIDECAR, suffix=".persona.yaml")
    catalog = core.list_masques()
    entry = next(m for m in catalog if m["name"] == "Codesmith")
    assert entry["has_sidecar"] is True


def test_inspect_exposes_rubric() -> None:
    info = core.inspect("Firekeeper")
    assert info["has_rubric"]
    assert info["rubric"]
    assert info["lens"] and info["context"] and info["attributes"]


def test_inspect_is_pure_and_advisory_with_sidecar(private: Path) -> None:
    _write(private, "codesmith", PRIVATE_CODESMITH)
    _write(private, "codesmith", VALID_SIDECAR, suffix=".persona.yaml")
    info = core.inspect("Codesmith")
    assert info["has_config"] is True
    assert info["config_source"] == "private"
    # inspect never sees a host snapshot => always advisory (Phase 2 m-inspect)
    assert info["capability_plan"]["host_apply"] == "none"
    assert info["measurement_policy"]["enabled"] is False


# --- ports ----------------------------------------------------------------------


def test_env_adapter_resolves_and_material_hidden_from_repr(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from masques_core import CredentialScope, PersonaRef, SecretRef
    from masques_core.ports import EnvAdapter

    monkeypatch.setenv("TEST_TOKEN_XYZ", "s3cr3t")
    secret = EnvAdapter().resolve(
        SecretRef.parse("env://TEST_TOKEN_XYZ"),
        PersonaRef("Codesmith", Version.parse("1.0.0")),
        scope=CredentialScope(audience=("host",)),
    )
    assert secret.status == "resolved"
    assert secret.material == "s3cr3t"
    assert "s3cr3t" not in repr(secret)  # material excluded from repr (B-secret)
    assert "material" not in secret.to_safe_dict()


def test_get_port_returns_degrading_defaults() -> None:
    from masques_core.ports import get_port, reset_ports

    reset_ports()
    assert get_port("mcp").capabilities()["max_tier"] == "none"
    assert get_port("telemetry").score()["status"] == "unavailable"
    with pytest.raises(KeyError):
        get_port("nonsense")
