// [LISTN] Sources/KSignApp/Views/FilesView.swift
// Language: Swift 5.9 | File: FilesView.swift | Target: KSign Files Management Tab
import SwiftUI
import UniformTypeIdentifiers

public struct FilesView: View {
    @EnvironmentObject private var fileVM: FileManagerViewModel
    @EnvironmentObject private var certVM: CertificateViewModel

    @State private var showingFileImporter: Bool = false
    @State private var showingDownloadSheet: Bool = false
    @State private var downloadURLString: String = ""

    @State private var signingTargetFile: FileItem? = nil
    @State private var injectTargetFile: FileItem? = nil

    @State private var p12PasswordPrompt: Bool = false
    @State private var pendingP12File: FileItem? = nil
    @State private var p12PasswordInput: String = ""

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Extension Filter Chips
                filterBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))

                // Download Progress Banner
                if fileVM.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Downloading...")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            Text(fileVM.downloadStatus)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Button(action: { fileVM.cancelDownload() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        ProgressView(value: fileVM.downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.tertiarySystemBackground))
                }

                // File List
                if fileVM.filteredFiles.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No files in Documents")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap + to import an IPA, dylib, or certificate.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(fileVM.filteredFiles) { item in
                            fileRow(item)
                                .contextMenu {
                                    fileContextMenu(item)
                                }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                fileVM.deleteFile(fileVM.filteredFiles[index])
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .refreshable {
                        fileVM.loadFiles()
                    }
                }
            }
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingFileImporter = true }) {
                            Label("Import File", systemImage: "doc.badge.plus")
                        }
                        Button(action: { showingDownloadSheet = true }) {
                            Label("Download via Link", systemImage: "link")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                    }
                }
            }
            // Sheets
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        fileVM.importFile(from: url)
                    }
                case .failure(let error):
                    fileVM.errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingDownloadSheet) {
                downloadLinkSheet
            }
            .sheet(item: $signingTargetFile) { item in
                SigningSheetView(sourceFile: item)
            }
            .sheet(item: $injectTargetFile) { item in
                InjectSheetView(sourceFile: item)
            }
            .alert("PKCS#12 Password", isPresented: $p12PasswordPrompt) {
                SecureField("Certificate Password", text: $p12PasswordInput)
                Button("Import", action: importPendingP12)
                Button("Cancel", role: .cancel) { pendingP12File = nil }
            } message: {
                Text("Enter the password for \(pendingP12File?.name ?? "certificate")")
            }
        }
    }

    // MARK: - Filter Bar
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: fileVM.selectedFilter == nil) {
                    fileVM.selectedFilter = nil
                }
                ForEach(FileExtensionType.allCases) { extType in
                    FilterChip(title: extType.rawValue.uppercased(), isSelected: fileVM.selectedFilter == extType) {
                        fileVM.selectedFilter = extType
                    }
                }
            }
        }
    }

    // MARK: - File Row Item
    private func fileRow(_ item: FileItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: item.extensionType.badgeColorHex).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: item.extensionType.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: item.extensionType.badgeColorHex))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            if item.extensionType == .ipa {
                Button(action: { signingTargetFile = item }) {
                    Text("Sign")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(14)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Context Menu
    @ViewBuilder
    private func fileContextMenu(_ item: FileItem) -> some View {
        if item.extensionType == .ipa {
            Button(action: { signingTargetFile = item }) {
                Label("Sign / ติดตั้ง", systemImage: "signature")
            }
            Button(action: { injectTargetFile = item }) {
                Label("Inject Tweak", systemImage: "puzzlepiece.extension")
            }
            Button(action: { fileVM.unpackFile(item) }) {
                Label("Unpack / แตกไฟล์", systemImage: "archivebox")
            }
        } else if item.extensionType == .p12 {
            Button(action: {
                pendingP12File = item
                p12PasswordInput = ""
                p12PasswordPrompt = true
            }) {
                Label("Import to Certificates", systemImage: "key.fill")
            }
        } else if item.extensionType == .mobileprovision {
            Button(action: {
                _ = certVM.importMobileprovision(sourceURL: item.url)
            }) {
                Label("Import Provision", systemImage: "doc.text.fill")
            }
        }

        Button(role: .destructive, action: { fileVM.deleteFile(item) }) {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Download Sheet
    private var downloadLinkSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Direct Download URL")) {
                    TextField("https://example.com/app.ipa", text: $downloadURLString)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Download File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingDownloadSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") {
                        fileVM.startDirectDownload(urlString: downloadURLString)
                        downloadURLString = ""
                        showingDownloadSheet = false
                    }
                    .disabled(downloadURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func importPendingP12() {
        guard let item = pendingP12File else { return }
        _ = certVM.importP12(sourceURL: item.url, password: p12PasswordInput)
        pendingP12File = nil
    }
}

// MARK: - UI Components
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(UIColor.systemBackground))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: isSelected ? 0 : 1)
                )
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
