"""
Masques core, re-exported from the portable `masques-core` package — plus the
local judge adapter, which stays with this surface (Phase 3 §2: telemetry
adapters live with the surfaces that need them, not in core).

`resolve()` now returns a `Persona` (pinned Identity + optional sidecar). It
is a strict drop-in for the old `Masque`: read-through properties keep
`m.name` / `m.source` / `m.lens` / `m.version` working verbatim, so the
server, CLI, and tests are unchanged. `Masque` is retained as an alias.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any

from masques_core import (
    MASQUE_SUFFIX,
    PERSONA_SUFFIX,
    REQUIRED_FIELDS,
    BoundRef,
    CapabilityPlan,
    HostSnapshot,
    Identity,
    MasqueError,
    MasqueNotFoundError,
    MasqueParseError,
    Persona,
    PersonaConfig,
    PersonaConfigError,
    PersonaRef,
    Version,
    build_capability_plan,
    build_identity_block,
    bundled_dir,
    compose,
    inspect,
    list_masques,
    private_dir,
    resolve,
    search_paths,
)

# Backward-compatible alias: Persona is the drop-in for the old dataclass.
Masque = Persona

__all__ = [
    "MASQUE_SUFFIX",
    "PERSONA_SUFFIX",
    "REQUIRED_FIELDS",
    "BoundRef",
    "CapabilityPlan",
    "HostSnapshot",
    "Identity",
    "Masque",
    "MasqueError",
    "MasqueNotFoundError",
    "MasqueParseError",
    "Persona",
    "PersonaConfig",
    "PersonaConfigError",
    "PersonaRef",
    "Version",
    "build_capability_plan",
    "build_identity_block",
    "bundled_dir",
    "compose",
    "inspect",
    "judge_script",
    "list_masques",
    "private_dir",
    "resolve",
    "score",
    "search_paths",
]


# =============================================================================
# score (local judge wrapper) — the LocalJudge telemetry adapter
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
