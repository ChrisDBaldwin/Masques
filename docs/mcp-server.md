# Masques MCP Server (local, stdio)

Masques ships as an **MCP server** so any MCP client — Claude Code, Claude
Desktop, Cursor, the MCP Inspector, or your own — can `list` / `inspect` / `don`
a masque and `score` a session locally. The server is a thin adapter over the
same authoritative core (`services/mcp/src/masques_mcp/core.py`) the Claude Code
plugin shells out to, so the two surfaces compose identical identities (no
drift).

Phase A is **local, free, and unauthenticated** over the **stdio** transport.
Scoring runs the local DuckDB judge on-device and never leaves the machine
(privacy spine, PRD D4).

## What it exposes

| Primitive | Name | Returns |
|-----------|------|---------|
| Tool | `list_masques` | catalog: name, version, domain, tagline, has_rubric, source (private over bundled) |
| Tool | `inspect_masque(name)` | full lens, context, attributes, rubric |
| Tool | `don(name, intent?)` | the composed `<masque-active>` identity block — what `/don` injects |
| Tool | `doff()` | clears local session state |
| Tool | `score(session_id?)` | local judge two-layer reaction (LOCAL only) |
| Prompt | `don-<name>` (one per masque) | the composed identity, as an MCP prompt |
| Resource | `masque://catalog`, `masque://{name}` | read-only discovery |

> **On persistence (PRD D5):** MCP is request/response and cannot pin a system
> prompt. `don` returns the identity block; the *host* must keep it in context
> for the masque to persist. Where a client supports MCP prompts, the
> `don-<name>` prompt is the native "select an identity" surface.

## Install

Requires Python ≥ 3.11 and [`uv`](https://docs.astral.sh/uv/).

```bash
cd services/mcp
uv venv && uv pip install -e .     # provides the `masque` CLI and `masques-mcp` server
```

Optionally put the `masque` CLI on your `PATH` (this is also what the plugin
prefers):

```bash
uv tool install /path/to/masques/services/mcp
```

## Register in a client

The server runs over stdio. The portable launch command (no activated venv
needed) is:

```
uv run --project /ABS/PATH/TO/masques/services/mcp masques-mcp
```

### Claude Code

```bash
claude mcp add masques -- uv run --project /ABS/PATH/TO/masques/services/mcp masques-mcp
claude mcp list        # → masques: ... ✓ Connected
```

Remove with `claude mcp remove masques`.

### Claude Desktop / Cursor (JSON config)

Add to the client's MCP config (`claude_desktop_config.json` for Claude
Desktop, or `.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "masques": {
      "command": "uv",
      "args": ["run", "--project", "/ABS/PATH/TO/masques/services/mcp", "masques-mcp"]
    }
  }
}
```

If you `uv tool install`ed the CLI, you can instead use `"command": "masques-mcp", "args": []`.

### MCP Inspector (quick check)

```bash
# List tools over stdio
npx -y @modelcontextprotocol/inspector --cli \
  /ABS/PATH/TO/masques/services/mcp/.venv/bin/masques-mcp --method tools/list

# Call a tool
npx -y @modelcontextprotocol/inspector --cli \
  /ABS/PATH/TO/masques/services/mcp/.venv/bin/masques-mcp \
  --method tools/call --tool-name don --tool-arg name=Codesmith
```

## Configuration (environment)

| Variable | Purpose | Default |
|----------|---------|---------|
| `MASQUES_HOME` | private masque dir (takes precedence) | `~/.masques` |
| `MASQUES_PERSONAS_DIR` | bundled personas dir override | `$CLAUDE_PLUGIN_ROOT/personas`, else repo `personas/` |
| `MASQUES_JUDGE` | path to `judge.sh` for `score` | `$CLAUDE_PLUGIN_ROOT/services/judge/judge.sh`, else repo |
| `MASQUES_SESSION_FILE` | mirror don/doff state to this YAML file | unset (in-process only) |
| `MCP_LOG_LEVEL` | server log level | `INFO` |

## Verified

- **MCP Inspector CLI** (canonical client): `tools/list` → `doff, don,
  inspect_masque, list_masques, score`; `prompts/list` → 39 prompts;
  `tools/call don name=Codesmith` → the composed identity block.
- **Claude Code** (`claude mcp add` → `claude mcp list`): `masques: … ✓
  Connected`.

## Scoring stays local

`score` shells out to `services/judge/judge.sh` (DuckDB) on your machine. It is
exposed only by this local server — never by a hosted one (PRD D4). If `duckdb`
or collector data is absent, `score` returns `{"status": "unavailable",
"reason": …}` rather than failing. To capture telemetry to score, run
`/audience seat` (Claude Code plugin) and work a session.
```
