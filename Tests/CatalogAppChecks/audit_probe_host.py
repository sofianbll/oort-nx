"""Link headless probes against the Swift Build debug app without entering its main."""
from pathlib import Path
import os
import pwd
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def run_host(host, source_fixture=None, *, save_model=False, capture=None, unix_sockets=False, environment=None, resources=(),
             package_name=None, launch_services_environment=False):
    build = ROOT / ".build"
    products = build / "out/Products/Debug"
    objects = list((build / "out/Intermediates.noindex/NXLibrary.build/Debug/NXLibrary-p.build/Objects-normal").glob("*/NXLibrary.LinkFileList"))
    if len(objects) == 1:
        modules = objects[0].parent
        inputs = shlex.split(objects[0].read_text())
    else:
        products = build / "debug"
        modules = products / "Modules"
        inputs = [str(p) for target in ("NXLibrary", "NXLibraryCore", "ArcanePorting", "OortCore")
                  for p in sorted((products / f"{target}.build").glob("*.swift.o"))]
        if not inputs or not (modules / "NXLibrary.swiftmodule").exists():
            raise SystemExit("Run the debug Swift suite first.")
    with tempfile.TemporaryDirectory(prefix="audit-probe-") as scratch:
        scratch = Path(scratch).resolve()
        source, binary = scratch / "host.swift", scratch / "probe"
        (scratch / "Library/Preferences").mkdir(parents=True)
        shutil.copytree(products / "NXLibrary_NXLibraryCore.bundle", scratch / "NXLibrary_NXLibraryCore.bundle")
        if capture is not None:
            shutil.copytree(ROOT / "Resources/Brands", scratch / "Brands")
            shutil.copytree(ROOT / "Resources/Selene/Fonts", scratch / "Selene/Fonts")
            shutil.copyfile(ROOT / "Resources/Selene/palettes.json", scratch / "Selene/palettes.json")
        for resource in resources:
            shutil.copy2(ROOT / "Resources" / resource, scratch / resource)
        home_check = r'''
func assertFixtureHome() {
    let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"]!).resolvingSymlinksInPath().path
    precondition(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path == home)
    precondition(AppData.profile.home.resolvingSymlinksInPath().path == home)
}
'''
        # A headless process has no LaunchServices notification-center proxy on macOS.
        notification_stub = r'''
import AppKit
import UserNotifications
import ObjectiveC

final class ProbeNotificationCenter: NSObject {
    @objc weak var delegate: AnyObject?
}

func suppressProbeNotifications() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let center = ProbeNotificationCenter()
    let getter: @convention(block) () -> AnyObject = { center }
    let method = class_getClassMethod(UNUserNotificationCenter.self, NSSelectorFromString("currentNotificationCenter"))!
    method_setImplementation(method, imp_implementationWithBlock(getter))
}
'''
        source.write_text(host + home_check + (notification_stub if save_model else ""))
        sources = [str(source)]
        if source_fixture is not None:
            fixture = scratch / "fixture.swift"
            fixture.write_text(source_fixture)
            sources.append(str(fixture))
        env = dict(os.environ, HOME=str(scratch), CFFIXED_USER_HOME=str(scratch),
                   PACKAGE_RESOURCE_BUNDLE_PATH=str(scratch))
        # A local fake may be spoken to; the network never.
        local = '(allow network* (local unix-socket) (remote unix-socket)) ' if unix_sockets else ''
        subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                        *(["-package-name", package_name] if package_name else []),
                        "-Xfrontend", "-entry-point-function-name", "-Xfrontend", "saveAuditMain",
                        "-Xlinker", "-e", "-Xlinker", "_saveAuditMain",
                        "-I", str(modules), "-I", str(products),
                        *sources, *inputs, "-o", str(binary)], cwd=ROOT, env=env, check=True)
        sandbox = ('(version 1) (allow default) (deny network*) ' + local +
                   '(deny file-read-data file-write* (subpath (param "REAL_HOME")) (subpath "/Volumes")) '
                   '(deny file-write* (subpath "/Applications"))')
        real_home = Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()
        try:
            if launch_services_environment:
                # LaunchServices strips the environment of a launch requested from seatbelt.
                # Only the isolated, windowless Play fixture exercises that production capability.
                fixture = Path((environment or {}).get("OORT_PLAY_FIXTURE_DIR", "")).resolve()
                if fixture.parent != Path("/private/tmp") or not fixture.name.startswith("oort-native-play-"):
                    raise ValueError("Expected a disposable native Play fixture")
                command = [str(binary)]
                env = {key: env[key] for key in ("HOME", "CFFIXED_USER_HOME", "PACKAGE_RESOURCE_BUNDLE_PATH")}
                env.update(PATH="/usr/bin:/bin:/usr/sbin:/sbin", OORT_HEADLESS_INPUT="1")
            else:
                command = ["sandbox-exec", "-D", f"REAL_HOME={real_home}", "-p", sandbox, str(binary)]
            subprocess.run(command, cwd=ROOT, env=dict(env, **(environment or {})), check=True)
        finally:
            if capture is not None and (scratch / "captures").is_dir():
                shutil.copytree(scratch / "captures", capture, dirs_exist_ok=True)
