#!/usr/bin/env python3
"""Drives the release APK in a running emulator, as a player would: finds the made-up games, starts one and comes back,
with the finger and with a controller, upright and on its side, on a phone and a tablet, in English and in French, with
large text. Writes pictures and a report; fails on a missing thing, a crash, or a touch target under 48 dp.

    emulator_check.py --apk oort.apk --games DIR --out DIR
"""
import argparse
import json
import re
import struct
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = "io.github.sofianbll.oortnx.alpha"
ACTIVITY = f"{PACKAGE}/io.github.sofianbll.oortnx.MainActivity"
ALPHA_VERSION = "0.1.0-alpha.2"
ALPHA_VERSION_CODE = "2"
PAD_TEST_WINDOW = (500, 300)
MIN_PAD_TOUCH_DP = 48
RES = Path(__file__).resolve().parents[1] / "app/src/main/res"
GAMES = ["Le phare de Brume", "Marée haute", "Collines rouges", "Les très longues aventures de la comète perdue"]
PAD = {"A": "BUTTON_A", "B": "BUTTON_B", "X": "BUTTON_X", "Y": "BUTTON_Y", "L1": "BUTTON_L1", "R1": "BUTTON_R1", "START": "BUTTON_START",
       "UP": "DPAD_UP", "DOWN": "DPAD_DOWN", "LEFT": "DPAD_LEFT", "RIGHT": "DPAD_RIGHT"}

passed, failed, small = [], [], {}
out = Path()
words = {}
api = 0
side = 0


def adb(*args, binary=False, check=False, timeout=90):
    done = subprocess.run(["adb", *map(str, args)], capture_output=True, timeout=timeout)
    if check and done.returncode:
        raise RuntimeError(f"adb {' '.join(map(str, args))}: {done.stderr.decode(errors='replace')}")
    return done.stdout if binary else done.stdout.decode(errors="replace")


def shell(command, **kw):
    return adb("shell", command, **kw)


def ok(name, good, detail=""):
    (passed if good else failed).append(name + (f" ({detail})" if detail and not good else ""))
    print(("ok    " if good else "FAIL  ") + name + (f": {detail}" if detail and not good else ""), flush=True)
    if not good:
        shot("FAIL-" + re.sub(r"[^a-z0-9]+", "-", name.lower())[:60])
    return good


def shot(name):
    (out / f"{name}.png").write_bytes(adb("exec-out", "screencap", "-p", binary=True))


class Node:
    def __init__(self, element):
        self.text, self.desc, self.package = element.get("text", ""), element.get("content-desc", ""), element.get("package", "")
        self.said = " ".join(filter(None, [self.text, self.desc]))
        self.clickable, self.checked, self.selected = (element.get(k) == "true" for k in ("clickable", "checked", "selected"))
        self.checkable = element.get("checkable") == "true"
        self.box = [int(n) for n in re.findall(r"-?\d+", element.get("bounds", "[0,0][0,0]"))]

    @property
    def centre(self):
        return (self.box[0] + self.box[2]) // 2, (self.box[1] + self.box[3]) // 2


def is_on(text, nodes):
    """Whether the line that says [text] is checked: its words are inside the line, which carries the state."""
    for said in (n for n in nodes if n.text == text):
        x, y = said.centre
        for n in nodes:
            if n.checkable and n.box[0] <= x <= n.box[2] and n.box[1] <= y <= n.box[3]:
                return n.checked
    return None


def chosen(nodes=None):
    """The game chosen on the first screen: its name is inside the cover, which carries the state."""
    nodes = screen() if nodes is None else nodes
    for said in (n for n in nodes if n.desc in GAMES):
        x, y = said.centre
        if any(n.selected and n.package == PACKAGE and n.box[0] <= x <= n.box[2] and n.box[1] <= y <= n.box[3] for n in nodes):
            return said.desc
    return None


def density():
    return int(re.findall(r"density: (\d+)", shell("wm density"))[-1]) / 160


def screen(check_targets=True):
    for _ in range(4):
        shell("rm -f /sdcard/oort-ui.xml; uiautomator dump /sdcard/oort-ui.xml")
        text = adb("exec-out", "cat", "/sdcard/oort-ui.xml")
        if "<hierarchy" in text:
            break
        time.sleep(1)
    else:
        return []
    nodes = [Node(e) for e in ET.fromstring(text[text.index("<"):]).iter("node")]
    if not check_targets:
        return nodes
    size = [max(n.box[2] for n in nodes), max(n.box[3] for n in nodes)]
    scale = density()
    for n in nodes:
        if n.package != PACKAGE or not n.clickable:
            continue
        w, h = n.box[2] - n.box[0], n.box[3] - n.box[1]
        # A line cut by the edge of its scrolling page is not a small target.
        edge = n.box[0] <= 0 or n.box[2] >= size[0] or n.box[1] <= 90 * scale or n.box[3] >= size[1] - 120 * scale
        if min(w, h) < 47.5 * scale and not edge:
            if (n.said or "(no name)") not in small:
                shot(f"SMALL-{len(small)}")
            small[n.said or "(no name)"] = f"{w / scale:.0f}x{h / scale:.0f} dp"
    return nodes


def find(text, nodes=None, exact=False):
    hits = [n for n in (screen() if nodes is None else nodes) if (text == n.text or text == n.desc if exact else text.lower() in n.said.lower())]
    return hits[0] if hits else None


def wait(text, seconds=20, exact=False):
    end = time.time() + seconds
    while True:
        node = find(text, exact=exact)
        if node or time.time() > end:
            return node
        time.sleep(0.5)


def see(name, text, **kw):
    node = wait(text, **kw)
    ok(name, node is not None, f"no “{text}” on screen")
    return node


def tap(text, exact=False, seconds=15):
    node = wait(text, seconds, exact)
    if not node:
        ok(f"tap “{text}”", False, "not on screen")
        return False
    shell("input tap %d %d" % node.centre)
    time.sleep(0.9)
    return True


def pad(*keys):
    for key in keys:
        shell(f"input gamepad keyevent {PAD[key]}")
        time.sleep(0.45)
    time.sleep(0.4)


def system_back():
    shell("input keyevent BACK")
    time.sleep(1)


def display():
    return [int(n) for n in re.findall(r"cur=(\d+)x(\d+)", shell("dumpsys window displays"))[0]]


def scroll(down=True):
    w, h = display()
    a, b = int(h * 0.7), int(h * 0.3)
    shell(f"input swipe {w // 2} {a if down else b} {w // 2} {b if down else a} 250")
    time.sleep(0.8)


def front():
    found = re.findall(r"(?:topResumedActivity|mResumedActivity|ResumedActivity)[=:].*?u0 ([\w.]+)/", shell("dumpsys activity activities"))
    return found[0] if found else ""


def wait_front(package, seconds=15):
    end = time.time() + seconds
    while time.time() < end:
        if front() == package:
            return True
        time.sleep(0.4)
    return False


def start():
    shell(f"am start -W -n {ACTIVITY}")
    time.sleep(1.5)


def fresh():
    shell(f"am force-stop {PACKAGE}")
    start()


def load_words(lang):
    folder = "values-fr" if lang == "fr" else "values"
    words.clear()
    words.update({s.get("name"): (s.text or "") for s in ET.parse(RES / folder / "strings.xml").getroot().iter("string")})


def language(lang):
    load_words(lang)
    tag = "fr-FR" if lang == "fr" else "en-US"
    if api >= 33:
        shell(f"cmd locale set-app-locales {PACKAGE} --user 0 --locales {tag}")
    elif shell("getprop persist.sys.locale").strip() not in (tag, "" if lang == "en" else tag):
        adb("root")
        time.sleep(3)
        adb("wait-for-device")
        shell(f"setprop persist.sys.locale {tag}; stop; sleep 2; start")
        time.sleep(15)
        for _ in range(90):
            if shell("getprop sys.boot_completed").strip() == "1" and "package:" in shell("pm path android") and shell("wm size").strip():
                break
            time.sleep(2)
        time.sleep(20)
        shell("wm dismiss-keyguard; input keyevent 82")
    time.sleep(1)


def w(name, *args):
    text = words[name]
    for i, a in enumerate(args, 1):
        text = text.replace(f"%{i}$d", str(a)).replace(f"%{i}$s", str(a))
    return text.replace("\\'", "'")


# ---- what is checked ------------------------------------------------------------------------------------------


def empty_library_controls(games):
    """The only button on the empty library rescans, just like a touch."""
    fixture = games / "org.nx2a.testmaree.apk"
    for device, command, search in (
        ("pad", "input gamepad keyevent BUTTON_A", "input gamepad keyevent BUTTON_Y"),
        ("keyboard", "input keyevent ENTER", "input keycombination CTRL_LEFT F"),
    ):
        if device == "keyboard" and api < 33:
            continue
        fresh()
        wait(w("empty_rescan"))
        shell(search)
        time.sleep(0.7)
        nodes = screen()
        home = find(w("nav_home"), nodes, exact=True)
        ok(f"empty Home, {device}: search does not take the player to an invisible field",
           home is not None and any(n.selected and n.package == PACKAGE
                                    and n.box[0] <= home.centre[0] <= n.box[2] and n.box[1] <= home.centre[1] <= n.box[3]
                                    for n in nodes))
        fresh()
        pad("R1")
        wait(w("empty_rescan"))
        shot(f"empty-{device}-before-confirm")
        adb("install", "-r", fixture, check=True)
        shell(command)
        see(f"empty Library, {device}: confirm rescans when a game was installed", GAMES[1], seconds=5)
        shot(f"empty-{device}-after-confirm")
        adb("uninstall", fixture.stem, check=True)


def low_pad_keyboard():
    """500 × 300 dp: the last row follows the controller, at both text sizes."""
    try:
        width, height = PAD_TEST_WINDOW
        shell(f"wm size {width}x{height}; wm density 160")
        time.sleep(3)
        ok("pad keyboard: the synthetic window is 500 × 300 dp", tuple(display()) == PAD_TEST_WINDOW and density() == 1)
        for scale in (1, 2):
            shell(f"settings put system font_scale {scale}.0")
            time.sleep(2)
            fresh()
            pad("Y")
            shot(f"pad-keyboard-low-{scale}x-first-row")
            pad(*(["DOWN"] * 5), "RIGHT", "RIGHT", "RIGHT")
            # Clipped neighbouring rows are expected; the selected key must be a full touch target.
            nodes = screen(check_targets=False)
            label = find("OK", nodes, exact=True)
            key = next((n for n in nodes if label and n.clickable and n.package == PACKAGE
                        and n.box[0] <= label.centre[0] <= n.box[2] and n.box[1] <= label.centre[1] <= n.box[3]), None)
            ok(f"pad keyboard at {scale}× text: the selected last-row key is fully visible",
               key is not None and min(key.box[3] - key.box[1], key.box[2] - key.box[0]) >= MIN_PAD_TOUCH_DP,
               str(key and key.box))
            shot(f"pad-keyboard-low-{scale}x-last-row")
            pad("A")
            nodes = screen(check_targets=False)
            ok(f"pad keyboard at {scale}× text: OK closes the keyboard, not the search",
               find(w("search_field"), nodes) is not None and find("OK", nodes, exact=True) is None)
    finally:
        shell("settings put system font_scale 1.0; wm size reset; wm density reset")
        time.sleep(4)


def library_focus_after_play(games):
    """Starting a non-first game moves its tile without changing what Options targets."""
    fresh()
    tap(w("nav_library"), exact=True)
    tap(w("sort"), exact=True)
    tap(w("sort_last"), exact=True)
    tap(GAMES[1])
    tap(w("detail_play"), exact=True)
    if not ok("focus on return: first game establishes the recent order", wait_front("org.nx2a.testmaree"), front()):
        return
    system_back()
    wait_front(PACKAGE)
    system_back()
    tap(GAMES[2])
    system_back()
    pad("START", "A")
    if not ok("focus on return: Options plays the second game", wait_front("org.nx2a.testcollines"), front()):
        return
    system_back()
    wait_front(PACKAGE)
    time.sleep(1)
    shot("library-focus-after-play")
    pad("START", "A")
    ok("focus on return: Options still plays that same game after it moved up", wait_front("org.nx2a.testcollines", 5), front())
    system_back()
    wait_front(PACKAGE)
    tap(w("sort"), exact=True)
    tap(w("sort_name"), exact=True)
    tap(GAMES[0])
    see("focus after removal: the library's target before backgrounding", "org.nx2a.testphare", exact=True)
    system_back()
    shell(f"input keyevent HOME; sleep 2; am kill {PACKAGE}")
    removed = games / "org.nx2a.testcollines.apk"
    adb("uninstall", removed.stem, check=True)
    try:
        start()
        wait(w("sort"), exact=True)
        pad("X")
        see("focus after removal: the restored library still targets the same game", "org.nx2a.testphare", exact=True, seconds=5)
        shot("library-focus-after-removal")
    finally:
        adb("install", "-r", removed, check=True)


def restored_sound_focus():
    fresh()
    tap(w("nav_settings"), exact=True)
    tap(w("settings_sound"))
    tap("Oort", exact=True)
    pad("DOWN")
    shot("sounds-before-process-death")
    pid = shell(f"pidof {PACKAGE}").strip()
    shell(f"input keyevent HOME; sleep 2; am kill {PACKAGE}; sleep 1")
    start()
    new_pid = shell(f"pidof {PACKAGE}").strip()
    ok("sound focus: Android rebuilt the process", bool(pid and new_pid and new_pid != pid))
    see("sound focus: same page on return", w("settings_pack"))
    shot("sounds-after-process-death")
    pad("A")
    nodes = screen()
    ok("sound focus: confirm chooses Pollen instead of toggling sound",
       is_on("Pollen", nodes) is True and is_on(w("settings_sound"), nodes) is True)
    shot("sounds-after-confirm")
    tap("Oort", exact=True)
    if is_on(w("settings_sound"), screen()) is False:
        tap(w("settings_sound"), exact=True)


def refocus_search():
    if api < 33:
        return
    fresh()
    shell("input keycombination CTRL_LEFT F")
    wait(w("search_field"))
    shell("input text maree; input keyevent DPAD_DOWN; input keycombination CTRL_LEFT F; sleep 1; input keyevent Q E")
    see("keyboard: Ctrl+F returns to a non-empty search and Q/E type there", "mareeqe", exact=True, seconds=5)
    shot("search-refocus")


def touch(lang):
    """Every screen with the finger, on a phone upright."""
    fresh()
    see(f"{lang}: the first screen offers Play", w("detail_play"))
    shot(f"{lang}-01-home")
    first = chosen()
    ok(f"{lang}: a made-up game is on the first screen", first is not None)
    width, height = display()
    # Slow, and ending off the cover: a short one can reach a busy emulator as a press and a release, with no movement.
    shell(f"input swipe {int(width * .8)} {int(height * .45)} {int(width * .08)} {int(height * .45)} 700")
    time.sleep(1.5)
    shot(f"{lang}-02-home-swiped")
    then = chosen()
    ok(f"{lang}: the swipe chose another game", then not in (None, first), f"{first}, then {then}")

    fresh()
    tap(w("nav_library"), exact=True)
    time.sleep(0.8)
    nodes = screen()
    for game in GAMES:
        ok(f"{lang}: the library lists {game}", find(game, nodes) is not None)
    ok(f"{lang}: the library leaves out an app that is not a game", find("Pas un jeu", nodes) is None)
    shot(f"{lang}-03-library")
    tap(w("sort"), exact=True)
    shot(f"{lang}-04-library-sort")
    tap(w("sort_name"), exact=True)
    nodes = [n for n in screen() if any(g == n.text or g in n.said for g in GAMES)]
    order = sorted({next(g for g in GAMES if g in n.said): n.centre for n in nodes}.items(), key=lambda e: (e[1][1] // 100, e[1][0]))
    ok(f"{lang}: sorted by name", [g for g, _ in order] == sorted(GAMES), str([g for g, _ in order]))

    tap(GAMES[1])
    see(f"{lang}: the game's page shows its version", "1.2.0")
    shot(f"{lang}-05-game")
    ok(f"{lang}: the page says it was never started, or when", find(w("started_never")) is not None or find(w("started_today")) is not None)
    scroll()
    scroll()
    shot(f"{lang}-06-game-bottom")
    ok(f"{lang}: Play stays on screen at the foot of the page", find(w("detail_play"), exact=True) is not None)
    # Android's Settings already open on another page: Back from the game's page must still come to Oort.
    shell("am start -a android.settings.LOCALE_SETTINGS; sleep 2; input keyevent HOME")
    start()
    tap(w("detail_info"))
    ok(f"{lang}: Android's page of the game opens", wait_front("com.android.settings"), front())
    time.sleep(5)  # a first start of Android's settings can be slow enough to miss the key
    system_back()
    ok(f"{lang}: one Back returns from Android's page", wait_front(PACKAGE) and wait(w("detail_play"), exact=True) is not None, front())

    tap(w("detail_play"), exact=True)
    ok(f"{lang}: the game starts", wait_front("org.nx2a.testmaree"), front())
    see(f"{lang}: the game shows its text", "FAUX JEU org.nx2a.testmaree")
    shot(f"{lang}-07-fake-game")
    system_back()
    ok(f"{lang}: Back returns from the game to Oort", wait_front(PACKAGE), front())
    scroll(False)
    scroll(False)
    see(f"{lang}: the page now says it was started today", w("started_today"))
    system_back()
    see(f"{lang}: Back leaves the page for the library", w("nav_library"))
    system_back()
    see(f"{lang}: Back leaves the library for the first screen", w("detail_play"))
    ok(f"{lang}: the game just started comes first", chosen() == GAMES[1], str(chosen()))

    tap(w("nav_controllers"), exact=True)
    see(f"{lang}: controllers", w("controllers_connected"))
    shot(f"{lang}-08-controllers")
    tap(w("controllers_test"))
    see(f"{lang}: the controller in dots", w("controllers_hold", "A", "B"))
    shot(f"{lang}-09-padtest")
    system_back()

    tap(w("nav_settings"), exact=True)
    see(f"{lang}: settings", w("settings_thanks"))
    shot(f"{lang}-10-settings")
    tap(w("settings_sound"))
    see(f"{lang}: the sounds have their own page", w("settings_pack"))
    shot(f"{lang}-11-sounds")
    tap("Umbra", exact=True)
    nodes = screen()
    ok(f"{lang}: a sound pack is chosen, and only one", is_on("Umbra", nodes) is True and is_on("Oort", nodes) is False)
    tap("Oort", exact=True)
    ok(f"{lang}: the sound switch reads as on", is_on(w("settings_sound"), screen()) is True or len([n for n in screen() if n.checkable and n.checked]) == 2)
    switch = next((n for n in screen() if n.checkable), None)
    if ok(f"{lang}: the sound switch is there", switch is not None):
        shell("input tap %d %d" % switch.centre)
        time.sleep(0.8)
        ok(f"{lang}: the sound switch turns off", len([n for n in screen() if n.checkable and n.checked]) == 1)
        shell("input tap %d %d" % switch.centre)
        time.sleep(0.8)
    system_back()
    tap(w("settings_cloud"))
    shot(f"{lang}-12-cloud")
    system_back()
    tap(w("settings_which"))
    see(f"{lang}: which games Oort finds", "org.nx2a")
    shot(f"{lang}-13-which")
    system_back()
    scroll()
    tap(w("settings_thanks"))
    see(f"{lang}: credits", "nx2android")
    shot(f"{lang}-14-thanks")
    scroll()
    tap(w("thanks_text_oort"), exact=True)
    see(f"{lang}: the MIT text", "Permission is hereby granted")
    shot(f"{lang}-15-licence")
    system_back()
    tap(w("thanks_text_notices"), exact=True)
    see(f"{lang}: the notices", "shirai91")
    system_back()
    tap(w("thanks_text_apache"), exact=True)
    see(f"{lang}: the Apache text", "Version 2.0")
    system_back()


def controller(lang):
    """The same app with a controller only."""
    fresh()
    see(f"{lang}, pad: first screen", w("detail_play"))
    pad("RIGHT")
    shot(f"{lang}-20-pad-home")
    before = chosen()
    pad("RIGHT")
    ok(f"{lang}, pad: right changes the game", chosen() not in (None, before))
    pad("DOWN", "RIGHT")
    shot(f"{lang}-21-pad-home-keys")
    pad("A")
    see(f"{lang}, pad: A opens the game's page", w("detail_package"))
    shot(f"{lang}-22-pad-game")
    pad("DOWN", "DOWN")
    shot(f"{lang}-23-pad-game-lines")
    pad("UP", "UP", "B")
    ok(f"{lang}, pad: B goes back", wait(w("nav_library"), exact=True) is not None and find(w("detail_package")) is None)
    pad("R1")
    ok(f"{lang}, pad: R1 opens the library", wait(w("sort"), exact=True) is not None)
    pad("DOWN", "RIGHT")
    shot(f"{lang}-24-pad-library")
    pad("X")
    see(f"{lang}, pad: X opens the game's page", w("detail_package"))
    pad("B", "START")
    see(f"{lang}, pad: START opens the game's options", w("favorite_add"))
    shot(f"{lang}-26-pad-game-menu")
    pad("B")
    ok(f"{lang}, pad: B closes the options", find(w("favorite_add")) is None and find(w("sort"), exact=True) is not None)
    pad("A")
    see(f"{lang}, pad: A opens a game from the library", w("detail_package"))
    pad("A")
    ok(f"{lang}, pad: the game starts", any(wait_front(f"org.nx2a.test{g}", 6) for g in ("phare", "maree", "collines", "comete")), front())
    system_back()
    ok(f"{lang}, pad: and comes back", wait_front(PACKAGE), front())
    pad("B", "L1")
    ok(f"{lang}, pad: L1 goes back to the first screen", wait(w("detail_play"), exact=True) is not None and find(w("sort"), exact=True) is None)
    pad("Y")
    see(f"{lang}, pad: Y opens the search", w("search_field"))
    shot(f"{lang}-27-pad-search")
    pad("DOWN", "A")
    see(f"{lang}, pad: Down and A type a letter with the controller", "h", exact=True)
    pad("B")
    nodes = screen()
    ok(f"{lang}, pad: first B closes the keyboard, leaving the search and its text",
       find(w("tab_all"), nodes, exact=True) is not None and find(w("search_field"), nodes) is not None
       and find("h", nodes, exact=True) is not None and find("H", nodes, exact=True) is None)
    shot(f"{lang}-27-pad-search-first-b")
    pad("B")
    ok(f"{lang}, pad: B closes the search", wait(w("tab_all"), exact=True) is not None and find(w("search_field")) is None)
    pad("R1")
    see(f"{lang}, pad: R1 opens the controllers", w("controllers_connected"))
    tap(w("settings_swap"), exact=True)
    pad("A")
    ok(f"{lang}, pad: A and B swapped, A goes back", wait(w("detail_play"), exact=True) is not None)
    pad("R1", "R1")
    tap(w("settings_swap"), exact=True)
    pad("R1", "DOWN", "DOWN")
    see(f"{lang}, pad: the settings", w("settings_thanks"))
    shot(f"{lang}-25-pad-settings")
    pad("B")


def newer(lang):
    """Options by a long press, favourites, search, a keyboard, a rebuilt activity and a low window."""
    fresh()
    tap(w("nav_library"), exact=True)
    node = wait(GAMES[1])
    shell("input swipe %d %d %d %d 900" % (node.centre * 2))
    time.sleep(1)
    see(f"{lang}: a long press opens the game's options", w("favorite_add"))
    shot(f"{lang}-30-game-menu")
    tap(w("favorite_add"))
    tap(w("tab_favorites"), exact=True)
    ok(f"{lang}: the favourites show the favourite only", find(GAMES[1]) is not None and find(GAMES[2]) is None)
    shot(f"{lang}-31-favorites")
    node = wait(GAMES[1])
    shell("input swipe %d %d %d %d 900" % (node.centre * 2))
    time.sleep(1)
    tap(w("favorite_remove"))
    see(f"{lang}: no favourite left says so", w("favorites_empty"))
    tap(w("tab_all"), exact=True)
    tap(w("search"), exact=True)
    shell("input text maree")
    time.sleep(1)
    shot(f"{lang}-32-search")
    ok(f"{lang}: the search ignores accents", find(GAMES[1]) is not None and find(GAMES[2]) is None)
    shell("input text zzz")
    see(f"{lang}: a search that finds nothing says so", w("search_none"))
    tap(w("close"), exact=True)
    see(f"{lang}: closing the search brings every game back", GAMES[2])
    if api >= 33:  # older images have no “input keycombination”
        shell("input keycombination CTRL_LEFT F")
        time.sleep(1)
        see(f"{lang}, keyboard: Ctrl+F opens the search", w("search_field"))
        shell("input keyevent ESCAPE")
        time.sleep(1)
        ok(f"{lang}, keyboard: Escape closes it", find(w("search_field")) is None)
        shell("input keyevent TAB")
        shell("input keycombination CTRL_LEFT O")
        time.sleep(1)
        see(f"{lang}, keyboard: Ctrl+O opens the options", w("favorite_add"))
        shell("input keyevent ESCAPE")
        time.sleep(1)
    if api >= 31:
        fresh()
        tap(w("nav_settings"), exact=True)
        tap(w("settings_sound"))
        shell("settings put secure font_weight_adjustment 300")
        time.sleep(3)
        see(f"{lang}: bold text keeps the open page", w("settings_pack"))
        shell("settings put secure font_weight_adjustment 0")
        time.sleep(2)
    fresh()
    tap(w("nav_library"), exact=True)
    tap(GAMES[1])
    shell("input keyevent HOME")
    time.sleep(1.5)
    shell(f"am kill {PACKAGE}")
    time.sleep(1)
    # Brought back as Android does from the recent apps: the activity of its task, with what it had kept.
    start()
    see(f"{lang}: a return after Android ended the app finds the same page", w("detail_package"))
    shell("wm size 1080x1100; wm density 420")
    time.sleep(4)
    fresh()
    play = wait(w("detail_play"), exact=True)
    ok(f"{lang}: Play stays on screen, in one line, in a low window",
       play is not None and play.box[2] - play.box[0] > play.box[3] - play.box[1] > 20 and play.box[3] <= display()[1], str(play and play.box))
    shot(f"{lang}-33-low-window")
    shell("wm size reset; wm density reset")
    time.sleep(4)


def real_pad():
    """A virtual controller, seen by Android as a real one: a stick, a hat and buttons held together."""
    def line(**kw):
        return (json.dumps(kw) + "\n").encode()
    axes = {0: (-32768, 32767), 1: (-32768, 32767), 2: (-32768, 32767), 5: (-32768, 32767), 9: (0, 255), 10: (0, 255), 16: (-1, 1), 17: (-1, 1)}
    register = line(id=1, command="register", name="Oort test pad", vid=1, pid=1, bus="usb",
                    configuration=[{"type": 100, "data": [1, 3]}, {"type": 101, "data": [304, 305, 307, 308, 310, 311, 312, 313, 314, 315, 316, 317, 318]}, {"type": 103, "data": list(axes)}],
                    abs_info=[{"code": c, "info": {"value": 0, "minimum": a, "maximum": b, "fuzz": 0, "flat": 0, "resolution": 0}} for c, (a, b) in axes.items()])
    process = subprocess.Popen(["adb", "shell", "uinput", "-"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def send(*events):
        process.stdin.write(line(id=1, command="inject", events=[n for e in events for n in (*e, 0, 0, 0)]))
        process.stdin.flush()
        time.sleep(0.6)

    process.stdin.write(register + line(id=1, command="delay", duration=1500))
    process.stdin.flush()
    time.sleep(4)
    if "Oort test pad" not in shell("dumpsys input"):
        print("note  this image does not take a virtual controller: left out", flush=True)
        process.kill()
        return
    fresh()
    tap(w("nav_controllers"), exact=True)
    see("virtual controller: listed by name", "Oort test pad")
    shot("pad-01-connected")
    tap(w("controllers_test"))
    send((1, 310, 1), (1, 307, 1), (3, 0, 32767), (3, 1, -20000), (3, 17, -1), (3, 9, 255))
    time.sleep(2)
    shot("pad-02-held")
    send((1, 310, 0), (1, 307, 0), (3, 0, 0), (3, 1, 0), (3, 17, 0), (3, 9, 0))
    see("virtual controller: the last button is named", w("controllers_last", "X"))
    send((1, 305, 1))
    time.sleep(1.6)
    send((1, 305, 0))
    ok("virtual controller: holding B closes the test", find(w("controllers_hold", "A", "B")) is None)
    send((1, 305, 1))
    send((1, 305, 0))
    see("virtual controller: B then goes to the first screen", w("detail_play"))
    before = chosen()
    send((3, 16, 1))
    send((3, 16, 0))
    ok("virtual controller: the hat moves", chosen() not in (None, before))
    before = chosen()
    # Back to the left: a held direction repeats, so the hat may have reached the last game.
    send((3, 0, -32768))
    send((3, 0, 0))
    ok("virtual controller: the stick moves", chosen() not in (None, before))
    send((1, 304, 1))
    send((1, 304, 0))
    ok("virtual controller: A plays", any(wait_front(f"org.nx2a.test{g}", 6) for g in ("phare", "maree", "collines", "comete")), front())
    process.stdin.close()
    process.kill()
    time.sleep(1)
    system_back()
    wait_front(PACKAGE)
    ok("the app survives the controller leaving", front() == PACKAGE, front())


def picture_size(name):
    return struct.unpack(">II", (out / f"{name}.png").read_bytes()[16:24])


def rotate(to):
    """Asks for the screen on its side (1) or upright (0). The tour checks the pictures: what is asked is not what is got."""
    global side
    side = to
    shell(f"settings put system accelerometer_rotation 0; settings put system user_rotation {to}")
    time.sleep(2.5)


def turned():
    """With the app in front, as Android 10 forgets the rotation when its own upright launcher comes back."""
    for _ in range(3):
        shot("turn")
        w_, h_ = picture_size("turn")
        if (w_ > h_) == (side == 1):
            break
        shell(f"settings put system user_rotation {1 - side}; sleep 1; settings put system user_rotation {side}; wm set-user-rotation lock {side}")
        time.sleep(3)
    (out / "turn.png").unlink()


def tour(prefix, with_pad=False, wide=None):
    """Pictures of every section, from where the app is."""
    fresh()
    if wide is not None:
        turned()
    see(f"{prefix}: first screen", w("detail_play"))
    shot(f"{prefix}-home")
    if wide is not None:
        w_, h_ = picture_size(f"{prefix}-home")
        ok(f"{prefix}: the picture is {'on its side' if wide else 'upright'}", (w_ > h_) == wide, f"{w_}x{h_}")
    if with_pad:
        pad("RIGHT")
        shot(f"{prefix}-home-pad")
        pad("DOWN")
        shot(f"{prefix}-home-pad-keys")
        pad("R1", "RIGHT")
        shot(f"{prefix}-library-pad")
        pad("A")
        see(f"{prefix}: page by the controller", w("game_page"))
        shot(f"{prefix}-game-pad")
        pad("DOWN", "DOWN")
        shot(f"{prefix}-game-pad-lines")
        pad("B", "START")
        shot(f"{prefix}-menu-pad")
        pad("B", "L1", "L1")
        shot(f"{prefix}-settings-pad")
        fresh()
        if wide is not None:
            turned()
        wait(w("detail_play"))
    tap(w("nav_library"), exact=True)
    shot(f"{prefix}-library")
    if not find(GAMES[0]):
        scroll()
    tap(GAMES[0])
    see(f"{prefix}: game page", w("game_page"))
    shot(f"{prefix}-game")
    system_back()
    tap(w("nav_controllers"), exact=True)
    shot(f"{prefix}-controllers")
    tap(w("controllers_test"))
    shot(f"{prefix}-padtest")
    system_back()
    tap(w("nav_settings"), exact=True)
    shot(f"{prefix}-settings")


def crashes():
    log = adb("logcat", "-d", "-b", "crash") + adb("logcat", "-d", "-b", "main,system", "-s", "AndroidRuntime:E", "ActivityManager:E")
    (out / "crash-log.txt").write_text("\n".join(l for l in log.splitlines() if "oortnx" in l or "FATAL" in l or l.lstrip().startswith("at ") or "Exception" in l))
    ok("no crash of Oort in logcat", f"Process: {PACKAGE}" not in log, "see crash-log.txt")
    ok("no “not responding” of Oort", f"ANR in {PACKAGE}" not in log)


def main():
    global out, api
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True)
    parser.add_argument("--games", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    api = int(shell("getprop ro.build.version.sdk"))
    print(f"Android API {api}, {shell('wm size').strip()}, {shell('wm density').strip()}", flush=True)
    adb("logcat", "-c")
    adb("install", "-r", args.apk, check=True)
    installed = shell(f"dumpsys package {PACKAGE}")
    asked = re.findall(r"^\s+([\w.]+\.permission\.[\w.]+|[\w.]+DYNAMIC_RECEIVER[\w]*)", installed, re.M)
    ok("the installed app asks for no Android permission", not [p for p in asked if p.startswith("android.permission")], str(asked))
    name = re.search(r"versionName=(\S+)", installed)
    code = re.search(r"versionCode=(\d+)", installed)
    ok("version name and code", name and code and (name[1], code[1]) == (ALPHA_VERSION, ALPHA_VERSION_CODE),
       f"name={name and name[1]}, code={code and code[1]}")
    shell("settings put system font_scale 1.0; settings put secure show_ime_with_hard_keyboard 0; settings put secure immersive_mode_confirmations confirmed; cmd uimode night yes")
    rotate(0)

    language("en")
    fresh()
    see("no game installed: the first screen says so", w("empty_title"))
    shot("en-00-empty")
    empty_library_controls(args.games)
    fresh()
    shell(f"am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:{PACKAGE}")
    see("Android shows the app under its name", "Oort NX alpha")
    shot("en-00-icon")
    start()
    apks = sorted(args.games.glob("*.apk"))
    for apk in apks:
        adb("install", "-r", apk, check=True)
    start()
    see("games installed meanwhile are found on return", w("detail_play"))
    touch("en")
    controller("en")
    newer("en")
    real_pad()

    language("fr")
    touch("fr")
    controller("fr")
    newer("fr")
    library_focus_after_play(args.games)
    restored_sound_focus()
    refocus_search()
    low_pad_keyboard()

    rotate(1)
    tour("fr-landscape", with_pad=True, wide=True)
    rotate(0)
    shell("cmd uimode night no")
    tour("fr-light-system", wide=False)
    shell("cmd uimode night yes")

    shell("settings put system font_scale 2.0")
    time.sleep(2)
    tour("fr-large-text", with_pad=True)
    rotate(1)
    tour("fr-large-text-landscape", wide=True)
    rotate(0)
    shell("settings put system font_scale 1.0")

    shell("settings put global animator_duration_scale 0")
    tour("fr-calm", wide=False)
    shell("settings put global animator_duration_scale 1")

    size, dens = shell("wm size"), shell("wm density")
    for name, value in (("tablet-landscape", "2560x1600"), ("tablet-portrait", "1600x2560")):
        shell(f"wm size {value}; wm density 320")
        time.sleep(4)
        tour(f"fr-{name}", with_pad=name == "tablet-landscape")
    shell("wm size 720x1280; wm density 320")
    time.sleep(4)
    tour("fr-small-phone")
    shell("wm size reset; wm density reset")
    time.sleep(4)

    # A game that goes away while its page is open.
    fresh()
    tap(w("nav_library"), exact=True)
    tap(GAMES[0])
    see("page open before the game is removed", w("game_page"))
    adb("uninstall", "org.nx2a.testphare")
    start()
    time.sleep(1)
    ok("the page of a removed game closes by itself", find(w("detail_package")) is None and find(GAMES[0]) is None)
    for apk in apks:
        adb("uninstall", apk.stem)
    start()
    see("every game removed: the app says so", w("empty_title"))
    shot("fr-99-empty")

    crashes()
    ok("every touch target is at least 48 dp", not small, str(small))
    report = {"api": api, "passed": passed, "failed": failed, "small_targets": small, "size": size, "density": dens}
    (out / "report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False))
    print(f"{len(passed)} passed, {len(failed)} failed", flush=True)
    for name in failed:
        print("  - " + name)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
