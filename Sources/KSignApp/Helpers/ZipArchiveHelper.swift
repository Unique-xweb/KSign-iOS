// [LISTN] Sources/KSignApp/Helpers/ZipArchiveHelper.swift
// Language: Swift 5.9 | File: ZipArchiveHelper.swift | Target: In-Memory / Streaming Zip Archiver & Extractor
import Foundation
import zlib

public final class ZipArchiveHelper {

    public enum ZipError: LocalizedError {
        case fileNotFound(String)
        case invalidArchive(String)
        case compressionFailed(String)
        case decompressionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let msg): return "File not found: \(msg)"
            case .invalidArchive(let msg): return "Corrupt or invalid zip archive: \(msg)"
            case .compressionFailed(let msg): return "Compression failure: \(msg)"
            case .decompressionFailed(let msg): return "Decompression failure: \(msg)"
            }
        }
    }

    private struct ZipEntry {
        var relativePath: String
        var isDirectory: Bool
        var uncompressedSize: UInt32
        var compressedSize: UInt32
        var crc32Value: UInt32
        var localHeaderOffset: UInt32
    }

    // MARK: - Unzip IPA Archive
    public static func unzip(archiveURL: URL, destinationURL: URL, progress: ((Double) -> Void)? = nil) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)

        guard let fileHandle = try? FileHandle(forReadingFrom: archiveURL) else {
            throw ZipError.fileNotFound(archiveURL.path)
        }
        defer { try? fileHandle.close() }

        let fileSize = try fileManager.attributesOfItem(atPath: archiveURL.path)[.size] as? UInt64 ?? 0
        guard fileSize > 22 else {
            throw ZipError.invalidArchive("File too small to be a zip archive")
        }

        var offset: UInt64 = 0

        while offset < fileSize - 4 {
            try fileHandle.seek(toOffset: offset)
            let sigData = fileHandle.readData(ofLength: 4)
            guard sigData.count == 4 else { break }

            let sig = sigData.withUnsafeBytes { $0.load(as: UInt32.self) }

            // Local file header signature: 0x04034b50
            if sig == 0x04034b50 {
                let headerData = fileHandle.readData(ofLength: 26)
                guard headerData.count == 26 else { break }

                let compMethod = headerData.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self) }
                let compSize = headerData.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self) }
                let uncompSize = headerData.subdata(in: 18..<22).withUnsafeBytes { $0.load(as: UInt32.self) }
                let nameLen = headerData.subdata(in: 22..<24).withUnsafeBytes { $0.load(as: UInt16.self) }
                let extraLen = headerData.subdata(in: 24..<26).withUnsafeBytes { $0.load(as: UInt16.self) }

                let nameData = fileHandle.readData(ofLength: Int(nameLen))
                let relativePath = String(data: nameData, encoding: .utf8) ?? "unknown_\(offset)"

                // Skip extra field
                if extraLen > 0 {
                    _ = fileHandle.readData(ofLength: Int(extraLen))
                }

                let targetURL = destinationURL.appendingPathComponent(relativePath)

                if relativePath.hasSuffix("/") {
                    try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
                } else {
                    try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

                    let compressedData = fileHandle.readData(ofLength: Int(compSize))
                    let uncompressedData: Data

                    if compMethod == 0 { // Stored
                        uncompressedData = compressedData
                    } else if compMethod == 8 { // Deflated
                        uncompressedData = try inflateData(compressedData, expectedSize: Int(uncompSize))
                    } else {
                        uncompressedData = compressedData
                    }

                    try uncompressedData.write(to: targetURL, options: .atomic)
                }

                offset = try fileHandle.offset()
                if fileSize > 0 {
                    progress?(Double(offset) / Double(fileSize))
                }
            } else if sig == 0x02014b50 || sig == 0x06054b50 {
                // Central Directory or End of Central Directory reached
                break
            } else {
                offset += 1
            }
        }

        progress?(1.0)
    }

    // MARK: - Zip App Bundle into IPA
    public static func zip(directoryURL: URL, destinationArchiveURL: URL, progress: ((Double) -> Void)? = nil) throws {
        try zip(directoryURL: directoryURL, outputArchiveURL: destinationArchiveURL, progress: progress)
    }

    public static func zip(directoryURL: URL, outputArchiveURL: URL, progress: ((Double) -> Void)? = nil) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputArchiveURL.path) {
            try fileManager.removeItem(at: outputArchiveURL)
        }

        fileManager.createFile(atPath: outputArchiveURL.path, contents: nil, attributes: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputArchiveURL) else {
            throw ZipError.fileNotFound("Cannot open \(outputArchiveURL.path) for writing.")
        }
        defer { try? outputHandle.close() }

        guard let enumerator = fileManager.enumerator(at: directoryURL,
                                                      includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                      options: [],
                                                      errorHandler: nil) else {
            throw ZipError.fileNotFound(directoryURL.path)
        }

        var entries: [ZipEntry] = []
        let baseURL = directoryURL.deletingLastPathComponent()
        let baseLength = baseURL.path.hasSuffix("/") ? baseURL.path.count : baseURL.path.count + 1

        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            guard path.count >= baseLength else { continue }
            let relativePath = String(path.dropFirst(baseLength))
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            let currentOffset = UInt32(try outputHandle.offset())

            if isDir {
                let dirPath = relativePath.hasSuffix("/") ? relativePath : relativePath + "/"
                let header = buildLocalHeader(path: dirPath, crc: 0, compSize: 0, uncompSize: 0, compMethod: 0)
                try outputHandle.write(contentsOf: header)
                entries.append(ZipEntry(relativePath: dirPath, isDirectory: true, uncompressedSize: 0, compressedSize: 0, crc32Value: 0, localHeaderOffset: currentOffset))
            } else {
                let data = try Data(contentsOf: fileURL)
                let crc = UInt32(crc32(0, [UInt8](data), uInt(data.count)))
                let compressed = try deflateData(data)

                let compMethod: UInt16 = compressed.count < data.count ? 8 : 0
                let payloadData = compMethod == 8 ? compressed : data
                let compSize = UInt32(payloadData.count)
                let uncompSize = UInt32(data.count)

                let header = buildLocalHeader(path: relativePath, crc: crc, compSize: compSize, uncompSize: uncompSize, compMethod: compMethod)
                try outputHandle.write(contentsOf: header)
                try outputHandle.write(contentsOf: payloadData)

                entries.append(ZipEntry(relativePath: relativePath,
                                        isDirectory: false,
                                        uncompressedSize: uncompSize,
                                        compressedSize: compSize,
                                        crc32Value: crc,
                                        localHeaderOffset: currentOffset))
            }
        }

        // Central Directory
        let cdOffset = UInt32(try outputHandle.offset())
        for entry in entries {
            let cdRecord = buildCentralDirectoryRecord(entry: entry)
            try outputHandle.write(contentsOf: cdRecord)
        }
        let cdSize = UInt32(try outputHandle.offset()) - cdOffset

        // End of Central Directory
        let eocd = buildEOCD(entriesCount: UInt16(entries.count), cdSize: cdSize, cdOffset: cdOffset)
        try outputHandle.write(contentsOf: eocd)
        progress?(1.0)
    }

    // MARK: - Internal Compression Primitives
    private static func buildLocalHeader(path: String, crc: UInt32, compSize: UInt32, uncompSize: UInt32, compMethod: UInt16) -> Data {
        var data = Data()
        var sig: UInt32 = 0x04034b50
        var version: UInt16 = 20
        var bitFlag: UInt16 = 0
        var method: UInt16 = compMethod
        var modTime: UInt16 = 0
        var modDate: UInt16 = 0
        var crcVal = crc
        var cSize = compSize
        var uSize = uncompSize
        var nameLen = UInt16(path.utf8.count)
        var extraLen: UInt16 = 0

        data.append(Data(bytes: &sig, count: 4))
        data.append(Data(bytes: &version, count: 2))
        data.append(Data(bytes: &bitFlag, count: 2))
        data.append(Data(bytes: &method, count: 2))
        data.append(Data(bytes: &modTime, count: 2))
        data.append(Data(bytes: &modDate, count: 2))
        data.append(Data(bytes: &crcVal, count: 4))
        data.append(Data(bytes: &cSize, count: 4))
        data.append(Data(bytes: &uSize, count: 4))
        data.append(Data(bytes: &nameLen, count: 2))
        data.append(Data(bytes: &extraLen, count: 2))
        data.append(path.data(using: String.Encoding.utf8) ?? Data())
        return data
    }

    private static func buildCentralDirectoryRecord(entry: ZipEntry) -> Data {
        var data = Data()
        var sig: UInt32 = 0x02014b50
        var versionMadeBy: UInt16 = 0x0314 // UNIX 2.0
        var versionNeeded: UInt16 = 20
        var bitFlag: UInt16 = 0
        var method: UInt16 = entry.isDirectory ? 0 : (entry.compressedSize < entry.uncompressedSize ? 8 : 0)
        var modTime: UInt16 = 0
        var modDate: UInt16 = 0
        var crcVal = entry.crc32Value
        var cSize = entry.compressedSize
        var uSize = entry.uncompressedSize
        var nameLen = UInt16(entry.relativePath.utf8.count)
        var extraLen: UInt16 = 0
        var commentLen: UInt16 = 0
        var diskStart: UInt16 = 0
        var intAttrs: UInt16 = 0
        var extAttrs: UInt32 = entry.isDirectory ? 0x41ED0010 : 0x81A40000 // 0755 dir, 0644 file
        var offset = entry.localHeaderOffset

        data.append(Data(bytes: &sig, count: 4))
        data.append(Data(bytes: &versionMadeBy, count: 2))
        data.append(Data(bytes: &versionNeeded, count: 2))
        data.append(Data(bytes: &bitFlag, count: 2))
        data.append(Data(bytes: &method, count: 2))
        data.append(Data(bytes: &modTime, count: 2))
        data.append(Data(bytes: &modDate, count: 2))
        data.append(Data(bytes: &crcVal, count: 4))
        data.append(Data(bytes: &cSize, count: 4))
        data.append(Data(bytes: &uSize, count: 4))
        data.append(Data(bytes: &nameLen, count: 2))
        data.append(Data(bytes: &extraLen, count: 2))
        data.append(Data(bytes: &commentLen, count: 2))
        data.append(Data(bytes: &diskStart, count: 2))
        data.append(Data(bytes: &intAttrs, count: 2))
        data.append(Data(bytes: &extAttrs, count: 4))
        data.append(Data(bytes: &offset, count: 4))
        data.append(entry.relativePath.data(using: String.Encoding.utf8) ?? Data())
        return data
    }

    private static func buildEOCD(entriesCount: UInt16, cdSize: UInt32, cdOffset: UInt32) -> Data {
        var data = Data()
        var sig: UInt32 = 0x06054b50
        var diskNum: UInt16 = 0
        var cdStartDisk: UInt16 = 0
        var totalEntriesDisk = entriesCount
        var totalEntries = entriesCount
        var size = cdSize
        var offset = cdOffset
        var commentLen: UInt16 = 0

        data.append(Data(bytes: &sig, count: 4))
        data.append(Data(bytes: &diskNum, count: 2))
        data.append(Data(bytes: &cdStartDisk, count: 2))
        data.append(Data(bytes: &totalEntriesDisk, count: 2))
        data.append(Data(bytes: &totalEntries, count: 2))
        data.append(Data(bytes: &size, count: 4))
        data.append(Data(bytes: &offset, count: 4))
        data.append(Data(bytes: &commentLen, count: 2))
        return data
    }

    private static func deflateData(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipError.compressionFailed("deflateInit2 failed")
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        let bufferSize = 32768
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        try data.withUnsafeBytes { rawBuffer in
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: rawBuffer.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)

            try buffer.withUnsafeMutableBufferPointer { bufPtr in
                while stream.avail_in > 0 {
                    stream.next_out = bufPtr.baseAddress
                    stream.avail_out = uInt(bufferSize)

                    let status = deflate(&stream, Z_NO_FLUSH)
                    guard status == Z_OK else {
                        throw ZipError.compressionFailed("deflate returned error: \(status)")
                    }

                    let bytesProduced = bufferSize - Int(stream.avail_out)
                    if bytesProduced > 0 {
                        output.append(bufPtr.baseAddress!, count: bytesProduced)
                    }
                }

                repeat {
                    stream.next_out = bufPtr.baseAddress
                    stream.avail_out = uInt(bufferSize)
                    let status = deflate(&stream, Z_FINISH)
                    guard status == Z_OK || status == Z_STREAM_END else {
                        throw ZipError.compressionFailed("deflate Z_FINISH error: \(status)")
                    }
                    let bytesProduced = bufferSize - Int(stream.avail_out)
                    if bytesProduced > 0 {
                        output.append(bufPtr.baseAddress!, count: bytesProduced)
                    }
                    if status == Z_STREAM_END { break }
                } while true
            }
        }

        return output
    }

    private static func inflateData(_ data: Data, expectedSize: Int) throws -> Data {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipError.decompressionFailed("inflateInit2 failed")
        }
        defer { inflateEnd(&stream) }

        var output = Data(capacity: expectedSize)
        let bufferSize = 32768
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        try data.withUnsafeBytes { rawBuffer in
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: rawBuffer.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)

            try buffer.withUnsafeMutableBufferPointer { bufPtr in
                var status: Int32 = Z_OK
                while status == Z_OK {
                    stream.next_out = bufPtr.baseAddress
                    stream.avail_out = uInt(bufferSize)

                    status = inflate(&stream, Z_SYNC_FLUSH)
                    if status != Z_OK && status != Z_STREAM_END {
                        throw ZipError.decompressionFailed("inflate returned error: \(status)")
                    }

                    let bytesProduced = bufferSize - Int(stream.avail_out)
                    if bytesProduced > 0 {
                        output.append(bufPtr.baseAddress!, count: bytesProduced)
                    }
                }
            }
        }

        return output
    }
}
