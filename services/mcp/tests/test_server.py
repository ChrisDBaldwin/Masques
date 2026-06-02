"""
Server tests — exercise the MCP surface through a real in-memory FastMCP
client. These are the spec for M1-M6 at the protocol layer.
"""

from __future__ import annotations

import json

import pytest
from fastmcp import Client

from masques_mcp import server


def _data(result):
    """Extract structured payload from a CallToolResult."""
    if getattr(result, "data", None) is not None:
        return result.data
    return result.structured_content


@pytest.fixture
async def client():
    async with Client(server.mcp) as c:
        yield c


async def test_tools_are_registered(client) -> None:
    names = {t.name for t in await client.list_tools()}
    assert {"list_masques", "inspect_masque", "don", "doff", "score"} == names


async def test_list_masques_returns_catalog(client) -> None:
    d = _data(await client.call_tool("list_masques", {}))
    assert d["count"] >= 35
    assert any(m["name"] == "Firekeeper" for m in d["masques"])


async def test_inspect_masque_returns_rubric(client) -> None:
    d = _data(await client.call_tool("inspect_masque", {"name": "Firekeeper"}))
    assert d["version"] == "0.3.0"
    assert d["has_rubric"] and d["rubric"]
    assert d["lens"] and d["context"]


async def test_don_returns_identity_block(client) -> None:
    d = _data(await client.call_tool("don", {"name": "Codesmith", "intent": "ship it"}))
    block = d["identity_block"]
    assert block.startswith('<masque-active name="Codesmith"')
    assert "## Lens" in block and "## Context" in block and "## Intent" in block


async def test_don_unknown_returns_error(client) -> None:
    d = _data(await client.call_tool("don", {"name": "nope-xyz"}))
    assert "error" in d


async def test_doff_clears_state(client) -> None:
    await client.call_tool("don", {"name": "Codesmith"})
    d = _data(await client.call_tool("doff", {}))
    assert d["status"] == "doffed"
    assert d["doffed"] == "Codesmith"


async def test_one_prompt_per_masque(client) -> None:
    prompts = await client.list_prompts()
    names = {p.name for p in prompts}
    assert len(prompts) >= 35
    assert "don-firekeeper" in names


async def test_prompt_returns_composed_identity(client) -> None:
    result = await client.get_prompt("don-codesmith", {})
    text = result.messages[0].content.text
    assert text.startswith('<masque-active name="Codesmith"')


async def test_catalog_resource(client) -> None:
    result = await client.read_resource("masque://catalog")
    payload = json.loads(result[0].text)
    assert payload["count"] >= 35


async def test_masque_resource_template(client) -> None:
    result = await client.read_resource("masque://Witness")
    payload = json.loads(result[0].text)
    assert payload["name"] == "Witness"


async def test_score_returns_status(client) -> None:
    """score always returns a status; ok if judge+data present, else unavailable."""
    d = _data(await client.call_tool("score", {}))
    assert d["status"] in {"ok", "unavailable"}
    if d["status"] == "ok":
        assert d["local_only"] is True
        assert "report" in d
