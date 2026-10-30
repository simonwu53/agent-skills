#!/usr/bin/env python3
"""Persistent bridge to Safari's built-in MCP server (`safaridriver --mcp`).

    safari_mcp.py start            start the background server (one Safari automation session)
    safari_mcp.py tools            list Safari's tools and their arguments
    safari_mcp.py call '<json>'    run [["tool", {args}], ...] in order and print the results
    safari_mcp.py status           say whether the server is running
    safari_mcp.py stop             end the session and stop the server

The server listens on a Unix socket in the temp dir. It exits on `stop`, or by
itself after IDLE_TIMEOUT seconds without a request, and removes the socket.
"""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time

SOCKET = os.path.join(tempfile.gettempdir(), f"safari-test-{os.getuid()}.sock")
IDLE_TIMEOUT = 3600


class SafariMCP:
    def __init__(self):
        self.proc = subprocess.Popen(
            ["/usr/bin/safaridriver", "--mcp"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
        self.next_id = 0
        self.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                    "clientInfo": {"name": "safari-test", "version": "1"}})
        self.write({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def write(self, msg):
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def request(self, method, params=None):
        self.next_id += 1
        self.write({"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params or {}})
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("safaridriver exited")
            reply = json.loads(line)
            if reply.get("id") == self.next_id:
                return reply

    def close(self):
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def recv_line(conn):
    data = b""
    while not data.endswith(b"\n"):
        chunk = conn.recv(65536)
        if not chunk:
            break
        data += chunk
    return json.loads(data)


def send_line(conn, obj):
    conn.sendall((json.dumps(obj) + "\n").encode())


def serve():
    safari = SafariMCP()
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET)
    server.listen()
    server.settimeout(IDLE_TIMEOUT)
    try:
        while True:
            try:
                conn, _ = server.accept()
            except socket.timeout:
                break
            with conn:
                conn.settimeout(None)
                req = recv_line(conn)
                if req["op"] == "stop":
                    send_line(conn, {"ok": True})
                    break
                try:
                    if req["op"] == "ping":
                        result = None
                    elif req["op"] == "tools":
                        result = safari.request("tools/list")["result"]["tools"]
                    else:
                        result = [[name, safari.request("tools/call", {"name": name, "arguments": args})]
                                  for name, args in req["calls"]]
                    send_line(conn, {"ok": True, "result": result})
                except Exception as e:
                    send_line(conn, {"ok": False, "error": str(e)})
                    if safari.proc.poll() is not None:
                        break
    finally:
        server.close()
        os.unlink(SOCKET)
        safari.close()


def client(req):
    """Send one request to the server; return its reply, or None if it isn't running."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.connect(SOCKET)
            send_line(conn, req)
            return recv_line(conn)
    except (FileNotFoundError, ConnectionRefusedError):
        return None


def start():
    if client({"op": "ping"}):
        print("already running")
        return
    if os.path.exists(SOCKET):  # left behind by a server that died
        os.unlink(SOCKET)
    subprocess.Popen([sys.executable, __file__, "serve"], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(30):
        time.sleep(0.5)
        if client({"op": "ping"}):
            print(f"started (socket {SOCKET}, idle timeout {IDLE_TIMEOUT}s)")
            return
    sys.exit("server did not start; run `safari_mcp.py serve` in the foreground to see the error")


def print_calls(results):
    for name, reply in results:
        if "error" in reply:
            print(f"== {name} ERROR: {json.dumps(reply['error'])}")
            continue
        flag = " ERROR" if reply["result"].get("isError") else ""
        for part in reply["result"].get("content", []):
            print(f"== {name}{flag}: {part.get('text', '<' + part.get('type', '?') + ' content>')}")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "serve":
        serve()
    elif cmd == "start":
        start()
    elif cmd in ("tools", "call", "status", "stop"):
        req = {"tools": {"op": "tools"},
               "call": {"op": "call", "calls": json.loads(sys.argv[2]) if len(sys.argv) > 2 else []},
               "status": {"op": "ping"},
               "stop": {"op": "stop"}}[cmd]
        reply = client(req)
        if reply is None:
            if cmd == "status":
                print("not running")
                return
            sys.exit("not running")
        if not reply["ok"]:
            sys.exit(f"error: {reply['error']}")
        if cmd == "tools":
            for tool in reply["result"]:
                print(tool["name"], json.dumps(tool.get("inputSchema", {}).get("properties", {})))
        elif cmd == "call":
            print_calls(reply["result"])
        else:
            print("running" if cmd == "status" else "stopped")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
