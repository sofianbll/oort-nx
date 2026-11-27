#!/usr/bin/env python3
"""Evaluate actual common header bodies without a window or app stores."""
from pathlib import Path
import subprocess,tempfile,os
ROOT=Path(__file__).resolve().parents[4]
import sys  # noqa: E402
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json
BIN=ROOT/'.build/debug'
files=[ROOT/'apps/mac/OortMac/Views/Components/GameLogoArea.swift', ROOT/'apps/mac/OortMac/Views/Components/GamePrimaryActions.swift']
actual='\n'.join(p.read_text() for p in files)
host='''import SwiftUI
import NXLibraryCore
import ArcanePorting
struct HeaderCanvas { func u(_ value: CGFloat) -> CGFloat { value } }
private struct CanvasKey: EnvironmentKey { static let defaultValue = HeaderCanvas() }
extension EnvironmentValues { var seleneCanvas: HeaderCanvas { get { self[CanvasKey.self] } set { self[CanvasKey.self] = newValue } } }
extension View { func seleneFont(_ token: SeleneTokens.Text, _ weight: Font.Weight = .regular) -> some View { font(.system(size: token.rawValue, weight: weight)) } }
enum SeleneTheme { static let ink = Color.white }
enum OortShadow { case text }
extension View { func oortShadow(_ role: OortShadow) -> some View { self } }
extension View { func seleneHover(_ reached: @escaping () -> Void) -> some View { onHover { if $0 { reached() } } } }
struct CloudLibraryIndicator {}
struct CloudLibraryPill: View { let indicator: CloudLibraryIndicator; let focused: Bool; let action: () -> Void; var body: some View { Color.clear } }
struct SelenePillButton: View {
 let title: String?; var icon: MaterialIcon? = nil; var iconSize: CGFloat = 26
 var minWidth: CGFloat = 180; var height: CGFloat = 60; var horizontalPadding: CGFloat = 36
 let focused: Bool; var enabled: Bool = true; var waveDots = false; var downloadFill: Double? = nil; let action: () -> Void
 static func buildQueue(focused: Bool, action: @escaping () -> Void) -> Self {
  Self(title: "Queued", focused: focused, action: action)
 }
 var body: some View { Color.clear }
}
'''+actual+'''
@main struct Check {
 @MainActor static func main() {
  for collection in [true,false] {
   withExtendedLifetime(GameLogoArea(title: "Fixture", logo: nil, collection: collection).body) {}
  }
  for queued in [true,false] {
   withExtendedLifetime(GamePrimaryActions(primaryTitle: "Play", secondaryTitle: "Options", isFavorite: true,
    focused: 0, primaryEnabled: !queued, primaryQueued: queued, cloud: CloudLibraryIndicator(), onAction: {_ in}).body) {}
  }
  print("Actual shared game header bodies work without injected stores, for both layouts/action states.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='game-header-check-') as folder:
 folder=Path(folder);swift=folder/'check.swift';swift.write_text(host);binary=folder/'check'
 subprocess.run(['xcrun','swiftc','-parse-as-library','-I',str(BIN),str(swift),*map(str, names.objects(BIN)),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,env=dict(os.environ,PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
