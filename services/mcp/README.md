# masques-mcp

Masques as an MCP server (PRD v1.2). One tool-agnostic **core**
(`resolve · compose · list · inspect · score`) with thin adapters:

- **`masques-cli`** — what the Claude Code plugin shells out to (one
  authoritative compose, no drift).
- **FastMCP stdio server** (`masques-mcp`) — exposes `list_masques`,
  `inspect_masque`, `don`, `doff`, `score` tools, one `don-<name>` prompt per
  masque, and `masque://catalog` / `masque://{name}` resources.

Local, free, no auth. Scoring runs the local DuckDB judge on-device and never
leaves the machine (privacy spine, PRD D4).

## Install

**Recommended — global `masques-cli` / `masques-mcp` on your PATH** (this is also
what the Claude Code plugin prefers):

```bash
cd services/mcp
uv tool install --editable .     # installs `masques-cli` + `masques-mcp` to ~/.local/bin
```

`--editable` keeps the install pointed at this checkout so it can find the
bundled `personas/`. Make sure `~/.local/bin` is on your `PATH` (`uv tool
install` prints a warning if it isn't; run `uv tool update-shell` to fix it).

> A **non-editable** `uv tool install .` currently won't find the bundled
> masques (it only sees private `~/.masques`), because `personas/` isn't yet
> vendored into the wheel — that's open question OQ4. Until then use
> `--editable`, or set `MASQUES_PERSONAS_DIR=/path/to/masques/personas`.

**Dev (venv, editable)** — note the `masques-cli` command only exists *inside* the
venv, so either activate it or prefix with `uv run`:

```bash
cd services/mcp
uv venv && uv pip install -e .
source .venv/bin/activate         # then `masques-cli ...` works
# or, without activating:
uv run masques-cli list
```

## CLI

```bash
masques-cli list                 # catalog (YAML)
masques-cli inspect Firekeeper   # full fields incl rubric
masques-cli compose Codesmith "ship the parser"   # the identity block /don injects
masques-cli score                # local judge two-layer reaction
```

## Run the stdio server

```bash
masques-mcp                      # transport: stdio (if installed via `uv tool install`)
# or, from the dev venv:
uv run masques-mcp
```

See `docs/mcp-server.md` for registering it in a real MCP client.
