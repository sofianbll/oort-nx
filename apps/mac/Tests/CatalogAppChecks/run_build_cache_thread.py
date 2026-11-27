#!/usr/bin/env python3
"""Exercise the real build completion's cache-adoption expression on the UI actor."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[4]
source = (root / "apps/mac/OortMac/ViewModels/PortingModel+BuildEvents.swift").read_text()
start = source.index("            do {", source.index("if let adoptingCache, result.success"))
end = source.index("                if relocatedCache", start)
adoption = source[start + len("            do {\n"):end]
host = """
import Foundation
enum LocalBuildCache {
    static func adopt(_ source: URL, as cache: URL) throws {
        guard !Thread.isMainThread else { throw CocoaError(.fileWriteUnknown) }
    }
}
@MainActor func finish(adoptingCache: (work: URL, cache: URL)) async throws {
// ADOPTION
}
let synthetic = URL(fileURLWithPath: "/unused")
do {
    try await finish(adoptingCache: (synthetic, synthetic))
    print("Cache adoption leaves the UI actor: PASS")
} catch {
    print("FAIL: the build completion adopts its cache on the UI thread")
    exit(1)
}
"""

with tempfile.TemporaryDirectory(prefix="arcane-build-cache-thread-") as folder:
    main = Path(folder) / "main.swift"
    executable = main.with_suffix("")
    main.write_text(host.replace("// ADOPTION", adoption))
    subprocess.run(["xcrun", "swiftc", str(main), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
