#!/usr/bin/env python3
"""Tiny MCP server used by the og integration tests.

Speaks JSON-RPC 2.0 over stdio and advertises a single `add` tool that sums
two integers. stdlib-only, so it runs on any Python 3.9+ without any pip
install. The og CLI spawns it with `python3 calculator.py`.
"""

import json
import sys


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        mid = msg.get("id")
        method = msg.get("method")

        if method == "initialize":
            send({
                "jsonrpc": "2.0",
                "id": mid,
                "result": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "serverInfo": {"name": "og-test-calc", "version": "0.1.0"},
                },
            })
        elif method == "notifications/initialized":
            # Notification — no response expected.
            pass
        elif method == "tools/list":
            send({
                "jsonrpc": "2.0",
                "id": mid,
                "result": {
                    "tools": [{
                        "name": "add",
                        "description": "Add two integers and return the sum.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "a": {"type": "integer", "description": "First addend"},
                                "b": {"type": "integer", "description": "Second addend"},
                            },
                            "required": ["a", "b"],
                        },
                    }],
                },
            })
        elif method == "tools/call":
            params = msg.get("params", {})
            args = params.get("arguments", {})
            if params.get("name") == "add":
                result = int(args.get("a", 0)) + int(args.get("b", 0))
                send({
                    "jsonrpc": "2.0",
                    "id": mid,
                    "result": {
                        "content": [{"type": "text", "text": str(result)}],
                        "isError": False,
                    },
                })
            else:
                send({
                    "jsonrpc": "2.0",
                    "id": mid,
                    "error": {
                        "code": -32601,
                        "message": f"unknown tool: {params.get('name')}",
                    },
                })
        else:
            if mid is not None:
                send({
                    "jsonrpc": "2.0",
                    "id": mid,
                    "error": {"code": -32601, "message": f"unknown method: {method}"},
                })


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
