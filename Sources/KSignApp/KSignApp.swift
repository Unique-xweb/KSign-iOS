// [LISTN] Sources/KSignApp/KSignApp.swift
// Language: Swift 5.9 | File: KSignApp.swift | Target: Application Entry Point & Global Environment Injector
import SwiftUI

@main
struct KSignApp: App {
    @StateObject private var fileVM = FileManagerViewModel()
    @StateObject private var certVM = CertificateViewModel()
    @StateObject private var appVM = AppManagerViewModel()

    init() {
        // Start local installation server in background
        do {
            try LocalInstallServer.shared.startServer(port: 8443)
        } catch {
            print("[!] Could not auto-start local install server: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(fileVM)
                .environmentObject(certVM)
                .environmentObject(appVM)
                .preferredColorScheme(.dark)
        }
    }
}
