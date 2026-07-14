import SwiftUI
import UniformTypeIdentifiers

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()

private func fmtSize(_ bytes: Int64) -> String { byteFormatter.string(fromByteCount: bytes) }

private func fmtAge(_ date: Date?) -> String {
    guard let date else { return "—" }
    let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    switch days {
    case ..<0: return "just now"
    case 0: return "today"
    case 1: return "yesterday"
    case ..<30: return "\(days)d ago"
    case ..<365: return "\(days / 30)mo ago"
    default: return "\(days / 365)y ago"
    }
}

struct ContentView: View {
    @EnvironmentObject var model: DownloadsModel
    @State private var sortOrder = [KeyPathComparator(\DownloadItem.addedSortKey, order: .reverse)]
    @State private var confirmTrashShown = false
    @State private var confirmTrashSelected = false
    @State private var confirmOrganize = false
    @State private var organizeScheme: OrganizeScheme = .source
    @State private var previewURL: URL?

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
            detail
                .frame(minWidth: 500)
        }
        .frame(minWidth: 760, minHeight: 480)
        .onChange(of: model.recursive) { _, _ in model.scan() }
    }

    // MARK: Sidebar

    private var sectionTitle: String {
        if model.appsMode { return "Last used" }
        switch model.groupMode {
        case .source: return "Sources"
        case .type: return "File types"
        case .date: return "When added"
        case .cleanup: return "Reclaimable"
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
                    Text("Where From").font(.headline)
                    Spacer()
                    Button { model.scan() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless).help("Rescan").disabled(model.isScanning)

                    Menu {
                        Menu("Scan Location") {
                            ForEach(DownloadsModel.presetLocations) { preset in
                                Button {
                                    model.open(folder: preset.url)
                                } label: { Label(preset.name, systemImage: preset.symbol) }
                            }
                            Divider()
                            Button {
                                model.scanApplications()
                            } label: { Label("Applications (by last use)", systemImage: "app.dashed") }
                        }
                        Button("Choose Folder…") { model.chooseFolder() }
                        Toggle("Scan subfolders", isOn: $model.recursive)
                        Toggle("Show reclaimable in menu bar", isOn: $model.showBadge)
                        Divider()
                        Button("About Where From") { AboutWindowController.shared.show() }
                        Button("Quit Where From") { NSApp.terminate(nil) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.borderless).menuIndicator(.hidden).fixedSize().help("Options")
                }
                Button { model.chooseFolder() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.appsMode ? "app.dashed" : "folder")
                        Text(model.appsMode ? "Applications" : model.folder.lastPathComponent)
                            .lineLimit(1).truncationMode(.middle)
                        if !model.appsMode && model.recursive {
                            Image(systemName: "arrow.turn.down.right").font(.caption2)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help(model.appsMode ? "Installed applications" : model.folder.path)

                if model.appsMode {
                    Label("Grouped by last use", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("", selection: $model.groupMode) {
                        ForEach(GroupMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }
            .padding(10)
            Divider()

            List(selection: $model.selectedBucketKey) {
                bucketRow(label: "All", systemImage: "tray.full",
                          count: model.totalItemsForGroup, size: model.totalSizeForGroup)
                    .tag(String?.none)
                Section(sectionTitle) {
                    ForEach(model.buckets) { bucket in
                        bucketRow(label: bucket.label, systemImage: bucket.symbol,
                                  count: bucket.count, size: bucket.size)
                            .tag(Optional(bucket.key))
                            .contextMenu {
                                Button("Move all \(bucket.count) to Trash…", role: .destructive) {
                                    model.selectedBucketKey = bucket.key
                                    confirmTrashShown = true
                                }
                            }
                    }
                    if model.buckets.isEmpty {
                        Text(model.groupMode == .cleanup ? "Nothing to reclaim 🎉" : "No files")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func bucketRow(label: String, systemImage: String, count: Int, size: Int64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).lineLimit(1)
                Text(fmtSize(size)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            table
            Divider()
            actionBar
        }
        .overlay {
            if let previewURL {
                previewOverlay(previewURL)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: previewURL)
    }

    private func previewOverlay(_ url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            QuickLookPreview(url: url)
                .padding(14)
            VStack(alignment: .trailing, spacing: 2) {
                Button { previewURL = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Close (Esc or Space)")
                Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 200, alignment: .trailing)
            }
            .padding(10)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter", text: $model.searchText).textFieldStyle(.plain).frame(maxWidth: 150)
            }
            Toggle("Never opened", isOn: $model.onlyNeverOpened).toggleStyle(.checkbox)
            HStack(spacing: 4) {
                Text("Older than")
                Stepper(value: $model.olderThanDays, in: 0...3650, step: 7) {
                    Text(model.olderThanDays == 0 ? "off" : "\(model.olderThanDays)d")
                        .monospacedDigit().frame(minWidth: 34, alignment: .leading)
                }
            }
            Spacer()
            if model.isScanning {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("\(model.scanProgress)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var table: some View {
        Table(model.filteredItems.sorted(using: sortOrder),
              selection: $model.selection,
              sortOrder: $sortOrder) {
            TableColumn("Name") { item in
                HStack(spacing: 6) {
                    Image(systemName: item.category.symbol).foregroundStyle(.secondary)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 150, ideal: 230)

            // Source (files) or Version (apps) — swapped, not sortable.
            TableColumn(model.appsMode ? "Version" : "Source") { item in
                if model.appsMode {
                    Text(item.version ?? "—").foregroundStyle(.secondary).monospacedDigit()
                } else if let d = item.sourceDomain {
                    Text(d).foregroundStyle(.primary).help(item.originURL ?? "")
                } else {
                    Text("unknown").foregroundStyle(.tertiary).italic()
                }
            }
            .width(min: 90, ideal: 130)

            TableColumn(model.appsMode ? "Bundle ID" : "Kind", value: \.category.rawValue) { item in
                Text(model.appsMode ? (item.bundleID ?? "—") : item.category.rawValue)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 70, ideal: model.appsMode ? 150 : 90)

            TableColumn(model.appsMode ? "Installed" : "Added", value: \.addedSortKey) { item in
                Text(fmtAge(item.dateAdded)).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 66, ideal: 84)

            TableColumn("Last opened", value: \.openedSortKey) { item in
                let unused = model.appsMode && UsageBucket.of(item.lastOpened).isUnused
                Text(item.neverOpened ? "never" : fmtAge(item.lastOpened))
                    .foregroundStyle(item.neverOpened || unused ? .orange : .secondary)
                    .monospacedDigit()
            }
            .width(min: 78, ideal: 96)

            TableColumn("Size", value: \.size) { item in
                Text(fmtSize(item.size)).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 58, ideal: 76)
        }
        .contextMenu(forSelectionType: DownloadItem.ID.self) { ids in
            let targets = model.items(for: ids)
            let hasOrigin = targets.contains { $0.originURL != nil }
            Button("Quick Look") { previewURL = targets.first?.url }.disabled(targets.isEmpty)
            Button("Open File") { model.openFiles(targets.map(\.url)) }
            Button("Reveal in Finder") { revealItems(ids) }
            Divider()
            Button("Open Source URL") { model.openSources(for: targets) }.disabled(!hasOrigin)
            Button("Copy Source URL") { model.copySources(for: targets) }.disabled(!hasOrigin)
            Divider()
            Button("Move to Trash", role: .destructive) {
                if !ids.isEmpty { model.selection = ids }
                confirmTrashSelected = true
            }
        } primaryAction: { ids in
            revealItems(ids)
        }
        .onKeyPress(.space) {
            if previewURL != nil { previewURL = nil; return .handled }
            if let id = model.selection.first,
               let url = model.items.first(where: { $0.id == id })?.url {
                previewURL = url; return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if previewURL != nil { previewURL = nil; return .handled }
            return .ignored
        }
        .confirmationDialog(trashSelectedPrompt, isPresented: $confirmTrashSelected, titleVisibility: .visible) {
            Button("Move \(model.selection.count) to Trash", role: .destructive) {
                model.moveToTrash(model.selectedItems().map(\.url))
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text("\(model.filteredItems.count) shown · \(fmtSize(model.filteredTotalSize))")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()

            if model.canUndoOrganize {
                Button { model.undoOrganize() } label: { Label("Undo Organize", systemImage: "arrow.uturn.backward") }
            }

            Menu {
                ForEach(OrganizeScheme.allCases) { scheme in
                    Button(scheme.rawValue) { organizeScheme = scheme; confirmOrganize = true }
                }
            } label: {
                Label("Organize", systemImage: "folder.badge.gearshape")
            }
            .menuStyle(.button)
            .fixedSize()
            .disabled(organizeTargets.isEmpty || model.appsMode)
            .help(model.appsMode ? "Not available for applications" : "Move files into subfolders")
            .confirmationDialog(organizePrompt, isPresented: $confirmOrganize, titleVisibility: .visible) {
                Button("Move into subfolders") { model.organize(organizeTargets, scheme: organizeScheme) }
                Button("Cancel", role: .cancel) {}
            }

            Button {
                confirmTrashSelected = true
            } label: { Label("Trash (\(model.selection.count))", systemImage: "trash") }
                .disabled(model.selection.isEmpty)

            Button(role: .destructive) {
                confirmTrashShown = true
            } label: { Label("Trash All Shown", systemImage: "trash.fill") }
                .disabled(model.filteredItems.isEmpty || model.appsMode)
                .help(model.appsMode ? "Disabled for apps — select apps individually" : "")
                .confirmationDialog(trashShownPrompt, isPresented: $confirmTrashShown, titleVisibility: .visible) {
                    Button("Move \(model.filteredItems.count) to Trash", role: .destructive) {
                        model.moveToTrash(model.filteredItems.map(\.url))
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: Helpers

    private var organizeTargets: [DownloadItem] {
        model.selection.isEmpty ? model.filteredItems : model.selectedItems()
    }

    private var organizePrompt: String {
        let p = model.organizePreview(organizeTargets, scheme: organizeScheme)
        let scope = model.selection.isEmpty ? "shown" : "selected"
        return "Move \(p.files) \(scope) file(s) into \(p.folders) subfolder(s) inside “\(model.folder.lastPathComponent)”, grouped \(organizeScheme.rawValue.lowercased()). You can undo this."
    }

    private var trashShownPrompt: String {
        "Move \(model.filteredItems.count) files (\(fmtSize(model.filteredTotalSize))) to the Trash? You can restore them from the Trash."
    }
    private var trashSelectedPrompt: String {
        let sel = model.selectedItems()
        let size = sel.reduce(0) { $0 + $1.size }
        if model.appsMode {
            let running = sel.filter { model.isRunning($0) }.map(\.name)
            var msg = "Move \(sel.count) app(s) (\(fmtSize(size))) to the Trash? This removes the app bundle only — leftover support files stay (full uninstall is on the roadmap). Recoverable from the Trash."
            if !running.isEmpty {
                msg += "\n\n⚠️ Currently running: \(running.joined(separator: ", ")). Quit before removing."
            }
            return msg
        }
        return "Move \(sel.count) selected file(s) (\(fmtSize(size))) to the Trash?"
    }

    private func revealItems(_ ids: Set<DownloadItem.ID>) {
        let urls = model.items.filter { ids.contains($0.id) }.map(\.url)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}
