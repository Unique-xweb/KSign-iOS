// [LISTN] Sources/KSignApp/Views/SettingsView.swift
// Language: Swift 5.9 | File: SettingsView.swift | Target: KSign Application & Installation Server Settings Tab
import SwiftUI
import UIKit

public struct SettingsView: View {
    @AppStorage("defaultBundleIDPrefix") private var defaultBundleIDPrefix: String = "com.ksign.signed"
    @AppStorage("defaultNameSuffix") private var defaultNameSuffix: String = ""
    @AppStorage("removeExtensionsByDefault") private var removeExtensionsByDefault: Bool = false
    @AppStorage("serverPort") private var serverPort: Int = 8443

    @ObservedObject private var installServer = LocalInstallServer.shared
    @State private var cacheClearedAlert: Bool = false

    public var body: some View {
        NavigationView {
            Form {
                // Section: Default Signing Options
                Section(header: Text("Default Signing Rules")) {
                    HStack {
                        Text("Bundle ID Prefix")
                        Spacer()
                        TextField("com.domain", text: $defaultBundleIDPrefix)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    HStack {
                        Text("Name Suffix")
                        Spacer()
                        TextField("e.g. (Signed)", text: $defaultNameSuffix)
                            .multilineTextAlignment(.trailing)
                    }

                    Toggle("Strip Extensions / PlugIns", isOn: $removeExtensionsByDefault)
                }

                // Section: Local Installation Server
                Section(header: Text("Local Installation Server (itms-services)"),
                        footer: Text("Apple's on-device installd daemon fetches manifests via HTTPS on localhost. Trusting the local CA allows zero-computer sideloading.")) {
                    HStack {
                        Text("Server Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(installServer.isRunning ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(installServer.isRunning ? "Running" : "Stopped")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Local Port")
                        Spacer()
                        TextField("8443", value: $serverPort, formatter: NumberFormatter())
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Button(action: toggleServer) {
                        Text(installServer.isRunning ? "Restart Server" : "Start Server")
                            .foregroundColor(.blue)
                    }

                    Button(action: installLocalRootCA) {
                        HStack {
                            Image(systemName: "checkmark.shield")
                                .foregroundColor(.purple)
                            Text("Install Local Root CA Profile")
                                .foregroundColor(.primary)
                        }
                    }
                }

                // Section: Maintenance
                Section(header: Text("Maintenance")) {
                    Button(action: clearTemporaryFiles) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Clear Temporary Cache")
                                .foregroundColor(.red)
                        }
                    }
                }

                // Section: About
                Section(header: Text("About KSign")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Darwin arm64)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Engine")
                        Spacer()
                        Text("Native C++ Mach-O / OpenSSL 1.1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Cache Cleared", isPresented: $cacheClearedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All temporary unpack files and signing artifacts have been deleted.")
            }
        }
    }

    private func toggleServer() {
        if installServer.isRunning {
            installServer.stopServer()
        }
        try? installServer.startServer(port: UInt16(serverPort))
    }

    private func installLocalRootCA() {
        if !installServer.isRunning {
            try? installServer.startServer(port: UInt16(serverPort))
        }
        let caURLString = "https://127.0.0.1:\(serverPort)/ca.mobileconfig"
        if let url = URL(string: caURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func clearTemporaryFiles() {
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        if let contents = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in contents {
                if file.lastPathComponent.hasPrefix("KSign_") || file.lastPathComponent.hasPrefix("Inject_") {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
        cacheClearedAlert = true
    }
}
