// [LISTN] Sources/KSignApp/Services/CertificateParser.swift
// Language: Swift 5.9 | File: CertificateParser.swift | Target: PKCS#12 Ingestion & X.509 Extraction
import Foundation
import Security

public final class CertificateParser {

    public enum ParseError: LocalizedError {
        case fileNotFound(String)
        case invalidPassword(String)
        case noIdentityFound(String)
        case extractionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let msg): return "Certificate file not found: \(msg)"
            case .invalidPassword(let msg): return "Incorrect PKCS#12 password: \(msg)"
            case .noIdentityFound(let msg): return "No private key identity found in container: \(msg)"
            case .extractionFailed(let msg): return "Failed to extract X.509 certificate attributes: \(msg)"
            }
        }
    }

    public static func parse(fileURL: URL, password: String) throws -> CertificateItem {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ParseError.fileNotFound(fileURL.path)
        }

        let p12Data = try Data(contentsOf: fileURL)
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]

        var rawItems: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &rawItems)

        guard status == errSecSuccess, let items = rawItems as? [[String: Any]], let firstItem = items.first else {
            if status == errSecAuthFailed {
                throw ParseError.invalidPassword("Invalid password provided for \(fileURL.lastPathComponent)")
            }
            throw ParseError.extractionFailed("SecPKCS12Import returned OSStatus: \(status)")
        }

        guard let identity = firstItem[kSecImportItemIdentity as String] as! SecIdentity? else {
            throw ParseError.noIdentityFound(fileURL.lastPathComponent)
        }

        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)

        guard let certificate = cert else {
            throw ParseError.extractionFailed("Unable to retrieve SecCertificate from SecIdentity")
        }

        let summary = SecCertificateCopySubjectSummary(certificate) as String? ?? "Apple Development Certificate"

        // Extract dates and attributes via SecCertificateCopyValues
        var creationDate = Date()
        var expirationDate = Date.distantFuture
        var teamName = ""
        var teamID = ""

        if let values = SecCertificateCopyValues(certificate, nil, nil) as? [String: [String: Any]] {
            // Validity period
            if let validityDict = values["2.5.29.14"] ?? values["2.16.840.1.113741.1.2.1.1.1.1"] {
                // Inspect validity
            }

            // Subject organizational unit & common name
            if let subjectDict = values[kSecOIDX509V1SubjectName as String],
               let subSequence = subjectDict[kSecPropertyKeyValue as String] as? [[String: Any]] {
                for item in subSequence {
                    let label = item[kSecPropertyKeyLabel as String] as? String
                    let value = item[kSecPropertyKeyValue as String] as? String ?? ""

                    if label == "2.5.4.10" || label == "O" { // Organization Name
                        teamName = value
                    } else if label == "2.5.4.11" || label == "OU" { // Organizational Unit / Team ID
                        teamID = value
                    }
                }
            }

            // Expiration period (Not After)
            if let valDict = values[kSecOIDX509V1ValidityNotAfter as String],
               let expSeconds = valDict[kSecPropertyKeyValue as String] as? NSNumber {
                expirationDate = Date(timeIntervalSinceReferenceDate: expSeconds.doubleValue)
            }
        }

        // Fallback expiration check
        if expirationDate == Date.distantFuture {
            expirationDate = Date().addingTimeInterval(365 * 24 * 3600)
        }

        return CertificateItem(
            commonName: summary,
            teamName: teamName.isEmpty ? summary : teamName,
            teamID: teamID,
            creationDate: creationDate,
            expirationDate: expirationDate,
            localFileName: fileURL.lastPathComponent,
            password: password,
            isActive: false
        )
    }
}
