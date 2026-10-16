// [LISTN] Sources/KSignApp/Services/AppSignerService.swift
// Language: Swift 5.9 | File: AppSignerService.swift | Target: Full IPA Re-Signing Pipeline Orchestrator
import Foundation

public final class AppSignerService {

    public enum SignError: LocalizedError {
        case payloadNotFound(String)
        case appBundleNotFound(String)
        case missingExecutable(String)
        case coreSigningFailed(String)
        case packagingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .payloadNotFound(let msg): return "Payload directory missing in archive: \(msg)"
            case .appBundleNotFound(let msg): return "No .app bundle discovered in Payload: \(msg)"
            case .missingExecutable(let msg): return "Executable binary not found in app bundle: \(msg)"
            case .coreSigningFailed(let msg): return "Mach-O signing failed: \(msg)"
            case .packagingFailed(let msg): return "IPA repacking failed: \(msg)"
            }
        }
    }

    public struct SigningOptions {
        public var newBundleID: String?
        public var newDisplayName: String?
        public var newVersion: String?
        public var dylibsToInject: [URL] = []
        public var removeExtensions: Bool = false

        public init(newBundleID: String? = nil,
                    newDisplayName: String? = nil,
                    newVersion: String? = nil,
                    dylibsToInject: [URL] = [],
                    removeExtensions: Bool = false) {
            self.newBundleID = newBundleID
            self.newDisplayName = newDisplayName
            self.newVersion = newVersion
            self.dylibsToInject = dylibsToInject
            self.removeExtensions = removeExtensions
        }
    }

    /// Complete automated pipeline: Unpack -> Modify -> Inject -> Sign Components -> Sign Binary -> Repack
    public static func signIPA(sourceIPA: URL,
                               certificate: CertificateItem,
                               provision: ProvisionItem,
                               p12Data: Data,
                               provisionData: Data,
                               options: SigningOptions,
                               outputDirectory: URL,
                               progress: @escaping (String, Double) -> Void) throws -> SignedAppItem {
        let fileManager = FileManager.default
        let sessionID = UUID().uuidString
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("KSign_\(sessionID)")

        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Step 1: Unpack IPA
        progress("Extracting IPA archive...", 0.1)
        try ZipArchiveHelper.unzip(archiveURL: sourceIPA, destinationURL: tempDir) { unzipPct in
            progress("Extracting IPA archive...", 0.1 + (unzipPct * 0.2))
        }

        let payloadDir = tempDir.appendingPathComponent("Payload")
        guard fileManager.fileExists(atPath: payloadDir.path) else {
            throw SignError.payloadNotFound(sourceIPA.lastPathComponent)
        }

        // Step 2: Locate .app bundle
        let payloadContents = try fileManager.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil)
        guard let appBundleURL = payloadContents.first(where: { $0.pathExtension == "app" }) else {
            throw SignError.appBundleNotFound(sourceIPA.lastPathComponent)
        }

        progress("Configuring bundle identifiers and plists...", 0.35)

        // Step 3: Handle extensions if requested
        if options.removeExtensions {
            let pluginsDir = appBundleURL.appendingPathComponent("PlugIns")
            if fileManager.fileExists(atPath: pluginsDir.path) {
                try? fileManager.removeItem(at: pluginsDir)
            }
        }

        // Step 4: Modify Info.plist
        let effectiveBundleID = options.newBundleID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? options.newBundleID!
            : (provision.bundleIdentifier.contains("*") ? "com.ksign.signed.\(UUID().uuidString.prefix(8))" : provision.bundleIdentifier)

        let modifiedPlist = try PlistHelper.modifyInfoPlist(
            at: appBundleURL,
            newBundleID: effectiveBundleID,
            newDisplayName: options.newDisplayName,
            newVersion: options.newVersion
        )

        let appName = (modifiedPlist["CFBundleDisplayName"] as? String)
            ?? (modifiedPlist["CFBundleName"] as? String)
            ?? appBundleURL.deletingPathExtension().lastPathComponent
        let appVersion = (modifiedPlist["CFBundleShortVersionString"] as? String) ?? "1.0"
        let executableName = modifiedPlist["CFBundleExecutable"] as? String ?? ""

        guard !executableName.isEmpty else {
            throw SignError.missingExecutable(appBundleURL.lastPathComponent)
        }

        // Step 5: Replace embedded.mobileprovision
        progress("Embedding provisioning profile...", 0.45)
        let embeddedProvURL = appBundleURL.appendingPathComponent("embedded.mobileprovision")
        if fileManager.fileExists(atPath: embeddedProvURL.path) {
            try? fileManager.removeItem(at: embeddedProvURL)
        }
        try provisionData.write(to: embeddedProvURL, options: .atomic)

        // Step 6: Inject Tweaks / Dylibs
        if !options.dylibsToInject.isEmpty {
            progress("Injecting dylibs into Mach-O load commands...", 0.55)
            for dylib in options.dylibsToInject {
                try DylibInjectorService.inject(dylibURL: dylib, intoAppBundle: appBundleURL, isWeak: false)
            }
        }

        // Step 7: Sign Internal Frameworks & Libraries (Inside-Out Signing)
        progress("Signing dynamic frameworks and libraries...", 0.65)
        let frameworksDir = appBundleURL.appendingPathComponent("Frameworks")
        if fileManager.fileExists(atPath: frameworksDir.path) {
            let fwContents = try fileManager.contentsOfDirectory(at: frameworksDir, includingPropertiesForKeys: nil)
            for item in fwContents {
                if item.pathExtension == "framework" {
                    let fwName = item.deletingPathExtension().lastPathComponent
                    let binaryURL = item.appendingPathComponent(fwName)
                    if fileManager.fileExists(atPath: binaryURL.path) {
                        _ = try? PlistHelper.generateCodeResources(appBundleURL: item)
                        _ = try? CoreSignEngine.signBinary(
                            atPath: binaryURL.path,
                            bundleID: "\(effectiveBundleID).framework.\(fwName)",
                            teamID: provision.teamID,
                            infoPlistData: nil,
                            codeResourcesData: nil,
                            entitlementsXml: provision.entitlementsXml,
                            entitlementsDer: nil,
                            p12Data: p12Data,
                            p12Password: certificate.password
                        )
                    }
                } else if item.pathExtension == "dylib" {
                    _ = try? CoreSignEngine.signBinary(
                        atPath: item.path,
                        bundleID: "\(effectiveBundleID).dylib.\(item.deletingPathExtension().lastPathComponent)",
                        teamID: provision.teamID,
                        infoPlistData: nil,
                        codeResourcesData: nil,
                        entitlementsXml: provision.entitlementsXml,
                        entitlementsDer: nil,
                        p12Data: p12Data,
                        p12Password: certificate.password
                    )
                }
            }
        }

        // Step 8: Generate Main Bundle CodeResources
        progress("Generating CodeResources SHA-256 seal...", 0.75)
        let codeResourcesData = try PlistHelper.generateCodeResources(appBundleURL: appBundleURL)

        // Step 9: Sign Main Mach-O Executable
        progress("Signing main application binary...", 0.85)
        let mainBinaryURL = appBundleURL.appendingPathComponent(executableName)
        let infoPlistData = try Data(contentsOf: appBundleURL.appendingPathComponent("Info.plist"))

        do {
            try CoreSignEngine.signBinary(
                atPath: mainBinaryURL.path,
                bundleID: effectiveBundleID,
                teamID: provision.teamID,
                infoPlistData: infoPlistData,
                codeResourcesData: codeResourcesData,
                entitlementsXml: provision.entitlementsXml,
                entitlementsDer: nil,
                p12Data: p12Data,
                p12Password: certificate.password
            )
        } catch {
            throw SignError.coreSigningFailed(error.localizedDescription)
        }

        // Step 10: Repack into final .ipa
        progress("Packaging signed IPA...", 0.92)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)

        let safeName = appName.replacingOccurrences(of: "/", with: "_")
        let finalFileName = "\(safeName)_signed_\(Int(Date().timeIntervalSince1970)).ipa"
        let outputIPAURL = outputDirectory.appendingPathComponent(finalFileName)

        try ZipArchiveHelper.zip(directoryURL: tempDir, outputArchiveURL: outputIPAURL)

        let finalAttributes = try fileManager.attributesOfItem(atPath: outputIPAURL.path)
        let finalSize = (finalAttributes[.size] as? Int64) ?? 0

        progress("Signing completed successfully!", 1.0)

        return SignedAppItem(
            name: appName,
            bundleIdentifier: effectiveBundleID,
            version: appVersion,
            localFileName: finalFileName,
            fileSize: finalSize,
            signedDate: Date(),
            iconFileName: nil
        )
    }
}
