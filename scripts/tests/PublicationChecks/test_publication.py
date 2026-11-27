import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[3] / "scripts/check_publication.py"


class PublicationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="NXPublication-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "engines/nxnative").mkdir(parents=True)  # where runtime.lock lives

    def track(self, name, content):
        file = self.root / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)
        subprocess.run(["git", "add", "--", name], cwd=self.root, check=True)

    def scan(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args], cwd=self.root,
                              capture_output=True, text=True)

    def test_source_referencing_a_game_file_is_allowed(self):
        self.track("Sources/Example.swift", 'let name = "Game.NSP"\n')
        self.assertEqual(self.scan().returncode, 0)

    def test_game_and_private_output_files_are_rejected_by_path(self):
        for name in ["Games/Game.NSP", "reports/private.md", "docs/audits/local.md",
                     "docs/superpowers/plans/plan.md", "docs/upstream-issues/note.md",
                     "design/Selene/Wallpapers/theme/one.jpg"]:
            with self.subTest(name=name):
                self.track(name, "synthetic")
                result = self.scan()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stdout)

    def test_key_material_is_rejected_without_echoing_its_value(self):
        value = "01" * 32
        self.track("notes.txt", "header_key = " + value)
        result = self.scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("notes.txt", result.stdout)
        self.assertNotIn(value, result.stdout + result.stderr)

    def test_licence_keeps_its_reviewed_digest(self):
        text = "MIT License\n\nCopyright (c) 2026 fixture\n"
        self.track("LICENSE", text)
        self.track("scripts/bundle-licences.json",
                   json.dumps({"LICENSE": hashlib.sha256(text.encode()).hexdigest()}))
        self.assertEqual(self.scan().returncode, 0)
        self.track("LICENSE", text.replace("fixture", "someone else"))
        result = self.scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LICENSE differs from its reviewed digest", result.stdout)

    def test_licence_digest_cannot_leave_the_manifest(self):
        self.track("LICENSE", "MIT License\n")
        self.track("scripts/bundle-licences.json", json.dumps({"NOTICE": "0" * 64}))
        result = self.scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LICENSE has no reviewed digest", result.stdout)

    def test_untracked_personal_files_are_not_read(self):
        (self.root / "prod.keys").write_text("header_key = " + "01" * 32)
        self.track("README.md", "Source code only.")
        self.assertEqual(self.scan().returncode, 0)

    def test_nintendo_exception_pins_paths_and_bytes_even_if_manifest_is_changed(self):
        project = SCRIPT.parent.parent
        name = "Brands/Platforms/Marks/Nintendo Switch 2.svg"
        original = (project / "design" / name).read_text()
        entry = json.loads((SCRIPT.parent / "bundle-licences.json").read_text())[name]
        self.track("design/" + name, original)
        self.track("scripts/bundle-licences.json", json.dumps({name: entry}))
        self.assertEqual(self.scan().returncode, 0)
        modified = original + "\n"
        self.track("design/" + name, modified)
        self.assertIn("Unreviewed or changed brand resource", self.scan().stdout)
        entry["sha256"] = hashlib.sha256(modified.encode()).hexdigest()
        self.track("scripts/bundle-licences.json", json.dumps({name: entry}))
        self.assertNotEqual(self.scan().returncode, 0)

    def test_runtime_must_match_the_exact_lock(self):
        lock = {"python": {"version": "3.14.6"}, "wheels": [], "brew": []}
        data = json.dumps(lock).encode()
        (self.root / "engines/nxnative/runtime.lock").write_bytes(data)
        runtime = self.root / "runtime"
        runtime.mkdir()
        for path in ["python/bin/python3", "bin/zstd", "bin/glslangValidator"]:
            file = runtime / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("fixture")
            file.chmod(0o755)
        (runtime / "licenses").mkdir()
        manifest = {"python": "3.14.6", "lock": hashlib.sha256(data).hexdigest()}
        (runtime / "versions.json").write_text(json.dumps(manifest))
        self.assertEqual(self.scan("--runtime", str(runtime)).returncode, 0)
        (self.root / "engines/nxnative/runtime.lock").write_bytes(data + b"\n")
        result = self.scan("--runtime", str(runtime))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runtime", result.stdout.lower())

    def test_runtime_must_carry_gpl_sources(self):
        lock = {"python": {"version": "3.14.6"}, "wheels": [], "brew": [],
                "sources": [{"name": "zbic", "file": "zbic-1.0.1.post1.tar.gz"}]}
        data = json.dumps(lock).encode()
        (self.root / "engines/nxnative/runtime.lock").write_bytes(data)
        runtime = self.root / "runtime"
        runtime.mkdir()
        for path in ["python/bin/python3", "bin/zstd", "bin/glslangValidator"]:
            file = runtime / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("fixture")
            file.chmod(0o755)
        (runtime / "licenses").mkdir()
        (runtime / "versions.json").write_text(json.dumps({"python": "3.14.6", "lock": hashlib.sha256(data).hexdigest()}))
        result = self.scan("--runtime", str(runtime))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source", result.stdout.lower())
        (runtime / "sources").mkdir()
        (runtime / "sources" / "zbic-1.0.1.post1.tar.gz").write_bytes(b"fixture")
        self.assertEqual(self.scan("--runtime", str(runtime)).returncode, 0)

    def test_release_app_requires_every_reviewed_text_and_source(self):
        app = self.root / "fixture.app"
        resources = app / "Contents/Resources"
        runtime = resources / "Runtime"
        lock = b'{"python":{"version":"3.14.6"},"wheels":[],"brew":[]}'
        (self.root / "engines/nxnative/runtime.lock").write_bytes(lock)
        for path in [runtime / name for name in ["python/bin/python3", "bin/zstd", "bin/glslangValidator"]]:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
            path.chmod(0o755)
        (runtime / "versions.json").write_text(json.dumps(
            {"python": "3.14.6", "lock": hashlib.sha256(lock).hexdigest()}))
        contents = {"NOTICE": b"main notice", "ThirdPartyLicenses/rclone-LICENSES.txt": b"rclone licence",
                    "Brands/Platforms/disc-3.svg": b"reviewed symbol",
                    "Brands/Platforms/NOTICE.txt": b"symbol provenance",
                    "Runtime/licenses/python.txt": b"Python licence",
                    "Runtime/sources/zbic.tar.gz": b"source archive"}
        manifest = {name: hashlib.sha256(data).hexdigest() for name, data in contents.items()}
        manifest.pop("NOTICE")
        (self.root / "NOTICE").write_bytes(contents["NOTICE"])
        (self.root / "scripts").mkdir()
        (self.root / "scripts/bundle-licences.json").write_text(json.dumps(manifest))
        for name, data in contents.items():
            path = resources / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.assertEqual(self.scan("--app", str(app)).returncode, 0)
        unreviewed = resources / "Brands/Platforms/extra.svg"
        unreviewed.write_text("unreviewed symbol")
        result = self.scan("--app", str(app))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unreviewed brand resource: Brands/Platforms/extra.svg", result.stdout)
        unreviewed.unlink()
        for relative in ("Contents/Helpers/rclone", "Contents/Resources/rclone-v1-osx-arm64.zip",
                         "Contents/MacOS/RCLONE"):
            with self.subTest(relative=relative):
                forbidden = app / relative
                forbidden.parent.mkdir(parents=True, exist_ok=True)
                forbidden.symlink_to("missing")
                result = self.scan("--app", str(app))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("must not contain rclone", result.stdout)
                forbidden.unlink()
        for name, data in contents.items():
            with self.subTest(name=name):
                path = resources / name
                path.unlink()
                result = self.scan("--app", str(app))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Missing bundle licence or source: " + name, result.stdout)
                path.write_bytes(b"")
                result = self.scan("--app", str(app))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Changed bundle licence or source: " + name, result.stdout)
                path.write_bytes(data)
        shutil.rmtree(runtime)
        self.assertNotEqual(self.scan("--app", str(app)).returncode, 0)
        self.assertEqual(self.scan("--app", str(app), "--without-runtime").returncode, 0)
        (resources / "NOTICE").unlink()
        self.assertNotEqual(self.scan("--app", str(app), "--without-runtime").returncode, 0)


if __name__ == "__main__":
    unittest.main()
