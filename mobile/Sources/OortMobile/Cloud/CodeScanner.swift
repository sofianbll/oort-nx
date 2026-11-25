#if os(iOS)
@preconcurrency import AVFoundation
import OortCore
import SwiftUI
import UIKit

/// The camera, only while this sheet is open, and only for a code. No picture is kept.
struct CodeScannerSheet: View {
    let take: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private enum Access { case asking, yes, refused, none }
    @State private var access = Access.asking

    var body: some View {
        NavigationStack {
            Group {
                switch access {
                case .asking: Color.clear
                case .yes:
                    CodeCamera { text in take(text); dismiss() }
                        .ignoresSafeArea()
                        .overlay(alignment: .bottom) {
                            Text(Oort.text("Point at the code on your Mac's screen.")).foregroundStyle(Oort.ink)
                                .padding(SeleneTokens.Space.medium).background(Oort.night.opacity(0.85), in: .capsule).padding(SeleneTokens.Space.section)
                        }
                        .accessibilityLabel(Oort.text("Point at the code on your Mac's screen."))
                case .refused:
                    ContentUnavailableView {
                        Label(Oort.text("The camera is not allowed"), systemImage: "camera.badge.ellipsis")
                    } description: { Text(Oort.text("You can paste the code instead, or allow the camera in Settings.")) } actions: {
                        Button(Oort.text("Open Settings")) { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                    }
                case .none:
                    ContentUnavailableView(Oort.text("No camera here"), systemImage: "camera", description: Text(Oort.text("Paste the code instead.")))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Oort.page)
            .navigationTitle(Oort.text("Scan your Mac's code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(Oort.text("Close")) { dismiss() } } }
            .task {
                guard AVCaptureDevice.default(for: .video) != nil else { access = .none; return }
                access = await AVCaptureDevice.requestAccess(for: .video) ? .yes : .refused
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct CodeCamera: UIViewRepresentable {
    let found: (String) -> Void
    func makeUIView(context: Context) -> CodeCameraView { CodeCameraView(found: found) }
    func updateUIView(_ view: CodeCameraView, context: Context) {}
    static func dismantleUIView(_ view: CodeCameraView, coordinator: ()) { view.stop() }
}

private final class CodeCameraView: UIView, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private let session = AVCaptureSession()
    private let work = DispatchQueue(label: "oort.code")
    private var found: ((String) -> Void)?

    init(found: @escaping (String) -> Void) {
        self.found = found
        super.init(frame: .zero)
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = layer as! AVCaptureVideoPreviewLayer
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        let session = session
        work.async { session.startRunning() }
    }
    required init?(coder: NSCoder) { nil }

    func stop() {
        found = nil
        let session = session
        work.async { session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let text = objects.lazy.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first, let found else { return }
        self.found = nil
        found(text)
    }
}
#endif
