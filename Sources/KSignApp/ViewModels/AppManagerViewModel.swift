// [LISTN] Sources/KSignApp/ViewModels/AppManagerViewModel.swift
// Language: Swift 5.9 | File: AppManagerViewModel.swift | Target: Signed Applications Registry & Installation Flow
import Foundation
import SwiftUI
import UIKit

public final class AppManagerViewModel: ObservableObject {
    @Published public var signedApps: [SignedAppItem] = []
    @Published public var errorMessage: String?

    private let fileManager = FileManager.default

    public var signedAppsDirectory: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SignedApps")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    private var appsMetadataURL: URL {
        signedAppsDirectory.appendingPathComponent("signed_apps.json")
    }

    public init() {
        loadMetadata()
    }

    public func loadMetadata() {
        if let data = try? Data(contentsOf: appsMetadataURL),
           let items = try? JSONDecoder().decode([SignedAppItem].self, from: data) {
            self.signedApps = items.sorted { $0.signedDate > $1.signedDate }
        }
    }

    public func saveMetadata() {
        if let data = try? JSONEncoder().encode(signedApps) {
            try? data.write(to: appsMetadataURL, options: .atomic)
        }
    }

    public func registerSignedApp(_ app: SignedAppItem) {
        signedApps.removeAll { $0.id == app.id }
        signedApps.insert(app, at: 0)
        saveMetadata()
    }

    public func installApp(_ app: SignedAppItem) {
        let ipaURL = signedAppsDirectory.appendingPathComponent(app.localFileName)
        guard fileManager.fileExists(atPath: ipaURL.path) else {
            errorMessage = "IPA binary file missing on disk."
            return
        }
        LocalInstallServer.shared.triggerInstall(app: app, ipaURL: ipaURL)
    }

    public func shareApp(_ app: SignedAppItem) {
        let ipaURL = signedAppsDirectory.appendingPathComponent(app.localFileName)
        guard fileManager.fileExists(atPath: ipaURL.path) else { return }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [ipaURL], applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }

    public func deleteApp(_ app: SignedAppItem) {
        let ipaURL = signedAppsDirectory.appendingPathComponent(app.localFileName)
        try? fileManager.removeItem(at: ipaURL)
        signedApps.removeAll { $0.id == app.id }
        saveMetadata()
    }
}
