#!/usr/bin/env python3
"""Check both compatibility exits notify the real queue after the engine operation ends."""
from pathlib import Path
import re

models = Path(__file__).resolve().parents[4] / "apps/mac/OortMac/ViewModels"
fetch = (models / "SetupCheckModel.swift").read_text().split("private func fetchEngine(", 1)[1]
fetch = fetch.split("private func backToTestedEngine(", 1)[0]
assert re.search(r"isSwitchingEngine = false\s+self\.viewModel\.setup\.detectEnvironment\(\)", fetch)

setup = (models / "SetupModel.swift").read_text()
assert re.search(r"func detectEnvironment\(.*?\n.*?restoreBuildInputs\(.*?\)\s+refreshCompatibility\(\)", setup, re.S)
refresh = setup.split("func refreshCompatibility()", 1)[1].split("func resolvedDeveloperDir()", 1)[0]
invalid, checked = refresh.split("isCheckingEnvironment = true", 1)
assert re.search(r"isCheckingEnvironment = false\s+app\.porting\.scheduleNextBuild\(\)\s+return", invalid), \
    "A failed clone leaves a queued build without a wakeup."
assert checked.index("self.environmentStatus = status") < checked.index("self.app.porting.scheduleNextBuild()")
print("Build queue wakeup: invalid and checked engine paths wired")
