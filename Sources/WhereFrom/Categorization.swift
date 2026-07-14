import Foundation

/// Coarse file-type category, derived from the extension (fast, no per-file
/// UTType round-trips). Drives the "Type" grouping and cleanup heuristics.
enum FileCategory: String, CaseIterable, Identifiable {
    case images = "Images"
    case documents = "Documents"
    case archives = "Archives"
    case installers = "Installers"
    case audio = "Audio"
    case video = "Video"
    case code = "Code"
    case models3D = "3D & CAD"
    case data = "Data"
    case folders = "Folders"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .images: return "photo"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .installers: return "shippingbox"
        case .audio: return "music.note"
        case .video: return "film"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .models3D: return "cube"
        case .data: return "tablecells"
        case .folders: return "folder"
        case .other: return "doc"
        }
    }

    private static let map: [String: FileCategory] = {
        var m: [String: FileCategory] = [:]
        func add(_ cat: FileCategory, _ exts: [String]) { for e in exts { m[e] = cat } }
        add(.images, ["png","jpg","jpeg","gif","heic","heif","webp","tiff","tif","bmp","svg","raw","cr2","nef","psd","ai"])
        add(.documents, ["pdf","doc","docx","pages","txt","rtf","md","key","ppt","pptx","odt","epub"])
        add(.archives, ["zip","rar","7z","tar","gz","bz2","xz","tgz","dmg"]) // dmg counted as installer below
        add(.installers, ["dmg","pkg","mpkg","app","exe","msi"])
        add(.audio, ["mp3","m4a","wav","aac","flac","aiff","ogg"])
        add(.video, ["mp4","mov","m4v","avi","mkv","webm","wmv","flv"])
        add(.code, ["swift","c","h","cpp","hpp","m","py","js","ts","java","rb","go","rs","sh","json","yaml","yml","xml","html","css","ino"])
        add(.models3D, ["stl","step","stp","3mf","obj","fbx","gltf","glb","dxf","dwg","iges","igs","f3d"])
        add(.data, ["csv","xls","xlsx","numbers","sqlite","db","tsv","parquet"])
        return m
    }()

    static func of(extension ext: String, isDirectory: Bool) -> FileCategory {
        if isDirectory { return .folders }
        return map[ext.lowercased()] ?? .other
    }
}

/// Human-friendly age buckets for the "Date" grouping.
enum DateBucket: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This week"
    case thisMonth = "This month"
    case thisYear = "This year"
    case older = "Older"
    case unknown = "Unknown date"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: return "clock"
        case .thisWeek: return "calendar"
        case .thisMonth: return "calendar"
        case .thisYear: return "calendar"
        case .older: return "calendar.badge.clock"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Ordering index so buckets sort newest → oldest.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 99 }

    static func of(_ date: Date?, now: Date = Date()) -> DateBucket {
        guard let date else { return .unknown }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if let d = cal.dateComponents([.day], from: date, to: now).day {
            if d < 7 { return .thisWeek }
            if d < 31 { return .thisMonth }
            if d < 365 { return .thisYear }
        }
        return .older
    }
}
