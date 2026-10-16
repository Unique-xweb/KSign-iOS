// [LISTN] Sources/KSignApp/Models/SignedAppItem.swift
// Language: Swift 5.9 | File: SignedAppItem.swift | Target: Signed Application Package Model
import Foundation

public struct SignedAppItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let bundleIdentifier: String
    public let version: String
    public let localFileName: String
    public let fileSize: Int64
    public let signedDate: Date
    public let iconFileName: String?

    public init(id: UUID = UUID(),
                name: String,
                bundleIdentifier: String,
                version: String,
                localFileName: String,
                fileSize: Int64,
                signedDate: Date = Date(),
                iconFileName: String? = nil) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.localFileName = localFileName
        self.fileSize = fileSize
        self.signedDate = signedDate
        self.iconFileName = iconFileName
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var formattedSignedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: signedDate)
    }
}
