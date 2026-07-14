import AppKit
import SwiftUI
import Combine

/// Menu-bar-only app: a status item that toggles a popover holding the
/// Downloads-triage panel. No Dock icon (accessory activation policy).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = DownloadsModel()
    private var pendingFolder: URL?   // a folder requested before the UI was ready
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Provide the Finder right-click Service ("Open in Where From").
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.down.circle",
                                   accessibilityDescription: "Where From")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Reflect reclaimable space in the menu bar. Updates only when the model
        // publishes new values (i.e. after a user-triggered scan) — no polling.
        model.$reclaimableBytes.combineLatest(model.$showBadge)
            .receive(on: RunLoop.main)
            .sink { [weak self] bytes, show in self?.updateBadge(bytes: bytes, show: show) }
            .store(in: &cancellables)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 780, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(model)
        )

        model.scan()

        // A folder may have been requested (Service / open event) before the
        // status item existed — honor it now that the UI is ready.
        if let pending = pendingFolder {
            pendingFolder = nil
            present(folder: pending)
        }
    }

    private static let badgeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useMB, .useGB]
        return f
    }()

    private func updateBadge(bytes: Int64, show: Bool) {
        guard let button = statusItem?.button else { return }
        button.title = (show && bytes > 0) ? " " + Self.badgeFormatter.string(fromByteCount: bytes) : ""
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Auto-refresh on open only for cheap (non-recursive) scans; a deep
            // scan stays put until you hit refresh, so opening is always instant.
            if !model.recursive { model.scan() }
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Retarget the panel to a folder and reveal it. If the UI isn't ready yet
    /// (cold launch via Service / open event), stash it until it is.
    private func present(folder url: URL) {
        guard statusItem != nil else { pendingFolder = url; return }
        model.open(folder: url)
        showPopover()
    }

    private static func firstFolder(in urls: [URL]) -> URL? {
        urls.first { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            ?? urls.first
    }

    // MARK: - Finder Service handler

    /// Invoked from Finder's contextual menu (NSServices → "Open in Where From").
    /// Signature must match `NSMessage` = "openInWhereFrom" as
    /// `openInWhereFrom:userData:error:`.
    @objc func openInWhereFrom(_ pboard: NSPasteboard,
                               userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        guard let folder = Self.firstFolder(in: urls) else { return }
        present(folder: folder)
    }

    // MARK: - `open -a WhereFrom <folder>` / drag-onto-app

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let folder = Self.firstFolder(in: urls) else { return }
        present(folder: folder)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
