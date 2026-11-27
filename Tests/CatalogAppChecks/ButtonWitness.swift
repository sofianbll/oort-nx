import AppKit
import PDFKit
import SwiftUI
@testable import NXLibrary
import NXLibraryCore

// Temporary witness (CI diagnosis): which modifier keeps a label out of ImageRenderer's PDF on this system.
struct Witness: View {
    @AccessibilityFocusState(for: .voiceOver) var focus: String?
    let variant: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch variant {
            case "button": Button("Libellé témoin") {}.buttonStyle(.plain)
            case "button-a11y-focus": Button("Libellé témoin") {}.buttonStyle(.plain).accessibilityFocused($focus, equals: "w")
            case "text-a11y-focus": Text("Libellé témoin").accessibilityFocused($focus, equals: "w")
            case "button-a11y-actions": Button("Libellé témoin") {}.buttonStyle(.plain).accessibilityActions { Button("X") {} }
            case "pill": SelenePillButton(title: "Libellé témoin", focused: false) {}
            case "row": OortRow(title: "Libellé témoin", platform: nil, preset: .navigation(label: "Ouvrir") {})
            case "row-a11y-focus": OortRow(title: "Libellé témoin", platform: nil, preset: .navigation(label: "Ouvrir") {})
                .accessibilityFocused($focus, equals: "w")
            default: Text("Libellé témoin")
            }
        }
        .padding(40).frame(width: 600, height: 200, alignment: .topLeading).background(Color.black).foregroundStyle(.white)
    }
}

@main struct ButtonWitnessProbe {
    @MainActor static func main() throws {
        assertFixtureHome()
        suppressProbeNotifications()
        SeleneFonts.register()
        let output = AppData.profile.home.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        for variant in ["text", "button", "button-a11y-focus", "text-a11y-focus", "button-a11y-actions", "pill", "row", "row-a11y-focus"] {
            let renderer = ImageRenderer(content: Witness(variant: variant).environment(\.seleneCanvas, SeleneCanvas(size: CGSize(width: 1440, height: 900))))
            let image = output.appendingPathComponent("witness-\(variant).png")
            if let png = renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]) {
                try png.write(to: image)
            }
            try saveProbeText(renderer, hidden: ImageRenderer(content: Witness(variant: variant).redacted(reason: .placeholder)), beside: image)
            let text = (try? readProbeText(output, name: "witness-\(variant)")) ?? "(pas de texte)"
            let seen = assertVisible(output, name: "witness-\(variant)", ["Libellé témoin"])
            print("témoin \(variant): PDF « \(text) » ; assertVisible \(seen.isEmpty ? "OK" : seen.joined(separator: "; "))")
        }
    }
}
