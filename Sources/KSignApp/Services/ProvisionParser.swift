// [LISTN] Sources/KSignApp/Services/ProvisionParser.swift
// Language: Swift 5.9 | File: ProvisionParser.swift | Target: Apple Mobileprovision Extraction & Validation
import Foundation

public final class ProvisionParser {

    public enum ParseError: LocalizedError {
        case fileNotFound(String)
        case invalidCMSWrapper(String)
        case invalidPlist(String)
        case missingEntitlements(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let msg): return "Provisioning profile not found: \(msg)"
            case .invalidCMSWrapper(let msg): return "Failed to locate XML payload within CMS message: \(msg)"
            case .invalidPlist(let msg): return "Failed to parse profile XML plist: \(msg)"
            case .missingEntitlements(let msg): return "Entitlements block missing: \(msg)"
            }
        }
    }

    public static func parse(fileURL: URL) throws -> ProvisionItem {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ParseError.fileNotFound(fileURL.path)
        }

        let rawData = try Data(contentsOf: fileURL)
        guard let (_, xmlData) = extractXMLPayload(from: rawData) else {
            throw ParseError.invalidCMSWrapper(fileURL.lastPathComponent)
        }

        guard let dict = try PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil) as? [String: Any] else {
            throw ParseError.invalidPlist(fileURL.lastPathComponent)
        }

        let name = dict["Name"] as? String ?? fileURL.deletingPathExtension().lastPathComponent
        let appIDName = dict["AppIDName"] as? String ?? ""
        let teamName = dict["TeamName"] as? String ?? ""

        var teamID = ""
        if let teamIDs = dict["TeamIdentifier"] as? [String], let firstID = teamIDs.first {
            teamID = firstID
        }

        let creationDate = dict["CreationDate"] as? Date ?? Date()
        let expirationDate = dict["ExpirationDate"] as? Date ?? Date.distantPast
        let deviceUDIDs = dict["ProvisionedDevices"] as? [String] ?? []

        var bundleID = ""
        var entitlementsXml = ""

        if let entitlements = dict["Entitlements"] as? [String: Any] {
            if let appID = entitlements["application-identifier"] as? String {
                // Application identifier is formatted as <TeamID>.<BundleID>
                if appID.hasPrefix("\(teamID).") {
                    bundleID = String(appID.dropFirst(teamID.count + 1))
                } else {
                    bundleID = appID
                }
            }

            if let entData = try? PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0),
               let entStr = String(data: entData, encoding: .utf8) {
                entitlementsXml = entStr
            }
        }

        return ProvisionItem(
            name: name,
            appIDName: appIDName,
            bundleIdentifier: bundleID,
            teamName: teamName,
            teamID: teamID,
            creationDate: creationDate,
            expirationDate: expirationDate,
            deviceUDIDs: deviceUDIDs,
            entitlementsXml: entitlementsXml,
            localFileName: fileURL.lastPathComponent
        )
    }

    /// Locates the inner XML plist inside the ASN.1 CMS message
    public static func extractXMLPayload(from cmsData: Data) -> (String, Data)? {
        guard let xmlStartRange = cmsData.range(of: "<?xml".data(using: .utf8)!) else {
            return nil
        }
        guard let plistEndRange = cmsData.range(of: "</plist>".data(using: .utf8)!, options: .backwards) else {
            return nil
        }

        let xmlEnd = plistEndRange.upperBound
        guard xmlStartRange.lowerBound < xmlEnd else { return nil }

        let xmlSubdata = cmsData.subdata(in: xmlStartRange.lowerBound..<xmlEnd)
        guard let xmlString = String(data: xmlSubdata, encoding: .utf8) else {
            return nil
        }

        return (xmlString, xmlSubdata)
    }
}
