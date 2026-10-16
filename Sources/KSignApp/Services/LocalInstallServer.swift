// [LISTN] Sources/KSignApp/Services/LocalInstallServer.swift
// Language: Swift 5.9 | File: LocalInstallServer.swift | Target: Embedded HTTPS Server for On-Device itms-services Sideloading
import Foundation
import Network
import UIKit

public final class LocalInstallServer: ObservableObject {
    public static let shared = LocalInstallServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public var port: UInt16 = 8443
    @Published public private(set) var lastErrorMessage: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.ksign.installserver", qos: .userInitiated)
    private var hostedApps: [String: (app: SignedAppItem, url: URL)] = [:]

    private init() {}

    // MARK: - Server Lifecycle
    public func startServer(port: UInt16 = 8443) throws {
        stopServer()
        self.port = port

        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "com.ksign.server", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }

        let newListener = try NWListener(using: parameters, on: nwPort)

        newListener.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.lastErrorMessage = nil
                case .failed(let error):
                    self?.isRunning = false
                    self?.lastErrorMessage = error.localizedDescription
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        newListener.start(queue: queue)
        self.listener = newListener
    }

    public func stopServer() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    // MARK: - App Registration & Installation Trigger
    public func registerAppForInstall(_ app: SignedAppItem, ipaURL: URL) {
        hostedApps[app.id.uuidString] = (app, ipaURL)
    }

    public func triggerInstall(app: SignedAppItem, ipaURL: URL) {
        if !isRunning {
            try? startServer(port: self.port)
        }

        registerAppForInstall(app, ipaURL: ipaURL)

        let manifestURLString = "https://127.0.0.1:\(port)/manifest/\(app.id.uuidString).plist"
        let itmsURLString = "itms-services://?action=download-manifest&url=\(manifestURLString)"

        if let itmsURL = URL(string: itmsURLString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(itmsURL, options: [:], completionHandler: nil)
            }
        }
    }

    // MARK: - Connection Handling & HTTP Dispatch
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            if let requestString = String(data: data, encoding: .utf8) {
                let firstLine = requestString.components(separatedBy: "\r\n").first ?? ""
                let parts = firstLine.components(separatedBy: " ")

                if parts.count >= 2 {
                    let path = parts[1]
                    self.dispatchHTTPPath(path, connection: connection)
                    return
                }
            }

            self.sendHTTPResponse(connection: connection, status: "400 Bad Request", contentType: "text/plain", body: "Bad Request".data(using: .utf8)!)
        }
    }

    private func dispatchHTTPPath(_ path: String, connection: NWConnection) {
        if path.hasPrefix("/manifest/") && path.hasSuffix(".plist") {
            let appID = String(path.dropFirst("/manifest/".count).dropLast(".plist".count))
            if let entry = hostedApps[appID] {
                let plistData = generateManifestPlist(app: entry.app, appID: appID)
                sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/x-plist", body: plistData)
                return
            }
        } else if path.hasPrefix("/download/") && path.hasSuffix(".ipa") {
            let appID = String(path.dropFirst("/download/".count).dropLast(".ipa".count))
            if let entry = hostedApps[appID], let fileData = try? Data(contentsOf: entry.url) {
                sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/octet-stream", body: fileData)
                return
            }
        } else if path == "/ca.mobileconfig" {
            let configData = generateLocalCAMobileconfig()
            sendHTTPResponse(connection: connection, status: "200 OK", contentType: "application/x-apple-aspen-config", body: configData)
            return
        }

        sendHTTPResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: "Not Found".data(using: .utf8)!)
    }

    private func sendHTTPResponse(connection: NWConnection, status: String, contentType: String, body: Data) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"

        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    // MARK: - Payload Generators
    private func generateManifestPlist(app: SignedAppItem, appID: String) -> Data {
        let ipaDownloadURL = "https://127.0.0.1:\(port)/download/\(appID).ipa"
        let manifest: [String: Any] = [
            "items": [
                [
                    "assets": [
                        [
                            "kind": "software-package",
                            "url": ipaDownloadURL
                        ]
                    ],
                    "metadata": [
                        "bundle-identifier": app.bundleIdentifier,
                        "bundle-version": app.version,
                        "kind": "software",
                        "title": app.name
                    ]
                ]
            ]
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)) ?? Data()
    }

    private func generateLocalCAMobileconfig() -> Data {
        let profile: [String: Any] = [
            "PayloadDisplayName": "KSign Local Installation Authority",
            "PayloadDescription": "Enables local HTTPS sideloading for KSign on-device signing.",
            "PayloadIdentifier": "com.ksign.localca",
            "PayloadType": "Configuration",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1,
            "PayloadContent": []
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)) ?? Data()
    }
}
