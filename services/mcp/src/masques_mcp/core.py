"""
Tool-agnostic Masques core.

This module is the ONE authoritative implementation of the operations that
*use* a masque — resolve, compose, list, inspect, score. The Claude Code
plugin, the local stdio MCP server, and (later) the hosted server are all thin
adapters over this core. Nothing here imports MCP, argparse, or any transport;
it is pure Python over YAML files and the local judge.

Discovery (mirrors commands/don.md, private takes precedence):
  1. Private:  ${MASQUES_HOME:-~/.masques}/<name>.masque.yaml
  2. Bundled:  <repo>/personas/<name>.masque.yaml

The identity block produced by `compose` is the SAME content that
commands/don.md Step 4 injects as `<masque-active>` — lifted out of prose so it
can no longer drift between the plugin and the MCP server (PRD M7).
"""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

REQUIRED_FIELDS = ("name", "version", "lens")
MASQUE_SUFFIX = ".masque.yaml"


# =============================================================================
# Errors
# =============================================================================


class MasqueError(Exception):
    """Base class for masque resolution/parsing errors."""


class MasqueNotFoundError(MasqueError):
    """No masque file matched the requested name in any search path."""


class MasqueParseError(MasqueError):
    """A masque file exists but is malformed or missing required fields."""


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

    Resolution order (OQ4 — finding personas/ when not run from the repo):
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

    # services/mcp/src/masques_mcp/core.py -> repo root is parents[4]
    repo_personas = Path(__file__).resolve().parents[4] / "personas"
    return repo_personas


def search_paths() -> list[tuple[str, Path]]:
    """Ordered (source, directory) pairs; private first (wins on conflict)."""
    return [("private", private_dir()), ("shared", bundled_dir())]


# =============================================================================
# Masque model
# =============================================================================


@dataclass
class Masque:
    """A resolved, parsed masque."""

    name: str
    version: str
    lens: str
    source: str  # "private" | "shared"
    path: Path
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


def _parse_masque_file(path: Path, source: str) -> Masque:
    """Load + validate a single masque YAML file."""
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

    return Masque(
        name=str(data["name"]),
        version=str(data["version"]),
        lens=str(data["lens"]),
        source=source,
        path=path,
        context=data.get("context"),
        attributes=data.get("attributes") or {},
        rubric=data.get("rubric"),
        spinner_verbs=data.get("spinnerVerbs"),
        raw=data,
    )


# =============================================================================
# resolve
# =============================================================================


def resolve(name: str) -> Masque:
    """
    Resolve a masque by name (case-insensitive on the filename stem).

    Private `~/.masques` takes precedence over bundled `personas/`. Raises
    MasqueNotFoundError if no file matches, MasqueParseError if a matched file
    is malformed.
    """
    stem = name.strip().lower()
    if stem.endswith(MASQUE_SUFFIX):
        stem = stem[: -len(MASQUE_SUFFIX)]

    checked: list[str] = []
    for source, directory in search_paths():
        candidate = directory / f"{stem}{MASQUE_SUFFIX}"
        checked.append(str(candidate))
        if candidate.is_file():
            return _parse_masque_file(candidate, source)

    raise MasqueNotFoundError(
        f'masque "{name}" not found. Checked:\n  ' + "\n  ".join(checked)
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


def build_identity_block(masque: Masque, intent: str | None = None) -> str:
    """
    Build the `<masque-active>` identity block — the exact string a host
    injects to adopt the masque. This mirrors commands/don.md Step 4 and is the
    single source of truth for the format (the plugin shells out to get it).
    """
    sections = [f'<masque-active name="{masque.name}" version="{masque.version}">']
    sections.append("## Lens\n" + masque.lens.rstrip())
    if masque.context:
        sections.append("## Context\n" + masque.context.rstrip())
    attrs = _render_attributes(masque.attributes)
    if attrs:
        sections.append("## Attributes\n" + attrs)
    if intent:
        sections.append("## Intent\n" + intent.strip())
    block = "\n\n".join(sections) + "\n</masque-active>"
    return block


def compose(masque: Masque, intent: str | None = None) -> dict[str, Any]:
    """
    Compose a masque into the identity payload an agent adopts.

    Returns the structured fields plus `identity_block` — the prose the host
    pins into context. This is what `don` (tool/prompt) and `/don` both serve.
    """
    return {
        "name": masque.name,
        "version": masque.version,
        "source": masque.source,
        "intent": intent,
        "lens": masque.lens,
        "context": masque.context,
        "attributes": masque.attributes,
        "spinnerVerbs": masque.spinner_verbs,
        "identity_block": build_identity_block(masque, intent),
    }


# =============================================================================
# list / inspect
# =============================================================================


def list_masques() -> list[dict[str, Any]]:
    """
    Catalog of available masques, merging private over bundled (private wins on
    a filename-stem collision). Each entry: name, version, domain, tagline,
    has_rubric, source, stem. Malformed files are skipped (best-effort listing).
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
                masque = _parse_masque_file(path, source)
            except MasqueError:
                continue
            by_stem[stem] = {
                "name": masque.name,
                "version": masque.version,
                "domain": masque.domain,
                "tagline": masque.tagline,
                "has_rubric": masque.has_rubric,
                "source": source,
                "stem": stem,
            }
    return sorted(by_stem.values(), key=lambda m: m["name"].lower())


def inspect(name: str) -> dict[str, Any]:
    """Full fields for one masque, including lens, context, attributes, rubric."""
    masque = resolve(name)
    return {
        "name": masque.name,
        "version": masque.version,
        "source": masque.source,
        "path": str(masque.path),
        "lens": masque.lens,
        "context": masque.context,
        "attributes": masque.attributes,
        "rubric": masque.rubric,
        "has_rubric": masque.has_rubric,
        "spinnerVerbs": masque.spinner_verbs,
    }


# =============================================================================
# score (local judge wrapper)
# =============================================================================


def judge_script() -> Path:
    """
    Locate services/judge/judge.sh.

    Order: $MASQUES_JUDGE (explicit), $CLAUDE_PLUGIN_ROOT/services/judge, then
    repo-relative.
    """
    override = os.environ.get("MASQUES_JUDGE")
    if override:
        return Path(override).expanduser()
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root:
        candidate = Path(plugin_root) / "services" / "judge" / "judge.sh"
        if candidate.is_file():
            return candidate
    return Path(__file__).resolve().parents[4] / "services" / "judge" / "judge.sh"


def score(session: str | None = None, *, timeout: int = 180) -> dict[str, Any]:
    """
    Run the LOCAL DuckDB judge and return its two-layer reaction.

    Scoring never leaves the machine (privacy spine, PRD D4). Degrades
    gracefully: if duckdb or collector data is absent, returns
    {"status": "unavailable", "reason": ...} rather than raising.
    """
    script = judge_script()
    if not script.is_file():
        return {"status": "unavailable", "reason": f"judge script not found at {script}"}

    import shutil

    if shutil.which("duckdb") is None:
        return {
            "status": "unavailable",
            "reason": "duckdb not found — install: brew install duckdb",
        }

    env = dict(os.environ)
    if session:
        env["TARGET_SESSION"] = session

    try:
        proc = subprocess.run(
            ["bash", str(script)],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return {"status": "unavailable", "reason": f"judge timed out after {timeout}s"}

    if proc.returncode != 0:
        return {
            "status": "unavailable",
            "reason": (proc.stderr or proc.stdout or "judge failed").strip(),
        }

    return {"status": "ok", "report": proc.stdout.rstrip(), "local_only": True}
