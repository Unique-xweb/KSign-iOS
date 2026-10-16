// [LISTN] Sources/KSignApp/Views/InjectSheetView.swift
// Language: Swift 5.9 | File: InjectSheetView.swift | Target: Mach-O Tweak Injection Configuration Sheet
import SwiftUI

public struct InjectSheetView: View {
    let sourceFile: FileItem

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fileVM: FileManagerViewModel

    @State private var selectedDylib: FileItem? = nil
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var statusMessage: String = ""

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Target IPA Archive")) {
                    HStack {
                        Image(systemName: "app.badge.fill")
                            .foregroundColor(.blue)
                        Text(sourceFile.name)
                            .font(.headline)
                    }
                }

                Section(header: Text("Select Dylib / Tweak to Inject")) {
                    let dylibs = fileVM.files.filter { $0.extensionType == .dylib || $0.extensionType == .deb }
                    if dylibs.isEmpty {
                        Text("No .dylib files available in Documents.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(dylibs) { item in
                            HStack {
                                Image(systemName: "puzzlepiece.extension.fill")
                                    .foregroundColor(.purple)
                                Text(item.name)
                                Spacer()
                                if selectedDylib?.id == item.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDylib = item
                            }
                        }
                    }
                }

                if isProcessing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(statusMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
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
            .navigationTitle("Inject Tweak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Inject") {
                        executeInject()
                    }
                    .disabled(isProcessing || selectedDylib == nil)
                }
            }
        }
    }

    private func executeInject() {
        guard let dylib = selectedDylib else { return }
        isProcessing = true
        errorMessage = nil
        statusMessage = "Unpacking and injecting LC_LOAD_DYLIB..."

        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Inject_\(UUID().uuidString)")

            do {
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                defer { try? fileManager.removeItem(at: tempDir) }

                try ZipArchiveHelper.unzip(archiveURL: sourceFile.url, destinationURL: tempDir)

                let payloadDir = tempDir.appendingPathComponent("Payload")
                let contents = try fileManager.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil)
                guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                    throw NSError(domain: "com.ksign.inject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid payload bundle."])
                }

                try DylibInjectorService.inject(dylibURL: dylib.url, intoAppBundle: appBundle, isWeak: false)

                let outputName = "\(sourceFile.url.deletingPathExtension().lastPathComponent)_patched.ipa"
                let outputURL = fileVM.documentsDirectory.appendingPathComponent(outputName)

                try ZipArchiveHelper.zip(directoryURL: tempDir, destinationArchiveURL: outputURL)

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.fileVM.loadFiles()
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
