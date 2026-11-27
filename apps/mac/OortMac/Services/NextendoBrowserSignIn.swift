import AppKit
import Network
import OortLibrary
import ArcanePorting

/// Nextendo redirects to an HTTP loopback URL, not an app scheme. Use the default browser.
@MainActor enum NextendoBrowserSignIn {
    private static let preferredPort: NWEndpoint.Port = 47823
    private typealias Requests = AsyncThrowingStream<(NWConnection, URL), Error>

    static func authorize(clientID: String, openBrowser: (URL) -> Bool = { NSWorkspace.shared.open($0) })
        async throws -> (NextendoAuthorization, String) {
        let binding: (NWListener, UInt16, Requests)
        do {
            binding = try await listen(on: preferredPort)
        } catch NWError.posix(.EADDRINUSE) {
            binding = try await listen(on: .any)
        }
        let (listener, port, requests) = binding
        defer { listener.cancel() }
        try Task.checkCancellation()
        let attempt = try NextendoAuthorization(clientID: clientID, port: port)
        guard openBrowser(attempt.url) else { throw NextendoError.browser }
        let completed = L10n.text("Return to Arcane to finish signing in.")
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                for try await (connection, url) in requests {
                    do {
                        if let code = try attempt.code(from: url) {
                            Self.respond(connection, message: completed)
                            return code
                        }
                        Self.respond(connection)
                    } catch {
                        Self.respond(connection)
                        throw error
                    }
                }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 300_000_000_000)
                throw NextendoError.timeout
            }
            defer { group.cancelAll() }
            guard let code = try await group.next() else { throw NextendoError.browser }
            return (attempt, code)
        }
    }

    private static func listen(on port: NWEndpoint.Port) async throws -> (NWListener, UInt16, Requests) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "io.github.sofianbll.oortnx.nextendo.callback")
        let ports = AsyncThrowingStream<UInt16, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let requests = Requests.makeStream(bufferingPolicy: .bufferingOldest(4))
        listener.stateUpdateHandler = { [weak listener] state in
            switch state {
            case .ready:
                if let port = listener?.port?.rawValue {
                    ports.continuation.yield(port)
                    ports.continuation.finish()
                } else {
                    ports.continuation.finish(throwing: NextendoError.browser)
                }
            case .failed(let error), .waiting(let error):
                ports.continuation.finish(throwing: error)
                requests.continuation.finish(throwing: NextendoError.browser)
            case .cancelled:
                ports.continuation.finish()
                requests.continuation.finish()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak listener] connection in
            guard let port = listener?.port?.rawValue else { connection.cancel(); return }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
            Self.readRequest(connection, port: port, bytes: Data()) { url in
                switch requests.continuation.yield((connection, url)) {
                case .enqueued: break
                default: connection.cancel()
                }
            }
        }
        listener.start(queue: queue)
        do {
            var iterator = ports.stream.makeAsyncIterator()
            guard let bound = try await iterator.next() else {
                try Task.checkCancellation()
                throw NextendoError.browser
            }
            return (listener, bound, requests.stream)
        } catch {
            listener.cancel()
            throw error
        }
    }

    nonisolated private static func readRequest(_ connection: NWConnection, port: UInt16, bytes: Data,
                                               action: @escaping (URL) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - bytes.count) { chunk, _, complete, error in
            var bytes = bytes
            if let chunk { bytes.append(chunk) }
            if let newline = bytes.firstIndex(of: 10) {
                let line = String(data: bytes[..<newline], encoding: .utf8)
                let parts = line?.split(separator: " ") ?? []
                if parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/callback?"),
                   parts[2].hasPrefix("HTTP/1."),
                   let url = URL(string: "http://127.0.0.1:\(port)\(parts[1])") {
                    action(url)
                } else {
                    respond(connection)
                }
            } else if complete || error != nil || bytes.count == 8192 {
                connection.cancel()
            } else {
                readRequest(connection, port: port, bytes: bytes, action: action)
            }
        }
    }

    nonisolated private static func respond(_ connection: NWConnection, message: String? = nil) {
        let status = message != nil ? "200 OK" : "404 Not Found"
        let body = message ?? ""
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
