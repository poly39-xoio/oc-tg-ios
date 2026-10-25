import Foundation
import Network

/// Minimal loopback HTTP/1.1 static file server.
///
/// Why not loadFileURL()? WKWebView treats `file://` and custom schemes as
/// non-secure contexts, which disables `crypto.subtle`, OPFS and service
/// workers — all of which the Telegram web client needs. Loopback HTTP on
/// 127.0.0.1 *is* a potentially-trustworthy origin, so the web app behaves
/// exactly like it does in Safari.
final class LocalWebServer {
    private let root: URL
    private let queue = DispatchQueue(label: "io.xoio.oc.webserver", qos: .userInitiated)
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    /// Storage (IndexedDB/localStorage) is scoped to origin, and the origin
    /// includes the port. A random port would wipe the Telegram session on every
    /// launch, so always serve from the same fixed port.
    static let fixedPort: UInt16 = 47823

    private static let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "htm": "text/html; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "mjs": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "map": "application/json; charset=utf-8",
        "webmanifest": "application/manifest+json; charset=utf-8",
        "wasm": "application/wasm",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "mp3": "audio/mpeg",
        "mp4": "video/mp4",
        "webm": "video/webm",
        "txt": "text/plain; charset=utf-8"
    ]

    init(root: URL) {
        self.root = root
    }

    @discardableResult
    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.fixedPort)!)

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var assignedPort: UInt16 = 0
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                assignedPort = listener.port?.rawValue ?? 0
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 5)

        guard assignedPort != 0 else {
            throw NSError(domain: "io.xoio.oc.webserver", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "failed to bind loopback port"])
        }
        self.listener = listener
        self.port = assignedPort
        NSLog("[OC] local web server on 127.0.0.1:\(assignedPort) root=\(root.path)")
        return assignedPort
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHeaders(on: connection, buffer: Data())
    }

    private func receiveHeaders(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            if let error {
                NSLog("[OC] receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = buffer.subdata(in: 0..<range.lowerBound)
                self.respond(to: head, on: connection)
                return
            }
            if isComplete || buffer.count > 64 * 1024 {
                connection.cancel()
                return
            }
            self.receiveHeaders(on: connection, buffer: buffer)
        }
    }

    private func respond(to head: Data, on connection: NWConnection) {
        guard let text = String(data: head, encoding: .utf8),
              let requestLine = text.split(separator: "\r\n").first else {
            send(status: 400, reason: "Bad Request", mime: "text/plain", body: Data("bad request".utf8), on: connection)
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(status: 400, reason: "Bad Request", mime: "text/plain", body: Data("bad request".utf8), on: connection)
            return
        }
        let method = String(parts[0]).uppercased()
        var path = String(parts[1])
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        if let hash = path.firstIndex(of: "#") { path = String(path[..<hash]) }
        path = path.removingPercentEncoding ?? path

        guard method == "GET" || method == "HEAD" else {
            send(status: 405, reason: "Method Not Allowed", mime: "text/plain", body: Data("method not allowed".utf8), on: connection)
            return
        }

        let resolved = resolve(path: path)
        guard let fileURL = resolved else {
            send(status: 404, reason: "Not Found", mime: "text/plain", body: Data("not found".utf8), on: connection)
            return
        }

        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            send(status: 500, reason: "Internal Server Error", mime: "text/plain", body: Data("read error".utf8), on: connection)
            return
        }

        let ext = fileURL.pathExtension.lowercased()
        let mime = Self.mimeTypes[ext] ?? "application/octet-stream"
        let cache = (ext == "html") ? "no-cache" : "public, max-age=31536000, immutable"

        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: \(mime)\r
        Content-Length: \(data.count)\r
        Cache-Control: \(cache)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r\n
        """
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in
            if method == "HEAD" || data.isEmpty {
                connection.cancel()
                return
            }
            self.sendBody(data, on: connection)
        })
    }

    private func sendBody(_ data: Data, on connection: NWConnection) {
        let chunkSize = 512 * 1024
        if data.count <= chunkSize {
            connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let chunk = data.prefix(chunkSize)
        let rest = data.dropFirst(chunkSize)
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil {
                connection.cancel()
                return
            }
            self?.sendBody(Data(rest), on: connection)
        })
    }

    private func send(status: Int, reason: String, mime: String, body: Data, on connection: NWConnection) {
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(mime)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r\n
        """
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Path resolution

    private func resolve(path: String) -> URL? {
        var relative = path
        while relative.hasPrefix("/") { relative.removeFirst() }
        if relative.isEmpty { relative = "index.html" }

        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            return nil
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let index = candidate.appendingPathComponent("index.html")
                return FileManager.default.fileExists(atPath: index.path) ? index : nil
            }
            return candidate
        }

        // SPA fallback: extensionless routes (e.g. /a/, /login) go to index.html
        if candidate.pathExtension.isEmpty {
            let index = root.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: index.path) { return index }
        }
        return nil
    }
}
