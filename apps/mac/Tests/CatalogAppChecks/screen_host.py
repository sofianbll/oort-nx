"""The cloud screens' host (run_cloud_screens.HOST) for a probe on the shared Debug app (audit_probe_host.run_host).

Same scenario code as a standalone probe, without copying the app: `@testable` imports reach its internals, the
captures, font and icon live in the fixture home (run_host copies them there and the captures back), and the app's
probe hooks (`oortProbe…`, Debug only) replace the source patches. No command-line argument reaches the host.
"""
import os
import re

from run_cloud_screens import HOST, ROOT

ICON = "design/Icons/AppIcon-Light.png"


def package_name():
    """The Debug build's package name: `package` declarations, such as CloudDriveScope, need it."""
    return re.search(r'"SWIFT_PACKAGE_NAME"\s*:\s*"([^"]+)"', (ROOT / ".build/manifest.pif").read_text())[1]


def header():
    """HOST up to its scenario, for run_host(..., save_model=True, capture=..., resources=(ICON,))."""
    head = HOST.split("        // SCENARIO")[0]
    for old, new in (
            ("import NxnativeAdapter\n", "@testable import NxnativeAdapter\n@testable import OortMac\n"),
            ("let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)",
             'let output = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("captures", isDirectory: true)\n'
             "        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)"),
            ("URL(fileURLWithPath: CommandLine.arguments[2])",
             'URL(fileURLWithPath: NSHomeDirectory() + "/Selene/Fonts/MaterialIcons-Regular.ttf")'),
            ("NSImage(contentsOfFile: CommandLine.arguments[3])",
             'NSImage(contentsOfFile: NSHomeDirectory() + "/AppIcon-Light.png")'),
            ("        let data = AppData.supportRoot\n",
             "        let data = AppData.supportRoot\n        suppressProbeNotifications()\n")):
        if head.count(old) != 1:
            raise ValueError(f"cloud screens host changed: {old!r}")
        head = head.replace(old, new)
    return head


def render(start="    @MainActor static func render<V: View>"):
    """HOST from one of its render functions to the end of its type."""
    return HOST[HOST.index(start):]


def rclone():
    """The pinned rclone CI installs (OORT_PROBE_RCLONE), copied into the fixture home: the sandbox denies the real home,
    where the runner keeps it. The host reads the variable relative to its home. Without it, the probe finds rclone."""
    pinned = os.environ.get("OORT_PROBE_RCLONE")
    return ((pinned,), {"OORT_PROBE_RCLONE": "rclone"}) if pinned else ((), {})
