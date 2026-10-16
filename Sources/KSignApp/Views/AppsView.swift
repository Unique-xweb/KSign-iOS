// [LISTN] Sources/KSignApp/Views/AppsView.swift
// Language: Swift 5.9 | File: AppsView.swift | Target: KSign Installed / Signed Applications Tab
import SwiftUI

public struct AppsView: View {
    @EnvironmentObject private var appVM: AppManagerViewModel
    @State private var searchText: String = ""

    public var filteredApps: [SignedAppItem] {
        if searchText.isEmpty {
            return appVM.signedApps
        }
        return appVM.signedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        NavigationView {
            VStack {
                if appVM.signedApps.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Signed Apps")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Sign an IPA from the Files tab to start installing.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredApps) { app in
                            appRow(app)
                                .contextMenu {
                                    Button(action: { appVM.installApp(app) }) {
                                        Label("Install via itms-services", systemImage: "arrow.down.app")
                                    }
                                    Button(action: { appVM.shareApp(app) }) {
                                        Label("Share / Export IPA", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive, action: { appVM.deleteApp(app) }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                appVM.deleteApp(filteredApps[index])
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .searchable(text: $searchText, prompt: "Search signed apps...")
                    .refreshable {
                        appVM.loadMetadata()
                    }
                }
            }
            .navigationTitle("Signed Apps")
        }
    }

    private func appRow(_ app: SignedAppItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "app.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("v\(app.version)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.tertiarySystemFill))
                        .cornerRadius(4)
                    Text(app.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(app.formattedSignedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { appVM.installApp(app) }) {
                Text("Install")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .cornerRadius(16)
            }
        }
        .padding(.vertical, 6)
    }
}
