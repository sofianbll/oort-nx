#if DEBUG
import AppKit
import Combine
import CoreText
import SwiftUI
import OortLibrary

/// Types into real fields with controller actions only, in a window that is never shown.
enum OortKeyboardProbe {
    private final class Draft: ObservableObject {
        @Published var name = ""
        @Published var notes = ""
        var submits = 0
    }

    /// Nothing may ever order it in.
    private final class HiddenWindow: NSWindow {
        override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {}
        override func orderFrontRegardless() {}
        override func makeKeyAndOrderFront(_ sender: Any?) {}
    }

    private struct Fields: View {
        @ObservedObject var draft: Draft
        var body: some View {
            ZStack {
                OortGalleryWallpaper()
                SeleneTheme.scrim45
                VStack {
                    TextField("Name", text: $draft.name).onSubmit { draft.submits += 1 }
                    TextEditor(text: $draft.notes).frame(height: 60)
                    Spacer()
                }
                .frame(width: 500).padding(.top, SeleneTokens.Space.group)
                SeleneHintsBar(left: [HintItem(.b, "Back")]).frame(maxHeight: .infinity, alignment: .bottom)
                    .environment(\.seleneHintsCovered, true)
                OortKeyboardLayer()
            }
        }
    }

    @MainActor static func run(to output: URL) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let font = URL(fileURLWithPath: "design/Selene/Fonts/MaterialIcons-Regular.ttf")
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let draft = Draft()
        let size = CGSize(width: 1440, height: 810)
        let presentation = OortKeyboardPresentation.shared
        let controller = CurrentValueSubject<Bool, Never>(true)
        presentation.watchHand(controller)

        for (language, region) in [(AppLanguage.french, "FR"), (.german, "DE"), (.english, "US")] {
            let locale = AppLocale(language: language, region: region)
            L10n.setContext(locale)
            draft.name = ""; draft.notes = ""; draft.submits = 0
            let host = NSHostingView(rootView: Fields(draft: draft)
                .frame(width: size.width, height: size.height)
                .environment(\.seleneCanvas, SeleneCanvas(size: size))
                .environment(\.nxAppLocale, locale)
                .environment(\.seleneReduceMotion, true)
                .environment(\.colorScheme, .dark))
            host.frame = CGRect(origin: .zero, size: size)
            let window = HiddenWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.alphaValue = 0
            func settle() {
                for _ in 0..<8 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)); host.layoutSubtreeIfNeeded() }
            }
            func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
            func focus(_ pick: (NSView) -> Bool) {
                window.makeFirstResponder(all(host).first(where: pick))
                settle()
            }
            func capture(_ name: String) throws {
                settle()
                precondition(!window.isVisible, "\(name) showed the window")
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("clavier-\(language.rawValue)-\(name).png"))
            }
            settle()
            presentation.follow(window)
            let isName: (NSView) -> Bool = { $0 is NSTextField && !($0 is NSSecureTextField) && ($0 as! NSTextField).isEditable }

            controller.send(false)
            focus(isName)
            precondition(!presentation.isOpen, "A mouse or a keyboard needs no keys")
            guard let nameEditor = window.firstResponder as? NSTextView, nameEditor.isFieldEditor else {
                preconditionFailure("The fixture must have a focused single-line editor")
            }
            controller.send(true)
            settle()
            let opened = window.firstResponder === nameEditor && presentation.isOpen && !presentation.isSecret
            if !presentation.isOpen {
                // Establish the reverse case independently when opening without refocus is broken.
                window.makeFirstResponder(nil); settle()
                focus(isName)
            }
            let sameEditor = window.firstResponder
            precondition(presentation.isOpen, "The reverse case begins with virtual keys open")
            controller.send(false)
            settle()
            let closed = window.firstResponder === sameEditor && !presentation.isOpen
            print("Single-line field: keys open without refocus=\(opened), close without refocus=\(closed)")
            guard opened && closed else { exit(1) }
            controller.send(true)
            settle()
            for action in [GamepadAction.confirm, .navigateRight, .confirm, .contextAction, .rightStickPress, .confirm] {
                precondition(presentation.handle(action))
            }
            settle()
            precondition(draft.name == "qw W", "Typed \(draft.name)")
            precondition(presentation.text == "qw W")
            _ = presentation.handle(.secondaryAction)
            _ = presentation.handle(.tabNext)
            settle()
            precondition(draft.name == "qw " && presentation.keyboard.page == .symbols)
            try capture("symboles")
            _ = presentation.handle(.tabNext)
            _ = presentation.handle(.confirm)
            try capture("accents")
            precondition(presentation.handle(.menu))
            settle()
            precondition(draft.submits == 1 && !presentation.isOpen, "Done submits once and stays closed")
            precondition(!presentation.handle(.navigateDown), "The screen has its buttons back")

            // A secret is never put in a window here: macOS shows its own panel for one, which orders the window in.
            precondition(OortKeyboardPresentation.isSecret(NSSecureTextField()) && !OortKeyboardPresentation.isSecret(NSTextField()))
            window.makeFirstResponder(nil); settle()
            focus(isName)
            precondition(presentation.isOpen, "Coming back to the field opens the keys again")
            precondition(presentation.handle(.cancel))
            settle()
            precondition(!presentation.isOpen && draft.submits == 1 && !(window.firstResponder is NSTextView), "B leaves without submitting")

            controller.send(false)
            focus { ($0 as? NSTextView)?.isFieldEditor == false }
            let notesEditor = window.firstResponder
            precondition(!presentation.isOpen)
            controller.send(true)
            settle()
            precondition(window.firstResponder === notesEditor && presentation.isOpen,
                         "Picking up the controller opens keys without refocusing the multiline field")
            controller.send(false)
            settle()
            precondition(window.firstResponder === notesEditor && !presentation.isOpen,
                         "Picking up the keyboard closes keys without refocusing the multiline field")
            controller.send(true)
            settle()
            _ = presentation.handle(.confirm)
            _ = presentation.handle(.menu)
            settle()
            precondition(draft.notes == "q" && !presentation.isOpen, "Done never adds a line to a longer text")

            focus(isName)
            presentation.ownKeys = 1
            window.makeFirstResponder(nil); settle()
            focus(isName)
            precondition(!presentation.isOpen, "A screen with its own keys keeps them")
            presentation.ownKeys = 0
            window.makeFirstResponder(nil)
            settle()
            window.contentView = nil
        }
        print("The on-screen keyboard typed into a field and a text with a controller, in three languages.")
    }
}
#endif
