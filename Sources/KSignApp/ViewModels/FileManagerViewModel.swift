// [LISTN] Sources/KSignApp/ViewModels/FileManagerViewModel.swift
// Language: Swift 5.9 | File: FileManagerViewModel.swift | Target: File Management & Download Coordinator
import Foundation
import SwiftUI
import Combine

public final class FileManagerViewModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published public var files: [FileItem] = []
    @Published public var selectedFilter: FileExtensionType? = nil
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadStatus: String = ""
    @Published public var errorMessage: String? = nil

    private let fileManager = FileManager.default
    private var downloadTask: URLSessionDownloadTask?
    private var activeDownloadDestination: URL?

    public var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public var filteredFiles: [FileItem] {
        if let filter = selectedFilter {
            return files.filter { $0.extensionType == filter }
        }
        return files
    }

    public override init() {
        super.init()
        loadFiles()
    }

    public func loadFiles() {
        do {
            let urls = try fileManager.contentsOfDirectory(at: documentsDirectory,
                                                           includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                           options: [.skipsHiddenFiles])
            self.files = urls
                .filter { !$0.hasDirectoryPath }
                .map { FileItem(url: $0) }
                .sorted { $0.modificationDate > $1.modificationDate }
        } catch {
            self.errorMessage = "Failed to list documents: \(error.localizedDescription)"
        }
    }

    public func importFile(from sourceURL: URL) {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            self.errorMessage = "Permission denied accessing security scoped resource"
            return
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let destURL = documentsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)
            loadFiles()
        } catch {
            self.errorMessage = "Failed to import file: \(error.localizedDescription)"
        }
    }

    public func deleteFile(_ item: FileItem) {
        do {
            try fileManager.removeItem(at: item.url)
            loadFiles()
        } catch {
            self.errorMessage = "Failed to delete file: \(error.localizedDescription)"
        }
    }

    public func unpackFile(_ item: FileItem) {
        guard item.extensionType == .ipa else { return }
        let destDir = documentsDirectory.appendingPathComponent(item.url.deletingPathExtension().lastPathComponent)
        do {
            try ZipArchiveHelper.unzip(archiveURL: item.url, destinationURL: destDir)
            loadFiles()
        } catch {
            self.errorMessage = "Unpack error: \(error.localizedDescription)"
        }
    }

    // MARK: - Direct Web Download
    public func startDirectDownload(urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            self.errorMessage = "Invalid download URL provided."
            return
        }

        let fileName = url.lastPathComponent.isEmpty ? "download_\(Int(Date().timeIntervalSince1970)).ipa" : url.lastPathComponent
        self.activeDownloadDestination = documentsDirectory.appendingPathComponent(fileName)

        self.isDownloading = true
        self.downloadProgress = 0.0
        self.downloadStatus = "Connecting..."

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        downloadStatus = ""
    }

    // MARK: - URLSessionDownloadDelegate
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            DispatchQueue.main.async {
                self.downloadProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                let current = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
                self.downloadStatus = "\(current) of \(total)"
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let dest = activeDownloadDestination else { return }
        do {
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadProgress = 1.0
                self.downloadStatus = "Completed"
                self.loadFiles()
            }
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.errorMessage = "Failed to save downloaded file: \(error.localizedDescription)"
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.errorMessage = "Download error: \(error.localizedDescription)"
            }
        }
    }
}
