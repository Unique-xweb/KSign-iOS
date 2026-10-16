// [LISTN] Sources/KSignApp/Views/CertificatesView.swift
// Language: Swift 5.9 | File: CertificatesView.swift | Target: KSign Certificate & Mobileprovision Management Tab
import SwiftUI
import UniformTypeIdentifiers

public struct CertificatesView: View {
    @EnvironmentObject private var certVM: CertificateViewModel

    @State private var showingP12Picker: Bool = false
    @State private var showingProvPicker: Bool = false
    @State private var p12PasswordPrompt: Bool = false
    @State private var pendingP12URL: URL? = nil
    @State private var p12PasswordInput: String = ""

    public var body: some View {
        NavigationView {
            List {
                // Section: Active Signing Pair Summary
                if let activeCert = certVM.activeCertificate {
                    Section(header: Text("Active Signing Pair")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activeCert.teamName)
                                        .font(.headline)
                                    Text("Team ID: \(activeCert.teamID.isEmpty ? "Standard" : activeCert.teamID)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                StatusBadge(isExpired: activeCert.isExpired, days: activeCert.daysRemaining)
                            }

                            Divider()

                            if let prov = certVM.activeProvision {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(prov.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("App ID: \(prov.bundleIdentifier)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("No matching .mobileprovision linked")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Section: PKCS#12 Certificates
                Section(header: Text("Certificates (.p12)")) {
                    if certVM.certificates.isEmpty {
                        Text("No certificates imported yet. Tap '+' to add a .p12")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(certVM.certificates) { cert in
                            certificateRow(cert)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    certVM.setActiveCertificate(cert)
                                }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                certVM.deleteCertificate(certVM.certificates[index])
                            }
                        }
                    }
                }

                // Section: Mobileprovisions
                Section(header: Text("Provisioning Profiles (.mobileprovision)")) {
                    if certVM.provisions.isEmpty {
                        Text("No profiles imported yet. Tap '+' to add a .mobileprovision")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(certVM.provisions) { prov in
                            provisionRow(prov)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                certVM.deleteProvision(certVM.provisions[index])
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Certificates")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingP12Picker = true }) {
                            Label("Import .p12 Certificate", systemImage: "key.fill")
                        }
                        Button(action: { showingProvPicker = true }) {
                            Label("Import .mobileprovision", systemImage: "doc.text.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
            }
            // P12 File Picker
            .fileImporter(
                isPresented: $showingP12Picker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    pendingP12URL = url
                    p12PasswordInput = ""
                    p12PasswordPrompt = true
                }
            }
            // Mobileprovision Picker
            .fileImporter(
                isPresented: $showingProvPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = certVM.importMobileprovision(sourceURL: url)
                }
            }
            // Password Alert
            .alert("Certificate Password", isPresented: $p12PasswordPrompt) {
                SecureField("Password", text: $p12PasswordInput)
                Button("Unlock & Import") {
                    if let url = pendingP12URL {
                        _ = certVM.importP12(sourceURL: url, password: p12PasswordInput)
                        pendingP12URL = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingP12URL = nil }
            } message: {
                Text("Enter the password for \(pendingP12URL?.lastPathComponent ?? "certificate")")
            }
        }
    }

    private func certificateRow(_ cert: CertificateItem) -> some View {
        HStack {
            Image(systemName: cert.isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(cert.isActive ? .green : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(cert.commonName)
                    .font(.system(size: 15, weight: .medium))
                HStack(spacing: 6) {
                    Text("Team: \(cert.teamName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(cert.formattedExpiration)
                        .font(.caption2)
                        .foregroundColor(cert.isExpired ? .red : .secondary)
                }
            }

            Spacer()
            StatusBadge(isExpired: cert.isExpired, days: cert.daysRemaining)
        }
        .padding(.vertical, 4)
    }

    private func provisionRow(_ prov: ProvisionItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(prov.name)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                StatusBadge(isExpired: prov.isExpired, days: prov.daysRemaining)
            }
            Text("App ID: \(prov.bundleIdentifier)")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Text("Team: \(prov.teamName) (\(prov.teamID))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("•")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(prov.deviceUDIDs.count) UDIDs")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let isExpired: Bool
    let days: Int

    var body: some View {
        if isExpired {
            Text("Expired")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red)
                .cornerRadius(8)
        } else {
            Text("\(days)d left")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(days < 30 ? Color.orange : Color.green)
                .cornerRadius(8)
        }
    }
}
