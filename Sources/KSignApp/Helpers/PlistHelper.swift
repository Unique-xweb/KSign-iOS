// [LISTN] Sources/KSignApp/Helpers/PlistHelper.swift
// Language: Swift 5.9 | File: PlistHelper.swift | Target: Info.plist Modifier & CodeResources Generator
import Foundation
import CommonCrypto

public final class PlistHelper {

    public enum PlistError: LocalizedError {
        case fileNotFound(String)
        case invalidFormat(String)
        case serializationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let msg): return "File not found: \(msg)"
            case .invalidFormat(let msg): return "Invalid plist structure: \(msg)"
            case .serializationFailed(let msg): return "Failed to serialize plist: \(msg)"
            }
        }
    }

    // MARK: - Read & Modify Info.plist
    public static func modifyInfoPlist(at appBundleURL: URL,
                                       newBundleID: String?,
                                       newDisplayName: String?,
                                       newVersion: String?) throws -> [String: Any] {
        let infoPlistURL = appBundleURL.appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw PlistError.fileNotFound(infoPlistURL.path)
        }

        let data = try Data(contentsOf: infoPlistURL)
        guard var dict = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            throw PlistError.invalidFormat(infoPlistURL.path)
        }

        if let newID = newBundleID, !newID.isEmpty {
            dict["CFBundleIdentifier"] = newID
        }

        if let newName = newDisplayName, !newName.isEmpty {
            dict["CFBundleDisplayName"] = newName
            dict["CFBundleName"] = newName
        }

        if let newVer = newVersion, !newVer.isEmpty {
            dict["CFBundleShortVersionString"] = newVer
            dict["CFBundleVersion"] = newVer
        }

        let updatedData = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try updatedData.write(to: infoPlistURL, options: .atomic)
        return dict
    }

    // MARK: - Generate CodeResources (_CodeSignature/CodeResources)
    public static func generateCodeResources(appBundleURL: URL) throws -> Data {
        let fileManager = FileManager.default
        let codeSignatureDir = appBundleURL.appendingPathComponent("_CodeSignature")
        try fileManager.createDirectory(at: codeSignatureDir, withIntermediateDirectories: true, attributes: nil)

        guard let enumerator = fileManager.enumerator(at: appBundleURL,
                                                      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                                                      options: [.skipsPackageDescendants]) else {
            throw PlistError.fileNotFound(appBundleURL.path)
        }

        var filesDict: [String: Any] = [:]
        var files2Dict: [String: Any] = [:]

        let baseLen = appBundleURL.path.hasSuffix("/") ? appBundleURL.path.count : appBundleURL.path.count + 1

        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            guard path.count >= baseLen else { continue }
            let relativePath = String(path.dropFirst(baseLen))

            // Ignore _CodeSignature and embedded.mobileprovision from CodeResources hashing
            if relativePath.hasPrefix("_CodeSignature") || relativePath == "embedded.mobileprovision" {
                continue
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            let isRegular = resourceValues?.isRegularFile ?? false
            let isSymlink = resourceValues?.isSymbolicLink ?? false

            if isRegular || isSymlink {
                let fileData: Data
                if isSymlink {
                    let dest = try fileManager.destinationOfSymbolicLink(atPath: fileURL.path)
                    fileData = dest.data(using: .utf8) ?? Data()
                } else {
                    fileData = try Data(contentsOf: fileURL)
                }

                let sha1 = sha1Hash(fileData)
                let sha256 = sha256Hash(fileData)

                filesDict[relativePath] = sha1
                files2Dict[relativePath] = [
                    "hash": sha1,
                    "hash2": sha256
                ]
            }
        }

        let rules: [String: Any] = [
            "^.*": true,
            "^.*\\.lproj/": ["weight": 1000],
            "^.*\\.lproj/locversion.plist$": ["omit": true, "weight": 1100],
            "^Base\\.lproj/": ["weight": 1010],
            "^version\\.plist$": true
        ]

        let rules2: [String: Any] = [
            "^.*": true,
            ".*\\.dSYM($|/)": ["weight": 11],
            "^(.*/)?\\.DS_Store$": ["omit": true, "weight": 2000],
            "^.*\\.lproj/": ["weight": 1000],
            "^.*\\.lproj/locversion.plist$": ["omit": true, "weight": 1100],
            "^Base\\.lproj/": ["weight": 1010],
            "^Info\\.plist$": ["omit": true, "weight": 20],
            "^PkgInfo$": ["omit": true, "weight": 20],
            "^embedded\\.mobileprovision$": ["weight": 20],
            "^version\\.plist$": ["weight": 20]
        ]

        let codeResourcesPlist: [String: Any] = [
            "files": filesDict,
            "files2": files2Dict,
            "rules": rules,
            "rules2": rules2
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: codeResourcesPlist, format: .xml, options: 0)
        let destinationURL = codeSignatureDir.appendingPathComponent("CodeResources")
        try data.write(to: destinationURL, options: .atomic)
        return data
    }

    private static func sha1Hash(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    private static func sha256Hash(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}
