import SwiftUI
import Quartz

/// Inline Quick Look preview (QLPreviewView) hosted in SwiftUI.
///
/// We use the *inline* view rather than the shared QLPreviewPanel on purpose:
/// the panel would steal key focus and dismiss our transient menu-bar popover.
/// This renders the preview inside the panel instead, so context is preserved.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? NSURL) as URL? != url {
            nsView.previewItem = url as NSURL
        }
    }
}
