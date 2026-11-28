#!/usr/bin/env python3
"""Keep the profile denial on the build, retry and dialog paths."""
from pathlib import Path

sources = Path(__file__).resolve().parents[4] / "apps/mac/OortMac"
models = sources / "ViewModels"
build = (models / "PortingModel+Build.swift").read_text()
retry = (models / "AppViewModel+PendingInstall.swift").read_text()
events = (models / "PortingModel+BuildEvents.swift").read_text()
dialog = (sources / "Views/Shell/AppShellView+Overlays.swift").read_text()
assert "try self?.app.requireSaveInstallLease(for: target)" in build, \
    "The worker loses the unreadable-profile reason before reporting a held build."
assert "try requireSaveInstallLease(for: game)" in retry
assert "result.error ??" in events.split("if result.installationFailed {", 1)[1].split("} else {", 1)[0]
assert "viewModel.installFailureDetail" in dialog
print("Install profiles: denial reaches the worker, retry and dialog")
