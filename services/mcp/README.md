# masques-mcp

Masques as an MCP server (PRD v1.2). One tool-agnostic **core**
(`resolve · compose · list · inspect · score`) with thin adapters:

- **`masque` CLI** — what the Claude Code plugin shells out to (one
  authoritative compose, no drift).
- **FastMCP stdio server** (`masques-mcp`) — exposes `list_masques`,
  `inspect_masque`, `don`, `doff`, `score` tools, one `don-<name>` prompt per
  masque, and `masque://catalog` / `masque://{name}` resources.

Local, free, no auth. Scoring runs the local DuckDB judge on-device and never
leaves the machine (privacy spine, PRD D4).

## Install (dev)

```bash
cd services/mcp
uv venv && uv pip install -e .
```

## CLI

```bash
masque list                      # catalog (YAML)
masque inspect Firekeeper        # full fields incl rubric
masque compose Codesmith "ship the parser"   # the identity block /don injects
masque score                     # local judge two-layer reaction
```

## Run the stdio server

```bash
uv run masques-mcp               # transport: stdio
```

See `docs/mcp-server.md` for registering it in a real MCP client.
