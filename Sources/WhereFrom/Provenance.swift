import Foundation
import CoreServices

/// Low-level reading of macOS provenance metadata that Finder keeps hidden.
enum Provenance {

    /// Read a raw extended attribute (e.g. the WhereFroms binary plist) off a path.
    static func extendedAttribute(_ name: String, atPath path: String) -> Data? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        if length < 0 { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            return getxattr(path, name, base, length, 0, 0)
        }
        return read < 0 ? nil : data
    }

    /// The origin URLs stored in `com.apple.metadata:kMDItemWhereFroms`.
    /// Decoded straight from the binary plist so it works even when Spotlight
    /// hasn't indexed the file.
    static func whereFroms(atPath path: String) -> [String] {
        guard let data = extendedAttribute("com.apple.metadata:kMDItemWhereFroms", atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return [] }

        if let strings = plist as? [String] {
            return strings.filter { !$0.isEmpty }
        }
        if let anything = plist as? [Any] {
            return anything.compactMap { $0 as? String }.filter { !$0.isEmpty }
        }
        return []
    }

    /// Spotlight's "last opened by the user" date. Best-effort — nil is treated
    /// as "never opened" in the triage view.
    static func lastUsedDate(atPath path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Reduce an origin URL to a clean display domain, dropping a leading `www.`.
    static func domain(from urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
