#!/usr/bin/env python3
"""Drives the release of Oort NX and Oort Cloud (built for checks: a stand-in for Google on this machine) in a running emulator: the whole
journey of the cloud library, what goes wrong, and what must not happen. Invented games only. Pictures and a report.

    cloud_check.py --files DIR --out DIR      (oort.apk, cloud.apk, cloud-other-key.apk, cloud-games/, certificate.txt)
"""
import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

import emulator_check as e

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tests/PhoneLibrary"))
import make_vectors  # noqa: E402

CLOUD = "io.github.sofianbll.oortnx.alpha.cloud"
PORT = 8799
PHARE, MAREE, HILLS, GLASS, MAGNET, ECHO, SHADOW = (f"0100000000AA{n}000" for n in range(1, 8))
w = e.w


def server(path, body=None):
    request = urllib.request.Request(f"http://127.0.0.1:{PORT}{path}", data=body.encode() if body is not None else None)
    return urllib.request.urlopen(request, timeout=60).read()


def asked():
    return json.loads(server("/__log"))


def calm():
    server("/__down", "0")
    server("/__slow", "0")
    server("/__faults", "[]")
    e.shell("setprop debug.oort.free ''; setprop debug.oort.metered 0")


class Library:
    def __init__(self, files, work):
        self.files, self.signer, self.other = files, make_vectors.Signer(work), make_vectors.Signer(work)
        self.certificate = (files / "certificate.txt").read_text().strip()

    def code(self, kind="desktop"):
        fields = {"oort": "drive-1", "kind": kind, "client": "1-oort.apps.googleusercontent.com", "folder": "ROOT", "signer": self.signer.public}
        return json.dumps(fields, separators=(",", ":"))

    def serve(self, update=False):
        t = make_vectors.Tree(self.signer)

        def apk(name, package, code):
            return {"path": "game.apk", "id": package, "version_code": code, "certificate_sha256": self.certificate}, ("game.apk", {"path": str((self.files / "cloud-games" / f"{name}.apk").resolve())})

        package, file = apk("phare-1", "org.nx2a.cloudphare", 1)
        arch = {"architecture": "x86_64", "features": []}
        self.phare = t.target(PHARE, "Le phare de Brume", "android", files=[file, ("data/RomFS/big.bin", "big", 6 << 20), ("data/RomFS/sub/a.bin", "a", 900)], package=package, **arch)
        if update:
            package, file = apk("phare-2", "org.nx2a.cloudphare", 2)
            t.target(PHARE, "Le phare de Brume", "android", stamp=make_vectors.T0 + 1000, version="1.1.0", files=[file, ("data/RomFS/big.bin", "big2", 2 << 20)], package=package, **arch)
        package, file = apk("maree-1", "org.nx2a.cloudmaree", 1)
        t.target(MAREE, "Marée haute", "android", version="2.3.0", files=[file], package=package, **arch)
        t.mac(HILLS, "Collines rouges")
        t.target(GLASS, "Verre", "android", system="99", files=[file], package=package, **arch)
        t.target(MAGNET, "Aimant", "android", files=[file], package=package, architecture="x86_64", features=["neverseen"])
        t.target(ECHO, "Écho", "android", files=[file], package=package, host=2, **arch)
        t.target(SHADOW, "Ombre", "android", files=[file], package=package, signer=self.other, **arch)
        server("/__vector", json.dumps({"drive": t.drive(), "auth": {"refresh": "none"}, "faults": []}))


def has(*texts, seconds=15):
    """The first of these words on screen: the system speaks its own language."""
    end = time.time() + seconds
    while time.time() < end:
        nodes = e.screen()
        for text in texts:
            node = e.find(text, nodes, exact=True)
            if node:
                return node
        time.sleep(0.5)
    return None


def press(*texts, seconds=15, name=None):
    node = has(*texts, seconds=seconds)
    if not node:
        e.ok(f"tap {name or texts[0]}", False, "not on screen")
        return False
    e.shell("input tap %d %d" % node.centre)
    time.sleep(1.2)
    return True


def row(text, seconds=12):
    """A line of a list, scrolled to."""
    for _ in range(6):
        node = e.wait(text, 2.5)
        if node:
            e.shell("input tap %d %d" % node.centre)
            time.sleep(1.2)
            return True
        e.scroll()
    e.ok(f"line “{text}”", False, "not on screen")
    return False


def home():
    for _ in range(4):
        e.system_back()
        if e.front() != e.PACKAGE:
            break
    e.fresh()


def to_cloud():
    e.tap(w("nav_settings"), exact=True)
    row(w("integrations"))
    e.tap(w("cloud_library"), exact=True)


def paste(code):
    row(w("cloud_paste"))
    e.wait(w("cloud_code_field"), 8)
    node = e.find(w("cloud_code_field"))
    if node:
        e.shell("input tap %d %d" % node.centre)
        time.sleep(1.5)
    # A busy emulator loses keys that come too fast: what was typed is read back.
    for size in (40, 12, 5):
        for start in range(0, len(code), size):
            e.shell("input text '%s'" % code[start:start + size])
        time.sleep(1.5)
        typed = [n.text for n in e.screen() if n.text.strip().startswith(code[:4])]
        if code in typed:
            break
        print("typed:", typed, flush=True)
        e.shell("input keyevent KEYCODE_MOVE_END; input keyevent --longpress " + " ".join(["KEYCODE_DEL"] * 40))
        for _ in range(len(code) // 40 + 2):
            e.shell("input keyevent " + " ".join(["KEYCODE_DEL"] * 40))
    if not e.find(w("cloud_use_code"), exact=True):
        e.system_back()  # the keyboard, over the key
    e.tap(w("cloud_use_code"), exact=True)
    time.sleep(1)


def sign_in(allow, name):
    row(w("cloud_sign_in"))
    end = time.time() + 60
    while time.time() < end:
        link = e.find("Allow" if allow else "Refuse", exact=True)
        if link and "Invented" in " ".join(n.said for n in e.screen()):
            e.shot(name)
            e.shell("input tap %d %d" % link.centre)
            time.sleep(4)
            return e.wait_front(e.PACKAGE, 20) or e.start() is None
        for text in ("Accept & continue", "Use without an account", "No thanks", "No Thanks", "Continue", "Got it"):
            node = e.find(text, exact=True)
            if node and node.package != e.PACKAGE:
                e.shell("input tap %d %d" % node.centre)
                time.sleep(1.5)
        time.sleep(1)
    e.ok("the browser shows the sign-in page", False, e.front())
    return False


def join(library):
    to_cloud()
    row(w("cloud_turn_on"))
    paste(library.code())
    sign_in(True, "cloud-07-browser")
    e.see("the folder is found", w("cloud_found"), seconds=40)


def library_cloud():
    e.tap(w("nav_library"), exact=True)
    e.tap(w("cloud_filter"), exact=True)


def game(name):
    library_cloud()
    for _ in range(4):
        if e.find(name, exact=True):
            break
        e.scroll()
    e.tap(name, exact=True)


def download():
    press(w("cloud_download"), w("cloud_update"), name="download")
    node = has("Allow", "Autoriser", seconds=4)
    if node:
        e.shell("input tap %d %d" % node.centre)
        time.sleep(1)


def install(first):
    press(w("cloud_install"), name="install")
    if first:
        e.shot("cloud-20-folder-why")
        press("Continue", "Continuer", name="why a folder")
        e.shot("cloud-21-folder")
        new = has("USE THIS FOLDER", "Use this folder", "UTILISER CE DOSSIER", "Utiliser ce dossier", seconds=12)
        if new:
            e.shell("input tap %d %d" % new.centre)
            time.sleep(1.5)
        press("Allow", "ALLOW", "Autoriser", "AUTORISER", name="allow the folder")
        if e.api and not e.shell(f"appops get {CLOUD} REQUEST_INSTALL_PACKAGES").count("allow"):
            press("Continue", "Continuer", name="why installing")
            e.shot("cloud-22-unknown-apps")
            e.shell(f"appops set {CLOUD} REQUEST_INSTALL_PACKAGES allow")  # the switch of that page
            e.system_back()
    question = has("Install", "INSTALL", "Installer", "INSTALLER", "Update", "UPDATE", "Mettre à jour", seconds=25)
    e.ok("Android asks before installing", question is not None and question.package != e.PACKAGE)
    e.shot("cloud-23-confirm")
    if question:
        e.shell("input tap %d %d" % question.centre)
    return e.see("installed: Play is offered", w("detail_play"), seconds=60)


def installed(package):
    return re.search(r"versionCode=(\d+)", e.shell(f"dumpsys package {package}"))


def shared():
    return e.shell("find /sdcard/Documents -type f 2>/dev/null").split()


def media(node=None):
    return [c for c in asked() if c["call"] == "media" and (node is None or c["node"] == node)]


def sockets(package):
    uid = re.search(r"userId=(\d+)", e.shell(f"dumpsys package {package}"))
    table = e.shell("cat /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6")
    return [line for line in table.splitlines() if uid and f" {uid.group(1)} " in line]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--files", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    e.out = args.out
    e.api = int(e.shell("getprop ro.build.version.sdk"))
    e.adb("root")
    time.sleep(3)
    e.adb("wait-for-device")
    tablet = min(e.display()) / e.density() >= 600
    with tempfile.TemporaryDirectory() as folder:
        work = Path(folder)
        (work / "empty.json").write_text('{"drive": {"root": "ROOT", "nodes": []}}')
        stand_in = subprocess.Popen([sys.executable, "-I", "-B", str(ROOT / "Tests/PhoneLibrary/fake_drive.py"), str(work / "empty.json"), str(PORT)])
        time.sleep(1)
        try:
            run(args.files, work, tablet)
        except Exception as error:  # a picture of where it stopped
            e.ok(f"the check itself: {type(error).__name__} {error}", False, "stopped")
        finally:
            stand_in.kill()
    crashes = e.shell("logcat -d -b crash")
    (args.out / "crash-log.txt").write_text(crashes)
    e.ok("nothing crashed", "oortnx" not in crashes, "see crash-log.txt")
    (args.out / "report.json").write_text(json.dumps({"api": e.api, "passed": e.passed, "failed": e.failed, "small": e.small}, indent=1, ensure_ascii=False))
    print(f"{len(e.passed)} passed, {len(e.failed)} failed")
    sys.exit(1 if e.failed else 0)


def run(files, work, tablet):
    library = Library(files, work)
    e.shell("settings put system screen_off_timeout 1800000; svc power stayon true; logcat -b crash -c")
    for flag in ("chrome",):
        e.shell(f"echo '{flag} --disable-fre --no-default-browser-check --no-first-run' > /data/local/tmp/chrome-command-line; am set-debug-app --persistent com.android.chrome")
    for package in (e.PACKAGE, CLOUD, "org.nx2a.cloudphare", "org.nx2a.cloudmaree"):
        e.adb("uninstall", package)
    e.adb("install", "-r", files / "oort.apk", check=True, timeout=300)
    e.language("fr")
    e.adb("reverse", f"tcp:{PORT}", f"tcp:{PORT}")
    calm()
    library.serve()
    asked()

    # Without the module, then with one another key signed.
    e.fresh()
    to_cloud()
    e.see("without Oort Cloud, it says so", w("cloud_missing"))
    e.shot("cloud-01-not-installed")
    e.adb("install", "-r", files / "cloud-other-key.apk", check=True, timeout=300)
    e.fresh()
    to_cloud()
    e.see("a module signed by someone else is not spoken to", w("cloud_missing"))
    e.adb("uninstall", CLOUD)
    e.adb("install", "-r", files / "cloud.apk", check=True, timeout=300)
    answer = e.shell(f"content call --uri content://{CLOUD}/state --method state 2>&1")
    e.ok("the module answers nobody but Oort NX", "SecurityException" in answer or "not Oort NX" in answer, answer[:200])
    e.shell(f"am start -n {CLOUD}/io.github.sofianbll.oortnx.cloud.StepActivity -a install 2>&1")
    time.sleep(2)
    e.ok("its steps cannot be started by someone else", e.front() != CLOUD, e.front())

    # Off.
    e.fresh()
    to_cloud()
    e.see("off: what it reads", w("cloud_reads"))
    e.shot("cloud-02-off")
    e.scroll()
    e.shot("cloud-03-off-more")
    time.sleep(3)
    e.ok("off: nothing is asked of the network", asked() == [])
    e.ok("off: no socket", sockets(CLOUD) == [], str(sockets(CLOUD)))
    e.ok("Oort NX: no socket", sockets(e.PACKAGE) == [], str(sockets(e.PACKAGE)))
    e.tap(w("nav_library"), exact=True) if tablet else None

    # The code.
    e.fresh()
    to_cloud()
    row(w("cloud_turn_on"))
    e.see("on: the code is asked for", w("cloud_scan"))
    e.shot("cloud-04-steps")
    paste("hello")
    e.see("a wrong code is refused", w("cloud_code_wrong"))
    e.shot("cloud-05-code-refused")
    paste(library.code("ios"))
    e.see("an iPhone's code is refused", w("cloud_code_other"))
    row(w("cloud_scan"))
    allow = has("While using the app", "WHILE USING THE APP", "Allow", "ALLOW", "Lorsque vous utilisez l'appli", "Autoriser", seconds=6)
    e.shot("cloud-06-camera-question")
    if allow:
        e.shell("input tap %d %d" % allow.centre)
        time.sleep(2)
    e.shot("cloud-06-scan")
    press("Close", "CLOSE", "Fermer", "FERMER", name="close the scan")
    e.ok("a code asks nothing of the network", asked() == [])
    paste(library.code())
    sign_in(False, "cloud-07-browser")
    e.see("Google refuses: said, nothing changed", w("cloud_sign_in_refused"), seconds=20)
    e.shot("cloud-08-refused")
    sign_in(True, "cloud-07-browser")
    e.see("the folder is found", w("cloud_found"), seconds=40)
    e.shot("cloud-09-found")
    e.scroll()
    e.shot("cloud-10-settings")

    # The library.
    library_cloud()
    e.see("a game that runs here", "Le phare de Brume", seconds=20)
    e.shot("cloud-11-library")
    for _ in range(3):
        e.scroll()
    for key in ("cloud_reason_mac", "cloud_reason_system", "cloud_reason_graphics", "cloud_reason_launcher", "cloud_reason_unsigned"):
        if not e.find(w(key)):
            e.scroll(down=False)
        e.see(f"its reason: {key}", w(key), seconds=6)
    e.shot("cloud-12-not-here")

    # Downloading: progress, pause, the end of the process, resume.
    game("Le phare de Brume")
    e.shot("cloud-13-game")
    server("/__slow", "400000")
    download()
    time.sleep(5)
    e.shot("cloud-14-downloading")
    e.ok("a notification says so", CLOUD in e.shell("dumpsys notification --noredact | grep -A3 NotificationRecord | head -60"))
    press(w("cloud_pause"), name="pause")
    e.see("paused", w("cloud_paused"), seconds=15)
    e.shot("cloud-15-paused")
    before = media(library.phare["ids"]["data/RomFS/big.bin"])
    time.sleep(3)
    e.ok("paused: nothing is asked", media() == [])
    press(w("cloud_resume"), name="resume")
    time.sleep(6)
    e.shell(f"kill -9 $(pidof {CLOUD})")
    time.sleep(8)
    e.ok("after its process was killed, it goes on", bool(media()) or "big.bin" in e.shell(f"find /data/data/{CLOUD} -name '*.part' | head"))
    server("/__slow", "0")
    e.fresh()
    game("Le phare de Brume")
    e.see("ready to install", w("cloud_install"), seconds=90)
    e.shot("cloud-16-ready")
    after = media(library.phare["ids"]["data/RomFS/big.bin"])
    e.ok("no range already here is asked for again", not (before and any(c["first"] == 0 for c in after)), f"{[c['first'] for c in before]} then {[c['first'] for c in after]}")

    # Installing, playing, the data beside.
    install(True)
    e.shot("cloud-24-installed")
    e.ok("Android installed version 1", (installed("org.nx2a.cloudphare") or [0, 0])[1] == "1")
    e.ok("its data is in the folder the player chose", any(p.endswith(f"{PHARE}/RomFS/sub/a.bin") for p in shared()), str(shared()))
    press(w("detail_play"), name="play")
    e.ok("the installed game starts", e.wait_front("org.nx2a.cloudphare"), e.front())
    e.system_back()
    e.start()

    # Update.
    library.serve(update=True)
    e.fresh()
    library_cloud()
    e.tap(w("cloud_again"))
    time.sleep(3)
    e.see("an update is seen", w("cloud_update"), seconds=20)
    e.shot("cloud-25-update")
    game("Le phare de Brume")
    download()
    e.see("ready", w("cloud_install"), seconds=60)
    install(False)
    e.ok("Android updated to version 2", (installed("org.nx2a.cloudphare") or [0, 0])[1] == "2")
    e.ok("what the old build alone had is gone", not any(p.endswith("sub/a.bin") for p in shared()) and any(p.endswith("big.bin") for p in shared()), str(shared()))

    # Removed by the player through Android's page: its data can go too.
    e.adb("uninstall", "org.nx2a.cloudphare")
    e.fresh()
    game("Le phare de Brume")
    e.scroll()
    row(w("cloud_clean"))
    time.sleep(3)
    e.ok("the data it left is deleted", not any(PHARE in p for p in shared()), str(shared()))

    # What goes wrong.
    e.fresh()
    game("Marée haute")
    server("/__faults", '[{"on": "media", "times": 99, "do": "corrupt"}]')
    download()
    e.see("a file that is not the Mac's is refused", w("cloud_error_file"), seconds=60)
    e.shot("cloud-30-wrong-file")
    server("/__faults", '[{"on": "media", "times": 99, "do": "status", "status": 403, "reason": "downloadQuotaExceeded"}]')
    press(w("cloud_try_again"), name="try again")
    e.see("Google's limit is said", w("cloud_error_quota"), seconds=60)
    e.shot("cloud-31-quota")
    calm()
    row(w("cloud_cancel"))
    e.see("cancelled", w("cloud_download"), seconds=20)
    e.ok("a cancelled download leaves nothing", "part" not in e.shell(f"find /data/data/{CLOUD}/no_backup -name '*.part'"))
    e.shell("setprop debug.oort.free 1000000")
    download()
    e.see("no room is said", w("cloud_error_room").split(":")[0], seconds=30)
    e.shot("cloud-32-no-room")
    row(w("cloud_cancel"))
    calm()
    e.shell("setprop debug.oort.metered 1")
    asked()
    time.sleep(1)
    press(w("cloud_download"), name="download")
    e.see("mobile data waits for Wi-Fi", w("cloud_error_wifi"), seconds=30)
    e.shot("cloud-33-wifi")
    e.ok("no mobile data was used", media() == [])
    calm()
    server("/__slow", "8000")
    e.shell("svc wifi disable; svc data disable")
    time.sleep(6)
    e.shot("cloud-34-offline")
    server("/__slow", "0")
    e.shell("svc wifi enable; svc data enable")
    e.see("back on line, it ends by itself", w("cloud_install"), seconds=120)
    server("/__revoke", "")
    e.shell(f"am force-stop {CLOUD}")
    e.fresh()
    library_cloud()
    e.tap(w("cloud_again"))
    e.see("access withdrawn is said", w("cloud_error_sign_in"), seconds=40)
    e.shot("cloud-35-revoked")

    # Off: keep, then delete.
    for delete in (False, True):
        calm()
        library.serve()
        if delete:
            e.fresh()
            join(library)
            game("Marée haute")
            press(w("cloud_download"), name="download")
            e.see("ready before turning off", w("cloud_install"), seconds=60)
        e.fresh()
        to_cloud()
        row(w("cloud_turn_off"))
        e.see("turning off says what stays", w("cloud_off_title"))
        e.shot("cloud-40-turn-off")
        row(w("cloud_delete" if delete else "cloud_keep"))
        e.see("off again", w("cloud_turn_on"), seconds=20) or e.scroll()
        kept = "game.apk" in e.shell(f"find /data/data/{CLOUD}/no_backup -name game.apk")
        e.ok("downloads deleted" if delete else "downloads kept", kept != delete)
        e.ok("the sign-in is erased", e.shell(f"ls /data/data/{CLOUD}/no_backup/cloud/sign-in 2>&1").count("No such") == 1)
        asked()
        e.fresh()
        time.sleep(4)
        e.ok("off again: nothing is asked", asked() == [])
    log = asked()
    e.ok("the cloud was only read", not any(c["call"] in ("write", "other", "revoke") for c in log))

    # Other shapes: English, the largest text, on its side, a controller.
    e.language("en")
    e.adb("reverse", f"tcp:{PORT}", f"tcp:{PORT}")
    library.serve()
    e.fresh()
    to_cloud()
    e.shot("en-cloud-02-off")
    row(w("cloud_turn_on"))
    paste(library.code())
    sign_in(True, "en-cloud-07-browser")
    e.see("en: the folder is found", w("cloud_found"), seconds=40)
    e.shot("en-cloud-09-found")
    library_cloud()
    time.sleep(2)
    e.shot("en-cloud-11-library")
    game("Le phare de Brume")
    e.shot("en-cloud-13-game")
    e.shell("settings put system font_scale 2.0")
    e.fresh()
    to_cloud()
    e.shot("en-large-cloud-settings")
    library_cloud()
    e.shot("en-large-cloud-library")
    game("Marée haute")
    e.shot("en-large-cloud-game")
    e.shell("settings put system font_scale 1.0; settings put system accelerometer_rotation 0; settings put system user_rotation 1")
    time.sleep(2)
    e.fresh()
    library_cloud()
    e.shot("en-landscape-cloud-library")
    game("Le phare de Brume")
    e.shot("en-landscape-cloud-game")
    e.fresh()
    e.pad("R1")
    e.pad("UP")
    e.shot("en-pad-cloud-library")
    e.pad("RIGHT", "A")
    e.see("a controller opens a game of the cloud", w("cloud_size"), seconds=10)
    e.shot("en-pad-cloud-game")
    e.shell("settings put system user_rotation 0")
    e.ok("every target is large enough", not e.small, json.dumps(e.small, ensure_ascii=False))


if __name__ == "__main__":
    main()
