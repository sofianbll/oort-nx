"""How a probe links or builds the core: always through here, so that ProbeStart.swift runs first.

ProbeStart.swift gives the core the Mac implementations of its joints (MacPlatformServices.register(), as the app
does at launch), then calls the probe's main. Without it the core runs without them: images are refused and texts
have no language, and a probe would silently test something else. scripts/check_probes.py refuses a probe that
reaches the core's objects or builds the package anywhere else.

A revision without apps/mac/OortMac/Services/MacPlatformServices.swift (before lot 3) has no joints: the probe still
starts there (its main stays renamed), with nothing to register.
"""
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json

START = Path(__file__).with_name("ProbeStart.swift")
SERVICES = "apps/mac/OortMac/Services"
REGISTRY = f"{SERVICES}/MacPlatformServices.swift"
# The probe's main is renamed; the program starts in ProbeStart.swift.
ENTRY = ["-Xfrontend", "-entry-point-function-name", "-Xfrontend", "oortProbeMain",
         "-Xlinker", "-e", "-Xlinker", "_oortProbeStart"]


def joints(tree=ROOT):
    """MacPlatformServices.swift and the file of every implementation it registers (Services/<Type>.swift)."""
    registry = Path(tree) / REGISTRY
    if not registry.is_file():
        return []
    types = re.findall(r"\b([A-Z]\w+)\(\)", registry.read_text(encoding="utf-8"))
    files = [Path(tree) / SERVICES / f"{name}.swift" for name in types]
    missing = [str(path) for path in files if not path.is_file()]
    if missing:
        raise SystemExit(f"{REGISTRY} registers types without their file: {missing}")
    return [registry, *files]


def start(tree=ROOT):
    """The flags and sources that run ProbeStart.swift before a probe compiled outside the app's module."""
    found = joints(tree)
    return [*ENTRY, str(START), *(map(str, found) if found else ["-D", "OORT_NO_JOINTS"])]


def core(folder, roles=("library", "nxnative", "core"), tree=ROOT):
    """swiftc inputs for a probe linked against the core's objects in `folder`: the start, then the objects."""
    return [*start(tree), *map(str, names.objects(folder, roles))]


def app(tree=ROOT):
    """(modules folder, products folder, swiftc inputs) for a probe linked against the whole debug app of `tree`."""
    build = Path(tree) / ".build"
    products = build / "out/Products/Debug"
    lists = list((build / f"out/Intermediates.noindex/{names.PACKAGE}.build/Debug/{names.APP}-p.build/Objects-normal")
                 .glob(f"*/{names.APP}.LinkFileList"))
    if len(lists) == 1:
        return lists[0].parent, products, [*start(tree), *shlex.split(lists[0].read_text())]
    products = build / "debug"
    objects = [str(p) for target in (names.APP, names.LIBRARY, names.NXNATIVE, names.CORE)
               for p in sorted((products / f"{target}.build").glob("*.swift.o"))]
    if not objects or not (products / f"Modules/{names.APP}.swiftmodule").exists():
        raise SystemExit("Run the debug Swift suite first.")
    return products / "Modules", products, [*start(tree), *objects]


def library(tree=ROOT):
    """(modules folder, swiftc inputs) for a probe linked against the library and the core of a debug build: the
    targets' link lists (Swift Build), the library archive, or the object files (native build system)."""
    build, products = Path(tree) / ".build", Path(tree) / ".build/debug"
    intermediates = build / f"out/Intermediates.noindex/{names.PACKAGE}.build/Debug"
    lists = [list((intermediates / f"{target}-t.build/Objects-normal").glob(f"*/{target}.LinkFileList"))
             for target in (names.LIBRARY, names.CORE)]
    archive = products / f"lib{names.LIBRARY}.a"
    if all(len(found) == 1 for found in lists):
        modules, objects = build / "out/Products/Debug", [o for found in lists for o in shlex.split(found[0].read_text())]
    elif archive.is_file():
        modules, objects = products, [str(archive)]
    else:
        modules = products / "Modules"
        objects = [str(p) for target in (names.LIBRARY, names.CORE) for p in sorted((products / f"{target}.build").glob("*.swift.o"))]
    if not objects:
        raise SystemExit("Run a debug swift build --jobs 4 first")
    return modules, [*start(tree), *objects]


def build_package(package, *, product=names.APP, jobs=4, env=None):
    """Build a staged copy of the package whose probe lives in the app's module: ProbeStart.swift joins that module
    and swift build passes the entry flags on to swiftc and the linker."""
    package = Path(package)
    command = ["swift", "build", "--package-path", str(package), "--product", product]
    (package / SERVICES / START.name).write_text(START.read_text(encoding="utf-8"), encoding="utf-8")
    for flag, value in zip(ENTRY[::2], ENTRY[1::2]):
        command += ["-Xswiftc", "-Xfrontend", "-Xswiftc", value] if flag == "-Xfrontend" else ["-Xlinker", value]
    if not joints(package):
        command += ["-Xswiftc", "-DOORT_NO_JOINTS"]
    if jobs is not None:
        command += ["--jobs", str(jobs)]
    subprocess.run(command, check=True, env=env)
    products = subprocess.check_output(command + ["--show-bin-path"], env=env, text=True).strip()
    return Path(products) / product
