"""
FastMCP server for Masques — local stdio (Phase A).

Mirrors the shape of OpenGander's `services/mcp-server/src/opengander_mcp/
server.py`, MINUS ClickHouse and MINUS auth (Phase A is local, free, unauth).
The hosted Phase-B server adds `auth=JWTTokenVerifier()` + HTTP transport over
this same surface (design-only here).

Surface (PRD §"MCP surface"):
  Tools     list_masques · inspect_masque(name) · don(name, intent?) · doff()
            · score(session?)  [LOCAL ONLY — privacy spine, D4]
  Prompts   don-<name>  (one per masque — the native "select an identity" surface)
  Resources masque://catalog · masque://{name}

Run:  masques-mcp           (entry point) — transport: stdio
      python -m masques_mcp.server
"""

from __future__ import annotations

import logging
import os
from typing import Any

from fastmcp import Context, FastMCP

from . import core, session

logging.basicConfig(
    level=os.environ.get("MCP_LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

mcp = FastMCP("Masques")


# =============================================================================
# Tools
# =============================================================================


@mcp.tool()
async def list_masques(ctx: Context) -> dict[str, Any]:
    """
    List available masques (cognitive identities an agent can adopt).

    Merges private `~/.masques` over the bundled `personas/` catalog (private
    wins on a name collision). Returns name, version, domain, tagline,
    has_rubric, and source for each.
    """
    catalog = core.list_masques()
    return {"count": len(catalog), "masques": catalog}


@mcp.tool()
async def inspect_masque(ctx: Context, name: str) -> dict[str, Any]:
    """
    Full detail for one masque: lens, context, attributes, and rubric.

    Args:
        name: masque name (case-insensitive, e.g. "Firekeeper").
    """
    try:
        return core.inspect(name)
    except core.MasqueError as exc:
        return {"error": str(exc)}


@mcp.tool()
async def don(ctx: Context, name: str, intent: str | None = None) -> dict[str, Any]:
    """
    Compose a masque identity for the agent to adopt.

    Returns the composed identity block (lens + context [+ intent]) — the same
    content the Claude Code `/don` command injects. NOTE (PRD D5): MCP cannot
    pin a system prompt; the *host* must keep `identity_block` in context for
    the masque to persist. This tool returns the content; it does not enforce
    persistence.

    Args:
        name: masque to don (case-insensitive).
        intent: optional, what you want to accomplish in this masque.
    """
    try:
        masque = core.resolve(name)
    except core.MasqueError as exc:
        return {"error": str(exc)}
    payload = core.compose(masque, intent)
    session.don(masque.name, masque.source)
    payload["note"] = (
        "Keep `identity_block` in context to stay in character. MCP cannot pin "
        "a system prompt, so persistence is the host's responsibility (PRD D5)."
    )
    return payload


@mcp.tool()
async def doff(ctx: Context) -> dict[str, Any]:
    """
    Doff the active masque and return to baseline.

    Clears local session state. The host should stop applying the previously
    donned identity block (MCP cannot un-pin it for you).
    """
    doffed = session.doff()
    if not doffed:
        return {"status": "baseline", "message": "No masque was active."}
    return {
        "status": "doffed",
        "doffed": doffed["name"],
        "message": (
            f"Doffed {doffed['name']}. Stop applying its identity block; "
            "you are back to baseline."
        ),
    }


@mcp.tool()
async def score(ctx: Context, session_id: str | None = None) -> dict[str, Any]:
    """
    Score a session with the LOCAL DuckDB judge — two-layer reaction
    (Layer A house reaction always; Layer B lift once earned).

    Scoring runs entirely on-device and never leaves the machine (privacy
    spine, PRD D4). This tool is exposed ONLY by the local server. Degrades
    gracefully: returns status "unavailable" if duckdb or collector data is
    absent rather than failing.

    Args:
        session_id: session to score (default: most recent captured session).
    """
    return core.score(session_id)


# =============================================================================
# Prompts — one per masque (don-<name>)
# =============================================================================
#
# The native "select an identity" surface. Each masque becomes a prompt named
# `don-<stem>`; prompts/get returns the composed identity block (PRD M5).


def _make_prompt(stem: str, display_name: str):
    async def _prompt() -> str:
        masque = core.resolve(stem)
        return core.compose(masque)["identity_block"]

    _prompt.__name__ = f"don_{stem.replace('-', '_')}"
    _prompt.__doc__ = f"Adopt the {display_name} masque (composed identity block)."
    return _prompt


def _register_prompts() -> int:
    registered = 0
    for entry in core.list_masques():
        stem = entry["stem"]
        fn = _make_prompt(stem, entry["name"])
        mcp.prompt(name=f"don-{stem}", description=fn.__doc__)(fn)
        registered += 1
    return registered


# =============================================================================
# Resources — read-only discovery
# =============================================================================


@mcp.resource("masque://catalog", mime_type="application/json")
async def catalog_resource() -> dict[str, Any]:
    """The full masque catalog (private over bundled)."""
    catalog = core.list_masques()
    return {"count": len(catalog), "masques": catalog}


@mcp.resource("masque://{name}", mime_type="application/json")
async def masque_resource(name: str) -> dict[str, Any]:
    """Full detail for a single masque by name."""
    try:
        return core.inspect(name)
    except core.MasqueError as exc:
        return {"error": str(exc)}


# =============================================================================
# Entry point
# =============================================================================

_PROMPT_COUNT = _register_prompts()
logger.info("Registered %d masque prompts", _PROMPT_COUNT)


def main() -> None:
    """Run the server over stdio (Phase A: local, free, no auth)."""
    logger.info("Starting Masques MCP server (stdio)...")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
