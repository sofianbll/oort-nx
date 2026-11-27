"""The package's technical names and folders, read from architecture/names.json, the only place they are written.

Python scripts and probes import this module instead of writing a name or a module folder; scripts/generate_names.py
writes the copies that cannot read JSON (Package.swift, build_app.sh, the LikeC4 model, one Swift constant).
"""
import io
import json
import shutil
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "architecture/names.json"


class Layout:
    """The package, its modules (role -> name, kind, layer, path, tests) at one revision."""

    def __init__(self, data):
        self.package = data["package"]
        self.modules = data["modules"]
        self.tests = {role: module["tests"] for role, module in self.modules.items() if "tests" in module}

    def name(self, role):
        return self.modules[role]["name"]

    def path(self, role):
        return self.modules[role]["path"]

    def test_path(self, role):
        return self.tests[role]["path"]

    @property
    def resource_bundle(self):
        # SwiftPM names the processed resources of a target <package>_<target>.bundle.
        return f"{self.package}_{self.name('library')}.bundle"

    def roots(self):
        """Every folder of Swift sources and Swift tests, in the order of the layers."""
        return [module["path"] for module in self.modules.values()] + [test["path"] for test in self.tests.values()]

    def objects(self, folder, roles=("library", "nxnative", "core")):
        """The object files SwiftPM leaves in a build folder, to link a probe against the modules."""
        return [Path(folder) / f"{self.name(role)}.o" for role in roles]


def load(root=ROOT):
    return json.loads((Path(root) / SOURCE).read_text(encoding="utf-8"))


DATA = load()
CURRENT = Layout(DATA)
PACKAGE = CURRENT.package
MODULES = CURRENT.modules
TESTS = CURRENT.tests
CORE, LIBRARY, NXNATIVE, APP = (CURRENT.name(role) for role in ("core", "library", "nxnative", "mac"))
TEST_TARGETS = tuple(test["name"] for test in TESTS.values())
RESOURCE_BUNDLE = CURRENT.resource_bundle
path, test_path, roots, objects = CURRENT.path, CURRENT.test_path, CURRENT.roots, CURRENT.objects


def layout_at(ref, root=ROOT):
    """The layout of a Git revision: its own names.json, or the last layout before names.json existed."""
    shown = subprocess.run(["git", "-C", str(root), "show", f"{ref}:{SOURCE}"], capture_output=True, text=True)
    if shown.returncode == 0:
        return Layout(json.loads(shown.stdout))
    return Layout(DATA["former"][-1])


def _former(ref, root):
    return subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{ref}:{SOURCE}"], capture_output=True).returncode != 0


def stage(package, ref=None, root=ROOT):
    """Copy Package.swift and every module into package (from the checkout, or from ref), with an empty file in
    each test target so that the manifest resolves. Return the staged Layout."""
    package = Path(package)
    layout = CURRENT if ref is None else layout_at(ref, root)
    if ref is None:
        shutil.copyfile(Path(root) / "Package.swift", package / "Package.swift")
        for relative in (module["path"] for module in layout.modules.values()):
            shutil.copytree(Path(root) / relative, package / relative)
    else:
        # A revision from before names.json may hold other modules than the last former layout: take Sources/ whole.
        folders = ["Sources"] if _former(ref, root) else [module["path"] for module in layout.modules.values()]
        archived = subprocess.check_output(["git", "-C", str(root), "archive", ref, "Package.swift", *folders])
        with tarfile.open(fileobj=io.BytesIO(archived)) as archive:
            archive.extractall(package, filter="data")
    for test in layout.tests.values():
        folder = package / test["path"]
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "Empty.swift").touch()
    return layout
