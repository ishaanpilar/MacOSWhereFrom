import Foundation
import SwiftUI
import CryptoKit

/// One file (or folder) with its surfaced provenance and derived category.
struct DownloadItem: Identifiable, Hashable {
    let id: URL
    var url: URL { id }
    let name: String
    let sourceURLs: [String]
    let sourceDomain: String?      // nil => unknown origin
    let dateAdded: Date?
    let lastOpened: Date?
    let size: Int64
    let isDirectory: Bool
    let ext: String
    let category: FileCategory
    var version: String? = nil     // apps only
    var bundleID: String? = nil    // apps only
    var isApp: Bool = false

    var originURL: String? { sourceURLs.first }
    var neverOpened: Bool { lastOpened == nil }

    /// Non-optional keys so SwiftUI's Table can sort by these columns.
    var addedSortKey: Date { dateAdded ?? .distantPast }
    var openedSortKey: Date { lastOpened ?? .distantPast }
    var domainSortKey: String { sourceDomain ?? "\u{10FFFF}" } // unknowns sort last

    var ageInDays: Int? {
        guard let dateAdded else { return nil }
        return Calendar.current.dateComponents([.day], from: dateAdded, to: Date()).day
    }
}

/// How the sidebar groups the current items.
enum GroupMode: String, CaseIterable, Identifiable {
    case source = "Source"
    case type = "Type"
    case date = "Date"
    case cleanup = "Cleanup"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .source: return "globe"
        case .type: return "square.grid.2x2"
        case .date: return "calendar"
        case .cleanup: return "sparkles"
        }
    }
}

/// Smart cleanup categories (the CCleaner-style triage).
enum CleanupCategory: String, CaseIterable, Identifiable {
    case incomplete = "Incomplete downloads"
    case duplicates = "Duplicates"
    case installers = "Old installers"
    case bigOld = "Big & never opened"
    var id: String { rawValue }
    var order: Int { Self.allCases.firstIndex(of: self) ?? 9 }
    var symbol: String {
        switch self {
        case .incomplete: return "exclamationmark.arrow.circlepath"
        case .duplicates: return "doc.on.doc"
        case .installers: return "shippingbox"
        case .bigOld: return "tray.full"
        }
    }
}

/// How the organizer groups files into subfolders.
enum OrganizeScheme: String, CaseIterable, Identifiable {
    case source = "By source"
    case type = "By type"
    case month = "By month"
    var id: String { rawValue }
}

/// A single sidebar group with aggregate counts.
struct Bucket: Identifiable, Hashable {
    let key: String
    let label: String
    let symbol: String
    let count: Int
    let size: Int64
    var id: String { key }
}

@MainActor
final class DownloadsModel: ObservableObject {
    @Published var items: [DownloadItem] = []
    @Published var folder: URL
    @Published var isScanning = false
    @Published var scanProgress = 0

    // Grouping + filters
    @Published var groupMode: GroupMode = .source {
        didSet { selectedBucketKey = nil; if groupMode == .cleanup { computeDuplicatesIfNeeded() } }
    }
    @Published var selectedBucketKey: String? = nil   // nil = "All"
    @Published var searchText = ""
    @Published var onlyNeverOpened = false
    @Published var olderThanDays = 0                   // 0 => off

    // Options
    @Published var recursive = false { didSet { Defaults.recursive = recursive } }

    /// When true, the panel is showing installed applications (by last use)
    /// rather than the contents of a folder.
    @Published var appsMode = false

    // Cleanup state
    @Published var duplicateIDs: Set<DownloadItem.ID> = [] { didSet { recomputeReclaimable() } }

    // Menu-bar badge (reclaimable space from the last scan; no background work)
    @Published var reclaimableBytes: Int64 = 0
    @Published var showBadge: Bool = Defaults.showBadge { didSet { Defaults.showBadge = showBadge } }

    // Organizer undo
    struct Move { let from: URL; let to: URL }
    @Published private(set) var lastOrganize: [Move] = []
    var canUndoOrganize: Bool { !lastOrganize.isEmpty }

    // Table selection
    @Published var selection = Set<DownloadItem.ID>()

    private var scanTask: Task<Void, Never>?

    /// Subtrees skipped during recursive scans (system noise).
    nonisolated static let dirsToSkip: Set<String> = ["Library", "node_modules", ".Trash"]

    private enum Defaults {
        static var folderPath: String? {
            get { UserDefaults.standard.string(forKey: "folderPath") }
            set { UserDefaults.standard.set(newValue, forKey: "folderPath") }
        }
        static var recursive: Bool {
            get { UserDefaults.standard.bool(forKey: "recursive") }
            set { UserDefaults.standard.set(newValue, forKey: "recursive") }
        }
        static var showBadge: Bool {
            get { UserDefaults.standard.object(forKey: "showBadge") as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: "showBadge") }
        }
    }

    /// Cheap reclaimable estimate from already-scanned items (incomplete +
    /// installers + big/never-opened, plus duplicates once computed). Runs only
    /// when items or duplicates change — never on a timer.
    func recomputeReclaimable() {
        guard !appsMode else { reclaimableBytes = 0; return }
        reclaimableBytes = items.reduce(0) { $0 + (cleanupCategory(for: $1) != nil ? $1.size : 0) }
    }

    init() {
        let defaultDownloads = (try? FileManager.default.url(for: .downloadsDirectory,
                                                             in: .userDomainMask,
                                                             appropriateFor: nil,
                                                             create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        if let saved = Defaults.folderPath, FileManager.default.fileExists(atPath: saved) {
            folder = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            folder = defaultDownloads
        }
        recursive = Defaults.recursive
    }

    // MARK: - Locations

    struct FolderPreset: Identifiable {
        var id: String { url.path }
        let name: String
        let symbol: String
        let url: URL
    }

    static var presetLocations: [FolderPreset] {
        let fm = FileManager.default
        func dir(_ d: FileManager.SearchPathDirectory) -> URL? {
            try? fm.url(for: d, in: .userDomainMask, appropriateFor: nil, create: false)
        }
        var list: [FolderPreset] = []
        if let u = dir(.downloadsDirectory) { list.append(.init(name: "Downloads", symbol: "arrow.down.circle", url: u)) }
        if let u = dir(.desktopDirectory)   { list.append(.init(name: "Desktop",   symbol: "macwindow", url: u)) }
        if let u = dir(.documentDirectory)  { list.append(.init(name: "Documents", symbol: "doc.text", url: u)) }
        if let u = dir(.moviesDirectory)    { list.append(.init(name: "Movies",    symbol: "film", url: u)) }
        if let u = dir(.picturesDirectory)  { list.append(.init(name: "Pictures",  symbol: "photo", url: u)) }
        list.append(.init(name: "Home", symbol: "house", url: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)))
        return list
    }

    func open(folder url: URL) {
        appsMode = false
        folder = url
        Defaults.folderPath = url.path
        scan()
    }

    /// Scan installed applications (in /Applications, /Applications/Utilities and
    /// ~/Applications) and show them grouped by how long since last used. System
    /// apps under /System are intentionally excluded.
    func scanApplications() {
        appsMode = true
        selectedBucketKey = nil
        scan()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Triage"
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url {
            open(folder: url)
        }
    }

    // MARK: - Streaming scan

    func scan() {
        scanTask?.cancel()
        let dir = folder
        let deep = recursive
        isScanning = true
        scanProgress = 0
        duplicateIDs = []
        items = []

        let apps = appsMode
        scanTask = Task { [weak self] in
            var batch: [DownloadItem] = []
            let stream = apps ? Self.appStream() : Self.itemStream(dir, recursive: deep)
            for await item in stream {
                if Task.isCancelled { return }
                batch.append(item)
                if batch.count >= 300 {
                    let toAdd = batch; batch = []
                    await MainActor.run {
                        guard let self, !Task.isCancelled else { return }
                        self.items.append(contentsOf: toAdd)
                        self.scanProgress = self.items.count
                    }
                }
            }
            let rest = batch
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.items.append(contentsOf: rest)
                self.selection = self.selection.intersection(Set(self.items.map(\.id)))
                self.scanProgress = self.items.count
                self.isScanning = false
                self.recomputeReclaimable()
                if self.groupMode == .cleanup { self.computeDuplicatesIfNeeded() }
            }
        }
    }

    nonisolated static func itemStream(_ dir: URL, recursive: Bool) -> AsyncStream<DownloadItem> {
        AsyncStream { continuation in
            let work = Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                let keys: [URLResourceKey] = [
                    .addedToDirectoryDateKey, .creationDateKey, .isDirectoryKey, .isPackageKey,
                    .totalFileAllocatedSizeKey, .fileSizeKey, .nameKey
                ]
                if recursive {
                    guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: keys,
                                                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                        continuation.finish(); return
                    }
                    while let url = e.nextObject() as? URL {
                        if Task.isCancelled { break }
                        let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                        let isDir = rv?.isDirectory ?? false
                        let isPkg = rv?.isPackage ?? false
                        if isDir && !isPkg {
                            if Self.dirsToSkip.contains(url.lastPathComponent) { e.skipDescendants() }
                            continue                    // don't surface plain folders in deep mode
                        }
                        if let item = makeItem(url) { continuation.yield(item) }
                    }
                } else {
                    let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                            options: [.skipsHiddenFiles])) ?? []
                    for url in urls {
                        if Task.isCancelled { break }
                        if let item = makeItem(url) { continuation.yield(item) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    nonisolated static func makeItem(_ url: URL) -> DownloadItem? {
        let keys: Set<URLResourceKey> = [
            .addedToDirectoryDateKey, .creationDateKey, .isDirectoryKey,
            .totalFileAllocatedSizeKey, .fileSizeKey, .nameKey
        ]
        let rv = try? url.resourceValues(forKeys: keys)
        let isDir = rv?.isDirectory ?? false
        let sources = Provenance.whereFroms(atPath: url.path)
        let domain = sources.lazy.compactMap { Provenance.domain(from: $0) }.first
        let size = Int64(rv?.totalFileAllocatedSize ?? rv?.fileSize ?? 0)
        let ext = url.pathExtension
        return DownloadItem(
            id: url,
            name: rv?.name ?? url.lastPathComponent,
            sourceURLs: sources,
            sourceDomain: domain,
            dateAdded: rv?.addedToDirectoryDate ?? rv?.creationDate,
            lastOpened: Provenance.lastUsedDate(atPath: url.path),
            size: size,
            isDirectory: isDir,
            ext: ext,
            category: FileCategory.of(extension: ext, isDirectory: isDir)
        )
    }

    // MARK: - Applications scan

    /// User-app locations only — never /System/Applications, so Apple's built-in
    /// apps can't be listed or trashed.
    nonisolated static var appSearchDirs: [URL] {
        var dirs = [URL(fileURLWithPath: "/Applications"),
                    URL(fileURLWithPath: "/Applications/Utilities")]
        dirs.append(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"))
        return dirs
    }

    nonisolated static func appStream() -> AsyncStream<DownloadItem> {
        AsyncStream { continuation in
            let work = Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                var seen = Set<String>()
                for dir in appSearchDirs {
                    guard let entries = try? fm.contentsOfDirectory(
                        at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                    for url in entries where url.pathExtension == "app" {
                        if Task.isCancelled { continuation.finish(); return }
                        if !seen.insert(url.standardizedFileURL.path).inserted { continue }
                        if let item = makeAppItem(url) { continuation.yield(item) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    nonisolated static func makeAppItem(_ url: URL) -> DownloadItem? {
        guard url.pathExtension == "app" else { return nil }
        let rv = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        let bundle = Bundle(url: url)
        let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
        return DownloadItem(
            id: url,
            name: url.deletingPathExtension().lastPathComponent,
            sourceURLs: Provenance.whereFroms(atPath: url.path),
            sourceDomain: nil,
            dateAdded: rv?.addedToDirectoryDate ?? rv?.creationDate,
            lastOpened: Provenance.lastUsedDate(atPath: url.path),
            size: directorySize(url),
            isDirectory: true,
            ext: "app",
            category: .applications,
            version: version,
            bundleID: bundle?.bundleIdentifier,
            isApp: true
        )
    }

    /// Recursive on-disk size of a bundle/folder. Runs on the background scan
    /// task, so a large app doesn't block the UI.
    nonisolated static func directorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: url,
                                                  includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                                  options: []) {
            for case let f as URL in e {
                if let s = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize {
                    total += Int64(s)
                }
            }
        }
        return total
    }

    /// Is this app currently running? (a guardrail hint before trashing)
    func isRunning(_ item: DownloadItem) -> Bool {
        guard let id = item.bundleID else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id }
    }

    // MARK: - Grouping

    func bucketKey(for item: DownloadItem) -> String {
        if appsMode { return UsageBucket.of(item.lastOpened).rawValue }
        switch groupMode {
        case .source:  return item.sourceDomain ?? ""
        case .type:    return item.category.rawValue
        case .date:    return DateBucket.of(item.dateAdded).rawValue
        case .cleanup: return cleanupCategory(for: item)?.rawValue ?? ""
        }
    }

    private func bucketLabel(_ key: String) -> String {
        if appsMode { return key }
        switch groupMode {
        case .source:  return key.isEmpty ? "Unknown source" : key
        case .cleanup: return key.isEmpty ? "Other" : key
        default:       return key
        }
    }

    private func bucketSymbol(_ key: String) -> String {
        if appsMode { return UsageBucket(rawValue: key)?.symbol ?? "app.dashed" }
        switch groupMode {
        case .source:  return key.isEmpty ? "questionmark.circle" : "globe"
        case .type:    return FileCategory(rawValue: key)?.symbol ?? "doc"
        case .date:    return DateBucket(rawValue: key)?.symbol ?? "calendar"
        case .cleanup: return CleanupCategory(rawValue: key)?.symbol ?? "sparkles"
        }
    }

    private func sortIndex(_ key: String) -> Int {
        if appsMode { return UsageBucket(rawValue: key)?.order ?? 99 }
        switch groupMode {
        case .date:    return DateBucket(rawValue: key)?.order ?? 99
        case .cleanup: return CleanupCategory(rawValue: key)?.order ?? 99
        default:       return 0
        }
    }

    /// Items eligible for grouping (cleanup mode only shows flagged items).
    private var groupableItems: [DownloadItem] {
        if appsMode { return items }
        return groupMode == .cleanup ? items.filter { cleanupCategory(for: $0) != nil } : items
    }

    var buckets: [Bucket] {
        var grouped: [String: (count: Int, size: Int64)] = [:]
        for item in groupableItems {
            let key = bucketKey(for: item)
            if groupMode == .cleanup && key.isEmpty { continue }
            var e = grouped[key] ?? (0, 0)
            e.count += 1; e.size += item.size
            grouped[key] = e
        }
        let useOrder = (appsMode || groupMode == .date || groupMode == .cleanup)
        return grouped
            .map { Bucket(key: $0.key, label: bucketLabel($0.key), symbol: bucketSymbol($0.key),
                          count: $0.value.count, size: $0.value.size) }
            .sorted { lhs, rhs in
                if useOrder {
                    let a = sortIndex(lhs.key), b = sortIndex(rhs.key)
                    if a != b { return a < b }
                } else if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
    }

    var totalItemsForGroup: Int { groupableItems.count }
    var totalSizeForGroup: Int64 { groupableItems.reduce(0) { $0 + $1.size } }

    var filteredItems: [DownloadItem] {
        groupableItems.filter { item in
            if let sel = selectedBucketKey, bucketKey(for: item) != sel { return false }
            if onlyNeverOpened && !item.neverOpened { return false }
            if olderThanDays > 0, (item.ageInDays ?? -1) < olderThanDays { return false }
            if !searchText.isEmpty {
                let hay = "\(item.name) \(item.sourceDomain ?? "") \(item.originURL ?? "") \(item.bundleID ?? "")"
                if hay.range(of: searchText, options: .caseInsensitive) == nil { return false }
            }
            return true
        }
    }

    var filteredTotalSize: Int64 { filteredItems.reduce(0) { $0 + $1.size } }

    // MARK: - Cleanup intelligence

    func cleanupCategory(for item: DownloadItem) -> CleanupCategory? {
        let ext = item.ext.lowercased()
        if ["crdownload", "part", "download", "partial", "tmp"].contains(ext) { return .incomplete }
        if duplicateIDs.contains(item.id) { return .duplicates }
        if ["dmg", "pkg", "mpkg", "msi"].contains(ext) { return .installers }
        if item.size >= 50_000_000 && item.neverOpened { return .bigOld }
        return nil
    }

    func computeDuplicatesIfNeeded() {
        guard duplicateIDs.isEmpty else { return }
        let snapshot = items.filter { !$0.isDirectory && $0.size > 0 }
        guard !snapshot.isEmpty else { return }
        Task.detached(priority: .utility) {
            let dups = Self.findDuplicates(snapshot)
            await MainActor.run { [weak self] in self?.duplicateIDs = dups }
        }
    }

    nonisolated static func findDuplicates(_ items: [DownloadItem]) -> Set<URL> {
        var bySize: [Int64: [DownloadItem]] = [:]
        for i in items { bySize[i.size, default: []].append(i) }
        var result: Set<URL> = []
        for (_, group) in bySize where group.count > 1 {
            var byHash: [String: [URL]] = [:]
            for i in group {
                if let h = sha256(i.url) { byHash[h, default: []].append(i.url) }
            }
            for (_, urls) in byHash where urls.count > 1 { result.formUnion(urls) }
        }
        return result
    }

    nonisolated static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Trash (recoverable)

    @discardableResult
    func moveToTrash(_ urls: [URL]) -> Int {
        var trashed = 0
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed += 1
            } catch {
                NSLog("Where From: failed to trash \(url.lastPathComponent): \(error)")
            }
        }
        scan()
        return trashed
    }

    // MARK: - Organizer (move into subfolders, with undo)

    private func organizeFolderName(_ item: DownloadItem, scheme: OrganizeScheme) -> String {
        switch scheme {
        case .source:
            return item.sourceDomain ?? "Unknown source"
        case .type:
            return item.category.rawValue
        case .month:
            guard let d = item.dateAdded else { return "Unknown date" }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM"
            return f.string(from: d)
        }
    }

    private func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private func uniqueURL(_ url: URL, claimed: inout Set<String>) -> URL {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = url
        var n = 2
        while fm.fileExists(atPath: candidate.path) || claimed.contains(candidate.standardizedFileURL.path) {
            let newName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            n += 1
        }
        claimed.insert(candidate.standardizedFileURL.path)
        return candidate
    }

    /// Preview how many files would move into how many folders.
    func organizePreview(_ items: [DownloadItem], scheme: OrganizeScheme) -> (files: Int, folders: Int) {
        let moves = planOrganize(items, scheme: scheme)
        let folders = Set(moves.map { $0.to.deletingLastPathComponent().path })
        return (moves.count, folders.count)
    }

    private func planOrganize(_ items: [DownloadItem], scheme: OrganizeScheme) -> [Move] {
        var moves: [Move] = []
        var claimed = Set<String>()
        for item in items {
            let groupName = sanitize(organizeFolderName(item, scheme: scheme))
            let destDir = folder.appendingPathComponent(groupName, isDirectory: true)
            // Already sitting directly in the right subfolder? leave it.
            if item.url.deletingLastPathComponent().standardizedFileURL == destDir.standardizedFileURL { continue }
            let dest = uniqueURL(destDir.appendingPathComponent(item.name), claimed: &claimed)
            moves.append(Move(from: item.url, to: dest))
        }
        return moves
    }

    @discardableResult
    func organize(_ items: [DownloadItem], scheme: OrganizeScheme) -> Int {
        let fm = FileManager.default
        var done: [Move] = []
        for m in planOrganize(items, scheme: scheme) {
            do {
                try fm.createDirectory(at: m.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: m.from, to: m.to)
                done.append(m)
            } catch {
                NSLog("Where From: organize failed for \(m.from.lastPathComponent): \(error)")
            }
        }
        lastOrganize = done
        scan()
        return done.count
    }

    func undoOrganize() {
        let fm = FileManager.default
        for m in lastOrganize.reversed() {
            try? fm.moveItem(at: m.to, to: m.from)
            let dir = m.to.deletingLastPathComponent()
            if let contents = try? fm.contentsOfDirectory(atPath: dir.path), contents.isEmpty {
                try? fm.removeItem(at: dir)
            }
        }
        lastOrganize = []
        scan()
    }

    // MARK: - Selection helpers

    func selectedItems() -> [DownloadItem] { items.filter { selection.contains($0.id) } }
    func items(for ids: Set<DownloadItem.ID>) -> [DownloadItem] { items.filter { ids.contains($0.id) } }

    // MARK: - Origin actions

    func openSources(for items: [DownloadItem]) {
        for url in items.compactMap({ $0.originURL }).compactMap(URL.init(string:)) {
            NSWorkspace.shared.open(url)
        }
    }

    func copySources(for items: [DownloadItem]) {
        let urls = items.compactMap { $0.originURL }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.joined(separator: "\n"), forType: .string)
    }

    func openFiles(_ urls: [URL]) {
        for url in urls { NSWorkspace.shared.open(url) }
    }
}
