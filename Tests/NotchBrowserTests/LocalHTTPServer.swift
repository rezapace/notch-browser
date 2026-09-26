import Foundation
import Network

/// Loopback-only fixture. No external network, request logging, or user data.
final class LocalHTTPServer {
    private let listener: NWListener
    var port: UInt16? {
        guard let port = listener.port?.rawValue, port != 0 else { return nil }
        return port
    }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .utility))
            Self.receive(connection, buffered: Data())
        }
        listener.start(queue: .global(qos: .utility))
    }

    deinit { listener.cancel() }

    private static func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
            var request = buffered
            if let data { request.append(data) }
            guard request.count <= 8192, error == nil else { connection.cancel(); return }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                let body = Data("<!doctype html><meta name='color-scheme' content='dark'><title>Timing fixture</title><body>Local fixture</body>".utf8)
                var response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: public, max-age=3600\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else if complete { connection.cancel() }
            else { receive(connection, buffered: request) }
        }
    }
}
