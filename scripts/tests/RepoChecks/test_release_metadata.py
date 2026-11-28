import contextlib
import io
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

from support import ROOT

sys.path.insert(0, str(ROOT / "scripts"))
import release_metadata as metadata


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.git("init", "-q")
        self.pin = "a" * 40
        self.repo = "https://github.com/fixture/nxnative"
        self.write("VERSION", "1.2.3\n")
        self.write(metadata.VIEW_MODEL,
                   f'    static let defaultPinnedEngineCommit = "{self.pin}"\n'
                   f'    static let defaultPinnedEngineRepository = "{self.repo}"\n')

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True, text=True)

    def write(self, path, text):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_version_rejects_mismatched_tag_and_ignores_platform_history(self):
        for ref in ("refs/heads/main", "refs/tags/v1.2.3", "refs/tags/windows-v0.1.0-alpha.1"):
            metadata.check_version(self.root, ref)
        for ref in ("refs/tags/v1.2.4", "refs/tags/v1.2.3-beta.1"):
            with self.assertRaisesRegex(ValueError, "matching VERSION"):
                metadata.check_version(self.root, ref)
        for version in ("01.2.3", "1.02.3", "1.2.3\n1.2.4", " 1.2.3", "1.2"):
            with self.subTest(version=version):
                self.write("VERSION", version)
                with self.assertRaisesRegex(ValueError, "one Oort SemVer"):
                    metadata.read_version(self.root)

    def test_pin_hash_not_duplicated_outside_source_or_history(self):
        self.write("docs/history/note.md", self.pin)
        metadata.check_version(self.root, "")
        self.write("notes.md", f"Pin `{self.pin[:8]}`.")
        with self.assertRaisesRegex(ValueError, "notes.md"):
            metadata.check_version(self.root, "")

    def test_only_release_workflow_can_write_a_release(self):
        self.write("scripts/release", 'codesign --verify "$APP"\n')
        self.write(".github/workflows/release.yml", "run: gh release create --draft\n")
        check = self.write(".github/workflows/ci.yml",
                           "uses: actions/upload-artifact@v7\n"
                           "run: curl https://github.com/fixture/app/releases/download/v1/example\n")
        metadata.check_release(self.root)
        for line in ("run: gh release upload v1 example", "run: gh api repos/fixture/app/releases",
                     "uses: softprops/action-gh-release@v2", "  contents: write", "permissions: write-all"):
            with self.subTest(line=line):
                check.write_text(line + "\n")
                with self.assertRaisesRegex(ValueError, "only release.yml"):
                    metadata.check_release(self.root)
        check.unlink()
        for line in ("git push origin HEAD", "gh release create"):
            self.write("scripts/release", line + "\n")
            with self.assertRaisesRegex(ValueError, "must not publish"):
                metadata.check_release(self.root)

    def test_verifies_version_exact_pin_and_private_keys_in_packaged_plist(self):
        plist = self.write("Fixture.app/Contents/Info.plist", "")
        app = plist.parent.parent
        valid = {"CFBundleShortVersionString": "1.2.3", "NXLibraryRelease": True,
                 "NXLibraryEngineRepository": self.repo, "NXLibraryEngineCommit": self.pin}
        plist.write_bytes(plistlib.dumps(valid))
        with contextlib.redirect_stdout(io.StringIO()) as proof:
            metadata.verify_app(self.root, app, public=True)
        self.assertIn("1.2.3 / " + self.pin, proof.getvalue())
        for key, wrong in (("CFBundleShortVersionString", "1.2.4"), ("NXLibraryRelease", False),
                           ("NXLibraryEngineRepository", "https://github.com/other/nxnative"),
                           ("NXLibraryEngineCommit", "f" * 40), ("NXLibraryDevelopmentProfile", True),
                           ("ArcaneGoogleClientSecret", "synthetic")):
            with self.subTest(key=key):
                plist.write_bytes(plistlib.dumps(valid | {key: wrong}))
                with self.assertRaises(ValueError):
                    metadata.verify_app(self.root, app, public=True)

    def test_local_release_has_no_publish_argument_and_refuses_dirty_tree(self):
        script = self.write("scripts/release", (ROOT / "scripts/release").read_text())
        result = subprocess.run(["bash", str(script), "--publish"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("usage:", result.stderr)
        fake_uname = self.write("bin/uname", "#!/bin/sh\nprintf 'Darwin\\n'\n")
        fake_uname.chmod(0o755)
        env = os.environ | {"PATH": f"{fake_uname.parent}:{os.environ['PATH']}"}
        result = subprocess.run(["bash", str(script)], capture_output=True, text=True, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("working tree has changes", result.stderr)

    def test_packaging_rejects_engine_not_on_a_public_branch(self):
        self.write("scripts/release", (ROOT / "scripts/release").read_text())
        self.write("scripts/release_metadata.py", (ROOT / "scripts/release_metadata.py").read_text())
        self.write(metadata.TOOLCHAIN, '    minimumXcode: "27.2",\n')
        self.write("scripts/check_publication.py", "")
        self.write(".gitignore", "/work/\n/bin/\n")
        self.write("work/Runtime/.fixture", "")
        for name, body in {"uname": "echo Darwin", "git": """case "$*" in
  *' clone '*) mkdir checkout ;;
  *' for-each-ref '*) : ;;
  *) exec "$REAL_GIT" "$@" ;;
esac"""}.items():
            tool = self.write(f"bin/{name}", f"#!/bin/sh\n{body}\n")
            tool.chmod(0o755)
        self.git("add", ".")
        self.git("-c", "commit.gpgsign=false", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-qm", "Fixture")
        env = os.environ | {"PATH": f"{self.root / 'bin'}:{os.environ['PATH']}", "REAL_GIT": shutil.which("git")}
        result = subprocess.run(["bash", "scripts/release"], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be reachable from a public branch", result.stderr)
