"""
Parity test (PRD M7) — the no-drift guarantee.

There is exactly ONE compose. This test proves the three adapters all produce
the byte-identical identity block:

  1. the `masque compose` CLI (a real subprocess — what the Claude Code plugin
     shells out to),
  2. the in-process core (`core.compose`),
  3. the MCP server `don` tool (what any MCP client receives).

If any adapter ever re-derives compose on its own, one of these comparisons
breaks. The plugin command specs (commands/{don,list,inspect}.md) inject the
CLI's stdout verbatim, so plugin == CLI by construction; this test pins
CLI == core == server so the chain is closed.
"""

from __future__ import annotations

import subprocess
import sys

import pytest
from fastmcp import Client

from masques_mcp import core, server

# A spread: with context, with a rubric, with/without intent.
SAMPLE_MASQUES = ["Codesmith", "Firekeeper", "Mirror", "Witness"]


def _cli_compose(name: str, intent: str | None = None) -> str:
    """Invoke the CLI exactly as the plugin would (module entry, real process)."""
    args = [sys.executable, "-m", "masques_mcp.cli", "compose", name]
    if intent:
        args.append(intent)
    proc = subprocess.run(args, capture_output=True, text=True, check=True)
    # CLI prints the identity block followed by a trailing newline from print().
    return proc.stdout.rstrip("\n")


@pytest.mark.parametrize("name", SAMPLE_MASQUES)
def test_cli_matches_core(name: str) -> None:
    core_block = core.compose(core.resolve(name))["identity_block"]
    assert _cli_compose(name) == core_block


@pytest.mark.parametrize("name", SAMPLE_MASQUES)
def test_cli_matches_core_with_intent(name: str) -> None:
    intent = "ship the thing"
    core_block = core.compose(core.resolve(name), intent)["identity_block"]
    assert _cli_compose(name, intent) == core_block


async def test_server_don_matches_cli() -> None:
    """The MCP server's don tool returns the same block the CLI emits."""
    async with Client(server.mcp) as c:
        for name in SAMPLE_MASQUES:
            result = await c.call_tool("don", {"name": name})
            data = result.data if result.data is not None else result.structured_content
            assert data["identity_block"] == _cli_compose(name)
