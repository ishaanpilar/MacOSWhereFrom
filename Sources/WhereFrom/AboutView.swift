import SwiftUI
import AppKit

/// Standalone About window, opened from the ⋯ menu.
@MainActor
final class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: AboutView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "About Where From"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 3) {
                Text("Where From").font(.system(size: 22, weight: .semibold))
                Text(version).font(.caption).foregroundStyle(.secondary)
            }

            Text("See where every file came from — then triage, group, and organize your folders by source, age, and use.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().frame(width: 220)

            VStack(spacing: 4) {
                Text("Built by Ishaan Pilar").font(.callout.weight(.medium))
                Text("A small native utility for the everyday question macOS never answers cleanly: “what is this file, where did it come from, and can I let it go?” No cloud, no accounts — everything stays on your Mac.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("© 2026 Ishaan Pilar")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 360)
    }
}
