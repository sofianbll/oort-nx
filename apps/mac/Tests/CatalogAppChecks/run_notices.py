#!/usr/bin/env python3
"""Exercise actual app notice helpers/bridge without constructing SwiftUI or AppKit.

Run after swift test on macOS. Core I/O uses generated temporary data only.
The host substitutes the surrounding view model, not the methods being checked.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
import sys  # noqa: E402
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json
import probe_start  # noqa: E402  every probe that links the core starts in ProbeStart.swift
BIN = ROOT / '.build/debug'

def method(source, signature):
    # A member made internal by a split is found without its old `private `.
    start = source.index(signature) if signature in source else source.index(signature.replace('private ', '', 1))
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

with tempfile.TemporaryDirectory(prefix='catalog-notice-check-') as scratch:
    scratch = Path(scratch)
    view = ''.join(p.read_text() for p in sorted((ROOT / 'apps/mac/OortMac/Views/Shell').glob('AppShellView*.swift')))
    bridge = '\n'.join(method(view, signature) for signature in (
        '    private func finishSettingsNotice(answer:', '    private func presentLegacyNotice()'))
    host = (ROOT / 'apps/mac/Tests/CatalogAppChecks/NoticeHost.swift').read_text()
    model = (ROOT / 'apps/mac/OortMac/ViewModels/AppViewModel.swift').read_text()
    host += '\n' + method(model, 'struct SettingsNotice: Identifiable')
    host += '\nstruct LegacyNoticeHost {\n let viewModel: AppViewModel\n'
    host += ' func deliver() { presentLegacyNotice() }\n func dismiss() { finishSettingsNotice() }\n'
    host += ' func choose(_ answer: SettingsNotice.AnswerID) { finishSettingsNotice(answer: answer) }\n'
    host += bridge + '\n}\n'
    main = scratch / 'main.swift'
    main.write_text(host)
    executable = scratch / 'notices'
    command = ['xcrun', 'swiftc', '-I', str(BIN), str(main),
               str(ROOT / 'apps/mac/OortMac/Models/LogEntry.swift'),
               str(ROOT / 'apps/mac/OortMac/ViewModels/AppViewModel+Catalog.swift'),
               *probe_start.core(BIN), '-o', str(executable)]
    subprocess.run(command, cwd=ROOT, check=True)
    env = dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN))
    subprocess.run([str(executable)], env=env, check=True)
