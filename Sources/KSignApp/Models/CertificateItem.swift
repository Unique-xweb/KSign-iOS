// [LISTN] Sources/KSignApp/Models/CertificateItem.swift
// Language: Swift 5.9 | File: CertificateItem.swift | Target: PKCS#12 Certificate Model
import Foundation

public struct CertificateItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public let commonName: String
    public let teamName: String
    public let teamID: String
    public let creationDate: Date
    public let expirationDate: Date
    public let localFileName: String
    public var password: String
    public var associatedProvisionID: UUID?
    public var isActive: Bool

    public init(id: UUID = UUID(),
                commonName: String,
                teamName: String,
                teamID: String,
                creationDate: Date,
                expirationDate: Date,
                localFileName: String,
                password: String = "",
                associatedProvisionID: UUID? = nil,
                isActive: Bool = false) {
        self.id = id
        self.commonName = commonName
        self.teamName = teamName
        self.teamID = teamID
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.localFileName = localFileName
        self.password = password
        self.associatedProvisionID = associatedProvisionID
        self.isActive = isActive
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
