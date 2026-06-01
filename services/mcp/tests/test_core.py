"""
Tests for the tool-agnostic core — these double as the spec for what
resolve/compose/list/inspect guarantee.

They run against the repo's bundled `personas/` and an isolated temp dir for
private-precedence cases (never the real ~/.masques).
"""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from masques_mcp import core


# --- fixtures ---------------------------------------------------------------


@pytest.fixture
def private(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """An isolated private masque dir wired in via $MASQUES_HOME."""
    monkeypatch.setenv("MASQUES_HOME", str(tmp_path))
    return tmp_path


def _write(dir_: Path, stem: str, body: str) -> Path:
    path = dir_ / f"{stem}.masque.yaml"
    path.write_text(textwrap.dedent(body), encoding="utf-8")
    return path


# --- resolve ----------------------------------------------------------------


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
    _write(
        private,
        "codesmith",
        """\
        name: Codesmith
        version: "9.9.9"
        lens: |
          private shadow
        """,
    )
    m = core.resolve("Codesmith")
    assert m.source == "private"
    assert m.version == "9.9.9"


def test_missing_required_field_raises_parse_error(private: Path) -> None:
    _write(private, "broken", "name: Broken\nversion: \"1.0.0\"\n")  # no lens
    with pytest.raises(core.MasqueParseError):
        core.resolve("broken")


# --- compose ----------------------------------------------------------------


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


# --- list / inspect ---------------------------------------------------------


def test_list_returns_full_bundled_catalog() -> None:
    catalog = core.list_masques()
    assert len(catalog) >= 35  # M2: at least the bundled set
    names = {m["name"] for m in catalog}
    assert {"Firekeeper", "Codesmith"} <= names


def test_list_dedupes_by_stem_private_wins(private: Path) -> None:
    _write(
        private,
        "codesmith",
        """\
        name: Codesmith
        version: "9.9.9"
        lens: |
          private shadow
        """,
    )
    catalog = core.list_masques()
    codesmiths = [m for m in catalog if m["name"] == "Codesmith"]
    assert len(codesmiths) == 1
    assert codesmiths[0]["source"] == "private"
    assert codesmiths[0]["version"] == "9.9.9"


def test_inspect_exposes_rubric() -> None:
    info = core.inspect("Firekeeper")
    assert info["has_rubric"]
    assert info["rubric"]
    assert info["lens"] and info["context"] and info["attributes"]
