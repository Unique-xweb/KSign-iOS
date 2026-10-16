// [LISTN] Sources/KSignApp/Views/SigningSheetView.swift
// Language: Swift 5.9 | File: SigningSheetView.swift | Target: Interactive IPA Signing Configuration Sheet
import SwiftUI

public struct SigningSheetView: View {
    let sourceFile: FileItem

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var certVM: CertificateViewModel
    @EnvironmentObject private var appVM: AppManagerViewModel
    @EnvironmentObject private var fileVM: FileManagerViewModel

    @State private var bundleID: String = ""
    @State private var displayName: String = ""
    @State private var version: String = ""
    @State private var removeExtensions: Bool = false
    @State private var selectedDylibs: Set<URL> = []

    @State private var isSigning: Bool = false
    @State private var signingStatus: String = ""
    @State private var signingProgress: Double = 0.0
    @State private var errorMessage: String? = nil

    public var body: some View {
        NavigationView {
            Form {
                // Section: App Metadata
                Section(header: Text("Application Metadata")) {
                    HStack {
                        Image(systemName: "app.badge.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sourceFile.name)
                                .font(.headline)
                            Text(sourceFile.formattedSize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    TextField("Bundle ID (Optional Override)", text: $bundleID)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Display Name (Optional)", text: $displayName)
                    TextField("Version (Optional)", text: $version)
                }

                // Section: Certificate & Provisioning Selection
                Section(header: Text("Signing Credentials")) {
                    if let cert = certVM.activeCertificate {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cert.teamName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Expires: \(cert.formattedExpiration)")
                                    .font(.caption)
                                    .foregroundColor(cert.isExpired ? .red : .secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                        }
                    } else {
                        NavigationLink(destination: Text("Please import a Certificate in the Certificates tab.")) {
                            Text("No Active Certificate Selected")
                                .foregroundColor(.red)
                        }
                    }

                    if let prov = certVM.activeProvision {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Provision: \(prov.name)")
                                    .font(.subheadline)
                                Text("Team ID: \(prov.teamID)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                        }
                    } else {
                        Text("No Matching Mobileprovision")
                            .foregroundColor(.orange)
                    }
                }

                // Section: Dylib Injection
                Section(header: Text("Tweak / Dylib Injection")) {
                    let dylibFiles = fileVM.files.filter { $0.extensionType == .dylib || $0.extensionType == .deb }
                    if dylibFiles.isEmpty {
                        Text("No .dylib or .deb files found in Documents.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(dylibFiles) { item in
                            HStack {
                                Image(systemName: "puzzlepiece.extension")
                                    .foregroundColor(.purple)
                                Text(item.name)
                                    .font(.subheadline)
                                Spacer()
                                if selectedDylibs.contains(item.url) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedDylibs.contains(item.url) {
                                    selectedDylibs.remove(item.url)
                                } else {
                                    selectedDylibs.insert(item.url)
                                }
                            }
                        }
                    }
                }

                // Section: Advanced Options
                Section(header: Text("Advanced Modifiers")) {
                    Toggle("Remove PlugIns & App Extensions", isOn: $removeExtensions)
                }

                // Section: Execution State
                if isSigning {
                    Section(header: Text("Signing Progress")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(signingStatus)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            ProgressView(value: signingProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Sign Package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSigning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: executeSigning) {
                        Text("Start Sign")
                            .fontWeight(.bold)
                    }
                    .disabled(isSigning || certVM.activeCertificate == nil || certVM.activeProvision == nil)
                }
            }
        }
    }

    private func executeSigning() {
        guard let cert = certVM.activeCertificate,
              let prov = certVM.activeProvision else {
            errorMessage = "Certificate or Mobileprovision missing."
            return
        }

        let certFile = certVM.certsDirectory.appendingPathComponent(cert.localFileName)
        let provFile = certVM.certsDirectory.appendingPathComponent(prov.localFileName)

        guard let p12Data = try? Data(contentsOf: certFile),
              let provData = try? Data(contentsOf: provFile) else {
            errorMessage = "Failed to read credential files from disk."
            return
        }

        isSigning = true
        signingProgress = 0.0
        signingStatus = "Starting signing engine..."
        errorMessage = nil

        let options = AppSignerService.SigningOptions(
            newBundleID: bundleID.isEmpty ? nil : bundleID,
            newDisplayName: displayName.isEmpty ? nil : displayName,
            newVersion: version.isEmpty ? nil : version,
            dylibsToInject: Array(selectedDylibs),
            removeExtensions: removeExtensions
        )

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let signedApp = try AppSignerService.signIPA(
                    sourceIPA: sourceFile.url,
                    certificate: cert,
                    provision: prov,
                    p12Data: p12Data,
                    provisionData: provData,
                    options: options,
                    outputDirectory: appVM.signedAppsDirectory
                ) { status, progress in
                    DispatchQueue.main.async {
                        self.signingStatus = status
                        self.signingProgress = progress
                    }
                }

                DispatchQueue.main.async {
                    self.isSigning = false
                    self.appVM.registerSignedApp(signedApp)
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSigning = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
