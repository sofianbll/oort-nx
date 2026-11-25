#!/usr/bin/env python3
"""Writes vectors/*.json, the cases both phones must answer the same way. Standard library, plus openssl to sign.

usage: make_vectors.py            The signing keys are made for the run and thrown away, so every run rewrites every signature.
"""
import base64, hashlib, json, pathlib, shutil, subprocess, tempfile, unicodedata
from fake_drive import content

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "vectors"
A, B, C, D, E = (f"01000000000{n}0000" for n in range(1, 6))  # invented titles
IOS = {"platform": "ios", "system": "26.1", "architecture": "arm64", "features": ["apple7", "apple8", "apple9", "bc"], "host": 1}
ANDROID = {"platform": "android", "system": "34", "architecture": "arm64", "features": ["bc", "vulkan1.1"], "host": 0}
T0 = 1790000000000
MEDIA = "media"


class Signer:
    def __init__(self, folder):
        self.key = folder / f"{id(self)}.pem"
        subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", self.key], check=True, capture_output=True)
        der = subprocess.run(["openssl", "ec", "-in", self.key, "-pubout", "-outform", "DER"], check=True, capture_output=True).stdout
        self.public = base64.b64encode(der).decode()

    def sign(self, data):
        return subprocess.run(["openssl", "dgst", "-sha256", "-sign", self.key], input=b"oort-target-1\n" + data, check=True, capture_output=True).stdout


def canonical(entries):
    return json.dumps([{"path": e["path"], "sha256": e["sha256"], "size": e["size"]} for e in entries],
                      ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()


def file_of(name, seed, size):
    return {"name": name, "fill": {"seed": seed, "size": size}}


IOS_FILES = [("Game.framework/Game", "ios-exe", 2500), ("Game.framework/game.manifest.json", "ios-man", 300),
             ("Game.framework/empty", "ios-empty", 0), ("data/romfs.img", "ios-data", 4096)]
APK_FILES = [("game.apk", "apk", 3000), ("data/romfs.bin", "apk-data", 2048)]


class Tree:
    def __init__(self, signer, page_size=1000):
        self.signer, self.page_size, self.nodes, self.count = signer, page_size, [], 0
        self.add({"id": "ROOT", "name": "Games", "parent": None, "type": "folder"})

    def add(self, node):
        self.nodes.append(node)
        return node["id"]

    def new(self, prefix):
        self.count += 1
        return f"{prefix}-{self.count}"

    def folder(self, parent, name):
        for n in self.nodes:
            if n.get("parent") == parent and n["name"] == name and n.get("type") == "folder":
                return n["id"]
        return self.add({"id": self.new("d"), "name": name, "parent": parent, "type": "folder"})

    def file(self, parent, name, **body):
        return self.add({"id": self.new("f"), "name": name, "parent": parent, **body})

    def game(self, title, name):
        return self.folder("ROOT", f"{name} [{title}]")

    def mac(self, title, name):
        text = json.dumps({"artifacts": [], "version": 2})
        manifests = self.folder(self.game(title, name), "manifests")
        self.file(manifests, f"{T0:016d}-{hashlib.sha256(text.encode()).hexdigest()}.json", text=text)

    def target(self, title, name, platform="ios", stamp=T0, files=None, version="1.0.0", system=None, features=None, host=None,
               architecture="arm64", edit=None, signer=None, sign=True, seal=None, file_edit=None, publish=True, sha=None, package=None):
        files = files if files is not None else (IOS_FILES if platform == "ios" else APK_FILES)
        # (path, seed, size) for invented bytes, (path, body) for a given one.
        bodies = [(f[0], f[1] if len(f) == 2 else {"fill": {"seed": f[1], "size": f[2]}}) for f in files]
        entries = [{"path": p, "size": len(content(b)), "sha256": hashlib.sha256(content(b)).hexdigest()} for p, b in bodies]
        entries.sort(key=lambda e: e["path"].encode())
        manifest = {"format": "oort-target", "version": 1, "title_id": title, "game_name": name, "game_version": version, "platform": platform,
                    "created_at": "2026-09-21T13:46:40Z", "engine": {"commit": "0123456789abcdef0123456789abcdef01234567"},
                    "requires": {"os": system or ("26.0" if platform == "ios" else "29"), "arch": architecture,
                                 "features": features if features is not None else ["bc"], "host": host if host is not None else (1 if platform == "ios" else 0)},
                    "package": package or ({"path": "Game.framework"} if platform == "ios" else
                                           {"path": "game.apk", "id": "org.example.game", "version_code": 1, "certificate_sha256": "c" * 64}),
                    "unpacked_size": sum(e["size"] for e in entries), "entry_count": len(entries),
                    "inventory_sha256": hashlib.sha256(canonical(entries)).hexdigest(), "entries": entries}
        if edit:
            edit(manifest)
        data = json.dumps(manifest, sort_keys=True, ensure_ascii=False).encode()
        digest = manifest["inventory_sha256"]
        place = self.folder(self.folder(self.game(title, name), "targets"), platform)
        stem = f"{stamp:016d}-{sha or hashlib.sha256(data).hexdigest()}"
        self.file(place, stem + ".json", text=data.decode())
        if sign:
            signature = (signer or self.signer).sign(data) if seal is None else seal
            self.file(place, stem + ".sig", base64=base64.b64encode(signature).decode())
        ids = {}
        if publish:
            top = self.folder(place, digest)
            for path, body in bodies:
                parent = top
                for part in path.split("/")[:-1]:
                    parent = self.folder(parent, part)
                ids[path] = self.file(parent, path.split("/")[-1], **body)
            if file_edit:
                file_edit({n["id"]: n for n in self.nodes}, ids)
        return {"digest": digest, "ids": ids, "files": {e["path"]: e["sha256"] for e in entries}, "bytes": manifest["unpacked_size"], "data": data}

    def drive(self):
        return {"root": "ROOT", "page_size": self.page_size, "nodes": self.nodes}


VECTORS = {}


def vector(name, why, tree, steps, faults=(), client=None, auth=None):
    assert name not in VECTORS, name
    base = {"device": IOS, "free": 10**12, "metered": False, "allow_metered": False, "chunk": 1024, "reserve": 0, "network": "up", "on": True}
    VECTORS[name] = {"why": why, "key": tree.signer.public, "drive": tree.drive(), "faults": list(faults), "auth": auth or {},
                     "client": {**base, **(client or {})}, "steps": steps}


def games(*items):
    return {"games": [{"title": t, "name": n, "version": v, "digest": b["digest"], "state": s} for t, n, v, b, s in items]}


def listing(*items, hidden=(), problems=(), **more):
    return {"do": "list", "expect": {**games(*items), "hidden": [list(h) for h in hidden], "problems": [list(p) for p in problems]}, **more}


def fails(code, do="list", **more):
    return {"do": do, "expect": {"error": code}, **more}


def got(title, build, **more):
    return {"do": "download", "title": title, "expect": {"files": build["files"], "visible": True, "waiting": False}, **more}


def stopped(title, code, waiting=True, **more):
    return {"do": "download", "title": title, "expect": {"error": code, "visible": False, "waiting": waiting}, **more}


def ranges(build, chunk=1024, files=None, start=None):
    out = []
    sizes = {p: s for p, _, s in (files or IOS_FILES)}
    for path in sorted(sizes, key=str.encode):
        first = (start or {}).get(path, 0)
        while first < sizes[path]:
            last = min(first + chunk, sizes[path]) - 1
            out.append([build["ids"][path], first, last])
            first = last + 1
    return out


def make(signer, other):
    # --- listing -------------------------------------------------------------------------------------------------
    def three():
        t = Tree(signer)
        t.mac(A, "Alpha")
        b = t.target(B, "Beta")
        t.mac(B, "Beta")
        c = t.target(C, "Gamma", platform="android")
        t.folder("ROOT", "GameFiles")
        t.folder("ROOT", "Switch")
        t.file("ROOT", "notes.txt", text="not a game")
        t.folder("ROOT", "Delta [0100000000040000")  # not a title folder
        return t, b, c

    t, b, c = three()
    vector("list-ios", "An iPhone shows the iPhone build, names the rest, and ignores what is not a game folder.", t,
           [listing((B, "Beta", "1.0.0", b, "available"), hidden=[(A, "Alpha", "notPrepared"), (C, "Gamma", "notPrepared")])])
    t, b, c = three()
    vector("list-android", "The same folder on Android.", t,
           [listing((C, "Gamma", "1.0.0", c, "available"), hidden=[(A, "Alpha", "notPrepared"), (B, "Beta", "notPrepared")])], client={"device": ANDROID})

    t = Tree(signer)
    t.target(A, "Alpha", system="27.0")
    t.target(B, "Beta", features=["bc", "apple10"])
    t.target(C, "Gamma", host=2)
    t.target(D, "Delta", architecture="x86_64")
    t.target(E, "Epsilon", system="27.0", stamp=T0 + 2, version="2.0.0")
    e = t.target(E, "Epsilon", stamp=T0 + 1, version="1.5.0", files=IOS_FILES[:3])
    t.target(E, "Epsilon", stamp=T0, version="1.0.0", files=IOS_FILES[:2])
    vector("device-filter", "System, graphics, launcher and processor each hide a build; the newest one that runs is kept.", t,
           [listing((E, "Epsilon", "1.5.0", e, "available"),
                    hidden=[(A, "Alpha", "system"), (B, "Beta", "graphics"), (C, "Gamma", "launcher"), (D, "Delta", "notPrepared")])])

    t = Tree(signer)
    names = [(A, "Écume", 3, 1), (B, "zeste", 1, 3), (C, "Ecrin", 2, 2), (D, "Zeste", 4, 1)]
    built = {}
    for title, name, stamp, size in names:
        built[title] = t.target(title, name, stamp=T0 + stamp, files=[("Game.framework/Game", title, size * 100)])
    row = lambda title: (title, dict((x[0], x[1]) for x in names)[title], "1.0.0", built[title], "available")
    vector("order", "By name without accents or case, newest first, largest first; ties by name then identifier.", t,
           [listing(*map(row, [C, A, B, D])), listing(*map(row, [D, A, C, B]), order="newest"), listing(*map(row, [B, C, A, D]), order="size")])

    t = Tree(signer)
    b = t.target(B, "Beta")
    vector("states", "Installed and update come from the digest on the device.", t,
           [listing((B, "Beta", "1.0.0", b, "installed"), installed={B: b["digest"]}),
            listing((B, "Beta", "1.0.0", b, "update"), installed={B: "0" * 64})])

    t = Tree(signer, page_size=2)
    made = [(title, name, t.target(title, name, files=[(f"Game.framework/{n}", n, 10) for n in "abcde"]))
            for title, name in [(A, "Alpha"), (B, "Beta"), (C, "Gamma"), (D, "Delta"), (E, "Epsilon")]]
    vector("pages", "Every page of every folder is read, in lists and in downloads.", t,
           [listing(*[(x, n, "1.0.0", b, "available") for x, n, b in sorted(made, key=lambda m: m[1].lower())]), got(A, made[0][2])])
    t = Tree(signer, page_size=2)
    for title, name in [(A, "Alpha"), (B, "Beta"), (C, "Gamma")]:
        t.mac(title, name)
    every = [(A, "Alpha", "notPrepared"), (B, "Beta", "notPrepared"), (C, "Gamma", "notPrepared")]
    vector("pages-loop", "A page that points to itself never loops for ever.", t, [fails("badResponse")],
           faults=[{"on": "list", "node": "ROOT", "times": 999, "do": "loop"}])
    vector("pages-restart", "A refused page token starts the folder again, once.", t, [listing(hidden=every)],
           faults=[{"on": "list", "node": "ROOT", "skip": 1, "do": "status", "status": 400, "reason": "invalid"}])
    vector("pages-refused", "Twice is an error, not a shorter list.", t, [fails("badResponse")],
           faults=[{"on": "list", "node": "ROOT", "skip": 1, "times": 9, "do": "status", "status": 400, "reason": "invalid"}])
    vector("list-partial", "An incomplete answer is not a list.", t, [fails("badResponse")], faults=[{"on": "list", "node": "ROOT", "do": "partial"}])
    vector("list-garbage", "Not JSON.", t, [fails("badResponse")], faults=[{"on": "list", "node": "ROOT", "do": "garbage"}])
    vector("list-redirect", "No redirection is followed: the credential stays with Google.", t, [fails("badResponse")],
           faults=[{"on": "list", "node": "ROOT", "do": "redirect", "to": "http://127.0.0.1:1/elsewhere"}])

    # --- access --------------------------------------------------------------------------------------------------
    t = Tree(signer)
    b = t.target(B, "Beta")
    ok = listing((B, "Beta", "1.0.0", b, "available"))
    vector("off", "A source the player has not turned on is not even contacted.", t, [fails("sourceOff", calls=0)], client={"on": False})
    vector("turned-off", "Turning it off erases the credential; nothing is asked afterwards.", t,
           [ok, {"do": "turn_off", "expect": {"credential": False}}, fails("sourceOff", calls=0)])
    vector("token-expired", "An access token refused half-way is renewed once, without the player.", t, [ok, got(B, b)], auth={"expires_after_calls": 3})
    vector("token-revoked", "A revoked access asks to sign in, and the dead credential is erased.", t,
           [fails("signInNeeded", waits=[]), {"do": "credential", "expect": {"credential": False}}], auth={"refresh": "revoked"})
    vector("client-deleted", "So does a client deleted in Google's console.", t, [fails("signInNeeded")], auth={"client": "deleted"})
    vector("token-server-down", "A token server in trouble keeps the credential.", t,
           [fails("server", waits=[1, 2, 4]), {"do": "credential", "expect": {"credential": True}}],
           faults=[{"on": "token", "times": 99, "do": "status", "status": 503}])
    vector("still-401", "A fresh token refused as well is not renewed for ever.", t, [fails("signInNeeded")],
           faults=[{"on": "list", "times": 99, "do": "status", "status": 401, "reason": "authError"}])
    vector("offline", "No connection: said at once, no waiting.", t, [fails("offline", waits=[])], client={"network": "down"})
    vector("root-gone", "The library folder is in the trash or no longer shared.", t, [fails("notFound")],
           faults=[{"on": "list", "node": "ROOT", "do": "status", "status": 404, "reason": "notFound"}])
    status = lambda code, reason, times=1, **more: [{"on": "list", "node": "ROOT", "times": times, "do": "status", "status": code, "reason": reason, **more}]
    vector("rate-403", "Too many requests, as Drive says it with 403: wait and try again.", t, [dict(ok, waits=[1, 2])], faults=status(403, "userRateLimitExceeded", 2))
    vector("rate-429", "429 with a delay: the delay is kept.", t, [dict(ok, waits=[7])], faults=status(429, "rateLimitExceeded", retry_after=7))
    vector("rate-long", "A delay too long to wait for is handed over.", t, [fails("busy", waits=[])], faults=status(429, "rateLimitExceeded", 9, retry_after=600))
    vector("rate-endless", "Four tries, then the player is told.", t, [fails("busy", waits=[1, 2, 4])], faults=status(429, "rateLimitExceeded", 99))
    vector("server-once", "A 5xx is tried again.", t, [dict(ok, waits=[1])], faults=status(502, "backendError"))
    vector("server-down", "And given up.", t, [fails("server", waits=[1, 2, 4])], faults=status(500, "backendError", 99))
    vector("quota-daily", "The account has nothing left for today: no retry.", t, [fails("quotaExceeded", waits=[])], faults=status(403, "dailyLimitExceeded", 9))
    vector("denied", "The folder is not readable by this account.", t, [fails("accessDenied", waits=[])], faults=status(403, "insufficientFilePermissions", 9))
    vector("domain-policy", "A school or company that forbids it.", t, [fails("accessDenied")], faults=status(403, "domainPolicy", 9))

    # --- download ------------------------------------------------------------------------------------------------
    vector("download", "Ranges, an empty file, nested folders; then it is installed and nothing is asked twice.", t,
           [got(B, b, media=ranges(b)), listing((B, "Beta", "1.0.0", b, "installed"), installed="store"), got(B, b, media=[])])
    exe, data = "Game.framework/Game", "data/romfs.img"
    t2 = Tree(signer)
    c = t2.target(C, "Gamma", platform="android")
    t2b = Tree(signer)
    long = [("Game.framework/Game", "long", 5 * 1024 * 1024 + 123)]
    d = t2b.target(D, "Delta", files=long)
    vector("large-file", "Megabytes per chunk, added one after the other.", t2b, [got(D, d, media=ranges(d, 2 << 20, long))], client={"chunk": 2 << 20})
    vector("download-android", "An APK and its data.", t2, [got(C, c, media=ranges(c, files=APK_FILES))], client={"device": ANDROID})
    cut = lambda times, skip=1, node=b["ids"][data]: [{"on": MEDIA, "node": node, "skip": skip, "times": times, "do": "cut", "bytes": 100}]
    order = ranges(b)
    first = [r for r in order if r[0] == b["ids"][data]]
    before = order[:order.index(first[0])]
    vector("cut-once", "A broken connection repeats the chunk, not the file.", t, [got(B, b, media=before + [first[0], first[1], first[1]] + first[2:], waits=[1])], faults=cut(1))
    vector("cut-resume", "Given up, then resumed where it stopped.", t,
           [stopped(B, "interrupted", media=before + [first[0]] + [first[1]] * 4, waits=[1, 2, 4]), got(B, b, media=first[1:])], faults=cut(4))
    vector("hang-up", "A connection closed without an answer.", t, [got(B, b)], faults=[{"on": MEDIA, "node": b["ids"][exe], "do": "hang_up"}])
    vector("cancel", "Cancelled after three chunks, then resumed.", t,
           [stopped(B, "cancelled", cancel_after=3, media=order[:3]), got(B, b, media=order[3:])])
    vector("discard", "Discarded: the next time starts from the beginning.", t,
           [stopped(B, "cancelled", cancel_after=3, media=order[:3]), {"do": "discard", "title": B, "expect": {"waiting": False}}, got(B, b, media=order)])
    vector("corrupt", "One wrong byte: nothing becomes visible, and only that file is asked again.", t,
           [stopped(B, "wrongDigest", media=before + first), got(B, b, media=first)], faults=[{"on": MEDIA, "node": b["ids"][data], "skip": 2, "do": "corrupt"}])
    vector("tampered-part", "A waiting file changed on the device is caught.", t,
           [stopped(B, "cancelled", cancel_after=2), {"do": "tamper_part", "title": B, "expect": {}}, stopped(B, "wrongDigest"), got(B, b)])
    vector("no-space", "Refused before the first byte.", t, [stopped(B, "noSpace", waiting=False, media=[])], client={"free": b["bytes"] - 1})
    vector("space-reserve", "The player's reserve counts.", t, [stopped(B, "noSpace", waiting=False, media=[])],
           client={"free": b["bytes"] + 1024 + 499, "reserve": 500})
    vector("space-exact", "And is enough when it is enough.", t, [got(B, b)], client={"free": b["bytes"] + 1024 + 500, "reserve": 500})
    vector("metered", "Mobile data is not used unless the player allows it.", t, [stopped(B, "networkNotAllowed", waiting=False, media=[])], client={"metered": True})
    vector("metered-allowed", "Allowed.", t, [got(B, b)], client={"metered": True, "allow_metered": True})
    for name, why, fault, code in [
            ("download-quota", "This file was downloaded too often today.", {"do": "status", "status": 403, "reason": "downloadQuotaExceeded"}, "quotaExceeded"),
            ("download-abusive", "Drive calls the file abusive: never overridden.", {"do": "status", "status": 403, "reason": "cannotDownloadAbusiveFile"}, "accessDenied"),
            ("download-gone", "Deleted between the list and the download.", {"do": "status", "status": 404, "reason": "notFound"}, "notFound"),
            ("range-ignored", "The whole file instead of the range.", {"do": "whole"}, "badResponse"),
            ("range-shifted", "Another range than the one asked for.", {"do": "shift"}, "badResponse"),
            ("range-total", "A file that is not the listed size.", {"do": "total", "total": 10**15}, "wrongSize"),
            ("body-longer", "More bytes than announced by the range.", {"do": "longer", "bytes": 5000}, "badResponse"),
            ("body-gzip", "A compressed body is refused: nothing is expanded.", {"do": "gzip"}, "badResponse"),
            ("media-redirect", "No redirection for content either.", {"do": "redirect", "to": "http://127.0.0.1:1/elsewhere"}, "badResponse")]:
        vector(name, why, t, [stopped(B, code, waits=[])], faults=[{"on": MEDIA, "node": b["ids"][exe], "times": 99, **fault}])
    vector("download-rate", "Too many requests in the middle of a file.", t, [got(B, b, waits=[3])],
           faults=[{"on": MEDIA, "node": b["ids"][data], "skip": 1, "do": "status", "status": 429, "reason": "rateLimitExceeded", "retry_after": 3}])
    vector("download-token", "A token that expires in the middle of a file.", t, [got(B, b)], auth={"expires_after_calls": 10})

    # --- a folder somebody tampered with -------------------------------------------------------------------------
    def tampered(name, why, edit, code, media=(), **more):
        t = Tree(signer)
        box = t.target(B, "Beta", file_edit=edit, **more)
        vector(name, why, t, [stopped(B, code, waiting=bool(media), media=media if media != () else [])])

    def set_node(path, **values):
        return lambda nodes, ids: nodes[ids[path]].update(values)

    tampered("replaced-listed", "A replaced file whose hash Drive lists is refused before a byte.", set_node(exe, fill={"seed": "evil", "size": 2500}), "wrongDigest")
    t3 = Tree(signer)
    b3 = t3.target(B, "Beta", file_edit=set_node(exe, fill={"seed": "evil", "size": 2500}, omit=["sha256Checksum", "md5Checksum"]))
    vector("replaced-unlisted", "And after it when Drive lists none.", t3, [stopped(B, "wrongDigest", media=ranges(b3)[:3])])
    t3 = Tree(signer)
    b3 = t3.target(C, "Gamma", platform="android", file_edit=set_node("game.apk", fill={"seed": "evil", "size": 3000}))
    vector("replaced-apk", "A replaced APK.", t3, [stopped(C, "wrongDigest", waiting=False, media=[])], client={"device": ANDROID})
    tampered("size-lies", "A listed size that is not the manifest's.", set_node(data, size_says=10**14), "wrongSize")
    tampered("shortcut", "A shortcut in place of a file is never followed.", set_node(exe, type="shortcut"), "filesMissing")
    tampered("file-is-folder", "A folder in place of a file.", set_node(exe, type="folder"), "filesMissing")

    t3 = Tree(signer)
    b3 = t3.target(B, "Beta")
    parent = next(n["parent"] for n in t3.nodes if n["id"] == b3["ids"][exe])
    t3.file(parent, "GAME", text="another")
    vector("twin-file", "Two files a disk could take for one.", t3, [stopped(B, "ambiguous", waiting=False, media=[])])
    t3 = Tree(signer)
    b3 = t3.target(B, "Beta")
    t3.file(parent, "unexpected.dylib", text="never asked for")
    t3.add({"id": "f-extra", "name": "link", "parent": parent, "type": "shortcut"})
    vector("extra-files", "What the manifest does not name is never downloaded.", t3, [got(B, b3, media=ranges(b3))])
    t3 = Tree(signer)
    b3 = t3.target(B, "Beta", publish=False)
    t3.target(C, "Gamma", file_edit=lambda nodes, ids: nodes[ids[exe]].update(trashed=True))
    vector("missing", "A manifest whose files are not there.", t3,
           [{"do": "list", "expect": {"hidden": [[B, "Beta", "filesMissing"]], "problems": []}}, stopped(C, "filesMissing", waiting=False, media=[])])

    t3 = Tree(signer)
    for title, name in [(A, "Alpha"), (B, "Beta")]:
        t3.mac(title, name)
    t3.add({"id": "d-twin", "name": f"alpha [{A}]", "parent": "ROOT", "type": "folder"})
    t3.add({"id": "d-accent1", "name": f"Café [{C}]", "parent": "ROOT", "type": "folder"})
    t3.add({"id": "d-accent2", "name": f"Café [{C}]", "parent": "ROOT", "type": "folder"})
    beta = next(n["id"] for n in t3.nodes if n["name"] == f"Beta [{B}]")
    t3.add({"id": "d-man2", "name": "manifests", "parent": beta, "type": "folder"})
    e = t3.target(E, "Epsilon")
    vector("twins", "Twin folders make a game ambiguous, and only that game.", t3,
           [listing((E, "Epsilon", "1.0.0", e, "available"), problems=[(A, "ambiguous"), (B, "ambiguous"), (C, "ambiguous")])])

    bad_paths = ["../outside", "Game.framework/../../x", "/absolute", "a\\b", "c:d", "prod.keys", "data/TITLE.KEYS", "save/user", "Save_1/slot", ".hidden", "a/.b",
                 "x.rclonelink", "line\nbreak", "left‮right", "dot.", "space ", "a//b", "", "a/./b", "n" * 300, "/".join("d" * 20)]
    t3 = Tree(signer)
    titles = []
    for i, path in enumerate(bad_paths):
        title = f"0100000000{i + 16:02X}0000"
        titles.append((title, "unsafeName"))

        def edit(m, path=path):
            m["entries"].append({"path": path, "size": 1, "sha256": "a" * 64})
            m["entry_count"] += 1
            m["unpacked_size"] += 1
            m["inventory_sha256"] = hashlib.sha256(canonical(m["entries"])).hexdigest()
        t3.target(title, f"Trap {i}", edit=edit, publish=False)
    for i, pair in enumerate([["Game.framework/game", "Game.framework/Game"], ["x/Café", "x/Café"], ["x", "x/y"], ["x/y", "x"], ["same", "same"]]):
        title = f"0100000000{i + 80:02X}0000"
        titles.append((title, "unsafeName"))

        def edit(m, pair=pair):
            m["entries"] = [{"path": p, "size": 1, "sha256": "a" * 64} for p in ["Game.framework/z"] + pair]
            m["entry_count"], m["unpacked_size"] = 3, 3
            m["inventory_sha256"] = hashlib.sha256(canonical(m["entries"])).hexdigest()
        t3.target(title, f"Clash {i}", edit=edit, publish=False)
    vector("hostile-paths", "Names that leave the folder, hide, spoof, collide, or stand for keys and saves.", t3, [listing(problems=titles)])

    t3 = Tree(signer)
    rows = []

    def bad(code, **more):
        title = f"0100000000{len(rows) + 16:02X}0000"
        rows.append((title, code))
        t3.target(title, f"Bad {len(rows)}", publish=False, **more)

    bad("unsigned", sign=False)
    bad("unsigned", signer=other)
    bad("unsigned", seal=b"")
    bad("unsigned", seal=b"not a signature")
    elsewhere = Tree(signer).target(E, "Epsilon")
    bad("unsigned", seal=signer.sign(elsewhere["data"]))
    bad("invalidManifest", sha="0" * 64)
    bad("invalidManifest", edit=lambda m: m.update(title_id=E))
    bad("invalidManifest", edit=lambda m: m.update(platform="android"))
    bad("invalidManifest", edit=lambda m: m.update(version=2))
    bad("invalidManifest", edit=lambda m: m.update(format="other"))
    bad("invalidManifest", edit=lambda m: m.update(unpacked_size=m["unpacked_size"] + 1))
    bad("invalidManifest", edit=lambda m: m.update(entry_count=99))
    bad("invalidManifest", edit=lambda m: m.update(inventory_sha256="0" * 64))
    bad("invalidManifest", edit=lambda m: m["entries"][0].update(size=-1))
    bad("invalidManifest", edit=lambda m: m["entries"][0].update(size=2**63 - 1))
    bad("invalidManifest", edit=lambda m: m["entries"][0].update(sha256="xyz"))
    bad("invalidManifest", edit=lambda m: m["entries"].clear())
    bad("invalidManifest", edit=lambda m: m.pop("requires"))
    bad("invalidManifest", edit=lambda m: m["requires"].update(os="latest"))
    bad("invalidManifest", edit=lambda m: m["package"].update(path="Other.framework"))
    bad("invalidManifest", edit=lambda m: m["package"].update(path="data/Game.framework"))
    bad("invalidManifest", edit=lambda m: m["engine"].update(commit="main"))
    bad("invalidManifest", edit=lambda m: m.update(game_version="1.0‮0"))
    vector("hostile-manifests", "Unsigned, signed by another Mac, moved from another game, renamed, or lying about itself.", t3, [listing(problems=rows)])

    t3 = Tree(signer)
    rows = []
    bad_ = [dict(id="org"), dict(id="org.x;rm"), dict(version_code=0), dict(certificate_sha256="c" * 63), dict(certificate_sha256=None), dict(path="x/game.apk")]
    for i, values in enumerate(bad_):
        title = f"0100000000{i + 16:02X}0000"
        rows.append((title, "invalidManifest"))
        t3.target(title, f"Bad {i}", platform="android", publish=False, edit=lambda m, v=values: m["package"].update(v))
    vector("hostile-packages", "An APK that does not say who signs it.", t3, [listing(problems=rows)], client={"device": ANDROID})

    t3 = Tree(signer)
    t3.target(B, "Beta", stamp=T0 + 5, signer=other, version="9.0.0")
    b3 = t3.target(B, "Beta", stamp=T0)
    vector("forged-newer", "A forged newer build is reported and does not hide the real one.", t3,
           [listing((B, "Beta", "1.0.0", b3, "available"), problems=[(B, "unsigned")])])
    t3 = Tree(signer)
    b3 = t3.target(B, "Beta", edit=lambda m: m.update(game_name="Be‮ta\n​"))
    vector("display-name", "A name from outside carries no line break and no direction mark.", t3, [listing((B, "Beta", "1.0.0", b3, "available"))])
    t3 = Tree(signer)
    b3 = t3.target(B, "Beta", files=[("Game.framework/Game", "x", 10), ("Game.framework/Café \"1\".bin", "y", 20), ("Game.framework/日本", "z", 30)])
    vector("unicode-paths", "Accents, quotes and other alphabets hash the same on both sides.", t3, [got(B, b3)])
    t3 = Tree(signer)
    big = 17 * 1024 * 1024
    place = t3.folder(t3.folder(t3.game(B, "Beta"), "targets"), "ios")
    stem = f"{T0:016d}-" + "0" * 64
    t3.file(place, stem + ".json", text="{}", size_says=big)
    t3.file(place, stem + ".sig", text="x")
    vector("manifest-huge", "A manifest too large to hold is not downloaded.", t3, [listing(problems=[(B, "invalidManifest")], calls=4)])

    # --- the Mac's own archive, as Oort 0.5.0-beta.3 wrote it -----------------------------------------------------
    t3 = Tree(signer)
    for item in json.loads((HERE / "mac/archive-0.5.0-beta.3.json").read_text()):
        path = item["path"].split("/")
        parent = "ROOT"
        for part in path[:-1]:
            parent = t3.folder(parent, part)
        if item["type"] == "folder":
            t3.folder(parent, path[-1])
        else:
            body = {"text": item["text"]} if "text" in item else {"text": ""}
            t3.file(parent, path[-1], size_says=item["size"], md5_says=item["md5"], sha256_says=item["sha256"], **body)
    title = "0100E65002BB8000"
    mac = {"do": "mac", "title": title, "expect": {"name": "Fixture", "version": "1.2", "engine": "72d43ff6", "bytes": 85722, "stamp": 1795600283143}}
    vector("mac-archive", "The Mac's real manifests are read and checked; its app is never offered to a phone.", t3,
           [listing(hidden=[(title, "Fixture", "notPrepared")]), mac])
    t4 = Tree(signer)
    t4.nodes = [dict(n) for n in t3.nodes]
    t4.count = t3.count
    f4 = t4.target(title, "Fixture")
    vector("mac-and-phone", "The same folder with an iPhone build beside it.", t4, [listing((title, "Fixture", "1.0.0", f4, "available")), mac, got(title, f4)])
    t5 = Tree(signer)
    t5.nodes = [dict(n) for n in t3.nodes]
    for n in t5.nodes:
        if n["name"].endswith(".json"):
            n["text"] = n["text"].replace('"unpacked_size":85722', '"unpacked_size":85723')
    vector("mac-altered", "A Mac manifest changed after its name was made.", t5, [{"do": "mac", "title": title, "expect": {"error": "invalidManifest"}}])


def main():
    with tempfile.TemporaryDirectory() as work:
        folder = pathlib.Path(work)
        make(Signer(folder), Signer(folder))
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir()
    for name, value in VECTORS.items():
        (OUT / f"{name}.json").write_text(json.dumps({"name": name, **value}, indent=1, ensure_ascii=True) + "\n")
    print(f"{len(VECTORS)} vectors, {sum(p.stat().st_size for p in OUT.iterdir()) // 1024} KiB")


if __name__ == "__main__":
    main()
