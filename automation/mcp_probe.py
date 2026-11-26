#!/usr/bin/env python3
"""Минимальный MCP stdio: один инструмент curskill_probe_ping.

Пишет токен в файл из argv[1] и возвращает тот же токен.
Секретов нет. Нужен, чтобы вкладка стенда могла доказать, что сервер ей виден.
"""
from __future__ import annotations

import json
import secrets
import sys
from pathlib import Path


def _read_message() -> dict | None:
    line = sys.stdin.buffer.readline()
    if not line:
        return None
    # Клиент может начать с Content-Type, а Content-Length поставить вторым заголовком.
    if line[:1] != b"{" and b":" in line[:40]:
        headers = [line]
        while line not in (b"\r\n", b"\n", b""):
            line = sys.stdin.buffer.readline()
            if not line:
                break
            headers.append(line)
            if line in (b"\r\n", b"\n"):
                break
        length = None
        for header in headers:
            if header.lower().startswith(b"content-length:"):
                length = int(header.split(b":", 1)[1].strip())
        if length is None:
            print("mcp_probe: кадр без Content-Length", file=sys.stderr, flush=True)
            return None
        body = sys.stdin.buffer.read(length)
        return json.loads(body.decode("utf-8"))
    return json.loads(line.decode("utf-8"))


def _write_message(payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def _result(msg_id: object, result: dict) -> None:
    _write_message({"jsonrpc": "2.0", "id": msg_id, "result": result})


def _tool_text(token: str) -> dict:
    return {
        "content": [{"type": "text", "text": token}],
        "isError": False,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("mcp_probe: нужен путь файла токена", file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    print("mcp_probe ready", file=sys.stderr, flush=True)
    while True:
        try:
            msg = _read_message()
        except (json.JSONDecodeError, UnicodeError, ValueError) as exc:
            print(f"mcp_probe read {type(exc).__name__}", file=sys.stderr, flush=True)
            return 1
        if msg is None:
            return 0
        method = msg.get("method")
        msg_id = msg.get("id")
        print(f"mcp_probe method={method}", file=sys.stderr, flush=True)
        if method == "initialize":
            version = "2024-11-05"
            params = msg.get("params")
            if isinstance(params, dict) and isinstance(params.get("protocolVersion"), str):
                version = params["protocolVersion"]
            _result(
                msg_id,
                {
                    "protocolVersion": version,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "curskill-probe", "version": "1"},
                },
            )
        elif method == "notifications/initialized":
            continue
        elif method == "tools/list":
            _result(
                msg_id,
                {
                    "tools": [
                        {
                            "name": "curskill_probe_ping",
                            "description": "Return a probe token.",
                            "inputSchema": {"type": "object", "properties": {}},
                        }
                    ]
                },
            )
        elif method == "tools/call":
            token = "probe-ok-" + secrets.token_hex(8)
            out.write_text(token + "\n", encoding="utf-8")
            _result(msg_id, _tool_text(token))
        elif msg_id is not None:
            _write_message(
                {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "error": {"code": -32601, "message": f"unknown {method}"},
                }
            )


if __name__ == "__main__":
    raise SystemExit(main())
