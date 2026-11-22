// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Network
import os.lock

public final class LocalHTTPServerEngine: @unchecked Sendable {
    public static let shared = LocalHTTPServerEngine()

    private var lock = os_unfair_lock()
    private var listener: NWListener?
    private var isServerActive: Bool = false
    private var boundPort: UInt16 = 8080
    private let queue = DispatchQueue(label: "org.mozilla.godmode.localserver", qos: .utility)

    public static let didChangeStateNotification = Notification.Name("GodModeLocalServerDidChangeState")

    private init() {}

    public var isRunning: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return isServerActive
    }

    public var port: UInt16 {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return boundPort
    }

    public var rootDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    public var serverURL: URL? {
        guard isRunning, let ip = localIPAddress else { return nil }
        return URL(string: "http://\(ip):\(port)")
    }

    public var localIPAddress: String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "pdp_ip0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                    if name == "en0" {
                        break
                    }
                }
            }
        }
        return address ?? "127.0.0.1"
    }

    public func start(port: UInt16 = 8080) throws {
        os_unfair_lock_lock(&lock)
        if isServerActive {
            os_unfair_lock_unlock(&lock)
            return
        }
        self.boundPort = port
        os_unfair_lock_unlock(&lock)

        let parameters = NWParameters.tcp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "LocalHTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }

        let newListener = try NWListener(using: parameters, on: nwPort)
        newListener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.setRunningState(true)
            case .failed, .cancelled:
                self.setRunningState(false)
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        newListener.start(queue: queue)

        os_unfair_lock_lock(&lock)
        self.listener = newListener
        os_unfair_lock_unlock(&lock)
    }

    public func stop() {
        os_unfair_lock_lock(&lock)
        let activeListener = self.listener
        self.listener = nil
        self.isServerActive = false
        os_unfair_lock_unlock(&lock)

        activeListener?.cancel()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeStateNotification, object: false)
        }
    }

    private func setRunningState(_ running: Bool) {
        os_unfair_lock_lock(&lock)
        self.isServerActive = running
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeStateNotification, object: running)
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection)
    }

    private func receiveHTTPRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if let data = content, let requestString = String(data: data, encoding: .utf8) {
                self.processHTTPRequest(requestString, connection: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func processHTTPRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "text/plain", body: "Bad Request".data(using: .utf8)!)
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "text/plain", body: "Bad Request".data(using: .utf8)!)
            return
        }

        let method = parts[0].uppercased()
        let rawPath = parts[1]

        guard method == "GET" || method == "HEAD" else {
            sendResponse(connection: connection, status: "405 Method Not Allowed", contentType: "text/plain", body: "Method Not Allowed".data(using: .utf8)!)
            return
        }

        let cleanPath = (rawPath.components(separatedBy: "?").first ?? "/").removingPercentEncoding ?? "/"
        let safePath = cleanPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let targetURL = safePath.isEmpty ? rootDirectoryURL : rootDirectoryURL.appendingPathComponent(safePath)
        let resolved = targetURL.standardizedFileURL

        guard resolved.path.hasPrefix(rootDirectoryURL.standardizedFileURL.path) else {
            sendResponse(connection: connection, status: "403 Forbidden", contentType: "text/plain", body: "Forbidden".data(using: .utf8)!)
            return
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) {
            if isDir.boolValue {
                serveDirectoryListing(resolved, relativePath: safePath, connection: connection, isHead: method == "HEAD")
            } else {
                serveFile(resolved, connection: connection, isHead: method == "HEAD")
            }
        } else {
            sendResponse(connection: connection, status: "404 Not Found", contentType: "text/html", body: "<html><body><h1>404 Not Found</h1></body></html>".data(using: .utf8)!)
        }
    }

    private func serveDirectoryListing(_ url: URL, relativePath: String, connection: NWConnection, isHead: Bool) {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [])) ?? []

        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Index of /\(relativePath)</title>
            <style>
                body { font-family: -apple-system, sans-serif; margin: 20px; background: #121212; color: #e0e0e0; }
                h1 { font-size: 1.2rem; border-bottom: 1px solid #333; padding-bottom: 8px; }
                table { width: 100%; border-collapse: collapse; }
                th, td { text-align: left; padding: 8px; border-bottom: 1px solid #222; }
                a { color: #4da3ff; text-decoration: none; }
                a:hover { text-decoration: underline; }
                .size { color: #888; font-size: 0.9rem; }
            </style>
        </head>
        <body>
            <h1>Index of /\(relativePath)</h1>
            <table>
                <tr><th>Name</th><th>Size</th></tr>
        """

        if !relativePath.isEmpty {
            let parentPath = (relativePath as NSString).deletingLastPathComponent
            html += "<tr><td><a href=\"/\(parentPath)\">📁 .. (Parent Directory)</a></td><td>-</td></tr>"
        }

        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isItemDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let fileSize = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let name = item.lastPathComponent
            let itemPath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
            let icon = isItemDir ? "📁" : "📄"
            let sizeString = isItemDir ? "-" : ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)

            html += "<tr><td><a href=\"/\(itemPath)\">\(icon) \(name)</a></td><td class=\"size\">\(sizeString)</td></tr>"
        }

        html += "</table></body></html>"

        let data = html.data(using: .utf8)!
        sendResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: isHead ? Data() : data, bodyLength: data.count)
    }

    private func serveFile(_ url: URL, connection: NWConnection, isHead: Bool) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            sendResponse(connection: connection, status: "500 Internal Error", contentType: "text/plain", body: "Error".data(using: .utf8)!)
            return
        }

        let mimeType = mimeType(for: url.pathExtension)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mimeType)\r\nContent-Length: \(fileSize)\r\nConnection: close\r\nAccept-Ranges: bytes\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if error != nil || isHead {
                connection.cancel()
                return
            }
            self?.streamFileChunks(url: url, connection: connection, totalBytes: fileSize)
        })
    }

    private func streamFileChunks(url: URL, connection: NWConnection, totalBytes: Int64) {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            connection.cancel()
            return
        }

        let chunkSize = 65536
        func sendNextChunk() {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                try? fileHandle.close()
                connection.cancel()
                return
            }

            connection.send(content: chunk, completion: .contentProcessed { error in
                if error != nil {
                    try? fileHandle.close()
                    connection.cancel()
                } else {
                    sendNextChunk()
                }
            })
        }

        sendNextChunk()
    }

    private func sendResponse(connection: NWConnection, status: String, contentType: String, body: Data, bodyLength: Int? = nil) {
        let length = bodyLength ?? body.count
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(length)\r\nConnection: close\r\n\r\n"
        var fullData = header.data(using: .utf8) ?? Data()
        if !body.isEmpty {
            fullData.append(body)
        }

        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain; charset=utf-8"
        case "mp4": return "video/mp4"
        case "mp3": return "audio/mpeg"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}
