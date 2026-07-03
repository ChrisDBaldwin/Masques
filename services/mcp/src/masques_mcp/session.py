"""
Minimal local session state for the stdio server.

MCP is request/response and cannot pin a system prompt (PRD D5), so "active
masque" is necessarily soft state: the server records what was last donned (in
process, and optionally mirrored to a YAML file for other local tools to read),
but the *host* is what actually keeps the identity in context.

Set $MASQUES_SESSION_FILE to mirror state to disk; otherwise state is
in-process only for the life of the server.
"""

from __future__ import annotations

import os
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import yaml

_active: dict[str, Any] | None = None
_previous: dict[str, Any] | None = None


def _now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _session_file() -> Path | None:
    path = os.environ.get("MASQUES_SESSION_FILE")
    return Path(path).expanduser() if path else None


def _mirror() -> None:
    path = _session_file()
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        yaml.safe_dump(
            {"active": _active, "previous": _previous}, sort_keys=False, allow_unicode=True
        ),
        encoding="utf-8",
    )


def don(name: str, source: str) -> dict[str, Any]:
    """Record a don; the prior active masque (if any) becomes previous."""
    global _active, _previous
    if _active and _active.get("name"):
        _previous = {**_active, "doffed_at": _now()}
    _active = {"name": name, "source": source, "donned_at": _now()}
    _mirror()
    return _active


def doff() -> dict[str, Any] | None:
    """Clear the active masque; return what was doffed (or None if baseline)."""
    global _active, _previous
    doffed = _active
    if doffed:
        _previous = {**doffed, "doffed_at": _now()}
    _active = None
    _mirror()
    return doffed


def active() -> dict[str, Any] | None:
    return _active
