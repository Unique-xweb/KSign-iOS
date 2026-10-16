// [LISTN] Sources/KSignApp/Models/FileItem.swift
// Language: Swift 5.9 | File: FileItem.swift | Target: File Management Data Model
import Foundation

public enum FileExtensionType: String, CaseIterable, Identifiable {
    case ipa = "ipa"
    case dylib = "dylib"
    case deb = "deb"
    case p12 = "p12"
    case mobileprovision = "mobileprovision"
    case other = "other"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .ipa: return "app.badge.fill"
        case .dylib: return "puzzlepiece.extension.fill"
        case .deb: return "shippingbox.fill"
        case .p12: return "key.fill"
        case .mobileprovision: return "doc.text.badge.plus"
        case .other: return "doc.fill"
        }
    }

    public var badgeColorHex: String {
        switch self {
        case .ipa: return "#007AFF"
        case .dylib: return "#AF52DE"
        case .deb: return "#FF9500"
        case .p12: return "#34C759"
        case .mobileprovision: return "#5856D6"
        case .other: return "#8E8E93"
        }
    }
}

public struct FileItem: Identifiable, Hashable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let size: Int64
    public let extensionType: FileExtensionType
    public let modificationDate: Date

    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        let pathExt = url.pathExtension.lowercased()
        self.extensionType = FileExtensionType(rawValue: pathExt) ?? .other

        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        self.size = Int64(resourceValues?.fileSize ?? 0)
        self.modificationDate = resourceValues?.contentModificationDate ?? Date()
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}
