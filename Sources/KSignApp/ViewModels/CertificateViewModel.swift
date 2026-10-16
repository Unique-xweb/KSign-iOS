// [LISTN] Sources/KSignApp/ViewModels/CertificateViewModel.swift
// Language: Swift 5.9 | File: CertificateViewModel.swift | Target: Certificate & Provisioning Profile State Coordinator
import Foundation
import SwiftUI

public final class CertificateViewModel: ObservableObject {
    @Published public var certificates: [CertificateItem] = []
    @Published public var provisions: [ProvisionItem] = []
    @Published public var activeCertificateID: UUID?
    @Published public var errorMessage: String?

    private let fileManager = FileManager.default

    public var certsDirectory: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Certificates")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    private var certsMetadataURL: URL {
        certsDirectory.appendingPathComponent("certificates.json")
    }

    private var provisionsMetadataURL: URL {
        certsDirectory.appendingPathComponent("provisions.json")
    }

    public var activeCertificate: CertificateItem? {
        certificates.first { $0.id == activeCertificateID } ?? certificates.first
    }

    public var activeProvision: ProvisionItem? {
        if let cert = activeCertificate, let provID = cert.associatedProvisionID {
            return provisions.first { $0.id == provID }
        }
        // Auto-match by TeamID
        if let cert = activeCertificate {
            return provisions.first { $0.teamID == cert.teamID } ?? provisions.first
        }
        return provisions.first
    }

    public init() {
        loadMetadata()
    }

    public func loadMetadata() {
        if let data = try? Data(contentsOf: certsMetadataURL),
           let items = try? JSONDecoder().decode([CertificateItem].self, from: data) {
            self.certificates = items
            if let active = items.first(where: { $0.isActive }) {
                self.activeCertificateID = active.id
            } else {
                self.activeCertificateID = items.first?.id
            }
        }

        if let data = try? Data(contentsOf: provisionsMetadataURL),
           let items = try? JSONDecoder().decode([ProvisionItem].self, from: data) {
            self.provisions = items
        }
    }

    public func saveMetadata() {
        if let data = try? JSONEncoder().encode(certificates) {
            try? data.write(to: certsMetadataURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(provisions) {
            try? data.write(to: provisionsMetadataURL, options: .atomic)
        }
    }

    public func importP12(sourceURL: URL, password: String) -> Bool {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            self.errorMessage = "Permission denied accessing certificate file."
            return false
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let destURL = certsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)

            var certItem = try CertificateParser.parse(fileURL: destURL, password: password)

            // Auto-link with matching provision if available
            if let matchingProv = provisions.first(where: { $0.teamID == certItem.teamID }) {
                certItem.associatedProvisionID = matchingProv.id
            }

            // If first certificate, make it active
            if certificates.isEmpty {
                certItem.isActive = true
                self.activeCertificateID = certItem.id
            }

            certificates.append(certItem)
            saveMetadata()
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    public func importMobileprovision(sourceURL: URL) -> Bool {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            self.errorMessage = "Permission denied accessing profile."
            return false
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let destURL = certsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)

            let provItem = try ProvisionParser.parse(fileURL: destURL)
            provisions.append(provItem)

            // Auto-link any unassociated certificate with matching team ID
            for i in 0..<certificates.count {
                if certificates[i].associatedProvisionID == nil && certificates[i].teamID == provItem.teamID {
                    certificates[i].associatedProvisionID = provItem.id
                }
            }

            saveMetadata()
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    public func setActiveCertificate(_ cert: CertificateItem) {
        for i in 0..<certificates.count {
            certificates[i].isActive = (certificates[i].id == cert.id)
        }
        self.activeCertificateID = cert.id
        saveMetadata()
    }

    public func deleteCertificate(_ cert: CertificateItem) {
        let fileURL = certsDirectory.appendingPathComponent(cert.localFileName)
        try? fileManager.removeItem(at: fileURL)
        certificates.removeAll { $0.id == cert.id }
        if activeCertificateID == cert.id {
            activeCertificateID = certificates.first?.id
        }
        saveMetadata()
    }

    public func deleteProvision(_ prov: ProvisionItem) {
        let fileURL = certsDirectory.appendingPathComponent(prov.localFileName)
        try? fileManager.removeItem(at: fileURL)
        provisions.removeAll { $0.id == prov.id }
        for i in 0..<certificates.count {
            if certificates[i].associatedProvisionID == prov.id {
                certificates[i].associatedProvisionID = nil
            }
        }
        saveMetadata()
    }
}
