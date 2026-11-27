#!/usr/bin/env python3
"""A fake rclone for refresh probes: a Drive kept in a JSON file, read through `rcd` on a Unix socket. No network.

The folder is beside this script's link (`FAKE_DRIVE`): drive.json {nodes, behavior}, and two logs, launches and calls.
"""
import hashlib, http.server, json, os, re, signal, socketserver, sys, time
from pathlib import Path

HOME = Path(__file__).absolute().parent

def drive(): return json.loads((HOME / "drive.json").read_text())
def log(name, line):
    with (HOME / name).open("a") as f: f.write(line + "\n")
def md5(body): return hashlib.md5(body.encode()).hexdigest()
def row(n): return {"Path": n["name"], "Name": n["name"], "ID": n["id"], "IsDir": n.get("body") is None, "Size": -1 if n.get("body") is None else len(n["body"]),
                    **({} if n.get("body") is None else {"Hashes": {"md5": md5(n["body"])}})}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def address_string(self): return "local"
    def send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        op = self.path.lstrip("/")
        p = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if op == "core/quit": self.send(200, {}); os._exit(0)
        if op == "rc/noop": return self.send(200, {})
        fs = p.get("fs") or p.get("srcFs") or ""
        parent = m[1] if (m := re.search(r"root_folder_id=([^,:]+)", fs)) else "AccountID"
        log("calls", f"{op} {parent}")
        d = drive(); b = d["behavior"]
        if b.get("delay"): time.sleep(b["delay"])
        if b.get("die"): os._exit(1)
        if b.get("error"): return self.send(500, {"error": b["error"], "status": 500})
        if op == "operations/list": return self.send(200, {"list": [row(n) for n in d["nodes"] if n["parent"] == parent]})
        if op == "backend/command":
            if b.get("old"): return self.send(500, {"error": "command not found"})
            q = p["arg"][0]
            out = []
            for n in d["nodes"]:
                if f"'{n['parent']}' in parents" not in q: continue
                item = {"id": n["id"], "name": n["name"], "parents": [n["parent"]], "mimeType": "application/vnd.google-apps.folder"}
                if n.get("body") is not None: item.update(mimeType="application/json", size=str(len(n["body"])), md5Checksum=md5(n["body"]))
                out.append(item)
            if b.get("moves"):  # The library is replaced while it is read.
                for n in d["nodes"]:
                    if n["id"] == "LibraryID": n["name"] = "Old games"
                (HOME / "drive.json").write_text(json.dumps(d))
            return self.send(200, {"result": out})
        if op == "operations/copyfile":
            n = next((n for n in d["nodes"] if n["parent"] == parent and n["name"] == p["srcRemote"]), None)
            if n is None: return self.send(404, {"error": "object not found"})
            (Path(p["dstFs"].removeprefix(":local:")) / p["dstRemote"]).write_text(n["body"])
            return self.send(200, {})
        self.send(404, {"error": "couldn't find method"})

def main():
    args = sys.argv[1:]
    log("launches", args[0])
    if args[0] == "config": print("Configuration file is stored at:\n" + str(HOME / "rclone.conf"))
    elif args[0] == "listremotes": print(json.dumps([{"name": "fixture", "type": "drive", "source": "file"}]))
    elif args[0] == "about":
        print("{}"); print(json.dumps({"msg": f"'root_folder_id = {drive()['account']}' - save this in the config to speed up startup"}), file=sys.stderr)
    elif args[0] == "rcd":
        log("pids", str(os.getpid()))
        class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
            daemon_threads = True
            request_queue_size = 64
        Server(next(a for a in args if a.startswith("unix://")).removeprefix("unix://"), Handler).serve_forever()
    else:
        if drive()["behavior"].get("error"): print(drive()["behavior"]["error"], file=sys.stderr); sys.exit(1)
        sys.exit(9)  # No single command is expected.

signal.signal(signal.SIGPIPE, signal.SIG_DFL)
main()
