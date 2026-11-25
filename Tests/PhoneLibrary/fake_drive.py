#!/usr/bin/env python3
"""A local stand-in for Google Drive v3 and Google's token endpoint, with injected failures. Standard library only.

usage: fake_drive.py <vector.json>           prints the port, serves 127.0.0.1 until its standard input closes
       fake_drive.py <vector.json> <port>    serves until it is killed: what a simulator or an emulator talks to

It answers the calls a read-only client makes (files.list by parent, files.get with alt=media and Range, token, revoke) and refuses
every other one, so a client that tried to write would fail. `GET /__log` returns and clears what was asked, without any credential.
`GET /auth` is a page that plays Google's sign-in: Allow and Refuse go back to the address the app gave. While it serves, a test can
POST `/__faults` (a JSON list of faults, replacing the others), `/__slow` (bytes per second, 0 for no limit), `/__down` ("1" or "0": every
connection is dropped), `/__vector` (another vector) and `/__revoke` (no token is good any more). None of these is a Google address.

A vector's `drive` is {"root", "page_size", "nodes": [{id, name, parent, type, text|base64|fill, size_says, sha256_says, ...}]}.
A fault is {"on": "list"|"media"|"token", "node": id, "skip": n, "times": n, "do": ..., ...}; `do` is one of:
  status    answer `status` with Drive's error body (`reason`) and `retry_after`
  cut       announce the whole body, send `bytes` of it, close
  hang_up   close without answering
  whole     ignore Range: answer 200 with the whole file
  total     lie about the total in Content-Range (`total`)
  shift     answer the range that starts one byte later
  longer    add `bytes` to the body
  corrupt   flip the first byte
  redirect  answer 302 to `to`
  gzip      answer a gzip body
  garbage   answer 200 with a body that is not JSON
  loop      answer a nextPageToken that never changes
  partial   set incompleteSearch
  shrink    answer fewer scopes or more (`scope`) on the token endpoint
"""
import base64, gzip, hashlib, html, json, pathlib, re, socketserver, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlsplit

FOLDER = "application/vnd.google-apps.folder"
TYPES = {"folder": FOLDER, "shortcut": "application/vnd.google-apps.shortcut", "document": "application/vnd.google-apps.document"}
SCOPE = "https://www.googleapis.com/auth/drive.readonly"


def content(node):
    if "text" in node:
        return node["text"].encode()
    if "path" in node:
        return pathlib.Path(node["path"]).read_bytes()
    if "base64" in node:
        return base64.b64decode(node["base64"])
    if "fill" in node:
        size, seed, out = node["fill"]["size"], node["fill"]["seed"], bytearray()
        block = 0
        while len(out) < size:
            out += hashlib.sha256(f"{seed}:{block}".encode()).digest()
            block += 1
        return bytes(out[:size])
    return b""


class Drive:
    def __init__(self, vector):
        self.slow, self.down, self.codes = 0, False, {}
        self.refresh, self.access, self.issued, self.calls, self.log = set(), set(), 0, 0, []
        self.lock = threading.Lock()
        self.load(vector)
        if self.auth.get("refresh", "good") == "good":
            self.refresh.add("RT-CANARY-0")
        self.codes.update(self.auth.get("codes", {}))

    def load(self, vector):
        drive = vector["drive"]
        self.page = drive.get("page_size", 1000)
        self.nodes = {n["id"]: dict(n, data=content(n)) for n in drive["nodes"]}
        self.order = [n["id"] for n in drive["nodes"]]
        self.faults = [dict(f, seen=0) for f in vector.get("faults", [])]
        self.auth = vector.get("auth", {})

    def fault(self, on, node=None):
        for f in self.faults:
            if f["on"] == on and f.get("node") in (None, node):
                f["seen"] += 1
                if f.get("skip", 0) < f["seen"] <= f.get("skip", 0) + f.get("times", 1):
                    return f
        return None

    def issue(self):
        self.issued += 1
        token = f"AT-CANARY-{self.issued}"
        self.access = {token}
        self.calls = 0
        return token

    def public(self, node):
        kind = node.get("type", "file")
        item = {"id": node["id"], "name": node["name"], "mimeType": TYPES.get(kind, "application/octet-stream")}
        if kind == "file":
            data = node["data"]
            item["size"] = str(node.get("size_says", len(data)))
            item["sha256Checksum"] = node.get("sha256_says", hashlib.sha256(data).hexdigest())
            item["md5Checksum"] = node.get("md5_says", hashlib.md5(data).hexdigest())
            for key in node.get("omit", []):
                item.pop(key, None)
        return item


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def answer(self, status, body=b"", headers=(), length=None):
        self.out = (status, body, headers, length)

    def handle_one(self, work):
        """Decides under the lock, writes outside it: a slow file does not hold the other requests."""
        self.out = None
        drive = self.server.drive
        if drive.down and not self.path.startswith("/__"):
            self.close_connection = True
            return
        with drive.lock:
            work()
        if self.out is None:
            return
        status, body, headers, length = self.out
        self.send_response(status)
        for key, value in headers:
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body) if length is None else length))
        self.end_headers()
        media = urlsplit(self.path).query.find("alt=media") >= 0
        step = max(1, drive.slow // 10) if drive.slow and media else max(1, len(body))
        for start in range(0, len(body), step):
            if drive.down and media:
                self.close_connection = True
                return
            self.wfile.write(body[start:start + step])
            if drive.slow and media:
                time.sleep(0.1)
        if length is not None:
            self.close_connection = True

    def json(self, status, value, headers=()):
        self.answer(status, json.dumps(value).encode(), [("Content-Type", "application/json"), *headers])

    def error(self, status, reason, retry_after=None):
        headers = [("Retry-After", str(retry_after))] if retry_after is not None else []
        # A server may echo anything: the client must not repeat it.
        self.json(status, {"error": {"code": status, "message": "echo " + self.headers.get("Authorization", ""),
                                     "errors": [{"domain": "usageLimits", "reason": reason}]}}, headers)

    def common(self, f):
        if f is None:
            return False
        kind = f["do"]
        if kind == "status":
            self.error(f["status"], f.get("reason", "error"), f.get("retry_after"))
        elif kind == "hang_up":
            self.close_connection = True
        elif kind == "redirect":
            self.answer(302, b"", [("Location", f["to"])])
        elif kind == "garbage":
            self.answer(200, b"<html>not json</html>", [("Content-Type", "application/json")])
        else:
            return False
        return True

    def note(self, **entry):
        self.server.drive.log.append(entry)

    def authorized(self):
        drive = self.server.drive
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        drive.calls += 1
        limit = drive.auth.get("expires_after_calls")
        if token in drive.access and (limit is None or drive.calls <= limit):
            return True
        self.error(401, "authError")
        return False

    def do_GET(self):
        self.handle_one(self.get)

    def get(self):
        drive, url = self.server.drive, urlsplit(self.path)
        query = {k: v[0] for k, v in parse_qs(url.query).items()}
        if url.path == "/__log":
            log, drive.log = drive.log, []
            return self.json(200, log)
        if url.path == "/auth":
            return self.page(drive, query)
        if url.path == "/drive/v3/files":
            match = re.fullmatch(r"'([A-Za-z0-9_-]+)' in parents and trashed = false", query.get("q", ""))
            if not match:
                return self.error(400, "invalidQuery")
            parent = match.group(1)
            self.note(call="list", node=parent, page=query.get("pageToken", ""))
            if not self.authorized():
                return None
            f = drive.fault("list", parent)
            if self.common(f):
                return None
            owner = drive.nodes.get(parent)
            if owner is None or owner.get("trashed"):
                return self.error(404, "notFound")
            children = [drive.nodes[i] for i in drive.order if drive.nodes[i].get("parent") == parent and not drive.nodes[i].get("trashed")]
            token = query.get("pageToken")
            if token is not None and not re.fullmatch(r"page-\d+", token):
                return self.error(400, "invalid")
            start = int(token[5:]) if token else 0
            size = min(drive.page, int(query.get("pageSize", "100")))
            body = {"files": [drive.public(n) for n in children[start:start + size]], "incompleteSearch": False}
            if start + size < len(children):
                body["nextPageToken"] = f"page-{start + size}"
            if f and f["do"] == "loop":
                body["nextPageToken"] = "page-0"
            if f and f["do"] == "partial":
                body["incompleteSearch"] = True
            return self.json(200, body)
        match = re.fullmatch(r"/drive/v3/files/([A-Za-z0-9_-]+)", url.path)
        if match and query.get("alt") == "media":
            return self.media(drive, match.group(1), query)
        self.note(call="other")
        return self.error(404, "notFound")

    def page(self, drive, query):
        redirect = query.get("redirect_uri", "")
        good = query.get("response_type") == "code" and query.get("scope") == SCOPE and query.get("code_challenge_method") == "S256" \
            and query.get("code_challenge") and query.get("state") and "client_secret" not in query \
            and re.match(r"(com\.googleusercontent\.apps\.[a-z0-9-]+:/oauth2redirect|http://127\.0\.0\.1:\d+/?[a-z0-9]*)\Z", redirect)
        self.note(call="auth", fields=sorted(query), good=bool(good))
        if not good:
            return self.answer(400, b"refused", [("Content-Type", "text/plain")])
        code = f"CODE-CANARY-{len(drive.codes)}-{drive.issued}"
        drive.codes[code] = query["code_challenge"]
        yes = html.escape(redirect + "?" + urlencode({"state": query["state"], "code": code, "scope": SCOPE}))
        no = html.escape(redirect + "?" + urlencode({"state": query["state"], "error": "access_denied"}))
        style = "font:22px sans-serif;padding:24px;display:block;margin:24px"
        return self.answer(200, f"""<!doctype html><meta name=viewport content="width=device-width"><title>Invented sign-in</title>
<h1 style="{style}">Invented sign-in</h1><p style="{style}">No real account. Read only: {html.escape(query["scope"])}</p>
<a style="{style};background:#234;color:#fff" href="{yes}">Allow</a><a style="{style}" href="{no}">Refuse</a>""".encode(),
                           [("Content-Type", "text/html; charset=utf-8")])

    def media(self, drive, node_id, query):
        asked = re.fullmatch(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
        first, last = (int(asked.group(1)), int(asked.group(2))) if asked else (None, None)
        self.note(call="media", node=node_id, first=first, last=last)
        if not self.authorized():
            return None
        f = drive.fault("media", node_id)
        if self.common(f):
            return None
        node = drive.nodes.get(node_id)
        if node is None or node.get("trashed") or node.get("type", "file") != "file":
            return self.error(404, "notFound")
        if query.get("acknowledgeAbuse"):
            return self.error(400, "refused")
        data, do = node["data"], f["do"] if f else None
        if first is None or do == "whole":
            return self.answer(200, data)
        if first >= len(data):
            return self.answer(416, b"", [("Content-Range", f"bytes */{len(data)}")])
        last = min(last, len(data) - 1)
        body, total = data[first:last + 1], len(data)
        headers = []
        if do == "total":
            total = f["total"]
        if do == "shift":
            first, last = first + 1, last + 1
        if do == "longer":
            body += b"x" * f["bytes"]
        if do == "corrupt":
            body = bytes([body[0] ^ 0xFF]) + body[1:]
        if do == "gzip":
            body = gzip.compress(body)
            headers.append(("Content-Encoding", "gzip"))
        headers.append(("Content-Range", f"bytes {first}-{last}/{total}"))
        if do == "cut":
            return self.answer(206, body[:f["bytes"]], headers, length=len(body))
        return self.answer(206, body, headers)

    def do_POST(self):
        self.handle_one(self.post)

    def post(self):
        drive = self.server.drive
        body = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode()
        form = {k: v[0] for k, v in parse_qs(body, keep_blank_values=True).items()}
        if self.path == "/token":
            grant = form.get("grant_type", "")
            # Field names only: the log never holds a credential.
            self.note(call="token", grant=grant, fields=sorted(form))
            f = drive.fault("token")
            if self.common(f):
                return None
            scope = f["scope"] if f and f["do"] == "shrink" else SCOPE
            if grant == "refresh_token":
                if drive.auth.get("client", "good") != "good":
                    return self.json(401, {"error": "invalid_client"})
                if form.get("refresh_token") not in drive.refresh:
                    return self.json(400, {"error": "invalid_grant", "error_description": "echo " + form.get("refresh_token", "")})
                return self.json(200, {"access_token": drive.issue(), "expires_in": drive.auth.get("expires_in", 3599), "token_type": "Bearer", "scope": scope})
            if grant == "authorization_code":
                challenge = drive.codes.pop(form.get("code", ""), None)
                digest = hashlib.sha256(form.get("code_verifier", "").encode()).digest()
                if challenge is None or base64.urlsafe_b64encode(digest).decode().rstrip("=") != challenge:
                    return self.json(400, {"error": "invalid_grant"})
                drive.refresh.add("RT-CANARY-NEW")
                return self.json(200, {"access_token": drive.issue(), "expires_in": 3599, "refresh_token": "RT-CANARY-NEW",
                                       "token_type": "Bearer", "scope": scope})
            return self.json(400, {"error": "unsupported_grant_type"})
        if self.path == "/revoke":
            self.note(call="revoke")
            drive.refresh.clear()
            drive.access.clear()
            return self.json(200, {})
        if self.path == "/__faults":
            drive.faults = [dict(f, seen=0) for f in json.loads(body)]
            return self.json(200, {})
        if self.path == "/__slow":
            drive.slow = int(body)
            return self.json(200, {})
        if self.path == "/__down":
            drive.down = body == "1"
            return self.json(200, {})
        if self.path == "/__vector":
            drive.load(json.loads(body))
            return self.json(200, {})
        if self.path == "/__revoke":
            drive.refresh.clear()
            drive.access.clear()
            return self.json(200, {})
        if self.path == "/__code":  # the test plays the browser: Google remembers the challenge of the page it showed
            drive.codes[form["code"]] = form["challenge"]
            return self.json(200, {})
        self.note(call="other")
        return self.error(403, "insufficientFilePermissions")

    def refuse(self):
        def work():
            self.note(call="write")
            self.error(403, "insufficientFilePermissions")
        self.handle_one(work)

    do_PUT = do_PATCH = do_DELETE = refuse


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # Not HTTPServer's, which looks up the machine's name and can wait half a minute for it.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address


def main():
    with open(sys.argv[1], encoding="utf-8") as file:
        vector = json.load(file)
    server = Server(("127.0.0.1", int(sys.argv[2]) if len(sys.argv) > 2 else 0), Handler)
    server.drive = Drive(vector)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(server.server_address[1], flush=True)
    if len(sys.argv) > 2:
        threading.Event().wait()
    sys.stdin.read()  # ends with the test that started it


if __name__ == "__main__":
    main()
