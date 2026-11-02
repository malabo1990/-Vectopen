#!/usr/bin/env python3
"""Pide al LSP de Godot los diagnósticos (errores y avisos) de todos los .gd."""
import json, os, socket, sys, time, glob

ROOT = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 6008

def connect():
    for _ in range(120):
        try:
            s = socket.create_connection((os.environ.get("LSP_HOST", "127.0.0.1"), PORT), timeout=5)
            return s
        except OSError:
            time.sleep(1)
    raise SystemExit("LSP no responde")

s = connect()
s.settimeout(0.5)
buf = b""
mid = 0

def send(method, params, req=True):
    global mid
    msg = {"jsonrpc": "2.0", "method": method, "params": params}
    if req:
        mid += 1
        msg["id"] = mid
    body = json.dumps(msg).encode()
    s.sendall(b"Content-Length: %d\r\n\r\n" % len(body) + body)

def read_msgs(timeout=1.0):
    global buf
    out = []
    end = time.time() + timeout
    while time.time() < end:
        try:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        except socket.timeout:
            pass
        while True:
            i = buf.find(b"\r\n\r\n")
            if i < 0:
                break
            head = buf[:i].decode()
            n = int([l for l in head.split("\r\n") if l.lower().startswith("content-length")][0].split(":")[1])
            if len(buf) < i + 4 + n:
                break
            out.append(json.loads(buf[i + 4:i + 4 + n]))
            buf = buf[i + 4 + n:]
    return out

uri_root = "file://" + ROOT
send("initialize", {"processId": os.getpid(), "rootUri": uri_root, "capabilities": {}})
read_msgs(3)
send("initialized", {}, req=False)
files = []
for f in glob.glob(ROOT + "/**/*.gd", recursive=True):
    rel = os.path.relpath(f, ROOT)
    if rel.startswith(("addons/", "test/", ".godot/", "build/", "dist/")):
        continue
    files.append(f)
diags = {}
for f in files:
    with open(f, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    send("textDocument/didOpen", {"textDocument": {"uri": "file://" + f, "languageId": "gdscript", "version": 1, "text": text}}, req=False)
    for m in read_msgs(0.15):
        if m.get("method") == "textDocument/publishDiagnostics":
            p = m["params"]
            diags[p["uri"]] = p["diagnostics"]
for m in read_msgs(5):
    if m.get("method") == "textDocument/publishDiagnostics":
        p = m["params"]
        diags[p["uri"]] = p["diagnostics"]
rows = []
for uri, ds in diags.items():
    for d in ds:
        rows.append((os.path.relpath(uri[7:], ROOT), d["range"]["start"]["line"] + 1, d.get("severity"), d.get("code", ""), d["message"]))
rows.sort()
with open(sys.argv[3] if len(sys.argv) > 3 else "/dev/stdout", "w") as out:
    for r in rows:
        out.write("%s:%d\tsev=%s\t%s\t%s\n" % r)
print("archivos=%d con_diag=%d diagnosticos=%d" % (len(files), len(diags), len(rows)), file=sys.stderr)
