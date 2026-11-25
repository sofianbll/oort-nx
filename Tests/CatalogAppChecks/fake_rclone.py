#!/usr/bin/env python3
"""A synthetic rclone for network measures: a local folder answers as a Drive account, each request waits.

FAKE_DRIVE: the folder; FAKE_LOG: one line per process and per request; FAKE_DELAY: seconds per request.
A recursive listing costs one request per folder, and waits once per level: rclone lists a level's folders together.
It never opens a network connection and never reads an rclone configuration.
"""
import fcntl
import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler
from pathlib import Path
import shutil
import socketserver
import sys
import time

ROOT = Path(os.environ["FAKE_DRIVE"])
LOG = os.environ["FAKE_LOG"]
DELAY = float(os.environ.get("FAKE_DELAY", "0.2"))
REMOTE = os.environ.get("FAKE_REMOTE", "fixture")
# With FAKE_EMPTY the connection exists only once a sign-in created it.
SIGNED_IN = Path(LOG + ".signed-in")


def log(kind, text):
    with open(LOG, "a") as file:
        fcntl.flock(file, fcntl.LOCK_EX)
        file.write(f"{time.time():.3f} {kind} {text}\n")


def request(name, count=1, waits=1):
    for _ in range(count):
        log("request", name)
    time.sleep(DELAY * waits)


def identity(path):
    return "account" if path == ROOT else "id" + hashlib.sha1(str(path.relative_to(ROOT)).encode()).hexdigest()[:16]


def by_identity(value):
    return next((path for path in [ROOT, *ROOT.rglob("*")] if path.is_dir() and identity(path) == value), None)


def item(path, base):
    entry = {"Path": str(path.relative_to(base)), "Name": path.name, "Size": -1 if path.is_dir() else path.stat().st_size,
             "IsDir": path.is_dir(), "ID": identity(path)}
    if path.is_file():
        entry["Hashes"] = {"md5": hashlib.md5(path.read_bytes()).hexdigest()}
    return entry


def listing(folder, recurse, depth, dirs, files):
    level, found, count, waits = [folder], [], 0, 0
    while level and waits < (depth if recurse else 1):
        count, waits = count + len(level), waits + 1
        children = [child for parent in level for child in sorted(parent.iterdir())]
        found += children
        level = [child for child in children if child.is_dir()]
    request("list", count, waits)
    return [item(path, folder) for path in found if not (dirs and path.is_file()) and not (files and path.is_dir())]


def located(target, root=None):
    remote, _, path = target.partition(":")
    for option in remote.split(",")[1:]:
        if option.startswith("root_folder_id=") and option != "root_folder_id=":
            root = option.partition("=")[2]
    base = by_identity(root) if root else ROOT
    return (base / path if path else base) if base else Path("/nonexistent")


def option(args, name, default=None):
    for index, value in enumerate(args):
        if value == name:
            return args[index + 1]
        if value.startswith(name + "="):
            return value.partition("=")[2]
    return default


class Control(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
        operation = self.path.strip("/")
        log("process", "curl")
        if operation in ("config/create", "config/update"):
            time.sleep(float(os.environ.get("FAKE_SIGN_IN", "0")))
            SIGNED_IN.touch()
            return self.reply(200, {})
        folder = located(body.get("fs", REMOTE + ":"))
        if body.get("remote"):
            folder = folder / body["remote"]
        options = body.get("opt", {})
        if operation == "operations/list":
            if not folder.is_dir():
                request("list")
                return self.reply(404, {"error": "error in ListJSON: directory not found"})
            depth = body.get("_config", {}).get("MaxDepth", 99)
            found = listing(folder, options.get("recurse", False), depth, options.get("dirsOnly"), options.get("filesOnly"))
            for entry in found:
                entry["Path"] = "/".join(part for part in (body.get("remote"), entry["Path"]) if part)
            return self.reply(200, {"list": found})
        if operation == "operations/stat":
            request("stat")
            return self.reply(200, {"item": item(folder, folder.parent) if folder.exists() else None})
        if operation == "operations/copyfile":
            request("get")
            destination = Path(body["dstFs"].partition(":local:")[2]) / body["dstRemote"]
            shutil.copyfile(located(body["srcFs"]) / body["srcRemote"], destination)
            return self.reply(200, {})
        return self.reply(404, {"error": "couldn't find method"})


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def get_request(self):
        connection, _ = super().get_request()
        return connection, ("local", 0)


def main(args):
    log("process", args[0])
    if args[0] == "version":
        print("rclone v1.75.2")
    elif args[0] == "listremotes":
        known = not os.environ.get("FAKE_EMPTY") or SIGNED_IN.exists()
        print(json.dumps([{"name": REMOTE, "type": "drive", "source": "file"}] if known else []))
    elif args[0] == "about":
        request("about")
        print("{}")
        print("'root_folder_id = account' - save this in the config to speed up startup", file=sys.stderr)
    elif args[0] == "config" and args[1:3] == ["encryption", "check"]:
        pass
    elif args[0] == "config" and args[1] == "delete":
        SIGNED_IN.unlink(missing_ok=True)
    elif args[0] == "config" and args[1] == "file":
        print(os.environ["FAKE_CONFIG"])
    elif args[0] == "config":
        print(f"[{REMOTE}]\ntype = drive" if args[1] == "redacted" else "")
    elif args[0] == "lsjson":
        folder = located(args[1], option(args, "--drive-root-folder-id"))
        if "--stat" in args:
            request("stat")
            print(json.dumps(item(folder, folder.parent)) if folder.exists() else "null")
        elif not folder.is_dir():
            request("list")
            print("directory not found", file=sys.stderr)
            return 3
        else:
            print(json.dumps(listing(folder, "--recursive" in args, int(option(args, "--max-depth", "99")),
                                     "--dirs-only" in args, "--files-only" in args)))
    elif args[0] == "copyto":
        request("get")
        shutil.copyfile(located(args[1], option(args, "--drive-root-folder-id")), args[2])
    elif args[0] == "mkdir":
        request("mkdir")
        located(args[1], option(args, "--drive-root-folder-id")).mkdir(parents=True, exist_ok=True)
    elif args[0] == "rcd":
        Server(option(args, "--rc-addr").partition("unix://")[2], Control).serve_forever()
    else:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
