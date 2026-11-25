#if os(iOS)
import UIKit

/// What the system laid over the app (Files, Photos, a share sheet). A controller cannot drive it: B closes it.
@MainActor enum OortOverlay {
    static func close() -> (() -> Void)? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        guard let top, top.presentingViewController != nil, !(top is UISearchController) else { return nil }
        return {
            // Whoever waits for the picker's answer hears the cancel.
            if let picker = top as? UIDocumentPickerViewController { picker.delegate?.documentPickerWasCancelled?(picker) }
            top.presentingViewController?.dismiss(animated: true)
        }
    }
}
#endif
