"""What can be checked about the Android project without a compiler or an SDK. None of this replaces a build."""
import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = Path(__file__).resolve().parents[2] / "android"
MAIN = ANDROID / "app/src/main"
KOTLIN = sorted((ANDROID / "app/src").rglob("*.kt"))
BASE = "io/github/sofianbll/oortnx"


def strings(path):
    return {s.get("name"): s.text for s in ET.parse(path).getroot().iter("string")}


def code_without_text(source):
    """The Kotlin source with comments, strings and character literals blanked, to count brackets."""
    source = re.sub(r'"""(?:.|\n)*?"""', '""', source)
    source = re.sub(r"/\*(?:.|\n)*?\*/", "", source)
    source = re.sub(r"//[^\n]*", "", source)
    source = re.sub(r"'(?:\\.|[^'\\])'", "''", source)
    return re.sub(r'"(?:\\.|\$\{[^}]*\}|[^"\\\n])*"', '""', source)


class AndroidProject(unittest.TestCase):
    def test_both_languages_have_the_same_strings(self):
        english, french = strings(MAIN / "res/values/strings.xml"), strings(MAIN / "res/values-fr/strings.xml")
        self.assertEqual(sorted(english), sorted(french))

    def test_format_arguments_match_between_languages(self):
        english, french = strings(MAIN / "res/values/strings.xml"), strings(MAIN / "res/values-fr/strings.xml")
        for name in english:
            self.assertEqual(sorted(re.findall(r"%\d\$[sd]", english[name])), sorted(re.findall(r"%\d\$[sd]", french[name])), name)

    def test_every_string_the_code_uses_exists(self):
        known = set(strings(MAIN / "res/values/strings.xml"))
        used = {m for f in KOTLIN for m in re.findall(r"R\.string\.(\w+)", f.read_text())}
        self.assertEqual(used - known, set())

    def test_no_string_is_left_unused(self):
        known = set(strings(MAIN / "res/values/strings.xml"))
        used = {m for f in KOTLIN for m in re.findall(r"R\.string\.(\w+)", f.read_text())}
        self.assertEqual(known - used - {"app_name"}, set(), "remove or use these")

    def test_every_resource_the_xml_names_exists(self):
        colors = set(re.findall(r'name="(\w+)"', (MAIN / "res/values/oort_colors.xml").read_text()))
        drawables = {p.stem for p in (MAIN / "res/drawable").glob("*.xml")}
        mipmaps = {p.stem for p in (MAIN / "res/mipmap-anydpi").glob("*.xml")}
        styles = set(re.findall(r'style name="([\w.]+)"', (MAIN / "res/values/themes.xml").read_text()))
        for path in MAIN.rglob("*.xml"):
            for kind, name in re.findall(r"@(color|drawable|mipmap|style|string)/([\w.]+)", path.read_text()):
                known = {"color": colors, "drawable": drawables, "mipmap": mipmaps, "style": styles,
                         "string": set(strings(MAIN / "res/values/strings.xml"))}[kind]
                self.assertIn(name, known, f"{path.name}: @{kind}/{name}")

    def test_the_launcher_asks_android_for_nothing(self):
        manifest = (MAIN / "AndroidManifest.xml").read_text()
        # The comment says what is absent; only the elements count.
        elements = re.sub(r"<!--(?:.|\n)*?-->", "", manifest)
        self.assertNotIn("uses-permission", elements)
        self.assertNotIn("INTERNET", elements)
        self.assertNotIn("QUERY_ALL_PACKAGES", elements)
        self.assertNotIn("MANAGE_EXTERNAL_STORAGE", elements)
        self.assertIn('android:allowBackup="false"', elements)

    def test_the_code_asks_for_no_network_api(self):
        for f in KOTLIN:
            self.assertNotRegex(f.read_text(), r"java\.net\.|HttpURLConnection|okhttp|android\.net\.http", f.name)

    def test_packages_follow_the_folders(self):
        for f in KOTLIN:
            declared = re.search(r"^package ([\w.]+)", f.read_text(), re.M).group(1)
            self.assertTrue(f.parent.as_posix().endswith(declared.replace(".", "/")), f"{f}: {declared}")

    def test_brackets_balance_in_every_kotlin_file(self):
        for f in KOTLIN:
            code = code_without_text(f.read_text())
            for open_, close in ("()", "{}", "[]"):
                self.assertEqual(code.count(open_), code.count(close), f"{f.name}: {open_}{close}")

    def test_the_manifest_and_the_build_agree_on_the_namespace(self):
        build = (ANDROID / "app/build.gradle.kts").read_text()
        self.assertIn('namespace = "io.github.sofianbll.oortnx"', build)
        self.assertTrue((ANDROID / "app/src/main/kotlin" / BASE / "MainActivity.kt").exists())
        self.assertIn('android:name=".MainActivity"', (MAIN / "AndroidManifest.xml").read_text())

    def test_alpha_2_build_workflow_and_readme_agree(self):
        version = "0.1.0-alpha.2"
        build = (ANDROID / "app/build.gradle.kts").read_text()
        workflow = (ANDROID.parent / ".github/workflows/android.yml").read_text()
        with self.subTest("APK metadata"):
            self.assertRegex(build, r"(?m)^\s*versionCode = 2\s*$")
            self.assertIn(f'versionName = "{version}"', build)
        with self.subTest("APK filename"):
            self.assertIn(f"APK: Oort-NX-Android-{version}-unsigned.apk", workflow)
        with self.subTest("emulator check"):
            emulator = (ANDROID / "tools/emulator_check.py").read_text()
            self.assertIn(f'ALPHA_VERSION = "{version}"', emulator)
            self.assertIn('ALPHA_VERSION_CODE = "2"', emulator)
        with self.subTest("README"):
            self.assertIn(f"`{version}`", (ANDROID / "README.md").read_text())

    def test_the_licences_in_the_app_are_the_repositorys(self):
        texts = MAIN / "assets/licences"
        self.assertEqual((texts / "oort-nx.txt").read_bytes(), (ANDROID.parent / "LICENSE").read_bytes())
        self.assertEqual((texts / "notices.txt").read_bytes(), (ANDROID / "NOTICE.md").read_bytes())
        self.assertIn("Version 2.0, January 2004", (texts / "apache-2.0.txt").read_text())
        named = set(re.findall(r'\w+\("([\w.-]+\.txt)"', (ANDROID / "app/src/main/kotlin" / BASE / "ui/Rows.kt").read_text()))
        self.assertEqual(named, {p.name for p in texts.iterdir()})

    def test_the_icon_is_the_apps_mark(self):
        svg = (ANDROID.parent / "Resources/AppIcon.icon/Assets/glyph.svg").read_text()
        icon = (MAIN / "res/drawable/ic_launcher_foreground.xml").read_text()
        self.assertEqual(len(re.findall(r"M[-\d.]+,", icon)), svg.count("<circle") + 1)
        self.assertEqual(icon.upper().count("F4CE8E"), 1)

    def test_the_sun_is_gold_in_one_place_in_the_code(self):
        hits = [f.name for f in KOTLIN if "F4CE8E" in f.read_text().upper()]
        self.assertEqual(hits, ["CloudBackdrop.kt"])


if __name__ == "__main__":
    unittest.main()
