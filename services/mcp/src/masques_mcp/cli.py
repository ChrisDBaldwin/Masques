"""
`masque` CLI — the thin command-line adapter over the core.

This is what the Claude Code plugin shells out to (PRD M7), so there is ONE
authoritative compose shared by the plugin and the MCP server. Commands:

    masque list                       # catalog (YAML; --json for JSON)
    masque inspect <name>             # full fields incl rubric
    masque compose <name> [intent]    # the identity block /don injects
    masque score [session]            # local judge two-layer reaction

`compose` prints the raw `<masque-active>` identity block to stdout by default
(what the host pins into context); pass --json for the structured payload.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

import yaml

from . import core


def _emit(data: Any, as_json: bool) -> None:
    if as_json:
        print(json.dumps(data, indent=2, ensure_ascii=False))
    else:
        print(yaml.safe_dump(data, sort_keys=False, allow_unicode=True).rstrip())


def cmd_list(args: argparse.Namespace) -> int:
    _emit(core.list_masques(), args.json)
    return 0


def cmd_inspect(args: argparse.Namespace) -> int:
    try:
        _emit(core.inspect(args.name), args.json)
    except core.MasqueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


def cmd_compose(args: argparse.Namespace) -> int:
    try:
        masque = core.resolve(args.name)
    except core.MasqueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    intent = " ".join(args.intent) if args.intent else None
    payload = core.compose(masque, intent)
    if args.json:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        # Default: emit the raw identity block — what the host injects.
        print(payload["identity_block"])
    return 0


def cmd_score(args: argparse.Namespace) -> int:
    result = core.score(args.session)
    if not args.json and result.get("status") == "ok":
        # The judge already emits YAML; pass it through verbatim.
        print(result["report"])
    else:
        _emit(result, args.json)
    return 0 if result.get("status") == "ok" else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="masque",
        description="Compose, list, inspect, and score masques (the authoritative core).",
    )
    # Shared `--json` flag, accepted both before and after the subcommand.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--json", action="store_true", help="emit JSON instead of YAML/identity block"
    )
    parser.add_argument(
        "--json", action="store_true", help="emit JSON instead of YAML/identity block"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_list = sub.add_parser(
        "list", parents=[common], help="list available masques (private over bundled)"
    )
    p_list.set_defaults(func=cmd_list)

    p_inspect = sub.add_parser(
        "inspect", parents=[common], help="full fields for one masque (incl rubric)"
    )
    p_inspect.add_argument("name")
    p_inspect.set_defaults(func=cmd_inspect)

    p_compose = sub.add_parser(
        "compose", parents=[common], help="the identity block /don injects"
    )
    p_compose.add_argument("name")
    p_compose.add_argument("intent", nargs="*", help="optional intent")
    p_compose.set_defaults(func=cmd_compose)

    p_score = sub.add_parser(
        "score", parents=[common], help="local judge two-layer reaction"
    )
    p_score.add_argument("session", nargs="?", default=None, help="session id (default: latest)")
    p_score.set_defaults(func=cmd_score)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
