import Foundation
import Network
import os

/// Lightweight local HTTP server that listens for the OAuth callback.
final class OAuthCallbackServer: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.echonotes", category: "OAuthServer")
    private let port: UInt16
    private let onCallback: @Sendable (String, String) -> Void // (code, state)
    private var listener: NWListener?

    init(port: UInt16, onCallback: @escaping @Sendable (String, String) -> Void) {
        self.port = port
        self.onCallback = onCallback
    }

    func start() throws {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("OAuth callback server listening on port \(self?.port ?? 0)")
            case .failed(let error):
                self?.logger.error("OAuth server failed: \(error.localizedDescription)")
            default:
                break
            }
        }

        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            guard let requestString = String(data: data, encoding: .utf8) else {
                self.sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid request")
                return
            }

            // Parse the HTTP request line
            guard let firstLine = requestString.split(separator: "\r\n").first else {
                self.sendResponse(connection: connection, status: "400 Bad Request", body: "No request line")
                return
            }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                self.sendResponse(connection: connection, status: "400 Bad Request", body: "Malformed request")
                return
            }

            let path = String(parts[1])

            // Parse the callback path
            guard path.hasPrefix("/auth/callback") else {
                self.sendResponse(connection: connection, status: "404 Not Found", body: "Not found")
                return
            }

            // Extract query parameters
            guard let urlComponents = URLComponents(string: "http://localhost\(path)"),
                  let queryItems = urlComponents.queryItems else {
                self.sendResponse(connection: connection, status: "400 Bad Request", body: "No query parameters")
                return
            }

            let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
                item.value.map { (item.name, $0) }
            })

            if let errorParam = params["error"] {
                let desc = params["error_description"] ?? errorParam
                self.sendResponse(connection: connection, status: "200 OK",
                    body: self.errorHTML(message: desc))
                return
            }

            guard let code = params["code"], let state = params["state"] else {
                self.sendResponse(connection: connection, status: "400 Bad Request", body: "Missing code or state")
                return
            }

            // Send success page to browser
            self.sendResponse(connection: connection, status: "200 OK", body: self.successHTML())

            // Fire the callback
            self.onCallback(code, state)
        }
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let isHTML = body.contains("<")
        let contentType = isHTML ? "text/html; charset=utf-8" : "text/plain; charset=utf-8"
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func successHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>EchoNotes — Signed In</title>
        <style>
            body { font-family: -apple-system, system-ui, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #1a1a2e; color: #e0e0e0; }
            .card { text-align: center; padding: 40px; border-radius: 16px; background: #16213e; box-shadow: 0 4px 24px rgba(0,0,0,0.3); }
            h1 { font-size: 24px; margin-bottom: 8px; }
            p { color: #888; }
        </style>
        </head>
        <body>
            <div class="card">
                <h1>✅ Signed in to EchoNotes</h1>
                <p>You can close this tab and return to EchoNotes.</p>
            </div>
        </body>
        </html>
        """
    }

    private func errorHTML(message: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><title>EchoNotes — Error</title>
        <style>
            body { font-family: -apple-system, system-ui, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #1a1a2e; color: #e0e0e0; }
            .card { text-align: center; padding: 40px; border-radius: 16px; background: #16213e; box-shadow: 0 4px 24px rgba(0,0,0,0.3); }
            h1 { font-size: 24px; margin-bottom: 8px; color: #ff6b6b; }
            p { color: #888; }
        </style>
        </head>
        <body>
            <div class="card">
                <h1>❌ Authentication Failed</h1>
                <p>\(message)</p>
                <p>Close this tab and try again in EchoNotes.</p>
            </div>
        </body>
        </html>
        """
    }
}
