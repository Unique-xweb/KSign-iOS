// [LISTN] Sources/KSignApp/Services/DylibInjectorService.swift
// Language: Swift 5.9 | File: DylibInjectorService.swift | Target: Dynamic Library & Tweak Injection
import Foundation

public final class DylibInjectorService {

    public enum InjectorError: LocalizedError {
        case appNotFound(String)
        case executableNotFound(String)
        case dylibNotFound(String)
        case injectionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .appNotFound(let msg): return "Application bundle not found: \(msg)"
            case .executableNotFound(let msg): return "CFBundleExecutable binary not found: \(msg)"
            case .dylibNotFound(let msg): return "Dylib file missing: \(msg)"
            case .injectionFailed(let msg): return "Mach-O load command injection failed: \(msg)"
            }
        }
    }

    /// Injects a dylib into the primary executable of an unpacked .app bundle
    public static func inject(dylibURL: URL, intoAppBundle appURL: URL, isWeak: Bool = false) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: dylibURL.path) else {
            throw InjectorError.dylibNotFound(dylibURL.path)
        }

        let infoPlistURL = appURL.appendingPathComponent("Info.plist")
        guard let infoData = try? Data(contentsOf: infoPlistURL),
              let dict = try? PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any],
              let executableName = dict["CFBundleExecutable"] as? String else {
            throw InjectorError.appNotFound("Invalid Info.plist or missing CFBundleExecutable in \(appURL.path)")
        }

        let mainExecURL = appURL.appendingPathComponent(executableName)
        guard fileManager.fileExists(atPath: mainExecURL.path) else {
            throw InjectorError.executableNotFound(mainExecURL.path)
        }

        // 1. Ensure Frameworks folder exists in .app
        let frameworksDir = appURL.appendingPathComponent("Frameworks")
        if !fileManager.fileExists(atPath: frameworksDir.path) {
            try fileManager.createDirectory(at: frameworksDir, withIntermediateDirectories: true, attributes: nil)
        }

        // 2. Copy dylib into Frameworks
        let destDylibURL = frameworksDir.appendingPathComponent(dylibURL.lastPathComponent)
        if fileManager.fileExists(atPath: destDylibURL.path) {
            try fileManager.removeItem(at: destDylibURL)
        }
        try fileManager.copyItem(at: dylibURL, to: destDylibURL)

        // 3. Construct @rpath reference
        let loadCommandPath = "@rpath/\(dylibURL.lastPathComponent)"

        // 4. Invoke CoreSignEngine C++ Mach-O injector
        do {
            try CoreSignEngine.injectDylib(atPath: loadCommandPath, intoBinaryAtPath: mainExecURL.path, isWeak: isWeak)
        } catch {
            throw InjectorError.injectionFailed(error.localizedDescription)
        }
    }
}
