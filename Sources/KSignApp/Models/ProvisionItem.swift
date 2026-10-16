// [LISTN] Sources/KSignApp/Models/ProvisionItem.swift
// Language: Swift 5.9 | File: ProvisionItem.swift | Target: Apple Mobileprovision Data Model
import Foundation

public struct ProvisionItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let appIDName: String
    public let bundleIdentifier: String
    public let teamName: String
    public let teamID: String
    public let creationDate: Date
    public let expirationDate: Date
    public let deviceUDIDs: [String]
    public let entitlementsXml: String
    public let localFileName: String

    public init(id: UUID = UUID(),
                name: String,
                appIDName: String,
                bundleIdentifier: String,
                teamName: String,
                teamID: String,
                creationDate: Date,
                expirationDate: Date,
                deviceUDIDs: [String],
                entitlementsXml: String,
                localFileName: String) {
        self.id = id
        self.name = name
        self.appIDName = appIDName
        self.bundleIdentifier = bundleIdentifier
        self.teamName = teamName
        self.teamID = teamID
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.deviceUDIDs = deviceUDIDs
        self.entitlementsXml = entitlementsXml
        self.localFileName = localFileName
    }

    public var isExpired: Bool {
        expirationDate < Date()
    }

    public var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
    }

    public var formattedExpiration: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: expirationDate)
    }
}
